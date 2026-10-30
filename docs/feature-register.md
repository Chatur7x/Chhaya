# Chhaya V14 feature register

This register transcribes the 127 numbered requests in the supplied Chhaya V14 reference. A requested description is a target, not evidence of implementation, safety, compatibility, range or performance. Statuses are conservative; consult [delivery-checklist.md](delivery-checklist.md) for implementation evidence and outstanding release gates.

**Status for every item below: not verified for release.** An existing implementation or partial implementation is described only where the current checklist supports it. Items without a note require a code and evidence audit; they are not assumed to be implemented. No item has an assigned human owner yet: the project owner must designate maintainers and independent reviewers.

The execution ledger, [feature-verification-127.csv](feature-verification-127.csv), separately records source-based implementation status and release evidence. `assessment pending` is a temporary indication that a requirement has not yet received a complete source-to-acceptance assessment; it is not a passing result or a removed requirement. Assessed requirements use the requested implementation categories. All 127 original IDs remain in scope.

## Shared acceptance requirements

For each entry, record its design and named owner; verify the user flow and supported Android/iOS behavior, backend changes where applicable, protocol/data and dependencies; document security/privacy limits; add meaningful automated and adversarial tests; and retain physical-device results for applicable platforms. Mark verified only when these checks and any independent security review required for that feature pass on the release commit. Windows support is a separate release decision.

The shared security boundaries and server-visible metadata are in [threat-model.md](threat-model.md); unfinished protocol and operational work is in [delivery-checklist.md](delivery-checklist.md). These common requirements do not replace feature-specific specifications or acceptance tests. The descriptions below are preserved from the supplied reference, including aspirational claims and numeric targets that have not been established.

## Communication

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 1 | E2EE text chat | Triple Ratchet encryption | Classical direct path exists; custom protocol remains unaudited and PQ ratchet is not active. |
| 2 | Disappearing messages | Per-contact + per-group timers | Local timer and encrypted expiry exist; cross-device and retention semantics incomplete. |
| 3 | Read receipts | Opt-out per contact | Global and per-conversation opt-out implemented; native peer/lifecycle evidence pending. |
| 4 | Reply threading | Quoted replies | Encrypted reply IDs and UI exist; device tests pending. |
| 5 | Media messages | Images, files, voice notes | Inline encrypted attachments limited to 256 KB; native tests pending. |
| 6 | Group conversations | Admin rights, participant management | Group administration exists; authenticated membership and device tests pending. |
| 7 | Message status | Sent / delivered / read | Delivery/read timestamps exist; group semantics and device evidence pending. |
| 8 | Sealed Sender | Server never knows sender | Not implemented. |
| 9 | E2EE voice calls | SFrame + DTLS-SRTP | Foreground WebRTC exists; SFrame and background integration missing. |
| 10 | E2EE video calls | Same stack | Foreground WebRTC exists; SFrame and background integration missing. |
| 11 | LAN calls (offline) | mDNS signaling on same Wi-Fi | Not implemented. |

## Cryptography

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 12 | X25519 | Key agreement (RFC 7748) | Audit implementation and define feature-specific acceptance evidence. |
| 13 | Ed25519 | Signatures (RFC 8032) | Audit implementation and define feature-specific acceptance evidence. |
| 14 | AES-256-GCM | AEAD encryption | Audit implementation and define feature-specific acceptance evidence. |
| 15 | HKDF-SHA256 | Key derivation (RFC 5869) | Audit implementation and define feature-specific acceptance evidence. |
| 16 | PBKDF2-HMAC-SHA256 | 100k iterations | Audit implementation and define feature-specific acceptance evidence. |
| 17 | SHA-256/512 | Hashing | Audit implementation and define feature-specific acceptance evidence. |
| 18 | BIP-39 | 12-word recovery | Audit implementation and define feature-specific acceptance evidence. |
| 19 | ML-KEM-1024 | Post-quantum KEM (Kyber, FIPS 203) | AWS-LC primitive exists; not integrated into live session establishment. |
| 20 | ML-DSA-87 | Post-quantum signatures (Dilithium, FIPS 204) | AWS-LC primitive exists; production authentication use and native validation pending. |
| 21 | Hybrid PQXDH | X25519 + ML-KEM-1024 | Scaffold only; not live. |
| 22 | Dual-KEM | Kyber + NTRU (algorithm diversity) | Placeholder; design decision and review needed. |
| 23 | Triple Ratchet | Symmetric + DH + SPQR | Classical ratchet exists; no fresh PQ ratchet contribution. |
| 24 | SPQR | Sparse Post-Quantum Ratchet | Deterministic epoch chain is not a PQ ratchet. |
| 25 | Skipped-key cache | Out-of-order (MAX_SKIP=1000) | Audit implementation and define feature-specific acceptance evidence. |

