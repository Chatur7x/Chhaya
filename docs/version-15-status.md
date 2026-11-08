# Chhaya — Version 15 preparation status register

Date: 2026-11-08. Repo: `D:\Projects\PROJ16`. Base commit: `5d2faf1`. Working tree additionally carries an uncommitted spec (`docs/spec-pq-hybrid-resync-v1.md`) and uncommitted native registrant noise (`android/.../GeneratedPluginRegistrant.java`, `ios/Runner/GeneratedPluginRegistrant.m`, `windows/flutter/generated_*`, `.gradle` lock files) that are NOT part of this register.

**Standing verdict: Version 15 is NOT ready. No release may be labeled final, v15 complete, or production ready. No row of the 127-feature ledger is release-verified. This document is an internal evidence register, not a release note and not marketing.**

## 1. Scope and provenance

- Product: Flutter app "Chhaya" + Node/PostgreSQL backend. 127 registered features in `docs/feature-register.md`, ledgered in `docs/feature-verification-127.csv`, tracked against `docs/delivery-checklist.md`; release plan in `docs/release-execution-plan.md`.
- This register covers the 2026-11-08 evidence window plus the 2026-10-29/30 audit record it builds on. It records what is proven, what is not, and what is lost.
- Evidence classes are distinguished throughout: **unit** (Flutter unit tests), **integration** (live backend/PostgreSQL), **device** (physical hardware), **audit** (document review), **CI** (GitHub Actions). Nothing here is an independent cryptographic review.
- Not covered: independent external review, iOS runtime, production Render operation, two-phone acceptance. These are absent, not passing.

## 2. Claims policy (binding)

Allowed:
- "internal review", "not release verified", "partially implemented", per-row evidence that names its class (unit/integration/device/audit).
- Engineering-internal: "Hybrid PQXDH session establishment (experimental)", "ML-KEM-1024 via AWS-LC v5.11.0 (pinned commit fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6)".

Forbidden (hard fail in any UI/store/marketing/README/SECURITY.md/CSV/checklist prose):
- "post-quantum secure messaging" / "quantum-safe" / "quantum-proof" — PQ is not live in messaging.
- "secure restore" / "safe restore" / "guaranteed session recovery" — restore re-derives byte-identical initiator sessions (key/nonce reuse hazard); defects pinned, no fix shipped.
- "production ready" / "final" / "v15 complete" / "audited" / "independently reviewed".
- Any multi-device semantics claim; any Windows/iOS PQ availability claim.

## 3. Commands and artifacts index

| Item | Class | Result / location |
|---|---|---|
| `flutter test test/unit/` | unit | 303 passed (recorded in `docs/ponytail-audit-2026-10-29.md`, Slice A, 2026-11-08) |
| `flutter analyze lib test` | static | No issues found (same record) |
| `test/unit/database/interrupted_delivery_test.dart` | unit (Windows-gated) | 2 passed vs real SQLCipher files |
| `backend/server/test/*` (prekey WS1) | integration | 38 backend tests reported for `5d2faf1`; NOT re-run in this window; CI not re-run |
| `scripts/run_android_acceptance.ps1` | script | Verified read-only as correct for the verification-package failure mode, EXCEPT a missing all-users pre-flight check |
| `scripts/verify_app_branding.py` | CI check | Present; branding asset dims checked in CI, not re-verified here |
| `docs/spec-pq-hybrid-resync-v1.md` | spec | Uncommitted design: PQXDH v2 establishment/negotiation/restore resync; hard external-review gate; Windows/iOS gaps; NOT implemented |
| `docs/ponytail-audit-2026-10-29.md` | audit | Prior audit + follow-ups through 2026-11-08 |
| `docs/release-verification-14.0.1.md`, `docs/render-deploy.md`, `docs/self-hosting.md` | ops record | Render free-tier expiry recorded 2026-11-27 |
| `docs/feature-verification-127.csv` | ledger | All 127 rows carry `NOT RELEASE VERIFIED` (grep count = 127) |

Do not read any row above as device or production evidence. None is.

## 4. Commit evidence (this session window)

