package com.proj16.backend.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "shared_links")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SharedLink {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "file_id")
    private FileMetadata fileMetadata;

    @Column(unique = true, nullable = false)
    private String shareToken;

    private String passwordHash; // BCrypt hash if password protected
    private LocalDateTime expiryDate;
    
    private Integer downloadLimit;
    @Builder.Default
    private Integer downloadCount = 0;

    private LocalDateTime createdAt;
    private String createdBy;
}