## Privacy and transport

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 26 | 3-hop onion routing | Region-diverse relays | Experimental code is not on the messaging path. |
| 27 | 512B fixed padding | Traffic analysis resistance | Audit implementation and define feature-specific acceptance evidence. |
| 28 | Circuit auto-renew | 10-minute lifetime | Audit implementation and define feature-specific acceptance evidence. |
| 29 | Zero persistent ID | No phone/email/username | No phone/email required, but account IDs persist and are visible to server. |
| 30 | Arke handshake | Unlinkable discovery | Audit implementation and define feature-specific acceptance evidence. |
| 31 | Rotating Shadow Codes | 60s, single-use | Audit implementation and define feature-specific acceptance evidence. |
| 32 | BLE mesh | ~30m offline | Not implemented. |
| 33 | Wi-Fi Aware (Android) | ~100m offline | Not implemented. |
| 34 | MultipeerConnectivity (iOS) | Apple offline transport | Not implemented. |
| 35 | Cover traffic | Traffic padding | Audit implementation and define feature-specific acceptance evidence. |
| 36 | No-push mode | Tor + TAP heartbeat | Audit implementation and define feature-specific acceptance evidence. |

## Device security

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 37 | SQLCipher DB | AES-256 page encryption | Integration exists; native at-rest evidence pending. |
| 38 | Android Keystore | Hardware key storage | Audit implementation and define feature-specific acceptance evidence. |
| 39 | StrongBox | Secure element (API 28+) | Audit implementation and define feature-specific acceptance evidence. |
| 40 | iOS Secure Enclave | P-256 wraps X25519/Ed25519 | Audit implementation and define feature-specific acceptance evidence. |
| 41 | Windows DPAPI | Per-user protection | Audit implementation and define feature-specific acceptance evidence. |
| 42 | Key zeroization | On background | Audit implementation and define feature-specific acceptance evidence. |
| 43 | Per-user DB keys | Derived from master | Audit implementation and define feature-specific acceptance evidence. |
| 44 | Rate limiting | API + WebSocket | Audit implementation and define feature-specific acceptance evidence. |
| 45 | Certificate pinning | SPKI fingerprint | Verify active implementation, rotation and failure behavior. |
| 46 | APK signature verify | Anti-repackaging | Audit implementation and define feature-specific acceptance evidence. |
| 47 | Play Integrity | Server attestation | Audit implementation and define feature-specific acceptance evidence. |

## Coercion resistance

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 48 | Duress PIN | Decoy UI + key destruction | Panic PIN local removal exists; decoy and duress design incomplete. |
| 49 | Duress iris | Android only | OS biometric APIs do not identify a particular duress biometric. |
| 50 | Duress Face ID | iOS alternative | OS biometric APIs do not identify a particular duress biometric. |
| 51 | CANARY protocol | Silent duress alert | Audit implementation and define feature-specific acceptance evidence. |
| 52 | Dead man's switch | Auto-destruct on no check-in | Audit implementation and define feature-specific acceptance evidence. |
| 53 | Plausible deniability | Hidden layer under decoy | Audit implementation and define feature-specific acceptance evidence. |
| 54 | Auto-blank on peek | Second-face detection | Audit implementation and define feature-specific acceptance evidence. |
| 55 | Gaze detection | Blank before peeker reads | Audit implementation and define feature-specific acceptance evidence. |
| 56 | Contextual blur | Blur content only | Audit implementation and define feature-specific acceptance evidence. |
| 57 | Root detection | su / Frida / Xposed | Audit implementation and define feature-specific acceptance evidence. |
| 58 | Jailbreak detection | iOS equivalent | Audit implementation and define feature-specific acceptance evidence. |
| 59 | Emulator detection | QEMU / build props | Audit implementation and define feature-specific acceptance evidence. |
| 60 | FLAG_SECURE | Screenshot prevention | Platform behavior and device evidence need verification. |
| 61 | Screen capture detect | iOS + Android 14+ | Audit implementation and define feature-specific acceptance evidence. |
| 62 | Custom secure keyboard | For sensitive input | Audit implementation and define feature-specific acceptance evidence. |
| 63 | Clipboard auto-clear | 30-second wipe | Audit implementation and define feature-specific acceptance evidence. |

