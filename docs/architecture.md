# Current architecture

Chhaya is a Flutter Android/iOS messenger with a Node/Express API, PostgreSQL persistence, and authenticated WebSocket call signaling at `/signaling` on the same public listener. The repository contains a test product, not a production deployment.

## Account and storage

The onboarding flow creates a BIP-39 recovery phrase. AccountIdentity deterministically derives the X25519 identity used in the public Chhaya ID. KeyManager stores identity roots through platform secure storage; Android uses a Keystore wrapping key and iOS attempts Secure Enclave wrapping with a documented Keychain fallback. Hardware behavior requires device verification.

LocalDatabase uses SQLCipher and encrypted payload columns for messages, contacts, profiles, and ratchet state. Migration versions are explicit. LocalDatabaseSessionStorage adapts persisted ratchet state to the messaging codec. The database and key stores are separate persistence systems; account restore does not yet offer an atomic transaction across both.

## Messaging path

Settings connects the account to a user-supplied HTTPS origin. Both participants need accounts on the same running server. ApiService performs a single-use identity-possession challenge and stores the resulting opaque session token in secure storage. The backend stores token hashes, expiration, and revocation state.

Contacts require independent full-ID or QR verification before encrypted direct messages or calls. MessagingService serializes account messaging operations. RatchetMessageCodec derives authenticated message envelopes using the existing ratchet and AES-GCM implementation. Outgoing ratchet advancement, pending plaintext database row, and retry ciphertext commit atomically before transport. Delivery acknowledgments remove the outbox entry atomically with marking the message sent. Receive commits combine plaintext persistence and ratchet advancement.

The API stores opaque envelopes and routing metadata. Foreground polling synchronizes conversations and message history. Stable timestamp/ID database cursors avoid dropping messages with equal timestamps. A retry reuses its exact envelope and message ID. Backend checks enforce active conversation membership and sender ownership.

## Calls and optional infrastructure

CallService captures microphone/camera after user action and uses WebRTC. Authenticated WebSocket messages relay encrypted SDP and ICE. STUN is configured; a separately provisioned TURN server may be needed. Current calls require the app in the foreground. Background ringing, native calling integration, and end-to-end push provisioning are incomplete.

Docker/self-hosting configuration is provided, but no public server, domain, TLS certificate, Firebase project, TURN service, or Apple distribution membership has been provisioned. See self-hosting.md and test-builds.md.

## Deliberately unavailable features

The current UI does not provide working attachments/polls or encrypted groups. Onion/mesh transports and decentralized file services contain legacy experimental code and are not the active messaging path. PQC wrappers remain gated placeholders; the product must not claim audited post-quantum security. Vault/duress workflows and the full design/accessibility/performance roadmap remain unfinished.
