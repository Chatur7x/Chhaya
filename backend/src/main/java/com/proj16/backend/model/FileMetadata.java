package com.proj16.backend.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "file_metadata")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FileMetadata {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String fileName;
    private String fileType;
    private Long fileSize;
    
    private String storagePath; // Path in Supabase or Appwrite
    private String storageProvider; // "SUPABASE" or "APPWRITE"
    
    private String ownerUsername;
    private boolean isEncrypted;
    
    private LocalDateTime uploadedAt;
}