## Encrypted vault

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 64 | Screenshot vault | Never reaches gallery | Audit implementation and define feature-specific acceptance evidence. |
| 65 | Per-file encryption | ChaCha20 or AES-256-GCM | Audit implementation and define feature-specific acceptance evidence. |
| 66 | Hardware-backed keys | Keystore / Enclave | Audit implementation and define feature-specific acceptance evidence. |
| 67 | Biometric unlock | Fingerprint / Face / Iris | Audit implementation and define feature-specific acceptance evidence. |
| 68 | Tamper detection | SHA-256 hash | Audit implementation and define feature-specific acceptance evidence. |
| 69 | Send from vault | Re-encrypt with session key | Audit implementation and define feature-specific acceptance evidence. |

## Multi-device

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 70 | Cross-platform pairing | Android / iOS / Windows | Enrollment scaffolding only; no complete authenticated linking. |
| 71 | QR-based linking | Ephemeral key exchange | Audit implementation and define feature-specific acceptance evidence. |
| 72 | Cryptographic binding | Server never sees keys | Audit implementation and define feature-specific acceptance evidence. |
| 73 | Remote revocation | Instant | Full device revocation protocol incomplete. |
| 74 | Session reset on revoke | Ratchet reset | Audit implementation and define feature-specific acceptance evidence. |
| 75 | Per-device push tokens | FCM / APNs | Audit implementation and define feature-specific acceptance evidence. |

## Backup and recovery

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 76 | BIP-39 recovery | 12 words | Audit implementation and define feature-specific acceptance evidence. |
| 77 | Encrypted backup | Master-key encrypted | Encrypted local backup exists; session recovery/device tests pending. |
| 78 | Local file export | User location | Export exists; platform validation pending. |
| 79 | Cloud backup (optional) | User-controlled | Audit implementation and define feature-specific acceptance evidence. |
| 80 | Account restore | From recovery phrase | Phrase-based identity recovery exists; device recovery testing pending. |
| 81 | Multi-device restore | Re-link after restore | Audit implementation and define feature-specific acceptance evidence. |

## Offline mode

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 82 | Chat (BLE) | ~30m range | Audit implementation and define feature-specific acceptance evidence. |
| 83 | Chat (Wi-Fi Aware) | ~100m | Audit implementation and define feature-specific acceptance evidence. |
| 84 | Voice/video (LAN) | Same Wi-Fi | Audit implementation and define feature-specific acceptance evidence. |
| 85 | QR contact add | Both present | QR identity check exists; device camera testing pending. |
| 86 | Vault/duress | Fully local | Audit implementation and define feature-specific acceptance evidence. |
| 87 | Message queue | 30s retry | Outbox and foreground retry exist; 30-second schedule not established. |
| 88 | Zero network calls | Local-Only mode verified | Local-only mode is not implemented. |

## Customization

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 89 | Claude Light theme | Coral on cream | Cream/coral UI exists; accessibility and device review pending. |
| 90 | V13 dark theme | Optional | Audit implementation and define feature-specific acceptance evidence. |
| 91 | DEPΛ2TɄRE_MONO | Technical font | Bundled Departure Mono exists; typography coverage needs review. |
| 92 | Inter + Tiempos | Body + display | Audit implementation and define feature-specific acceptance evidence. |
| 93 | Full color picker | Custom themes | Audit implementation and define feature-specific acceptance evidence. |
| 94 | App icon variants | Multiple | Audit implementation and define feature-specific acceptance evidence. |
| 95 | Proxy support | SOCKS5/HTTP/HTTPS | Audit implementation and define feature-specific acceptance evidence. |
| 96 | Connection toggle | Online/Local/Auto | Not implemented. |

