# Current architecture

Chhaya is a Flutter Android/iOS messenger with a Node/Express API, PostgreSQL persistence, and authenticated WebSocket call signaling at `/signaling` on the same public listener. The repository contains a test product, not a production deployment.

## Account and storage

The onboarding flow creates a BIP-39 recovery phrase. AccountIdentity deterministically derives the X25519 identity used in the public Chhaya ID. KeyManager stores identity roots through platform secure storage; Android uses a Keystore wrapping key and iOS attempts Secure Enclave wrapping with a documented Keychain fallback. Hardware behavior requires device verification.

LocalDatabase uses SQLCipher and encrypted payload columns for messages, contacts, profiles, and ratchet state. Migration versions are explicit. LocalDatabaseSessionStorage adapts persisted ratchet state to the messaging codec. Backup restore validates that the decrypted keypair matches the recovery phrase, then replaces the local account snapshot in one SQLCipher transaction; old ratchets and queued ciphertext are discarded instead of cloned. Keychain/Keystore and SQLCipher are separate stores, so credential rollback is compensating rather than a single cross-store atomic commit. Restored contacts need fresh pairwise session establishment before messaging resumes.

## Messaging path

Settings connects the account to a user-supplied HTTPS origin. Both participants need accounts on the same running server. ApiService performs a single-use identity-possession challenge and stores the resulting opaque session token in secure storage. The backend stores token hashes, expiration, and revocation state. Optional server-side app and panic PIN settings use individually salted scrypt verifiers; the server never needs the PIN after hashing.

Contacts require independent full-ID or QR verification before encrypted direct messages or calls. MessagingService serializes account messaging operations. RatchetMessageCodec derives authenticated message envelopes using the existing ratchet and AES-GCM implementation. Outgoing ratchet advancement, pending plaintext database row, and retry ciphertext commit atomically before transport. Delivery acknowledgments remove the outbox entry atomically with marking the message sent. Receive commits combine plaintext persistence and ratchet advancement.

The API stores opaque envelopes and routing metadata. Foreground polling synchronizes conversations and message history. Stable timestamp/ID database cursors avoid dropping messages with equal timestamps. A retry reuses its exact envelope and message ID. Backend checks enforce active conversation membership and sender ownership.

For message delivery status, an authenticated participant's history fetch records `delivered_at` for newly fetched messages sent by another account. The separate read endpoint records `read_at`; the sender receives these fields during foreground sync. In groups the current timestamp means at least one recipient fetched the message, not that every member received or read it.

HTTP API rate limits use atomic fixed-window counters in PostgreSQL, keyed by an HMAC-SHA-256 of the caller address with the server secret, so raw IPs are not stored and limits survive restarts or are shared by API instances. The request limiter runs before JSON body parsing and fails closed if its database operation fails. Health and metrics endpoints are exempt. This does not make the in-memory WebSocket signaling registry multi-instance; call signaling still needs shared pub/sub or sticky routing and multi-instance validation.

Poll definitions and vote changes are typed payloads inside the same E2EE ratchet envelopes. Clients enforce bounded question/option fields, validate choices against the poll definition, reject votes after the close time, and render aggregate totals from the latest authenticated vote per account. The server sees only ciphertext. Poll history and multi-device vote reconciliation still need real-device validation.

Disappearing-message choices are stored in the locally encrypted settings payload as inherit-global, never, or a duration, keyed by conversation ID. The chosen duration is authenticated inside each message's encrypted payload. These preferences do not synchronize between devices, and the server retains opaque ciphertext until its normal retention policy removes it; no per-message ciphertext deletion job is implemented yet.

Basic group messaging encrypts each message body once with a fresh content key, then wraps that key separately to every verified group member using that member's pairwise ratchet. The sender commits all ratchet advances, the message row, and the exact retry envelope in one local SQLCipher transaction. The server enforces that group participants are active contacts at creation. If a historical envelope lacks a key wrapper for the local account, sync stores a local system marker with the remote message ID so the history gap is visible without displaying ciphertext as text. Membership changes, admin controls, join/leave key rotation, and recipient-side verification/acceptance UX are not implemented; recipients must already have independently verified each sender.

## Calls and optional infrastructure

CallService captures microphone/camera after user action and uses WebRTC. Authenticated WebSocket messages relay encrypted SDP and ICE. Direct chats also send ephemeral typing state over that authenticated channel; the server checks active two-person membership, rate-limits events and does not persist them. Clients expire a remote indicator after six seconds without a refresh. STUN is configured; a separately provisioned TURN server may be needed. Current calls require the app in the foreground. Background ringing, native calling integration, and end-to-end push provisioning are incomplete.

Docker/self-hosting configuration is provided, but no public server, domain, TLS certificate, Firebase project, TURN service, or Apple distribution membership has been provisioned. See self-hosting.md and test-builds.md.

On SIGTERM/SIGINT, the backend stops its cleanup timer, sends WebSocket close frames, waits for HTTP and database connections to drain, and force-closes stragglers after a bounded deadline. Deployment health reports PostgreSQL readiness rather than process-only liveness.

## Deliberately unavailable features

Encrypted inline attachments (up to 256 KB), polls, and basic group messaging are implemented. Group membership administration and device-to-device acceptance/verification remain incomplete. Onion/mesh transports and decentralized file services contain legacy experimental code and are not the active messaging path. PQC wrappers remain gated placeholders; the product must not claim audited post-quantum security. Vault/duress workflows and the full design/accessibility/performance roadmap remain unfinished.
