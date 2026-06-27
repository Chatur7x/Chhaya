package com.proj16.backend.controller;

import com.proj16.backend.model.MeshContact;
import com.proj16.backend.model.MeshMessage;
import com.proj16.backend.repository.MeshContactRepository;
import com.proj16.backend.repository.MeshMessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * MeshLink API Controller — handles mesh message storage and contact management.
 * Used when a device connects to the local backend for backup/sync.
 */
@RestController
@RequestMapping("/api/mesh")
@RequiredArgsConstructor
public class MeshController {

    private final MeshMessageRepository messageRepo;
    private final MeshContactRepository contactRepo;

    // ─── Messages ───

    /** Store a message (backup from device or store-and-forward) */
    @PostMapping("/messages")
    public ResponseEntity<MeshMessage> storeMessage(@RequestBody MeshMessage message) {
        if (message.getTimestamp() == null) {
            message.setTimestamp(LocalDateTime.now());
        }
        return ResponseEntity.ok(messageRepo.save(message));
    }

    /** Get conversation between two users */
    @GetMapping("/messages/conversation")
    public ResponseEntity<List<MeshMessage>> getConversation(
            @RequestParam String userId,
            @RequestParam String contactId) {
        return ResponseEntity.ok(messageRepo.findConversation(userId, contactId));
    }

    /** Get queued messages for a recipient (store-and-forward pickup) */
    @GetMapping("/messages/queued/{recipientId}")
    public ResponseEntity<List<MeshMessage>> getQueuedMessages(
            @PathVariable String recipientId) {
        return ResponseEntity.ok(
                messageRepo.findByRecipientIdAndStatusOrderByTimestampAsc(
                        recipientId, MeshMessage.MessageStatus.QUEUED));
    }

    /** Update message status */
    @PatchMapping("/messages/{messageId}/status")
    public ResponseEntity<Void> updateStatus(
            @PathVariable String messageId,
            @RequestBody Map<String, String> body) {
        return messageRepo.findById(messageId)
                .map(msg -> {
                    msg.setStatus(MeshMessage.MessageStatus.valueOf(body.get("status")));
                    messageRepo.save(msg);
                    return ResponseEntity.ok().<Void>build();
                })
                .orElse(ResponseEntity.notFound().build());
    }

    // ─── Contacts ───

    /** Register a new contact (after QR pairing) */
    @PostMapping("/contacts")
    public ResponseEntity<MeshContact> registerContact(@RequestBody MeshContact contact) {
        if (contactRepo.existsByDeviceId(contact.getDeviceId())) {
            return ResponseEntity.badRequest().build();
        }
        contact.setPairedAt(LocalDateTime.now());
        contact.setLastSeen(LocalDateTime.now());
        return ResponseEntity.ok(contactRepo.save(contact));
    }

    /** Get all contacts */
    @GetMapping("/contacts")
    public ResponseEntity<List<MeshContact>> getAllContacts() {
        return ResponseEntity.ok(contactRepo.findAll());
    }

