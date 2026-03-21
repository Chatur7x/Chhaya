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
}
