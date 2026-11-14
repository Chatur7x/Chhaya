# Ponytail release audit — 29 October 2026

What this repo does: Chhaya is a Flutter encrypted messenger backed by an authenticated Node/PostgreSQL service. This review assumes ordinary users with growing chat histories, unreliable mobile networks and multiple devices. It assesses readiness for the requested public Version 15 release; it is not an independent cryptographic audit.

## Must fix

1. **Windows cannot use the mobile database path.**
   - What this is: `lib/core/database/local_database.dart` opens production storage through sqflite_sqlcipher. `windows/flutter/generated_plugins.cmake` registers no SQLCipher implementation.
   - Problem: a Windows build is not evidence that account storage can initialize and persist securely.
   - Fix: implement a supported encrypted Windows database opener, then test creation, restart, wrong-key rejection and restore on Windows.
   - If we skip it: desktop account and backup flows cannot be promised to work.

2. **Linked devices are not an enrollment protocol.**
   - What this is: `lib/services/auth/auth_service.dart::generateDeviceLinkCode` generates a public-key QR payload.
   - Problem: the function does not persist the generated private linking key or establish authenticated key transfer, device approval or revocation.
   - Fix: implement a complete authenticated enrollment flow with expiring requests and per-device sessions before presenting linking as functional.
   - If we skip it: scanning a code cannot provide the requested synchronized desktop account.

3. **PQ primitives are not live PQ messaging.**
   - What this is: `lib/core/crypto/ratchet/spqr.dart` derives epochs deterministically from an existing seed; its comments explicitly require a future fresh KEM contribution.
   - Problem: passing AWS-LC primitive tests does not establish authenticated PQ session negotiation or fresh PQ ratcheting in the messenger.
   - Fix: specify and review authenticated key distribution, negotiation, downgrade handling, fresh contributions and migration, then integrate and test them end to end.
   - If we skip it: advertising quantum-resistant messaging would exceed the implemented protocol.

4. **Onion and offline mesh controls have no operational transport.**
   - What this is: `lib/ui/screens/settings/settings_screen.dart` deliberately disables both switches and reports unavailable transport.
   - Problem: enabling a switch cannot create deployed relays or a native BLE transport.
   - Fix: implement and test each transport with its own authentication, lifecycle and leak tests before enabling the control.
   - If we skip it: users cannot send over the requested privacy/offline networks.

5. **Call connection readiness has a race.**
   - What this is: `lib/services/call/call_service.dart::ensureConnected` returns when `_socket` is non-null before checking `_connecting`; `_connect` assigns `_socket` before awaiting the authenticated join.
   - Problem: a second typing/call action can send before the first join finishes.
   - Fix: await an in-flight connection before accepting the socket as ready; add a delayed-join regression test and isolate old socket close callbacks from a new connection.
   - If we skip it: intermittent signaling failures remain possible during connection/reconnection.

## Should fix

6. **Sync work grows with the entire local history.**
   - What this is: `lib/services/messaging/messaging_service.dart::sync` calls `getMessages` for every conversation; `getMessages` decrypts every stored row.
   - Problem: periodic foreground synchronization repeatedly decrypts old history as accounts grow. The recent UI filtering fix does not remove this storage cost.
   - Fix: use bounded metadata/cursor queries for synchronization and paginated display, preserving receipt reconciliation and recovery behavior.
   - If we skip it: larger accounts can remain slow and consume battery.

7. **The disappearance picker lacks a clear unlimited option.**
   - What this is: the global duration picker offered only positive durations and unconditionally enabled its switch after saving.
   - Problem: users looking in the picker could not select Never; leaving the screen during the write could call setState after disposal.
   - Fix applied: added Never with duration zero and a mounted check; switch state now follows the stored duration. Static analysis passes.
   - If we skip it: confusing settings and a lifecycle error remain.

## Existing verification and boundaries

The preceding work verified Android native SQLCipher/StrongBox/PQ primitives on one Pixel 8a, backend integration, public HTTPS/WSS client flows and build CI. Profile editing has since passed five account/profile/backup tests. These results do not establish all-device or full-roadmap correctness.

Verdict: not ready to label Version 15 complete. Resolve desktop storage, authenticated linking, protocol integration and real-device calling/messaging acceptance before publication as a final product.

Not checked: every one of the 127 features end to end; independent cryptographic review; Windows runtime; two-phone calling/NAT and push; iOS native runtime; production load; complete dependency/license inventory; relay deployment; full UI accessibility. This is a prioritized release-path audit, not a claim that every repository file was read. Remaining checklist items retain their existing status.

## Follow-up: call-path tracing

- Fixed the signaling readiness ordering: concurrent callers now wait for the pending authenticated join before reusing the socket. Old socket close/error callbacks cannot clear a replacement socket. Static analysis passes; a delayed-join regression test remains required.
- Found and fixed missing block enforcement in the shared call peer lookup. Both contact-record blocking and the persisted block list now reject calls before signaling/media access. Two new regression tests pass.
- Native audio/video, background ringing, reconnect and cross-network calls are not established by these tests. No new full-repository or 127-feature completion claim is made.

## Follow-up verification: authenticated signaling and socket lifetime

The delayed-join regression now passes: two concurrent client actions share one connection and neither completes before the authenticated join response. The client accepts an injectable socket factory solely to exercise that boundary without opening microphone/camera streams. All six call service/window tests pass, and targeted analysis reports no issues.

