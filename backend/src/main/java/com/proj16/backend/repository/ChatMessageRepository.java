package com.proj16.backend.repository;

import com.proj16.backend.model.ChatMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {

    @Query("SELECT m FROM ChatMessage m WHERE " +
           "(m.senderUsername = :username1 AND m.recipientUsername = :username2) OR " +
           "(m.senderUsername = :username2 AND m.recipientUsername = :username1) " +
           "ORDER BY m.timestamp ASC")
    List<ChatMessage> findConversation(String username1, String username2);

    List<ChatMessage> findBySenderUsernameOrRecipientUsernameOrderByTimestampDesc(String username1, String username2);

    @Query("SELECT m FROM ChatMessage m WHERE " +
           "LOWER(m.content) LIKE LOWER(CONCAT('%', :query, '%')) " +
           "ORDER BY m.timestamp DESC")
    List<ChatMessage> searchMessages(String query);
}
