package com.proj16.backend.controller;

import com.proj16.backend.dto.ReadReceiptDto;
import com.proj16.backend.dto.TypingIndicatorDto;
import com.proj16.backend.model.ChatMessage;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.time.LocalDateTime;

@Controller
public class ChatController {

    private final SimpMessagingTemplate messagingTemplate;

    public ChatController(SimpMessagingTemplate messagingTemplate) {
        this.messagingTemplate = messagingTemplate;
    }

    @MessageMapping("/chat.sendMessage")
    public void processMessage(@Payload ChatMessage chatMessage) {
        chatMessage.setTimestamp(LocalDateTime.now());
        chatMessage.setStatus(ChatMessage.MessageStatus.SENT);

        messagingTemplate.convertAndSendToUser(
                chatMessage.getRecipientUsername(), "/queue/messages",
                chatMessage
        );
    }

    @MessageMapping("/chat.typing")
    public void handleTyping(@Payload TypingIndicatorDto typingDto) {
        typingDto.setTyping(typingDto.isTyping());
        messagingTemplate.convertAndSendToUser(
                typingDto.getRecipientUsername(), "/queue/typing",
                typingDto
        );
    }

    @MessageMapping("/chat.readReceipt")
    public void handleReadReceipt(@Payload ReadReceiptDto receiptDto) {
        receiptDto.setReadAt(LocalDateTime.now());
        messagingTemplate.convertAndSendToUser(
                receiptDto.getSenderId(), "/queue/readReceipts",
                receiptDto
        );
    }
}