A separate server defect was found in `backend/server/src/signaling.ts`: the heartbeat removed stale/unauthenticated sockets from bookkeeping but did not terminate the network connection. The heartbeat now terminates them. A real WebSocket regression waits for the production 15-second heartbeat and verifies disconnection. All 18 backend tests pass against disposable PostgreSQL, with zero skips; npm audit reports zero vulnerabilities.

The isolated Android preview was rebuilt, installed with `adb install -r` and launched on the connected Pixel 8a. It includes profile editing, explicit Never retention and the call fixes. The running process was verified after launch. Existing account packages were preserved. Installation/launch is not a two-phone call, profile UI acceptance or all-feature device test.

Pipeline review covered CI, Android, iOS and PQ native workflow definitions. Existing CI covers Flutter analysis/tests, backend tests/advisories/SBOM and isolated database restore. Android compiles debug/release; iOS exports unsigned developer builds. There is no Windows runtime pipeline or automated two-phone native acceptance suite. Missing pipeline/device coverage remains a release blocker, rather than a passing feature check.

## Follow-up: corrupt session state must not restart a ratchet

`LocalDatabase.loadSessionBlob` returned null when a present encrypted blob failed authentication. `LocalDatabaseSessionStorage.loadSession` also returned null for malformed JSON or state. `RatchetMessageCodec._state` interprets null as permission to derive a new initial session from the existing identity keys and conversation. Resetting deterministic initial state can reuse initial message key/nonce material. Both persistence paths now distinguish absence from corruption and throw on corruption. Five new checks cover absence, malformed JSON, malformed state, and authenticated database-field tampering. The combined database/session/messaging suite passes 46 tests; targeted analysis passes.

Remaining related blocker: backups clear old ratchets/outboxes but retain the account identity and conversations. Safe re-establishment requires a fresh authenticated session generation with peer coordination, not silently deriving the old initial state again. Existing restore round-trip tests do not verify this protocol property. This finding prevents marking backup-to-resumed-conversation acceptance complete. No protocol migration or live PQ completion is claimed.

## Backup file workflow follow-up

The prior checklist described file export but the settings flow only copied encrypted text. Settings now offers explicit encrypted file export; onboarding can choose an encrypted backup file. Reads are bounded at 16 MB and reject invalid UTF-8/empty input. Windows save dialogs return a path rather than writing the supplied bytes, so desktop explicitly writes the selected file. Eight file/recovery tests pass, including a real temporary-file write with a simulated picker. Android/iOS picker and restore UI remain unverified, and peer-coordinated post-restore session recovery remains incomplete.

## Database key identity review

`LocalDatabase.init` derives its database key using the secure-storage Chhaya ID when present, otherwise the fixed local owner ID. `AuthService.createAccount` and phrase restore do not write that secure-storage ID, and the only production `storeChhayaId` call found is rollback of a previously existing value. Consequently the current account flow ordinarily uses the installation master secret with the fixed local owner context; the requested per-user derivation is not established. Do not simply start writing the ID: changing the derivation context for existing installations would make existing encrypted databases unreadable without an explicitly tested migration. Preserve existing data and design a crash-safe migration before claiming requirement 43 complete.

## Desktop backup overwrite safety

Desktop save dialogs return a path and require the application to write the backup. The original implementation wrote directly to that path, which could truncate an existing backup if writing failed. Export now writes and flushes a temporary file in the destination directory before renaming it to the selected path; temporary files are removed on failure. On Windows, tests passed for first save, replacing an existing file, failed replacement preserving an existing destination, and cleanup, plus bounded/invalid import handling. Mobile save remains delegated to the operating-system picker and still requires device acceptance evidence.

## Windows build attempt

On 29 October 2026, `flutter build windows --debug` reached CMake but failed: generated plugin configuration references `flutter_sound_plugin`, while the installed `flutter_sound` 9.30.0 Windows CMake defines `taudio_plugin` and its native handler implements only a platform-version method. This is an upstream Windows implementation mismatch, not evidence of a usable voice feature. Fixing generated files or adding a dummy target would only conceal the absence of recording and playback. A replacement must support real recording and playback on Android, iOS and Windows, preserve bounded recording, cleanup, privacy and AAC interoperability, and be tested on devices. SQLCipher Windows support remains a separate runtime blocker. Build did not produce a usable Windows app.

