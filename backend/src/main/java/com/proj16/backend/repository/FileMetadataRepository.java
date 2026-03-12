package com.proj16.backend.repository;

import com.proj16.backend.model.FileMetadata;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface FileMetadataRepository extends JpaRepository<FileMetadata, Long> {
    List<FileMetadata> findAllByOwnerUsername(String ownerUsername);
    List<FileMetadata> findAllByOwnerUsernameAndStorageProvider(String ownerUsername, String storageProvider);
}
