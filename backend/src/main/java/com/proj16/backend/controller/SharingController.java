package com.proj16.backend.controller;

import com.proj16.backend.model.SharedLink;
import com.proj16.backend.repository.FileMetadataRepository;
import com.proj16.backend.repository.SharedLinkRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/share")
public class SharingController {

    private final SharedLinkRepository shareRepository;
    private final FileMetadataRepository fileRepository;
    private final PasswordEncoder passwordEncoder;

    public SharingController(SharedLinkRepository shareRepository, FileMetadataRepository fileRepository, 
                             PasswordEncoder passwordEncoder) {
        this.shareRepository = shareRepository;
        this.fileRepository = fileRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @PostMapping("/generate")
    public ResponseEntity<?> generateLink(@RequestBody Map<String, Object> request) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long fileId = Long.valueOf(request.get("fileId").toString());

        return fileRepository.findById(fileId).map(file -> {
            if (!file.getOwnerUsername().equals(username)) {
                return ResponseEntity.status(403).body("Unauthorized");
            }

            SharedLink link = SharedLink.builder()
                    .fileMetadata(file)
                    .shareToken(UUID.randomUUID().toString())
                    .createdAt(LocalDateTime.now())
                    .createdBy(username)
                    .downloadCount(0)
                    .build();

            if (request.containsKey("password")) {
                link.setPasswordHash(passwordEncoder.encode(request.get("password").toString()));
            }
            if (request.containsKey("expiryDays")) {
                link.setExpiryDate(LocalDateTime.now().plusDays(Long.parseLong(request.get("expiryDays").toString())));
            }
            if (request.containsKey("limit")) {
                link.setDownloadLimit(Integer.parseInt(request.get("limit").toString()));
            }

            return ResponseEntity.ok(shareRepository.save(link));
        }).orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/info/{token}")
    public ResponseEntity<?> getLinkInfo(@PathVariable String token) {
        return shareRepository.findByShareToken(token)
                .map(link -> {
                    if (link.getExpiryDate() != null && link.getExpiryDate().isBefore(LocalDateTime.now())) {
                        return ResponseEntity.status(410).body("Link expired");
                    }
                    if (link.getDownloadLimit() != null && link.getDownloadCount() >= link.getDownloadLimit()) {
                        return ResponseEntity.status(410).body("Download limit reached");
                    }
                    return ResponseEntity.ok(Map.of(
                            "fileName", link.getFileMetadata().getFileName(),
                            "fileSize", link.getFileMetadata().getFileSize(),
                            "isPasswordProtected", link.getPasswordHash() != null
                    ));
                }).orElse(ResponseEntity.notFound().build());
    }
}