    /** Get contact by device ID */
    @GetMapping("/contacts/{deviceId}")
    public ResponseEntity<MeshContact> getContact(@PathVariable String deviceId) {
        return contactRepo.findByDeviceId(deviceId)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /** Update contact status */
    @PatchMapping("/contacts/{deviceId}/status")
    public ResponseEntity<Void> updateContactStatus(
            @PathVariable String deviceId,
            @RequestBody Map<String, String> body) {
        return contactRepo.findByDeviceId(deviceId)
                .map(contact -> {
                    contact.setStatus(MeshContact.ContactStatus.valueOf(body.get("status")));
                    contact.setLastSeen(LocalDateTime.now());
                    contactRepo.save(contact);
                    return ResponseEntity.ok().<Void>build();
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /** Get trusted ring contacts */
    @GetMapping("/contacts/trusted-ring")
    public ResponseEntity<List<MeshContact>> getTrustedRing() {
        return ResponseEntity.ok(contactRepo.findByTrustedRingTrue());
    }

    /** Delete a contact */
    @DeleteMapping("/contacts/{deviceId}")
    public ResponseEntity<Void> deleteContact(@PathVariable String deviceId) {
        return contactRepo.findByDeviceId(deviceId)
                .map(contact -> {
                    contactRepo.delete(contact);
                    return ResponseEntity.ok().<Void>build();
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /** Update battery level */
    @PatchMapping("/contacts/{deviceId}/battery")
    public ResponseEntity<MeshContact> updateBatteryLevel(
            @PathVariable String deviceId,
            @RequestBody BatteryLevelUpdateDto dto) {
        return contactRepo.findByDeviceId(deviceId)
                .map(contact -> {
                    contact.setBatteryLevel(dto.getBatteryLevel());
                    contact.setLastSeen(LocalDateTime.now());
                    
                    // Update status based on battery threshold (15%)
                    if (dto.getBatteryLevel() != null && dto.getBatteryLevel() < 15) {
                        contact.setStatus(MeshContact.ContactStatus.UNREACHABLE);
                    } else if (contact.getStatus() == MeshContact.ContactStatus.UNREACHABLE && 
                               dto.getBatteryLevel() != null && dto.getBatteryLevel() >= 15) {
                        contact.setStatus(MeshContact.ContactStatus.NEARBY);
                    }
                    
                    return ResponseEntity.ok(contactRepo.save(contact));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /** Update BLE advertising interval */
    @PatchMapping("/contacts/{deviceId}/advertising-interval")
    public ResponseEntity<MeshContact> updateAdvertisingInterval(
            @PathVariable String deviceId,
            @RequestBody AdvertisingIntervalUpdateDto dto) {
        return contactRepo.findByDeviceId(deviceId)
                .map(contact -> {
                    Integer interval = dto.getAdvertisingInterval();
                    // Validate allowed intervals: 1000ms, 5000ms, 30000ms
                    if (interval != 1000 && interval != 5000 && interval != 30000) {
                        return ResponseEntity.badRequest().<MeshContact>build();
                    }
                    contact.setBleAdvertisingInterval(interval);
                    return ResponseEntity.ok(contactRepo.save(contact));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /** Get discoverable contacts */
    @GetMapping("/contacts/discoverable")
    public ResponseEntity<List<MeshContact>> getDiscoverableContacts() {
        return ResponseEntity.ok(contactRepo.findDiscoverableContacts());
    }

    /** Update discoverable status */
    @PatchMapping("/contacts/{deviceId}/discoverable")
    public ResponseEntity<MeshContact> updateDiscoverable(
            @PathVariable String deviceId,
            @RequestBody DiscoveryConfigDto dto) {
        return contactRepo.findByDeviceId(deviceId)
                .map(contact -> {
                    contact.setDiscoverable(dto.getDiscoverable());
                    if (dto.getDiscoverable() != null && dto.getDiscoverable()) {
                        int timeoutMinutes = dto.getTimeoutMinutes() != null ? dto.getTimeoutMinutes() : 5;
                        contact.setDiscoverableUntil(LocalDateTime.now().plusMinutes(timeoutMinutes));
                    } else {
                        contact.setDiscoverableUntil(null);
                    }
                    return ResponseEntity.ok(contactRepo.save(contact));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /** Broadcast message to trusted ring */
    @PostMapping("/broadcast")
    public ResponseEntity<List<MeshMessage>> broadcastToTrustedRing(
            @RequestBody BroadcastMessageDto dto) {
        List<MeshContact> trustedContacts = contactRepo.findByTrustedRingTrue();
        List<MeshMessage> broadcastMessages = trustedContacts.stream()
                .map(contact -> {
                    MeshMessage message = new MeshMessage();
                    message.setId(java.util.UUID.randomUUID().toString());
                    message.setSenderId(dto.getSenderId() != null ? dto.getSenderId() : "system");
                    message.setSenderName(dto.getSenderName() != null ? dto.getSenderName() : "system");
                    message.setRecipientId(contact.getDeviceId());
                    message.setContent(dto.getContent());
                    message.setTimestamp(LocalDateTime.now());
                    message.setType(MeshMessage.MessageType.BROADCAST);
                    message.setStatus(MeshMessage.MessageStatus.QUEUED);
                    message.setMaxHops(1);
                    return message;
                })
                .collect(java.util.stream.Collectors.toList());
        
        messageRepo.saveAll(broadcastMessages);
        return ResponseEntity.ok(broadcastMessages);
    }

    /** Sync queued messages for a user */
    @GetMapping("/sync/{userId}")
    public ResponseEntity<List<MeshMessage>> syncMessages(@PathVariable String userId) {
        List<MeshMessage> messages = messageRepo.findQueuedMessagesWithPriority(userId);
        messages.forEach(msg -> {
            msg.setStatus(MeshMessage.MessageStatus.SENT);
            messageRepo.save(msg);
        });
        return ResponseEntity.ok(messages);
    }
}
