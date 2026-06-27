package com.proj16.backend.repository;

import com.proj16.backend.model.MeshMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public interface MeshMessageRepository extends JpaRepository<MeshMessage, String> {

    List<MeshMessage> findByRecipientIdAndStatusOrderByTimestampAsc(
            String recipientId, MeshMessage.MessageStatus status);

    @Query("SELECT m FROM MeshMessage m WHERE " +
           "(m.senderId = :userId AND m.recipientId = :contactId) OR " +
           "(m.senderId = :contactId AND m.recipientId = :userId) " +
           "ORDER BY m.timestamp ASC")
    List<MeshMessage> findConversation(String userId, String contactId);

    List<MeshMessage> findByRecipientIdOrderByTimestampDesc(String recipientId);

    long countByRecipientIdAndStatus(String recipientId, MeshMessage.MessageStatus status);
}
