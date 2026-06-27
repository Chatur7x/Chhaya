package com.proj16.backend.repository;

import com.proj16.backend.model.MeshContact;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
public interface MeshContactRepository extends JpaRepository<MeshContact, String> {
    Optional<MeshContact> findByDeviceId(String deviceId);
    List<MeshContact> findByTrustedRingTrue();
    List<MeshContact> findByGroupOrderByUsernameAsc(String group);
    boolean existsByDeviceId(String deviceId);
}