| SHA | What it is | What it is NOT |
|---|---|---|
| `b42d4e5` | Background reauth lifecycle guard: locked signed-in session shows lock gate on backgrounded first frame and on resume; HomeShell sync suppression driven by single `appLockedProvider` predicate; back consumed through lock gate only while locked; 18 lock tests | Any device/lock/biometric acceptance on hardware; any claim the guard is foolproof |
| `4194a35` | Fail-closed unreadable lock setting: corrupt `biometric_lock` blob no longer breaks `appLockedProvider`/lifecycle guard; `safeBiometricLockEnabled()` locks on read error; +2 tests | Proof of correct lock UX on device; covers other secure-storage failures |
| `56f054d` | Adversarial retry/replay/concurrency/rollback/restore tests: replayed/tampered envelopes rejected without session advance; exact-envelope retry after commit-crash converges; concurrent dual-instance retry dedups; 303 unit tests pass. **Pinned known defects:** (1) restore re-derives byte-identical initiator session = key/nonce reuse hazard; (2) sync swallows malformed envelopes silently; (3) restored initiator early messages replay consumed counters; (4) restored unsent message stuck pending forever | A fix. These defects are pinned, not remediated. No restore-security claim permitted |
| `5d2faf1` | WS1 (PQ spec) prekey bundle API: additive tables/endpoints/rate limits/atomic one-time pop (SKIP LOCKED); 38 backend tests reported | NOT deployment-verified; NOT rendered on Render; CI not re-run; no client/crypto change; no PQ messaging |
| `b18604d` | Requirements 1–25 implementation-category assessment appended to ledger | Any release verification |
| `12c934d`, `5b2ebcf` | Real-backend sync regression evidence (loopback Node + disposable `chhaya_test` PostgreSQL); backlog pagination fix | Physical-device evidence; production evidence |

Earlier context (pre-window, retained for honesty): `8a534cf` CI runs 40866770193 (Windows debug build + SQLCipher native test, not launched) and 40866770191 (unsigned iOS debug build + macOS analysis/tests). Neither establishes signing, installation, or runtime acceptance.

## 5. 127-ledger pointer

- Ledger: `docs/feature-verification-127.csv` (127 rows; all `NOT RELEASE VERIFIED`). Register index: `docs/feature-register.md`. Cross-check: `docs/delivery-checklist.md`.
- Every release claim for a feature must cite its ledger row and distinguish unit vs integration vs device vs audit. Several rows carry 2026-11-08 unit evidence (IDs 1, 77, 80, 81, 87 per Slice A); none carries device, audit-pass, or release evidence.
- No CSV/checklist status was flipped in this work. Status changes are a lead/human decision after the external-review gate.

## 6. Audit pointers

- `docs/ponytail-audit-2026-10-29.md` — must-fix findings (Windows DB path [since addressed via FFI SQLCipher, not runtime-accepted], linked-device enrollment, PQ-not-live, onion/mesh non-operational, call-readiness race [fixed + delayed-join regression]), plus Slice A pinned defects. Verdict there stands: **not ready to label Version 15 complete.**
- `docs/threat-model.md`, `docs/crypto.md`, `docs/pqc-provider-proposal.md`, `docs/security-competitive-analysis.md` — context, not sign-off.
- `docs/release-execution-plan.md` — plan; its "Current next work" section is consistent with this register.

## 7. Workstream tracker (release-execution-plan WS1–WS9)

