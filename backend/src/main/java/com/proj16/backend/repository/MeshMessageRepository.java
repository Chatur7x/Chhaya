package com.proj16.backend.repository;

import com.proj16.backend.model.MeshMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime;
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
    
    @Query("SELECT m FROM MeshMessage m WHERE m.recipientId = :recipientId AND m.status = 'QUEUED' ORDER BY m.isSos DESC, m.timestamp ASC")
    List<MeshMessage> findQueuedMessagesWithPriority(String recipientId);
    
    @Query("SELECT m FROM MeshMessage m WHERE m.expiresAt IS NOT NULL AND m.expiresAt < CURRENT_TIMESTAMP")
    List<MeshMessage> findExpiredMessages();
    
    @Modifying
    @Query("DELETE FROM MeshMessage m WHERE m.expiresAt IS NOT NULL AND m.expiresAt < CURRENT_TIMESTAMP")
    void deleteExpiredMessages();
    
    @Query("SELECT m FROM MeshMessage m WHERE m.isSos = true AND m.status = 'QUEUED' ORDER BY m.timestamp ASC")
    List<MeshMessage> findSosMessages();

    @Modifying
    @Query("DELETE FROM MeshMessage m WHERE m.senderId = :senderId OR m.recipientId = :recipientId")
    void deleteBySenderIdOrRecipientId(String senderId, String recipientId);
}
