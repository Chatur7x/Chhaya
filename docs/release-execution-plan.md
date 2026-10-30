# Chhaya release execution plan

Objective: complete and verify every requirement in feature-register.md, including supported platforms and release gates. The 127-row feature-verification-127.csv is the evidence ledger; no row is release verified merely because a screen or a unit test exists. Keep the 127 requirements intact and record contradictions and duplicates explicitly.

## Workstreams and gates

1. Audit Flutter UI, state, persistence, authentication, messaging, calling and recovery; backend APIs, database and signaling; Android/iOS and Windows native integrations; PQ provider, dependencies, deployment and CI. Record code paths, findings and areas not yet reviewed in ponytail-audit-2026-10-29.md.
2. Finish reliable messaging and recovery with authenticated new session establishment after restore, avoiding key/nonce reuse. Verify offline/retry, restart, duplicate acceptance, group/multi-device semantics and server retention on real devices.
3. Replace inline-only media with encrypted resumable transfers, limits, cancellation and cleanup; verify microphone, camera and playback.
4. Implement independently authenticated group membership and invitations, key rotation, multi-device linking, approval, per-device sessions and revocation. Verify simultaneous sends and membership changes.
5. Complete calls, native background ringing, push, TURN and SFrame; verify interruption, reconnection and cross-platform devices.
6. Specify, implement and independently review authenticated PQ key distribution, real session negotiation, downgrade protection, fresh ratchet contributions and migration, including native Android/iOS vectors. Resolve Dual-KEM/NTRU design.
7. Implement and verify requested metadata/privacy transports, onion relays, offline mesh/LAN modes, proxy leak resistance, vault and safety flows, with truthful capability reporting.
8. Complete UI flows, appearance, accessibility, desktop platform storage, responsive behavior, performance, lifecycle and device protection. Verify every settings action and error state.
9. Validate public operations, migrations, backup and populated-data restore, monitoring and rollback; maintain dependency/license inventory and SBOM. Free Render testing only unless the owner changes the budget. The currently recorded free database expiry is 27 November 2026.
10. Run requirement-specific tests and real-device acceptance for every ledger row; audit remaining findings and external review. Sign/install release candidate without deleting existing accounts, verify upgrade and clean install, then build and publish Version 15 only when gates pass.

## Evidence and constraints

- Existing Android account packages and their data must not be reset or uninstalled. Use dedicated isolated test package/accounts.
- Android Pixel 8a was connected on 29 October 2026; iOS device/signing and a second phone are not yet evidenced. Recheck availability before relevant tests.
- The latest existing security fixes and passing tests are in the audit record. A corrupt session now fails closed; backup restore still lacks peer-coordinated fresh session establishment.
- The old linked-device settings created fictitious local entries and offered a local-only action named Revoke. This does not revoke a server session. Until genuine enrollment/revocation is implemented, the UI explicitly identifies legacy entries and does not claim either action succeeded; underlying user data is retained.
- Independent review, iOS signing, real-device cross-platform flows and external infrastructure remain unverified. None blocks independent implementation and test work.

## Current next work

The sync index and demonstrated recent-send/backlog overlap defect are fixed with local evidence. Continue durable forward checkpoints, incomplete-history reporting and large-backlog/ratchet-limit handling; continue the reviewed authenticated restore/session-generation handshake and full feature assessment. Add adversarial retry, replay, concurrent and rollback tests before integrating new protocol flows. The Android verification package disappeared during Flutter test cleanup; its account recovery is unresolved. Preserve the main account in private-space user 11, use the guarded acceptance script for future device tests, and do not reinstall/reset the missing verification package until recovery is assessed. Continue all independent implementation, repository audit and evidence mapping.