| WS | Plan item | Status | Evidence / notes |
|---|---|---|---|
| WS1 | Audit UI/state/persistence/auth/messaging/calls/recovery; backend; native; CI | **done-local** (audit complete; findings NOT all closed) | `docs/ponytail-audit-2026-10-29.md`; must-fix items open |
| WS2 | Reliable messaging + authenticated recovery | **in-progress, blocked on protocol redesign** | `56f054d` adversarial tests; restore key/nonce defect pinned; `b18604d` assessment; resync spec uncommitted; no fix shipped |
| WS3 | Encrypted resumable transfers (large attachments) | **not_started** | Inline attachments capped at 256 KB; no resume/limits/cancel cleanup for large blobs |
| WS4 | Authenticated group membership, linking, revocation | **in-progress / blocked** | Group admin APIs + backend lock tests exist; linking is scaffolding only; no authenticated enrollment/revocation; "Revoke" legacy UI does not revoke server sessions |
| WS5 | Calls, background ringing, push, TURN, SFrame | **blocked / not_started** | Foreground WebRTC only; SFrame absent; background calls incomplete; no two-phone NAT/TURN/push evidence |
| WS6 | PQ key distribution, negotiation, migration | **in-progress (WS1 of PQ spec done-local)** | `5d2faf1` prekey backend (not deployed, CI not re-run); `docs/spec-pq-hybrid-resync-v1.md` uncommitted; PQ-spec WS2–WS6 not started; hard external-review gate NOT passed; Windows PQ stub, iOS vectors pending |
| WS7 | Privacy transports (onion/mesh/LAN/shim/Arke) | **not_started** | Onion legacy code disabled; mesh/LAN/Arke/Shadow Codes not implemented; no relay deployment |
| WS8 | UI flows, accessibility, desktop storage, lifecycle, device protection | **in-progress** | `b42d4e5`, `4194a35` lock lifecycle (unit evidence); Windows FFI SQLCipher done-local + CI; voice `record`/`audioplayers` migration; local `flutter build windows` blocked by missing ATL (`atlstr.h`); Windows build CI ok but app never launched; accessibility not device-reviewed |
| WS9 | Ops: migrations, backup/restore drills, monitoring, rollback, SBOM/licenses | **in-progress / at risk** | Local restore drill + CI workflow exist; monitoring basic; SBOM/license inventory incomplete (root license effectively empty); **Render free-tier DB expiry 2026-11-27**; no production backup/restore evidence |

Plan item 10 (tag/publish Version 15) — **not_started and gated**; must not begin until gates in §9 pass.

## 8. Verification-device matrix

| Platform / device | Last known state | Verified today? |
|---|---|---|
| Android Pixel 8a | NOT currently connected. Last seen 2026-10-29/30 (ADB: no device on 2026-10-30). `com.chaaya.app.chaaya.verification` **LOST 2026-10-29** — presumed uninstalled by `integration_test` teardown default targeting the stale cached APK package id. `allowBackup=false`; no backup evidence found (workspace/Downloads/Documents/phone search); Keystore-wrapped identity destroyed with sandbox. **Only recovery path: owner-held BIP-39 recovery phrase.** Status: **LOST, not compromised.** | No — nothing re-verified today |
| Android main package `com.chaaya.app.chaaya` | Last observed in Android private-space user 11. Not re-checked today. | No |
| Emulator `emulator-5554` | Only an x86_64 emulator visible; not a substitute for arm64/AWS-LC/device acceptance | No (and not equivalent) |
| iOS | No device, no signing, unsigned CI build only (`8a534cf`, run 40866770191) | No |
| Windows | Local build blocked (missing ATL); CI debug build ok (run 40866770193), SQLCipher native test passed there; app never launched against an account | CI only; not local, not runtime |
| Second phone | None available/evidenced | No |

## 9. Release gates checklist — pass/fail by evidence

| Gate | State | Evidence |
|---|---|---|
| Production signing key custody + backup | **FAIL / UNVERIFIED** | Release APK signed with private local key (14.0.1); custody/backup unverified |
| iOS device + signing | **FAIL / UNVERIFIED** | Unsigned CI artifact only |
| Second-device Android testing | **FAIL / NOT DONE** | No second phone |
| Two-phone calling / NAT / TURN / push | **FAIL / NOT DONE** | Foreground WebRTC unit/integration only |
| Independent cryptographic review | **FAIL / NOT COMMISSIONED** | Hard gate for PQ + any final claim |
| Render production resources / paid plan | **FAIL / NO-GO (budget)** | Free tier only; DB expires 2026-11-27 |
| Render backup/restore drill on production | **FAIL / UNVERIFIED** | Local/CI drills only |
| Hardware prerequisites (all) | **FAIL / UNVERIFIED** | Pixel 8a lost verification package; no current device |
| 127-row ledger release-verified | **FAIL** | 0/127 rows verified |
| PQ negotiation / resync implemented + gated | **FAIL / NOT DONE** | Spec uncommitted; WS2–WS6 not started |
| Monitoring / alerting / SBOM / licenses | **FAIL / INCOMPLETE** | Basic metrics; license inventory missing |
| Offline large-attachment/resumable transfers | **FAIL / NOT DONE** | 256 KB inline cap |
| Authenticated linking/revocation | **FAIL / NOT DONE** | Scaffolding only |
| Vault/duress/Canary safety features | **FAIL / NOT IMPLEMENTED** | — |
| Windows desktop acceptance | **FAIL / NOT DONE** | CI build only; not launched; ATL missing locally |
| Internal engineering gate (analysis + unit tests green) | **PASS (local)** | `flutter analyze` clean; 303 unit tests pass (2026-11-08) |

