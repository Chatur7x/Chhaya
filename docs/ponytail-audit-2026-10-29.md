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
