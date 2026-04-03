package com.proj16.backend.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.proj16.backend.dto.MessageEditDto;
import com.proj16.backend.dto.ReactionDto;
import com.proj16.backend.exception.ResourceNotFoundException;
import com.proj16.backend.model.ChatMessage;
import com.proj16.backend.repository.ChatMessageRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/messages")
@RequiredArgsConstructor
@Tag(name = "Messages", description = "Message management APIs")
public class MessageController {

    private final ChatMessageRepository messageRepository;
    private final ObjectMapper objectMapper;

    private static final long EDIT_WINDOW_MINUTES = 15;

    @PutMapping("/{id}")
    @Operation(summary = "Edit message", description = "Edit a message within 15-minute window")
    public ResponseEntity<ChatMessage> editMessage(
            @PathVariable Long id,
            @RequestBody MessageEditDto editDto,
            @AuthenticationPrincipal UserDetails user) {

        ChatMessage message = messageRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Message not found with id: " + id));

        if (!message.getSenderUsername().equals(user.getUsername())) {
            throw new RuntimeException("You can only edit your own messages");
        }

        LocalDateTime now = LocalDateTime.now();
        LocalDateTime editWindow = message.getTimestamp().plusMinutes(EDIT_WINDOW_MINUTES);
        if (now.isAfter(editWindow)) {
            throw new RuntimeException("Edit window has expired. Messages can only be edited within 15 minutes of sending");
        }

        message.setContent(editDto.getContent());
        message.setEdited(true);
        message.setEditedAt(now);

        ChatMessage saved = messageRepository.save(message);
        return ResponseEntity.ok(saved);
    }

    @PostMapping("/{id}/reactions")
    @Operation(summary = "Add reaction", description = "Add emoji reaction to a message")
    public ResponseEntity<ChatMessage> addReaction(
            @PathVariable Long id,
            @RequestBody ReactionDto reactionDto,
            @AuthenticationPrincipal UserDetails user) {

        ChatMessage message = messageRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Message not found with id: " + id));

        Map<String, List<String>> reactions = parseReactions(message.getReactions());
        String emoji = reactionDto.getEmoji();
        String userId = user.getUsername();

        reactions.computeIfAbsent(emoji, k -> new java.util.ArrayList<>()).add(userId);
        message.setReactions(serializeReactions(reactions));

        ChatMessage saved = messageRepository.save(message);
        return ResponseEntity.ok(saved);
    }

    @DeleteMapping("/{id}/reactions/{emoji}")
    @Operation(summary = "Remove reaction", description = "Remove your reaction from a message")
    public ResponseEntity<ChatMessage> removeReaction(
            @PathVariable Long id,
            @PathVariable String emoji,
            @AuthenticationPrincipal UserDetails user) {

        ChatMessage message = messageRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Message not found with id: " + id));

        Map<String, List<String>> reactions = parseReactions(message.getReactions());
        String userId = user.getUsername();

        if (reactions.containsKey(emoji)) {
            reactions.get(emoji).remove(userId);
            if (reactions.get(emoji).isEmpty()) {
                reactions.remove(emoji);
            }
        }
        message.setReactions(serializeReactions(reactions));

        ChatMessage saved = messageRepository.save(message);
        return ResponseEntity.ok(saved);
    }

    @GetMapping("/search")
    @Operation(summary = "Search messages", description = "Full-text search in messages")
    public ResponseEntity<List<ChatMessage>> searchMessages(@RequestParam String query) {
        List<ChatMessage> results = messageRepository.searchMessages(query);
        return ResponseEntity.ok(results);
    }

    private Map<String, List<String>> parseReactions(String reactionsJson) {
        if (reactionsJson == null || reactionsJson.isEmpty()) {
            return new HashMap<>();
        }
        try {
            return objectMapper.readValue(reactionsJson,
                objectMapper.getTypeFactory().constructMapType(HashMap.class, String.class, List.class));
        } catch (JsonProcessingException e) {
            return new HashMap<>();
        }
    }

    private String serializeReactions(Map<String, List<String>> reactions) {
        if (reactions.isEmpty()) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(reactions);
        } catch (JsonProcessingException e) {
            return null;
        }
    }
}