Potential candidates require evaluation rather than blind substitution: `record` documents AAC capture on Android/iOS/Windows (https://pub.dev/packages/record); `audioplayers` documents Windows support (https://pub.dev/packages/audioplayers). Verify actual container/codec compatibility, temporary plaintext behavior, dependency licenses and platform tests before migration.


## Voice and Windows follow-up

Replaced `flutter_sound` (whose Windows implementation was a placeholder and prevented CMake generation) with `record` 7.1.2 and `audioplayers` 6.5.1. AAC ADTS recording is bounded in memory; the existing `audio/aac` message representation remains unchanged. Android and Windows use in-memory playback; iOS/macOS/Linux playback uses an app-owned temporary file because this player package otherwise creates an unmanaged cache file. Files are removed on stop, completion, background and disposal, with narrowly scoped stale-file cleanup at next startup; a crash may leave the file until then.

On Pixel 8a / Android 17, a native integration test captured AAC ADTS using the microphone and completed playback. It used in-memory audio only, restored the ordinary verification APK, and restored the previously denied microphone permission. The test did not send audio to a peer or establish iOS/Windows compatibility. Widget tests cover recording-to-attachment, denied microphone permission and oversize cancellation; cleanup and messaging payload tests pass. The Windows build moved beyond the original audio CMake failure but local compilation then failed because the installed Visual Studio Build Tools lack ATL (`atlstr.h`); current shell is not elevated. A Windows 2022 GitHub build workflow was added to exercise the build on a runner with ATL. Windows SQLCipher remains separately unimplemented, and iOS capture/playback still needs device evidence.


## Windows encrypted storage implementation

Windows now chooses an FFI database opener backed by the SQLCipher native asset (`sqlite3` hooks select SQLCipher on Windows and the ordinary SQLite asset elsewhere). It validates the key format, applies it before schema access, requires a nonempty `cipher_version`, and enables the same memory/journal settings. The database lives in the app-specific support directory; no old database is migrated or deleted. A Windows-native test created encrypted files in a disposable temporary directory, verified an encrypted header, rejected unkeyed SQLite and an incorrect key, reopened with the correct key, and exercised LocalDatabase contact persistence across restart. The combined database, auth and messaging run passed 59 tests. The Windows CI workflow now includes this native storage test. Full app startup, Windows Credential Manager/DPAPI behavior, production distribution, real accounts and cross-device linking still need verification. The fixed local-owner context and backup session re-establishment findings remain open.

The previous full Flutter CI run for the audio migration failed analysis on an existing public test-constructor initializer lint. Its argument names are part of test callers, so the lint is locally suppressed with a reason; targeted analysis passes. The next CI run must verify this against its pinned Flutter version.

Windows storage follow-up: database open and explicit destruction now resolve the same app-specific path and use the Windows FFI factory. A native test destroyed only a disposable test database and confirmed a neighboring encrypted test file remained. This tests the database operation only, not a real account logout or panic-PIN flow.

GitHub Actions Windows run 40866770193 at commit 8a534cf successfully built the debug desktop app, ran the voice widget/cleanup and native Windows SQLCipher tests, and uploaded a developer build. This build has not been launched against an isolated Windows account, and it is not a signed release or end-to-end desktop acceptance result.

GitHub Actions iOS run 40866770191 at commit 8a534cf built and uploaded an unsigned debug developer build and passed Flutter analysis and tests on the macOS runner. This does not establish iOS signing, installation, native security, microphone/camera, calls, or cross-device behavior.

An Android debug build can opt into a separately named acceptance package using a validated `CHHAYA_ACCEPTANCE_INSTANCE`; ordinary debug and release package IDs remain unchanged. On 29 October 2026 `com.chaaya.app.chaaya.acceptance_oct29a` was installed on the Pixel 8a for `integration_test/native_security_test.dart`. All three tests passed: native wrapping reported StrongBox and rejected tampering, SQLCipher reported 4.10.0 and rejected plaintext opening while reopening the disposable encrypted database, and AWS-LC reported 5.11.0 and passed ML-KEM/ML-DSA primitive and corruption checks. These are native primitive/storage checks, not post-quantum session establishment, an independent audit, or a two-device acceptance test.

**Data-loss incident:** after that run the existing `com.chaaya.app.chaaya.verification` package was no longer listed, including with `pm list packages -u`; the main `com.chaaya.app.chaaya` package is still installed. The verification package previously contained an account, and its data may have been deleted; recovery has not been established. Inspection of Flutter's integration-test runner shows it captures the application package from an existing APK before rebuilding and, by default, uninstalls that captured package at test teardown. The existing build artifact was the verification APK, whereas the test built and ran the newly suffixed acceptance APK. This is the likely cause, though device logs do not independently prove the exact uninstall event. Do not run Flutter integration tests against the device again without checking the cached APK identity and disabling automatic uninstall; do not reinstall or reset the missing package until data recovery is assessed.

The main Chhaya package is present in Android's private-space user (11); the missing verification package is not listed for either device user. The manifest disables Android automatic backup. A filename search of the workspace, Windows Downloads/Documents and the phone's Download/Documents found no Chhaya backup file; this does not rule out backups elsewhere or recovery information held by the owner. `scripts/run_android_acceptance.ps1` now refuses an existing acceptance package, builds and validates the cached APK package ID, and passes `--no-uninstall` to the test runner. Its existing-package refusal was tested without modifying the phone. This is a safeguard, not evidence that lost verification data has been recovered.

## Sync storage performance — 30 October 2026

Addressed the repeated local-history decryption in finding 6. Schema migration 6 adds a content-free message index inside SQLCipher. Existing message ciphertext is preserved; initialization backfills metadata in batches of 20, retaining unreadable rows rather than deleting them. Message writes, ratchet/outbox commits and index updates share transactions. Expiry cleanup removes both messages and queued envelopes. Snapshot restore and explicit conversation/message deletion also maintain the index; downgrading the index migration preserves encrypted messages.

Sync checks known IDs only for the current server page (at most 200), reconciles outgoing receipts by message ID, and decrypts the latest valid message for the preview. Retry reads only unsent messages. Regression tests cover legacy backfill, corruption preservation, expiry/outbox cleanup, scoped/parameterized lookup, atomic rollback, receipts and the absence of full-history calls in sync/retry. Database, messaging, native Windows SQLCipher, recovery and benchmark checks passed 43 tests; targeted analysis passed.

`flutter test tool/benchmarks/local_sync_test.dart` uses a disposable Windows SQLCipher file. In the debug test run with 40 synthetic 16 KiB attachments, the median full-history read was 1590.892 ms; known-ID + pending + latest lookups took 55.219 ms. This is a local storage comparison, not Android UI, network, battery, release-mode or production-load evidence. An earlier larger run (200 × 64 KiB, five samples) exceeded its three-minute test limit and yielded no usable timing; its disposable file was removed after the process exited.

Still open: initial legacy backfill cost, paginated chat display, local search/poll-history scans, repeated network history fetches and physical-device performance.

## Backlog paging after a local send — 30 October 2026

Confirmed a sync defect where one known message in the newest page stopped pagination, hiding an older incoming message after an offline backlog and a recent local send. The direct-message regression failed before the fix (one page fetched instead of two). Direct and group sync now stop at a fully known page rather than any known row. The regression decrypts two real direct envelopes in chronological order around a 201-row history; the group regression preserves an older unavailable-key marker. The messaging suite passed seven tests and targeted analysis passed.

This fixes the demonstrated overlap case. A fully known page still does not prove there are no older gaps from earlier interrupted or failed syncs, and the existing 50-page cap remains. Durable forward checkpoints, explicit incomplete-history reporting and large-backlog/ratchet-limit recovery still need implementation and acceptance tests. No general reliable-messaging completion claim is made.

## Real-backend regression — 30 October 2026

At commit 5b2ebcf, `live_account_connection_test.dart` and `live_messaging_flow_test.dart` both passed against the actual loopback Node service and the disposable `chhaya_test` PostgreSQL database. Coverage includes authenticated account connection, bidirectional direct messages, server-accepted/lost-acknowledgement retry with one stored/received message, injected offline queue retry, encrypted 4 KiB attachment transfer, three-client group messages/polls, membership removal and denied access for the removed member. Local client databases in this test are in-memory FFI databases; this does not prove physical-device restart, native SQLCipher or actual airplane-mode behavior. GitHub CI for 5b2ebcf also passed Flutter analysis/tests, backend lint/tests and the database backup/restore drill. Platform builds for that commit are tracked separately.

## Communication and cryptography requirement assessment — 30 October 2026

Requirements 1–25 now have explicit implementation categories and source/acceptance notes in the 127-row ledger. Unassessed rows remain visibly pending, and no row is release-verified. Primitive presence is assessed separately from the requested live protocol and native-platform behavior.

The PQ establishment helpers need more than wiring into the messenger. `Pqxdh.establish` discards the ML-KEM encapsulation ciphertext and returns only the combined secret and ephemeral X25519 public key; a receiver has no returned KEM ciphertext to decapsulate. `DualKem.establish` likewise returns only the combined secret and discards both encapsulation ciphertexts. These helpers are referenced in tests, not the live messaging path. Neither provides authenticated reciprocal transcript negotiation or a complete deployed session handshake. A real protocol design must address those omissions, prekey/device authentication, replay/downgrade protection and recovery; changing comments or declaring the primitive provider available cannot complete them.

The native PQ plugin declares Android and iOS only; there is no Windows plugin registration in `packages/chhaya_pqc/pubspec.yaml`. Android builds outside arm64 explicitly use an unavailable-provider stub. The Windows app build therefore does not prove Windows PQ primitive availability. These platform gaps are recorded on requirements 19 and 20.

On 30 October 2026, ADB reported no connected device. No new physical-device test or installation was attempted for the sync-index changes. The earlier missing verification-package recovery remains unresolved.

## Authentication responsiveness

Credential hashing and verification previously used synchronous scrypt on the Node event loop, delaying unrelated requests during registration, login or PIN updates. These operations now use asynchronous scrypt with the same salt and hash format; registration computes the hash before opening its database transaction. A compatibility test verifies an existing synchronous-format hash, and an event-loop test verifies derivation does not block a scheduled callback. The backend suite passed 19 tests against a disposable PostgreSQL database, including real registration, login and PIN storage. This does not establish throughput under load: the shared crypto worker pool and authentication rate limits still need load testing.

The current debug verification APK was installed with `adb install -r` and launched on the Pixel 8a on 29 October 2026. This was an upgrade of the isolated verification package, not a clean-install, release-signing or full acceptance test; existing app data was not cleared.

## Server settings acknowledgement

The settings endpoint accepted read-receipt, disappearing-duration, onion-routing and notification values but ignored them and returned success. It now rejects requests containing those unsupported server settings before applying any other fields. Database-backed tests cover each unsupported value and confirm a mixed request does not partially change biometric settings. This avoids a false success; the missing server-side functionality and its end-to-end behavior remain unfinished. Local per-chat privacy controls are separate and are not established by this endpoint test.

## HKDF expand bound

The custom HKDF-Expand helper did not enforce the one-byte block counter limit in RFC 5869. It now rejects requests above 8,160 bytes for SHA-256; existing ratchet callers request much shorter outputs. Tests cover the RFC expand vector and the maximum and first invalid lengths, alongside the existing primitive and ratchet tests (31 passed). This is a primitive-level check, not an independent review of the messaging protocol.

## Contact profile verification label

The contact profile derived its verification label from a separate numeric level and defaulted to level 3 while the contact was loading. It could therefore show “Verified” even when the locally stored `isVerified` flag was false. The label and color now follow the flag used by messaging authorization, with an unverified state while the contact is unavailable. Widget tests cover a level-3 contact with each flag value. This only corrects the display; independently authenticated device and contact verification still need end-to-end security review.

Own-profile editing previously saved the display name only in the local profile. The authenticated server endpoint now updates the account name, and online profile editing requires that request to succeed before saving locally. Widget tests cover successful save and server failure; database-backed API tests cover authorization, validation, account isolation and the name returned in a group conversation. The edit dialog also no longer disposes its controller before the closing transition completes. Local-only accounts can still edit locally. Existing peer contact aliases are preserved by sync, so this change does not prove names update on other devices. Offline edits for connected accounts, cross-device conflict resolution, server-success/local-write-failure recovery and device acceptance remain open.

After deployment, an unauthenticated request to the Render profile endpoint returned 401, showing that the endpoint is present and authentication is required; it did not test a live account edit. The debug verification APK containing this UI was installed with `adb install -r` and launched on the Pixel without clearing data. The profile edit was not performed on the user's account.

## Hybrid PQXDH client helpers (WS2) — 8 November 2026

Implemented the Dart-side client protocol helpers from `docs/spec-pq-hybrid-resync-v1.md` §5 WS2 (§3.0–§3.6), behind no feature flag yet — nothing is wired into the codec or messaging paths. Verified on this Windows dev machine; the native AWS-LC path was NOT verified (test skips with reason).

- `lib/core/crypto/pqc/transcript.dart` (new): canonical LP transcript encoder `T` (spec §3.3, both peers compute identical bytes), `SHA256(T)` salt, `SK = HKDF-SHA256(0xFF*32 ‖ DH1‖DH2‖DH3[‖DH4]‖SS, salt=SHA256(T), info="Chhaya-PQXDH-v1"‖suite_string)`, and the domain-separated consented-classical fallback `"Chhaya-Classical-Fallback-v1"` (spec §3.4). `buildEstablishmentTranscript` binds the fixed v2 constants; it is the only T assembly in `lib/` (enforced by the static gate).
- `lib/core/crypto/pqc/negotiation.dart` (new): suite registry (`chhaya-pqxdh-v1`, `chhaya-classical-consent-v1`), highest-common selection (spec §3.5 rule 2), full offer-echo verification (rule 3), state machine with terminal abort, AEAD-failure hard abort with SK wipe, classical selection refused unless PQ is unavailable AND consent is explicit, downgrade-retry assertion. Client protocol range is exactly v2.
- `lib/core/crypto/pqc/prekey_bundle.dart` (new): fail-closed parser/verifier for WS1's bundle JSON (`GET /prekeys/:userId/bundle`): structure (missing/extra/type-confused fields reject), `lastResortUsed` invariant, Ed25519 signature verification of every present signature (SPK, PQSPK, one-time prekeys, reseed KEM key), 7-day/30-day validity window enforcement, expired/not-yet-valid rejection. Signature preimages follow SD-1 (LP encoding, u64be ms epochs) and are review-pending.
- `lib/services/api/prekey_bundle_client.dart` (new): the only new network path, invoked explicitly; no automatic retries; 404/409/503/401 and malformed bodies all throw, never guess.
- `lib/core/crypto/pqc/pqxdh.dart` (modified): `Pqxdh.establish` no longer discards the ML-KEM encapsulation ciphertext (returns it, nullable on the consented classical path). New `establishHybridV2` / `acceptHybridV2` (initiator/responder) derive the identical SK from public material plus own keys; not referenced by production messaging (WS3 wires it).
- `scripts/check_transcript_binding.py` (new): static gate implementing spec §6 criterion 14 (canonical-builder singularity, v2-path HKDF salt/info binding, boundary-string confinement, production-messaging PQ import denylist). Exits 0; not yet wired into CI (WS5, lead edit).

Test counts (`flutter test`): 78 new tests — `transcript_test` 16 (golden T/salt/SK vectors, both-peers SK equivalence, ≥1000-mutation T-tamper property test), `negotiation_test` 20, `pqxdh_v2_test` 9 (round-trip SK agreement, AEAD-under-SK with `header‖T` AD, wrong-echo abort, one-attempt-only retry assertion), `prekey_bundle_test` 19, `prekey_bundle_client_test` 14. `flutter test test/unit/crypto/` 172 passed (~1 skip-with-reason). `flutter test test/unit/` 383 passed. `flutter analyze lib test` — No issues found. `python scripts/check_transcript_binding.py` — exit 0.

What this does NOT establish: independent cryptographic review; any PQ claim; WS3 integration (v2 helpers are unused by the codec — no user-facing messaging path changed); native AWS-LC ML-KEM round trip on this host; AEAD on a live session; bundle signature byte-encoding until SD-1/SD-3 review passes; reseed/ratchet redesign. The external-review gate (spec §7) is unchanged and still blocks default-on and any claim. CSV and delivery-checklist statuses untouched.

NOT verified: Android arm64/iOS native AWS-LC paths (Windows host has no provider); real server bundle fetch against a live backend; Windows consent dialog (WS6); the negotiation flight over the wire (WS3); CI wiring of the static gate.

Verification commands (exact): `flutter analyze lib test` — No issues found; `flutter test test/unit/crypto/` — 172 passed (~1 skip-with-reason); `flutter test test/unit/crypto/pqc/` — 85 passed (~1 skip-with-reason), incl. 78 new; `flutter test test/unit/` — 383 passed; `python scripts/check_transcript_binding.py` — exit 0.

## Slice A: adversarial delivery retry, replay, rollback and restore coverage - 8 November 2026

Tests added (all pass):
- `test/unit/crypto/ratchet/replay_skip_limit_test.dart` (7 tests): replayed envelope rejected with persisted session unchanged; tampered body/header rejected without advancing the session; out-of-order envelopes within the skip window are served from the skipped cache and consumed keys are single-use; a gap of exactly 1000 (DoubleRatchet.maxSkip) is served; a gap of 1001 throws TooManySkippedException with the persisted session intact (message 1001 still decryptable); an envelope older than the receive counter is rejected as too old.
- `test/unit/messaging/delivery_adversarial_test.dart` (4 tests): server accepts but the local sent-marker commit crashes (StateError) - retry re-sends the byte-identical envelope/messageId and converges to one stored message and a cleared outbox; two MessagingService instances retry the same outbox row concurrently (20 ms wire delay, server-side exact-retry dedup) - at most one acceptance, identical bytes on the wire; a pending message whose outbox envelope is missing is never re-sent (pinned, skipped silently); sync does not store an undecryptable remote envelope (pinned, swallowed silently). Server-side dedup semantics are simulated at the HTTP layer (200 identical retry / 409 conflicting reuse), mirroring backend/server/src/routes.ts POST /messages.
- `test/unit/database/restore_resume_test.dart` (4 tests): protocol pin - two initial sessions derived from identical inputs are byte-identical (root key, send/recv chains, SPQR seed, public keys); initiator-role restore re-derives the byte-identical initial session (root key, send chain, public key, SPQR seed all reused; sendCounter resets to 0) - pinned dangerous defect; the non-restored peer rejects the replayed counter-0 first message (RatchetException: duplicate or over-delayed) and its session is untouched; a restored unsent message is stuck pending forever (its outbox envelope is deleted by replaceAccountSnapshot).
- `test/unit/database/interrupted_delivery_test.dart` (2 tests, Windows-gated, executed on Windows against real SQLCipher files): an unsent outbox survives an encrypted-file restart (message pending, exact retry envelope intact); a message_sync_index row deleted to simulate a partial index write is rebuilt by the init backfill, recovering the pending message and envelope.
Full unit sweep: `flutter test test/unit/` - 303 tests passed. `flutter analyze lib test` - No issues found.

Defects found / pinned (file:line):
1. Restore re-derives the deterministic initial session for the INITIATOR role: byte-identical root key, send chain, ourPublicKey and SPQR seed, message number restarts at 0, so early-message key/nonce derivation is reused after a restore (lib/services/messaging/ratchet_message_codec.dart:20-37, lib/core/crypto/ratchet/double_ratchet.dart initSession, lib/core/database/local_database.dart:915 replaceAccountSnapshot). Fresh entropy enters only via the responder's first-send DH ratchet; the SPQR seed is identical in both roles (lib/core/crypto/ratchet/triple_ratchet.dart:113-117). This is the known dangerous failure mode, now pinned by test; it is NOT acceptable design and NOT officially supported.
2. A restored initiator's post-restore messages replay already-consumed counters (n=0); a peer that did not restore rejects them as duplicate/over-delayed. The conversation is effectively broken until both sides lose state again; sync swallows the failure (messaging_service.dart:536-538) with no user-visible signal. Backup-to-resumed-conversation acceptance CANNOT be claimed; a fresh, authenticated, peer-coordinated session generation is required and does not exist.
3. A restored unsent message is stuck pending forever: replaceAccountSnapshot deletes ratchet_session/outbox:* (local_database.dart:936-944) while keeping the isSent=false row, and retryPending (messaging_service.dart:308-316) silently skips pending messages with no outbox envelope.
4. Pinned gaps, no surfacing (unchanged behaviour): retryPending silently skips pending messages with a missing envelope; sync catch-all swallows malformed/over-limit envelopes (messaging_service.dart:475-478, 536-538) - no durable forward checkpoint, repeated silent re-failure per sync.
5. Test-harness pitfall: multiple LocalDatabase instances on sqflite_common_ffi inMemoryDatabasePath SHARE one in-memory database unless OpenDatabaseOptions(singleInstance: false). The restore tests isolate instances that way (mirrors test/integration/live_messaging_flow_test.dart).

Backend deliverable: NOT executed here. No PostgreSQL reachable, no psql, Docker Desktop daemon unavailable (docker ps fails to connect). The backend exact-retry/dedup implementation (backend/server/src/routes.ts POST /messages: id-conflict 409 / identical 200) and the group membership race regression (backend/server/test/api.test.cjs, exact-retry-after-removal and concurrent removal/send blocks) were read but not run. Flutter-side tests simulate server dedup at the HTTP layer instead. The backend harness (backend/server/test/local_api_server.cjs with the disposable chhaya_test DB) remains the way to run those; it needs a local PostgreSQL that is not present on this host.

CSV: docs/feature-verification-127.csv - evidence-column notes appended for IDs 1, 77, 80, 81, 87 (2026-11-08); all 127 IDs retained; no release_status flipped; other rows untouched.

NOT verified: physical device / two-phone acceptance; Android or iOS runtime behaviour; the Windows-SQLCipher restart tests are Windows-only (not run elsewhere); restore-to-resumed-conversation acceptance (pinned as defect - explicitly NOT claimed); backend/live tests in this environment; PQ protocol flows (out of scope); independent security review; 30-second retry scheduling.

Verification commands (exact): `flutter analyze lib test` - No issues found; `flutter test test/unit/messaging/ test/unit/database/` - 59 passed; `flutter test test/unit/crypto/` - 94 passed (incl. the 1M-message fuzz); `flutter test test/unit/` - 303 passed.

## WS3 — Hybrid session establishment & post-restore resync — 8 November 2026

Implemented the client half of `docs/spec-pq-hybrid-resync-v1.md` (WS3 block). The v2 path is compiled, wired and unit-tested but **not enabled** anywhere: `chhaya_pq_hybrid_v1` defaults off, no UI flips, no claims shipped. The deterministic identity-ECDH `_state` path is deleted (spec §3.11); without the flag a fresh conversation fails closed rather than reusing old material.

What changed (high level):

- `ratchet_message_codec.dart` — `_state` deleted. v2 establishment runs behind lazy `chhaya_pq_hybrid_v1` flag. AEAD additional data for v2 sessions is `msgAad‖header‖T` (transcript bound, spec SD-4). v2 envelopes carry `establish` (PQXDH flight) and `echo` (offer echo); v1 envelopes and retrace-only fallback preserved for legacy.
- `messaging_service.dart` — initiator: on restore, sends `chhaya-resync-v1` as a first-class ratchet message before any user content; holds outbound messages until a valid v2 inbound (the peer's ack). Responder: adopts the resync, drops the stale session, sends DH-first ACK. Stuck pending messages are re-created from DB content with **fresh messageIds** after the ack (`§3.7.5`). `_deliver` paths reused; no transport semantics changed.
- `local_database.dart` — `replaceAccountSnapshot` now writes per-conversation `session_resync_pending` kv with a fresh `restore_generation` (uuid). `session_generation` monotonic u64 dual-stored SQLCipher kv + keystore (keystore first, then kv) with fail-closed rollback detection → forced resync marker + stale session wipe. additive kv/plainkeys only; no data rewritten.
- `session_state.dart` — additive `sessionVersion`, `transcript`, `nonPQ`, `consented` fields (backwards compatible).
- `negotiation.dart` — added optional `Negotiation.responder(...)` factory used by the responder half of the handshake.
- `key_manager.dart` — additive read-only `getIdentityEd25519PublicKeyBytes()` (the v2 transcript binds the Ed25519 identity pubkey).
- `pq_hybrid_v1.dart` (new) — the `chhaya_pq_hybrid_v1` flag (default OFF, lazy read) and its test-only seams (`testEnabled/testKem/testBundleFetcher/testPrekeyProvider/testEd25519PublicKey`). Production leaves all nil. `productionBundleFetcher` wiring moved out of messaging_service into pq_hybrid_v1.dart.
- `check_transcript_binding.py` — WS3 allowlist mechanism: the static gate exits 0 with the two WS3 source files allowlisted under the spec-sanctioned allowlist mechanism (spec §6 criterion 14); recorded here.
- Test rewrite (criterion 1): `restore_resume_test.dart` now asserts byte-*inequality* of the post-restore session (rootKey, chains, SPQR seed, transcript). `ratchet_message_codec_test.dart` rewritten to v2 expectations. New `session_generation_test.dart` covers dual-store rollback. Existing skip-soak tests (fuzz, replay) stay green.

What was verified in this environment (8 Nov 2026): `flutter analyze lib test` — No issues found. `flutter test test/unit/` — **389 passed**. `flutter test test/integration/` — 4 passed + 2 skipped with reason. `python scripts/check_transcript_binding.py` — exits 0. Backend `npm test` — not run (prekey endpoints are WS1; flag turn-off unchanged).

What is **not** verified (explicit list):

- Live loopback backend round trip (criteria 2 and 3) — docker daemon unavailable on this host (`dockerDesktopLinuxEngine` not registered; `docker` binary not present), PostgreSQL not reachable. The env-gated test file `test/integration/resync_restore_test.dart` skips unless `CHHAYA_TEST_API_PORT` is set; criteria 2 and 3 are NOT RUN on this host. The pending re-send-with-new-id mechanism is covered at the DB/kv layer via unit fixtures and via the in-memory codec fixtures (resync ack → fresh messageId same content).
- Android device / two-phone drill — never attempted this slice.
- iOS runtime — never attempted this slice.
- Windows PQ — does not exist (no chhaya_pqc Windows plugin). Everything on Windows runs through the classical-consent path, which was not exercised end-to-end here.
- External cryptographic review — unverified; review gate still blocks default-on and any "post-quantum"/"secure restore" claim.
- Live prekey bundle fetch against a real server; bundle bytes vs SD-1 preimage (review pending).
- Group path per-member resync — wired through the shared codec (no separate group design), but criterion 9 is NOT exercised end-to-end; the outgoing group store path unchanged and covered by existing green suites.

Known limits / honest caveats:

- The v2 path is inert without `chhaya_pq_hybrid_v1` (default off). The pinned tests are rewritten, not deleted — they now assert safety properties rather than a dangerous behaviour.
- WS3 does not claim PQXDH is the right call without review — it is the spec's call. The external review gate remains binding (§7.2).

Commit SHA and `git status` recorded in the PR description. CSV rows (21, 80, 81) and delivery checklist rows are intentionally NOT flipped.

## Follow-up verification: delayed ML-KEM reseed (WS4, 14 Nov 2026)

Scope: spec §3.9 Tier-1 reseed only (hash-step chain + sparse ML-KEM-1024 reseed). The reseed flight rides the normal authenticated envelope path as a trailing section of the ratchet header; no network round-trip is ever required inside a message. Flag `chhaya_pq_hybrid_v1` remains OFF by default; nothing is default-on; no claim is made that messaging is post-quantum or quantum-safe.

What changed (high level):

- `spqr.dart` — one-way hash-step evolution for the chain seed (`seed_{n+1} = HKDF(seed_n, "Chhaya-SPQR-step-v1" || u32be(n+1))`); epoch keys derive from the seed at that epoch; past in-window epoch keys are served from a bounded cache keyed by generation; gaps beyond 1000 are refused (`TooManySkippedException`). New `ReseedKem` structural seam (fail closed when no provider). See spec §3.9.
- `session_state.dart` — additive, backwards-compatible persistence: retired epoch-key window cache, `spqrGeneration`, reseed cadence counters/timestamp, pending reseed keypair (wiped on transition).
- `triple_ratchet.dart` — epoch keys step the seed one-way (state intact on refusal); trailing `pq` section added to the header (soft extension: fixed 44-byte prefix unchanged; unknown trailing sections are skipped; malformed reseed sections are ignored; oversized trailing rejected). Delayed-reseed flight: the session initiator advertises a fresh ML-KEM-1024 keypair every ~25 sends or ≥7 days; the peer encapsulates on its next message; both derive `HKDF(step(seed, generation+1) || SS_reseed, "Chhaya-SPQR-reseed-v1")` and switch chain state. The initiator side alone offers (prevents cross-flight forking); the responder answers once per offer (persisted dedup).
- `ratchet_message_codec.dart` — threads the same ML-KEM provider used elsewhere (flag-gated, fail closed) through the reseed seam. No behaviour change when the flag is off.
- `pqc_provider.dart` / `ml_kem.dart` — `PqKem` gained `generateKeyPair()` (default throws → reseed silently stays classical).
- New `test/unit/crypto/ratchet/spqr_step_reseed_test.dart` — 15 tests covering the cadence boundary, seed change, old-epoch underivability, in-window decrypt across the boundary, >1000 gap refusal with state intact, provider-absent fail-closed path, and header soft-extension tolerance.

What was verified in this environment (14 Nov 2026): `flutter analyze lib test` — No issues found. `flutter test test/unit/crypto/` — green (incl. 1M-message fuzz). `flutter test test/unit/messaging/` and `test/unit/database/` — green (81 passed). `python scripts/check_transcript_binding.py` — exits 0. No claim is made that a live reseed flight has traversed the loopback backend; the flight is wired through the normal envelope path and exercised at the ratchet layer only.

What is **not** verified (explicit list):

- Live reseed flights through the loopback backend — docker daemon unavailable on this host; not run.
- Android/iOS device behaviour — never attempted.
- Windows ML-KEM reseed path — no chhaya_pqc Windows provider; fail-closed path only.
- External cryptographic review — unverified; review gate still blocks default-on and any post-quantum/secure-restore wording.
- Store-and-forward reseed arrival reordering against a live relay — only the in-memory unit-level flight is exercised.

CSV/checklist statuses intentionally NOT flipped.

## WS4 delayed reseed — review outcome (2026-11-14)

The Tier-1 delayed reseed implementation (`c237f9d`, `1d43b8b`, `81be967`, `443f52d`) received an adversarial final review on 2026-11-14. Verdict: `needs_changes`. It is not approved for any flag-on and supports no claim. The earlier "Follow-up verification: delayed ML-KEM reseed (WS4, 14 Nov 2026)" section above records what was built and locally tested; this section records what the review found.

Findings:

- **C1 (HIGH, spec fidelity).** The implementation uses an ephemeral in-band offer/ct flight advertised in a trailing ratchet-header section instead of the spec's bundle-advertised `reseedKemKey` single-flight encapsulation with a `chhaya-reseed-v1` payload. The spec's "requires researcher sign-off" for ephemeral reseed KEM keys is unmet. Docs/comments mislabel this as "spec §3.9 done". `reseedKemKey` exists in the WS2 bundle parser but is never wired to the reseed. The two-flight design is inherently more complex than the spec.
- **C2 (HIGH, availability, latent — flag OFF).** Store-and-forward reordering (M1 ct arrives after M2 data) would tear down the whole v2 conversation via the v==2 AEAD hard-abort. There are no reorder tests. The two-flight design cannot fix this without a two-chain receiver.
- **B1 (MEDIUM).** The `spqrEpoch = +101` bump violates the spec's "advanceEvery stays 10; reseed cadence independent".
- **C3 / C5 / B2 / C4 / E1.** State mutation before AEAD verification; offer persistence stores on flag-off peers; dead `nextIndex`; an oversized section is a throw, not a soft-fail; a lost offer permanently stalls the reseed cadence (no timeout); the epoch-key cache retains retired keys.

Tests rerun by the reviewer: `flutter analyze lib test` clean; `flutter test test/unit/` — 422 passed / ~1 skipped; the 15 reseed tests pass; `python scripts/check_transcript_binding.py` — exit 0. Green tests here do not close the findings above.

Required before ANY flag-on:

1. Implement the spec flight (bundle-advertised `reseedKemKey`, single-flight encapsulation, `chhaya-reseed-v1` payload), or a signed researcher-approved deviation together with a spec revision.
2. Fix C2 or obtain a formal waiver for it.
3. Add the missing §F tests: reorder flight, duplicate-offer dedup, multi-generation key inequality, role-lock, cache eviction.
4. External cryptographic review.

Status: experimental. Flag `chhaya_pq_hybrid_v1` OFF (`const bool.fromEnvironment('chhaya_pq_hybrid_v1')` unset). NOT protocol-complete. NOT §3.9 satisfied. NO claim is made.
