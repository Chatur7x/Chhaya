package com.proj16.backend.model;

import jakarta.persistence.*;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import java.time.LocalDateTime;

/**
 * MeshLink contact — stores paired device information.
 */
@Entity
@Table(name = "mesh_contacts")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class MeshContact {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private String id;

    @Column(nullable = false)
    private String username;

    @Column(name = "device_id", nullable = false, unique = true)
    private String deviceId;

    @Column(name = "public_key", nullable = false, length = 500)
    private String publicKey;

    @Column(name = "paired_at", nullable = false)
    private LocalDateTime pairedAt;

    @Column(name = "contact_status")
    @Enumerated(EnumType.STRING)
    private ContactStatus status = ContactStatus.UNREACHABLE;

    @Column(name = "last_seen")
    private LocalDateTime lastSeen;

    @Column(name = "contact_group")
    private String group;

    @Column(name = "is_trusted_ring")
    private boolean trustedRing = false;

    @Column(name = "is_stealth")
    private boolean stealth = false;

    public enum ContactStatus {
        NEARBY,
        RELAY,
        UNREACHABLE
    }
}
