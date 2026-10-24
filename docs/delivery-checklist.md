# Chhaya V14 delivery checklist

The user's complete-project reference is the requested scope. Its checkmarks,
percentages, benchmark numbers and uniqueness claims are not evidence of delivery.
This file tracks implementation separately from release verification. No merge,
hosted service, Apple membership or external audit is assumed.

| Requirement | Current implementation | Acceptance evidence still required |
|---|---|---|
| Android and iOS apps | Flutter targets and native build workflows; arm64 Android release-mode APK built and signature-verified with the repository's debug key | Physical-device functional/lifecycle tests; production signing; iOS build and device validation |
| Windows | Legacy target and storage support | Complete build, plugin compatibility, pairing and device QA |
| Account without phone/email | Public-key identity and recovery phrase | Device recovery and migration testing |
| Identity verification | Full-ID/QR checks | Camera/device and adversarial substitution tests |
| Direct encrypted text | Ratchet envelopes and membership-checked transport | Independent protocol audit; live two-phone validation |
| Message retry | Atomic outbox; exact-envelope retries; foreground automatic retry | Network-loss/restart/device tests |
| Replies | Encrypted reply IDs; compose/cancel/quoted-message UI | Regression/layout and real peer tests |
| Photos/files | Inline encrypted attachments, preview and explicit export, up to 256 KB | Larger encrypted blob/chunk transfer; picker/export device tests |
| Voice messages | User-started AAC recording up to 60s; playback and encrypted attachment | Microphone, interruptions, playback and temporary-file device tests |
| Groups/admin roles | Group creation from verified contacts; server checks creator's active contact list; group body is AES-GCM encrypted once and its one-time key is wrapped in each member's ratchet session; all sender ratchets/message/outbox commit atomically; sync authenticates both wrapper and body; each recipient must independently verify each sender; membership changes/admin management are not exposed | Per-member verification/acceptance UX, two/three-phone tests, visible skipped-history state, delivery/read semantics, membership-removal/key rotation design, external protocol review |
| Polls | Encrypted poll definitions and vote-change events use the regular E2EE ratchet (including group key wrapping); bounded question/options; single or multiple choice; optional expiry; each client reconstructs anonymous aggregate totals from authenticated vote history; invalid choices/closed-poll votes are rejected | Real two/three-device history and expiry tests; race/abuse limits, multi-device vote reconciliation, accessible physical-device review and protocol assessment |
| Read/delivery states | Read receipts and message state handling | Independent delivery acknowledgments; multi-device receipt semantics |
| Typing indicators | Authenticated WebSocket events in direct chats; server verifies two-party membership, rate-limits, sends only conversation ID/state and stores nothing; encrypted local privacy toggle; UI clears after 6 seconds without refresh | Two-phone Android/iOS delivery, background/disconnect expiry and privacy-toggle device tests |
| Disappearing content | Local expiry, app-wide timer, persistent per-conversation local override (inherit/never/custom), encrypted per-message expiry | Cross-device timer synchronization, server ciphertext deletion/retention policy, clock-skew behavior and honest export limits |
| Search/pin/block/history | Implemented local flows | Physical-device and resynchronization edge cases |
| Foreground calls | WebRTC with encrypted SDP/ICE over authenticated WSS | Two-phone NAT/TURN, cancellation, interruption, reconnect and permissions |
| Background calls | Incomplete | CallKit/Android native call integration and lifecycle tests |
| SFrame | Not integrated | Reviewed media frame encryption and interoperable native support |
| Push | Backend/provider scaffolding | Firebase/APNs credentials, native registration, background integration and privacy QA |
| Classical cryptography | X25519, AEAD, HKDF, ratchet implementation | Independent composition/implementation review |
| Post-quantum primitives | AWS-LC v5.11.0 pinned to commit `fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6`; Flutter hybrid-layer tests pass and Android arm64 release native build succeeds | Native provider known-answer tests on Android/iOS; independent protocol review and device validation |
| PQ hybrid/session bootstrap | Scaffolded | Authenticated PQ key distribution, version negotiation, downgrade protection and migration |
| PQ ratchet | Deterministic epoch chain only | Real PQ reseeding and external protocol review |
| Dual-KEM/NTRU | Placeholder scope | Threat-model rationale, approved implementation and protocol review |
| SQLCipher | Encrypted database and field payloads | Real native at-rest test and version evidence on each platform |
| Hardware key wrapping | Android Keystore; iOS Enclave attempt/Keychain fallback | Report actual device capabilities; never promise universal StrongBox |
| App/device lock | Authentication gate and PIN handling | Background/race/device tests |
| Panic PIN | Local data/key removal | Physical-device validation and documented remote-copy limits |
| Encrypted backup | Versioned export/import | Atomic restore strategy and safe conversation-session recovery; avoid cloned ratchet state |
| Multi-device pairing/revocation | Incomplete enrollment scaffolding | Authenticated key transfer, per-device sessions, revocation propagation and recovery |
| Onion transport | Experimental legacy code, disabled | Reviewed key establishment, relay deployment, circuit lifecycle and traffic analysis |
| Arke/Shadow Codes | Not implemented | Protocol specification, unlinkability analysis, integration and external review |
| Sealed Sender | Not implemented | Authenticated anonymous delivery and abuse controls; metadata review |
| Offline mesh | Not implemented | BLE/native transports, capability detection, discovery, queueing and cross-platform tests |
| Local-only/Auto modes | Not implemented | Transport separation plus a test demonstrating zero internet calls in local mode |
| LAN calls | Not implemented | Local discovery/signaling, authentication and network permission tests |
| Vault/decoy/duress | Not implemented | Threat model, storage lifecycle, safe behavior and platform validation |
| CANARY/dead-man/gaze features | Not implemented | Explicit recipient/trigger UX, consent, reliability and privacy review |
| Root/jailbreak/Frida detection | Not a verified cross-platform protection | Defined detection/response; realistic bypass limitations |
| Capture protection | Not established as complete | Android/iOS-specific implementation and honest OS limitations |
| Memory clearing | Best-effort secret wiping | Native/runtime-copy review; no absolute erasure guarantee |
| Cream/coral + Departure Mono | Implemented and bundled font licenses | New-feature accessibility and physical-device review |
| App identity/avatar | Custom Chhaya crescent-chat emblem is used in onboarding, startup, Android launcher icons and the iOS app icon set | Verify rendered icon on physical Android/iOS devices and store previews |
| Dark theme/customizer/icons | Legacy dark APIs, incomplete product flow | Semantic theme migration, controls and contrast checks |
| Proxy modes | Incomplete | HTTP/WebSocket/WebRTC routing behavior, DNS and leak tests |
| Backend/self-hosting | Node/PostgreSQL, Docker/nginx preparation; DB readiness health check; bounded HTTP/WebSocket/PostgreSQL shutdown | Live domain/TLS/server, backups, restore drills and operations ownership |
| Monitoring/rate limits | Basic metrics and health; atomic PostgreSQL fixed-window HTTP limits shared across instances with keyed-HMAC caller identifiers and stale-bucket cleanup | Deployed monitoring, alert routing, retention and multi-instance/load tests |
| Licensing | Third-party font notices present; root license is effectively empty | Confirm project license and complete dependency notice inventory |
| Performance claims | Chat-local database refresh reduced from every 2 seconds to every 15 seconds; immediate refresh remains on resume and after sends | Reproducible device benchmarks, release size, battery and network measurements |
| Store distribution | Android test APK and unsigned iOS artifacts | Signing ownership, memberships, store assets/privacy disclosures and submission |
| External audit | Not commissioned | Assessor engagement, findings remediation and retest |

An item is complete only when its implementation and acceptance evidence exist.
Implementation work proceeds on `codex/` branches; the user retains merge control.
