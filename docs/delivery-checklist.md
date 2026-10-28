# Chhaya V14 delivery checklist

The user's complete-project reference is the requested scope. Its checkmarks,
percentages, benchmark numbers and uniqueness claims are not evidence of delivery.
This file tracks implementation separately from release verification. No merge,
hosted service, Apple membership or external audit is assumed.
The [feature register](feature-register.md) indexes all 127 requested reference items and additional product requests.

| Requirement | Current implementation | Acceptance evidence still required |
|---|---|---|
| Android and iOS apps | Flutter targets and native build workflows; arm64 Android release-mode APK built and signature-verified with the repository's debug key | Physical-device functional/lifecycle tests; production signing; iOS build and device validation |
| Windows | Legacy target and storage support | Complete build, plugin compatibility, pairing and device QA |
| Account without phone/email | Public-key identity and recovery phrase; registration and login challenge proofs verified across Flutter and a local Node/PostgreSQL backend | Live HTTPS, device recovery and migration testing |
| Identity verification | Full-ID/QR checks | Camera/device and adversarial substitution tests |
| Direct encrypted text | Ratchet envelopes and membership-checked transport; two Flutter clients exchanged messages in both directions through the local Node/PostgreSQL backend with independent in-memory test databases | Independent protocol audit; production TLS and live two-phone validation; native SQLCipher verification |
| Message retry | Atomic outbox; exact-envelope retries; foreground automatic retry | Network-loss/restart/device tests |
| Replies | Encrypted reply IDs; compose/cancel/quoted-message UI | Regression/layout and real peer tests |
| Photos/files | Inline encrypted attachments, preview and explicit export, up to 256 KB | Larger encrypted blob/chunk transfer; picker/export device tests |
| Voice messages | User-started AAC recording up to 60s; playback and encrypted attachment | Microphone, interruptions, playback and temporary-file device tests |
| Groups/admin roles | Group creation from verified contacts; admin role promote/demote, member removal and self-leave APIs; transactional server checks preserve at least two active members and one active admin; group sends are accepted only when their key-wrapper recipient list matches active membership under the same database lock; local three-client backend test covers messages and member removal; accepted-envelope retries and stale-recipient rejection pass PostgreSQL tests | Concurrent removal/send race tests; trusted-server membership enforcement is not cryptographic group membership authentication; stale queued envelopes currently require the sender to copy and resend after refresh or discard locally; per-member verification/acceptance UX, two/three-phone tests, reviewed membership/key-rotation semantics, external protocol review |
| Polls | Encrypted poll definitions and vote-change events use the regular E2EE ratchet (including group key wrapping); bounded question/options; single or multiple choice; optional expiry; each client reconstructs anonymous aggregate totals from authenticated vote history; invalid choices/closed-poll votes are rejected | Real two/three-device history and expiry tests; race/abuse limits, multi-device vote reconciliation, accessible physical-device review and protocol assessment |
| Read/delivery states | Recipient message fetch independently records `delivered_at`; explicit read endpoint advances `read_at`; sender sync displays each timestamp as a distinct state | PostgreSQL-backed end-to-end test on two accounts; group-recipient and multi-device receipt semantics |
| Typing indicators | Authenticated WebSocket events in direct chats; server verifies two-party membership, rate-limits, sends only conversation ID/state and stores nothing; encrypted local privacy toggle; UI clears after 6 seconds without refresh | Two-phone Android/iOS delivery, background/disconnect expiry and privacy-toggle device tests |
| Disappearing content | Local expiry, app-wide timer, persistent per-conversation local override (inherit/never/custom), encrypted per-message expiry | Cross-device timer synchronization, server ciphertext deletion/retention policy, clock-skew behavior and honest export limits |
| Search/pin/block/history | Implemented local flows | Physical-device and resynchronization edge cases |
| Foreground calls | WebRTC with encrypted SDP/ICE over authenticated WSS; server retains encrypted offers for up to 60 seconds and exposes them only to the intended account on reconnect; answer/end clears the queued offer; client suppresses duplicate live/queued delivery for the ring window with bounded state | Two-phone NAT/TURN, cancellation, interruption, reconnect and permissions |
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
| Encrypted backup | Version 2 encrypted export; phrase-derived identity validation; SQLCipher transaction replaces profile/contacts/conversations/messages; old ratchets and outbox are cleared rather than cloned; credentials are compensating-rolled-back if import fails | Native Keychain/Keystore plus database failure tests, device recovery flows, and UX to re-establish messaging sessions after restore |
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
| App identity/avatar | Custom coral chat-bubble/crescent Chhaya mark is used in onboarding, startup, Android launcher icons, all iOS app icon sizes and the web favicon; iOS display name corrected to Chhaya; CI checks source and native asset dimensions/catalog references via `python scripts/verify_app_branding.py` | Verify rendered icon on physical Android/iOS devices and store previews |
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
