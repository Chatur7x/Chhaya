package com.proj16.backend.repository;

import com.proj16.backend.model.MeshContact;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface MeshContactRepository extends JpaRepository<MeshContact, String> {
    Optional<MeshContact> findByDeviceId(String deviceId);
    List<MeshContact> findByUsername(String username);
    List<MeshContact> findByTrustedRingTrue();
    List<MeshContact> findByGroupOrderByUsernameAsc(String group);
    boolean existsByDeviceId(String deviceId);
    
    @Query("SELECT m FROM MeshContact m WHERE m.isDiscoverable = true AND (m.discoverableUntil IS NULL OR m.discoverableUntil > CURRENT_TIMESTAMP)")
    List<MeshContact> findDiscoverableContacts();
    
    @Modifying
    @Query("UPDATE MeshContact m SET m.isDiscoverable = false WHERE m.discoverableUntil IS NOT NULL AND m.discoverableUntil < CURRENT_TIMESTAMP")
    void disableExpiredDiscoverableContacts();

    @Modifying
    @Query("DELETE FROM MeshContact m WHERE m.username = :username")
    void deleteByUsername(String username);
}
