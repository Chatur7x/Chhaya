# Security Policy

## Threat model

Chhaya protects message content and metadata against network observers,
compromised servers, and device coercion:

- End-to-end encryption (X25519 + AES-256-GCM, Double Ratchet)
- Post-quantum hybrid key exchange (X25519 + ML-KEM-1024, V14)
- Onion-routed transport (3-hop, region-diverse circuits)
- No phone number, email, or central identity
- Coercion resistance (duress PIN, decoy vault, V14)

Out of scope: endpoint compromise with unlocked device, rubber-hose
attacks beyond the duress design, quantum attacks against classical
signatures before the ML-DSA migration completes.

## Reporting a vulnerability

**Do not open public issues for security bugs.**

Email the maintainers privately with:
1. Affected version / commit
2. Steps to reproduce (proof of concept preferred)
3. Impact assessment

We aim to acknowledge within 72 hours and ship a fix within 30 days.
Credit is given with reporter consent.

## Cryptography policy

- Only audited primitives: X25519, Ed25519, AES-256-GCM, HKDF-SHA256,
  PBKDF2-HMAC-SHA256, SHA-256/512, ML-KEM-1024, ML-DSA-87.
- No custom ciphers, no ECB, no nonce reuse, no `Random()` for secrets.
- New protocol code (ratchet, handshake, mesh) requires external audit
  before release — see the V14 roadmap.

## Historical issues (V13 entropy disclosure, TASK A1)

1. V13 database-key weakness — **never publicly released.**
   - Location (unreleased dev code on `main`): `lib/core/database/local_database.dart`
     (`_platformBytes` seeded Fortuna from `DateTime.now().microsecond % 256`,
     used by `_randomBytes` for the SQLCipher key in `_getOrCreateDbKey` and
     the AES IV).
   - Evidence: file first added in commit `9920d82` (2026-08-14), after the
     last public release `Chaaya-V5` (2026-05-18). No public tag contains
     `local_database.dart`.
   - Fix: V14 Part 3 derives the 32-byte key via
     `lib/core/database/database_key.dart` (`DatabaseKey.derive` →
     `KeyManager.getDatabaseKey()`), fresh `chhaya_v14.db`; legacy V13 data
     is not migrated (pre-release, weak legacy key).

2. Pre-V1.0.4 released weak RNG (fixed before V14) — **was in public APKs.**
   - Location: `frontend/lib/core/crypto/signal_protocol_service.dart`
     (Fortuna seeded from `DateTime.now().microsecondsSinceEpoch + i` for
     ephemeral X3DH keys, the placeholder shared secret, and AES-GCM IVs).
   - Present in tags `v1.0.0`, `Chaaya-Relase-V1.01`,
     `Chaaya-Release-V1.0.2`, `Chaaya-Release-BetaV1.0.3`,
     `Chaaya-Release-BetaV1.0.4`, `Chaaya-Release-V1.1` (all had public APKs).
   - Fixed in commit `fd755ba` (2026-04-25, "V1.0.4 — Critical crypto fixes")
     using `Random.secure()` seed material; verified absent in tags
     `Chaaya-V1.0.4` and `Chaaya-V5`. Recommendation: anyone still on a
     pre-V1.0.4 APK should upgrade; sessions from those builds should be
     considered suspect.

3. Known placeholder (not key material, flagged for a later part):
   `lib/ui/screens/contacts/contacts_tab.dart` fabricates a 66-char hex
   placeholder pubkey from `DateTime.now().microsecond` when empty.
