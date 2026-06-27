package com.proj16.backend.model;

import jakarta.persistence.*;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import java.time.LocalDateTime;

/**
 * MeshLink message — stored for backup and store-and-forward.
 */
@Entity
@Table(name = "mesh_messages")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class MeshMessage {

    @Id
    @Column(nullable = false, length = 36)
    private String id;

    @Column(name = "sender_id", nullable = false)
    private String senderId;

    @Column(name = "sender_name")
    private String senderName;

    @Column(name = "recipient_id", nullable = false)
    private String recipientId;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String content;

    @Column(nullable = false)
    private LocalDateTime timestamp;

    @Column(name = "message_type")
    @Enumerated(EnumType.STRING)
    private MessageType type = MessageType.TEXT;

    @Column(length = 20)
    private String channel = "ble";

    @Column(name = "hop_count")
    private int hopCount = 0;

    @Column(name = "max_hops")
    private int maxHops = 7;

    @Column(name = "message_status")
    @Enumerated(EnumType.STRING)
    private MessageStatus status = MessageStatus.QUEUED;

    @Column(name = "is_sos")
    private boolean sos = false;

    public enum MessageType {
        TEXT, IMAGE, VIDEO, AUDIO, FILE, LOCATION, RECEIPT, SOS, BROADCAST, PTT, CONTACT, SYSTEM
    }

    public enum MessageStatus {
        QUEUED, SENT, DELIVERED, READ, FAILED
    }
}
