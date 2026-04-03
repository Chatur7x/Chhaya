package com.proj16.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class TypingIndicatorDto {
    private String senderId;
    private String recipientUsername;
    private boolean isTyping;
}
