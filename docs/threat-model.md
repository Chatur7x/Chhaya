# Threat model and release status

This document records intended protections and known limits. It is not an independent security assessment. No zero-bug, production-ready, anonymity, or post-quantum guarantee is made.

## Assets and trust boundaries

Protect recovery words, identity private keys, database keys, message plaintext, ratchet state, and API session tokens. Treat the network, API responses, peer input, and backup files as untrusted. The operating system, platform keystore/keychain, runtime, cryptography dependencies, and installed app binary are trusted components. HTTPS certificate validation protects client/server transport; independent contact verification establishes the intended peer key.

## Implemented protections to verify

- Account registration/login requires a short-lived single-use proof bound to the public key, device, purpose, and fresh server challenge. Credentials and random session tokens are hashed at rest on the server; tokens expire and can be revoked.
- Membership checks restrict conversation messages and signaling. Device IDs cannot be reassigned across users. Message retries verify the existing sender/conversation/content before returning an existing record.
- Direct-message ciphertext authenticates the conversation, message ID, sender, and ratchet header. Tamper, replay, and failed database-commit behavior have automated coverage.
- SQLCipher and encrypted payloads protect database contents at rest. Platform wrapping attempts to protect stored roots. Native SQLCipher and hardware-backed key behavior still require real-device evidence.
- The lock screen fails closed when device authentication fails and no app PIN exists. Enabling/disabling the lock requires native device authentication. The current lock needs further lifecycle/background review.

## Metadata and residual risks

The server can see account IDs, conversation membership, timing, message sizes, and network addresses. WebRTC can expose network information to peers; STUN may use an external provider. There is no active onion/mesh anonymity layer. A compromised device or process with access while unlocked can obtain plaintext. Dart memory wiping is best effort and cannot guarantee removal of runtime copies.

Encrypted backups protect confidentiality under their recovery-derived key, but key/database restore is not fully atomic, and active ratchet state is not yet included in backup. Restoring an existing conversation therefore requires further protocol recovery work. Do not treat backup tests as proof of uninterrupted multi-device messaging. Linked-device enrollment is not a complete authenticated device-transfer protocol.

Disappearing messages currently hide expired local content; remote copies, backups, screenshots, and forensic erasure are not guaranteed. Panic PIN removes local account data and roots only. It does not erase remote recipients or backups. A free Render testing service is live; it is subject to sleeping and database-expiry limits and is not a production availability guarantee.

## Required production gates

Finish unavailable roadmap features; test real Android/iPhone devices and adversarial network/lifecycle cases; verify native storage behavior; complete signed distribution; provision and monitor backend/TURN/push; review backup recovery and device linking; measure accessibility/performance; perform an independent protocol and implementation audit; resolve licensing and operational ownership. Compile/test success does not replace these gates.
