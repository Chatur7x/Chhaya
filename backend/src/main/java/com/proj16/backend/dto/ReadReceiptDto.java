package com.proj16.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ReadReceiptDto {
    private String messageId;
    private String senderId;
    private String recipientUsername;
    private LocalDateTime readAt;
}
