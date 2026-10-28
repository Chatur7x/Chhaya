# Security policy and current claims

Chhaya is an in-progress privacy-focused messenger. This document describes the checked-in implementation, not a certification or guarantee of protection from state-level attackers.

## Current implementation

- Direct message bodies are encrypted on-device with AES-GCM. Session setup currently uses X25519 over account identity keys, followed by Chhaya's custom Double Ratchet and a deterministic HKDF epoch chain.
- Contacts must be marked verified locally before ratchet sessions can be used. Users can scan a contact QR or compare the full identity through a trusted channel. Verification depends on the user making that comparison correctly.
- The normal delivery backend stores encrypted message envelopes and can observe account IDs, conversation membership, sender, IP address, request timing, delivery activity and message sizes.
- Group messages create a fresh body key for the message and wrap it for each current member. This does not make previously delivered group history disappear after a member is removed.
- SQLCipher and platform secure-storage integration exist, but native at-rest encryption and key-wrapping behavior still require physical-device evidence on each platform.
- ML-KEM/ML-DSA native primitives exist in the repository. They are not currently integrated into the live session-establishment/message path. Chhaya therefore does not claim post-quantum protected conversations.
- The onion router is experimental and not used by the normal API messaging path. Chhaya therefore does not claim onion anonymity or IP-address protection.
- Panic PIN, capture prevention, duress safety, secure deletion and memory clearing have platform and endpoint limitations and are not absolute guarantees.

See [the delivery checklist](docs/delivery-checklist.md) and [the competitive security analysis](docs/security-competitive-analysis.md) for status, evidence gaps and comparison context.

## Threat-model limits

E2EE is intended to protect message content from passive network observers and the delivery server when the implementation and identity checks operate correctly. It does not by itself protect against compromised/unlocked endpoints, malicious or coerced recipients, screenshots or external cameras, traffic analysis, account/device takeover, abusive contacts, or denial of service. No independent cryptographic protocol audit, mobile penetration test or production operations review has been completed for this version.

Do not use Chhaya as a claimed intelligence-agency, military, clandestine-operations or state-adversary protection system. There is no relevant certification or deployment evidence in this repository.

## Reporting a vulnerability

Please do not publish exploitable security issues before maintainers can investigate. Send the affected version/commit, reproducible steps and impact through a private maintainer contact established by the project. Do not include real users' private data.

## Cryptography changes

Do not add custom cipher or key-exchange designs as a feature shortcut. Any protocol change requires a versioned specification, test vectors, replay/downgrade/state-rollback analysis, Android and iOS native tests, independent security review and updates to the claims above. Primitive availability in a dependency is not evidence that the application protocol uses it securely.

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

3. Historical placeholder (not key material): an earlier version of
   `lib/ui/screens/contacts/contacts_tab.dart` fabricated a 66-character
   placeholder public key from the current time when empty. The current
   contact flow validates an actual Chhaya ID instead.
