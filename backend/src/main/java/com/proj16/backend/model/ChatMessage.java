package com.proj16.backend.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "chat_messages")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ChatMessage {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String senderUsername;
    private String recipientUsername;
    
    @Column(columnDefinition = "TEXT")
    private String content; // End-to-end encrypted content

    private LocalDateTime timestamp;

    @Enumerated(EnumType.STRING)
    private MessageStatus status;

    @Column(columnDefinition = "TEXT")
    private String replyToId;

    @Column(columnDefinition = "TEXT")
    private String quotedText;

    @Column(columnDefinition = "TEXT")
    private String reactions;

    private boolean edited = false;

    private LocalDateTime editedAt;

    public enum MessageStatus {
        SENT, DELIVERED, READ
    }
}