## UI and accessibility

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 97 | Spring physics | Critically damped | Audit implementation and define feature-specific acceptance evidence. |
| 98 | Message send animation | Slide+scale+sweep+check | Audit implementation and define feature-specific acceptance evidence. |
| 99 | Skeleton loading | Coral shimmer | Audit implementation and define feature-specific acceptance evidence. |
| 100 | Typing indicator | Coral ripple / mono cursor | Direct-chat typing exists; device and lifecycle testing pending. |
| 101 | Encryption pulse | Breathing lock | Audit implementation and define feature-specific acceptance evidence. |
| 102 | Shared element transitions | Avatar flight | Audit implementation and define feature-specific acceptance evidence. |
| 103 | Haptic language | Consistent per action | Audit implementation and define feature-specific acceptance evidence. |
| 104 | Onboarding ritual | Word-by-word reveal | Audit implementation and define feature-specific acceptance evidence. |
| 105 | Empty state art | Animated diagram | Audit implementation and define feature-specific acceptance evidence. |
| 106 | Duress visual mode | Full transformation | Audit implementation and define feature-specific acceptance evidence. |
| 107 | Responsive layouts | Phone/tablet/desktop | Audit implementation and define feature-specific acceptance evidence. |
| 108 | A11y compliant | Screen readers, 44×44 | Audit implementation and define feature-specific acceptance evidence. |

## Infrastructure

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 109 | Express API | 17 endpoints | Node/Express backend exists; live operations still required. |
| 110 | WebSocket signaling | Port 8444 | Authenticated signaling exists on shared HTTP listener /signaling; deployment validation pending. |
| 111 | Onion relay | Port 8445 | No production onion relay deployment. |
| 112 | PostgreSQL 16 | 10-table schema | PostgreSQL backend exists; production operation not established. |
| 113 | Redis 7 | Sessions/circuits | Audit implementation and define feature-specific acceptance evidence. |
| 114 | FCM + APNs | Push | Scaffolding only; provider credentials and mobile integration missing. |
| 115 | Docker Compose | One-command deploy | Self-hosting scaffolding exists; restore and deployment drills pending. |
| 116 | Nginx TLS | Reverse proxy | TLS reverse-proxy configuration exists; live certificate and deployment pending. |
| 117 | Prometheus | `/metrics` | Metrics exist; deployed monitoring and alerts pending. |
| 118 | Winston logging | Structured JSON | Audit implementation and define feature-specific acceptance evidence. |
| 119 | Self-hostable | Full stack | Deployment preparation exists; no production deployment evidence. |

## Quality and release

| ID | Requested feature | Requested detail (unverified) | Current evidence or next step |
|---:|---|---|---|
| 120 | CI Android | analyze+test+APK | Workflow exists; signed release/device evidence pending. |
| 121 | CI iOS | macOS runner | Workflow exists; signed distribution/device evidence pending. |
| 122 | Test coverage | 75+ tests | Audit implementation and define feature-specific acceptance evidence. |
| 123 | External audit prep | Parts 4,5,12,14 | Audit implementation and define feature-specific acceptance evidence. |
| 124 | SBOM | Bill of materials | Audit implementation and define feature-specific acceptance evidence. |
| 125 | Pentest checklist | 12 categories | Audit implementation and define feature-specific acceptance evidence. |
| 126 | Play Store + App Store | Listings | Store distribution not complete. |
| 127 | Documentation | Complete | Audit implementation and define feature-specific acceptance evidence. |

## Additional product requests from the delivery plan

The following items were discussed beyond the numbered reference. Each remains **unverified**, has no assigned owner, and needs a specific product/privacy design, platform/backend dependency analysis, automated and device tests, and acceptance criteria before implementation can be claimed complete.

| Request | Design decision and acceptance work still required |
|---|---|
| Stories/status | Define audience, expiry, storage, content encryption and moderation. |
| Channels and communities | Define audience, roles, discovery, moderation and privacy model. |
| Larger groups and moderation | Define limits, authenticated membership, administration, abuse handling and scale tests. |
| Bots and integrations | Define consent and explicitly disclose when a service receives message content. |
| Search and discovery | Define local/server search, identity verification and metadata exposure. |
| Stickers and rich media | Define formats, transfer limits, validation and accessibility. |
| Business/team features | Define users, administrators, permissions, retention and separate privacy expectations. |
| Message editing, deletion, forwarding and reactions | Define encrypted event semantics, permissions, conflict handling and history behavior. |
| Media transfers | Specify encrypted resumable uploads, quotas, cancellation and cleanup. |
| Production operations and distribution | Define hosting, budgets, monitoring, backups, incident response, signing and store ownership. |

## Release evidence rule

A screen, source file, algorithm name or passing mocked test is not proof of an end-to-end feature. Record actual tests and their environment, unresolved failures, device results and review findings in the delivery checklist. No claim of a completed product or independent audit is made by this register.
