# PRODUCT.md — Chhaya (Secure Messenger)

## Product Identity
**Name:** Chhaya  
**Tagline:** Privacy Redefined. Speed Perfected.  
**Version:** 12.0.0  
**Platform:** Flutter (Android, iOS, Windows, Web)

## Core Value Proposition
A privacy-first, end-to-end encrypted messenger inspired by Threema and Session. No phone number, no email, no central server — just a 66-character anonymous identity and military-grade encryption.

## Target Audience
- **Primary:** Privacy-conscious consumers, activists, journalists, professionals handling sensitive communications
- **Secondary:** Security researchers, crypto enthusiasts, teams needing confidential collaboration
- **Tertiary:** General users seeking WhatsApp/Telegram alternative with true anonymity

## Key Differentiators
1. **Zero-Knowledge Identity** — No phone/email tied to account
2. **Double Ratchet + AES-256-GCM** — Forward secrecy, keys rotate per message
3. **Onion Routing (3-hop)** — Hides origin IP across anonymous relays
4. **P2P WebRTC Calls** — Direct peer-to-peer voice/video, no server relay
5. **Decentralized File Sharing** — Chunked, encrypted, swarm-distributed
6. **Steganography** — Hide messages inside PNG images (LSB)
7. **Panic PIN** — Instant wipe on coercion
8. **Biometric Lock** — Fingerprint/FaceID gate
9. **Disappearing Messages** — Configurable TTL per conversation
10. **QR Verification** — In-person contact verification

## Product Mode
**Operate** — This is a daily-use communication tool. Scanability, consistency, native expectations, and real usage scenes outrank expression. Brand lives in precise details.

## Current State
- **Architecture:** Clean layered (UI → Services → Core → Storage)
- **State Management:** Riverpod (providers + StateNotifier)
- **Navigation:** Named routes with MaterialPageRoute
- **Theme:** Custom Material 3 dark theme (ChhayaTheme) — 700+ lines
- **Backend:** Go Onion Node (WSS) + Rust Swarm Relay (Axum)
- **Tests:** Basic widget + crypto/onion unit tests

## Constraints
- Must maintain Flutter/Dart codebase (not React)
- Must preserve all existing crypto/security logic
- Must work on Android, iOS, Windows, Web
- Must support RTL languages (future)
- Must pass WCAG AA accessibility
- Must honor `prefers-reduced-motion` equivalent

## Success Metrics
- App launch < 500ms cold start
- Message send-to-deliver < 200ms (onion routing)
- Call connect < 3s (WebRTC)
- 60fps animations on 5-year-old devices
- Zero critical security findings