**No gate that matters for a public release passes. "Version 15" must not be tagged, shipped, or labeled final.**

## 10. Open questions for the owner

1. **Verification-account recovery phrase** — do you hold the BIP-39 phrase for the LOST `com.chaaya.app.chaaya.verification` account? Without it the account is unrecoverable. (Do not paste it into any tool/chat.)
2. **Render paid resources** — free-tier DB expires 2026-11-27. Approve paid plan + migration budget, or accept service loss? Currently a recorded no-go.
3. **Signing keys custody** — where are the Android release keystore and (future) Apple credentials held, backed up, and who besides you has access?
4. **Maintainer/reviewer designation** — the register requires a named maintainer and an independent reviewer per feature area; none assigned. Who?
5. **Main-account preservation review** — `com.chaaya.app.chaaya` in private-space user 11: confirm it must be preserved as-is and excluded from any acceptance/reset flow. Any tolerance for its test use?
6. **PQ review budget** — commission independent cryptographic review now (blocks all PQ and restore claims), or formally descope PQ from v15?
7. **Reduced-scope honest shipping** — if gates cannot pass by target date, which reduced scope ships (e.g. classical-only, no PQ claims, documented limits), and who signs off on the wording?

## 11. Recommended next steps, in order

1. Owner answers §10.1 (recovery phrase custody) and confirms main-package preservation; do NOT reinstall/reset the verification package until recovery is assessed.
2. Owner decision on Render (§10.2) BEFORE 2026-11-27, or accept and document service loss; migrate/restore drill on the target Postgres with evidence.
3. Commission independent cryptographic review (§10.6) OR formally descope PQ/restore from the release; record the decision.
4. Fix the verification-package failure mode: add the missing all-users pre-flight check to `scripts/run_android_acceptance.ps1`; re-verify its read-only behavior; then re-establish a device-test path (replace/repair Pixel 8a access).
5. Implement PQ-spec WS2 (Dart protocol helpers + negotiation) and WS3 (resync/restore replacing deterministic restart), re-running `56f054d`-pinned restore tests to green; keep the external-review gate binding; do not default-on.
6. Deploy WS1 prekey backend to a persistent Postgres (not free tier) with re-upload runbook; re-run backend tests and CI; only then integration-test bundle pop against a real device.
7. Two-phone Android acceptance for direct messaging, restore-resume, lock/lifecycle, and calls-signaling (not media); then iOS signing + device pass; then second-phone matrix.
8. Large-attachment resumable encrypted transfers (WS3 of plan); authenticated linking/revocation (WS4); push/TURN/SFrame (WS5) — each behind its own acceptance evidence.
9. SBOM + license inventory; monitoring/alerting; production backup/restore drill evidence; dependency advisories.
10. Only when §9 is all PASS (or explicitly de-scoped by owner): tag and publish. Until then every artifact says "not release verified".

## 12. Honesty notes / what this register does NOT show

- No independent review has occurred. Green unit tests are not audits.
- The 2026-10-29 verification-package loss is unresolved; data is presumed destroyed; the cause is presumed (not device-log-proven) runner teardown.
- Working tree contains uncommitted registrant/gradle changes and the uncommitted PQ spec; this register's base is `5d2faf1` plus untracked `docs/spec-pq-hybrid-resync-v1.md`.
- Render free-tier evidence will expire 2026-11-27 regardless of this document.
