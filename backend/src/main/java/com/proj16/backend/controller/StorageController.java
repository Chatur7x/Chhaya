package com.proj16.backend.controller;

import com.proj16.backend.model.FileMetadata;
import com.proj16.backend.repository.FileMetadataRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/api/storage")
public class StorageController {
    
    private final FileMetadataRepository fileRepository;

    public StorageController(FileMetadataRepository fileRepository) {
        this.fileRepository = fileRepository;
    }

    @GetMapping("/files")
    public ResponseEntity<List<FileMetadata>> getUserFiles(@RequestParam(required = false) String provider) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        if (provider != null) {
            return ResponseEntity.ok(fileRepository.findAllByOwnerUsernameAndStorageProvider(username, provider.toUpperCase()));
        }
        return ResponseEntity.ok(fileRepository.findAllByOwnerUsername(username));
    }

    @PostMapping("/metadata")
    public ResponseEntity<FileMetadata> saveMetadata(@RequestBody FileMetadata metadata) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        metadata.setOwnerUsername(username);
        metadata.setUploadedAt(LocalDateTime.now());
        return ResponseEntity.ok(fileRepository.save(metadata));
    }

    @DeleteMapping("/files/{id}")
    public ResponseEntity<?> deleteFile(@PathVariable Long id) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        return fileRepository.findById(id)
                .map(file -> {
                    if (!file.getOwnerUsername().equals(username)) {
                        return ResponseEntity.status(403).body("Error: Unauthorized to delete this file");
                    }
                    fileRepository.delete(file);
                    return ResponseEntity.ok("File deleted successfully");
                })
                .orElse(ResponseEntity.notFound().build());
    }
}
