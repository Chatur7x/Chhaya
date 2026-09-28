# Changelog

All notable changes to Chhaya are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [14.0.0] — V14 (in progress)

Target: post-quantum cryptography, Arke handshake, mesh networking,
vault + duress, Claude Light theme, restructured backend.

### Added (Part 1)
- `lib/core/crypto/primitives/`: extracted X25519, Ed25519, AES-GCM,
  HKDF, PBKDF2, SHA, CSPRNG, BIP-39 from the engine monolith.
- `lib/core/log.dart`: structured app logger (replaces `print`).
- `test/unit/crypto/primitives_test.dart`: NIST/RFC/BIP-39 known-answer
  vectors (FIPS 180-4, RFC 5869, RFC 8018, RFC 7748 §6.1, RFC 8032 §7.1).
- Key zeroization: `ChhayaKeyPair.dispose()`, `Csprng.wipe()`.
- `docs/`, `test/README.md`, CI workflow, CONTRIBUTING, SECURITY, LICENSE.

### Changed
- `ChhayaCryptoEngine` is now a thin facade over `primitives/`; public
  API unchanged for existing callers.
- BIP-39 generation is now spec-compliant (entropy + SHA-256 checksum,
  full 2048-word list) instead of random word picking.
- Version bumped to 14.0.0+1 (app) / 14.0.0 (backend).

## [13.0.0] — V13 SaaS release

- Backend API server (Node.js/TypeScript): auth, contacts, conversations,
  messages, devices, push notifications.
- WebSocket signaling server for WebRTC calls; onion relay server.
- Firebase push notifications (FCM/APNs); PostgreSQL schema + Docker.
- Flutter `ApiService` with offline-first backend sync.
- 18 security vulnerabilities resolved (C1–C4, H1–H5, M1–M6, L1–L4).
- Hacker-terminal dark theme; zero analyzer issues.

## [12.0.2] — V12 security hardening

- Real X25519 ECDH, AES-256-GCM, PBKDF2 account keys.
- `mobile_scanner` pinned to 7.2.0. Biometric gate, secure storage,
  Double Ratchet forward secrecy.
