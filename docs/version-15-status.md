# Chhaya — Version 15 preparation status register

Date: 2026-11-14 (register opened 2026-11-08; refreshed 2026-11-14). Repo: `D:\Projects\PROJ16`. Base commit: `8eeff19`. Working tree additionally carries uncommitted native registrant noise (`android/.../GeneratedPluginRegistrant.java`, `ios/Runner/GeneratedPluginRegistrant.m`, `windows/flutter/generated_*`, `.gradle` lock files) that is NOT part of this register. The PQ spec (`docs/spec-pq-hybrid-resync-v1.md`) was committed in `1274999`; `docs/spec-media-transfer-v1.md` is added in the same docs commit as this refresh.

**Last verified (LOCAL ONLY): 2026-11-14 — `flutter test test/unit/` 406 passed + ~1 skipped, per the reviewer's re-run; no CI, device, or integration evidence implied.**

**Standing verdict: Version 15 is NOT ready. No release may be labeled final, v15 complete, or production ready. No row of the 127-feature ledger is release-verified. This document is an internal evidence register, not a release note and not marketing.**

## 1. Scope and provenance

- Product: Flutter app "Chhaya" + Node/PostgreSQL backend. 127 registered features in `docs/feature-register.md`, ledgered in `docs/feature-verification-127.csv`, tracked against `docs/delivery-checklist.md`; release plan in `docs/release-execution-plan.md`.
- This register covers the 2026-11-08 evidence window plus the 2026-11-09..14 refresh (PQ-spec WS2/WS3 commits and media-transfer spec, §4) and the 2026-10-29/30 audit record it builds on. It records what is proven, what is not, and what is lost.
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
| `flutter test test/unit/` | unit | 406 passed + ~1 skipped (LOCAL ONLY; reviewer's re-run reported 2026-11-14; recorded in `docs/ponytail-audit-2026-10-29.md` for the 2026-11-08 window at 303; prior local run reported ≈404) |
| `flutter analyze lib test` | static | No issues found (2026-11-08 record; NOT re-run in this refresh) |
| `test/unit/database/interrupted_delivery_test.dart` | unit (Windows-gated) | 2 passed vs real SQLCipher files |
| `backend/server/test/*` (prekey WS1) | integration | 38 backend tests reported for `5d2faf1`; NOT re-run in this window; CI not re-run |
| `scripts/run_android_acceptance.ps1` | script | Verified read-only as correct for the verification-package failure mode, EXCEPT a missing all-users pre-flight check |
| `scripts/verify_app_branding.py` | CI check | Present; branding asset dims checked in CI, not re-verified here |
| `docs/spec-pq-hybrid-resync-v1.md` | spec | Committed in `1274999`: PQXDH v2 establishment/negotiation/restore resync; hard external-review gate; Windows/iOS gaps; implementation landed locally behind default-OFF flag (see §4, §7) |
| `docs/spec-media-transfer-v1.md` | spec | Added 2026-11-14: encrypted resumable media transfer ("Media Transfer v1"); **Proposed spec — not implemented, not release-verified, Do not ship, claims gated**; no new cryptography; no checklist/CSV changes |
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
| `98aa043` | WS2 (PQ spec): hybrid PQXDH establish/transcript/negotiation helpers — `pqxdh.dart`, `transcript.dart`, `negotiation.dart`, prekey-bundle client, golden vectors, ~1.9k lines of new unit tests; audit notes appended | Deployed or live-verified prekey fetch; any PQ messaging claim; external review |
| `1274999` | Record Version 15 preparation status + commit `docs/spec-pq-hybrid-resync-v1.md` (vNext PQ/restore spec) | Any release verification; spec is a design, not an implementation claim |
| `ed1ff93` | WS3 (PQ spec): v2 establishment/resync restore recovery wired — restore resync before user content, `session_generation` dual-store with fail-closed rollback detection, `chhaya_pq_hybrid_v1` flag default OFF; local suite green (389 passed at the time); live loopback criteria NOT RUN (Docker down) | Live loopback round trip; two-phone drill; iOS/Windows PQ; external review; any "secure restore" claim |
| `2d6b9bb` | Fail-closed on settings lock read (settings screen); +40-line unit test | Device lock UX proof; other settings fail-closed paths |
| `e022db8` | WS3 F1: advanced legacy session persisted under legacy key; +127 lines of codec tests | Restore-security claim; external review |
| `4d2e60b` | WS3 F2: stale establishment flights rejected at the acceptance gate; +73 lines of codec tests | Live resync acceptance; two-phone evidence |
| `fecb2cf` | WS3 F7: vice-versa `session_generation` rollback covered by tests | Runtime rollback proof on device |
| `88ea78f` | WS3 F4: unreadable `session_generation` values fail closed; +169-line garbage-value test | Device/keystore evidence; Windows PQ (does not exist) |
| `2eeb9b9` | WS3 F3: v2 sessions hard-abort on AEAD tag failure; +62 lines of codec tests | Independent review; any robustness claim beyond unit suite |
| `1c46316` | WS3 F5: establishment flight adopted only after AEAD verification; +81 lines of codec tests | Live flight-adoption evidence (loopback NOT RUN) |
| `8eeff19` | WS3 F6: echo verified before committing received messages; +53 lines of codec tests | End-to-end echo verification on device/loopback |

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
| WS2 | Reliable messaging + authenticated recovery | **done-local** (code + local suite; live criteria NOT RUN) | Resync/restore redesign landed locally behind default-OFF `chhaya_pq_hybrid_v1` flag (`ed1ff93`, `98aa043`); WS3 audit findings F1–F7 resolved locally and confirmed fixed in code by the 2026-11-14 re-review (`pass_with_observations`; residuals R1/R2/R3 open, see WS3-F1..F7 row) (`e022db8`, `4d2e60b`, `fecb2cf`, `88ea78f`, `2eeb9b9`, `1c46316`, `8eeff19`); restore key/nonce defect addressed locally; live loopback NOT RUN (Docker down); two-phone not run; external review NOT commissioned; no "secure restore" claim |
| WS3 | Encrypted resumable transfers (large attachments) | **not_started** (spec added, claims gated) | Inline attachments capped at 256 KB; no resume/limits/cancel cleanup for large blobs. `docs/spec-media-transfer-v1.md` added 2026-11-14 — proposed spec only, not implemented, do not ship, claims gated |
| WS4 | Authenticated group membership, linking, revocation | **in-progress / blocked** | Group admin APIs + backend lock tests exist; linking is scaffolding only; no authenticated enrollment/revocation; "Revoke" legacy UI does not revoke server sessions |
| WS5 | Calls, background ringing, push, TURN, SFrame | **blocked / not_started** | Foreground WebRTC only; SFrame absent; background calls incomplete; no two-phone NAT/TURN/push evidence |
| WS6 | PQ key distribution, negotiation, migration | **in-progress (PQ-spec WS1/WS2/WS3 done-local; WS4–WS6 not started)** | `5d2faf1` prekey backend (not deployed, CI not re-run); `docs/spec-pq-hybrid-resync-v1.md` committed in `1274999`; PQ-spec WS2 helpers `98aa043` done-local; PQ-spec WS3 v2 establishment/resync restore `ed1ff93` done-local; flag default OFF; hard external-review gate NOT passed; Windows PQ stub, iOS vectors pending |
| PQ-WS1 | PQ spec: prekey bundle backend | **done-local** | `5d2faf1`; 38 backend tests reported; NOT deployed; CI not re-run |
| PQ-WS2 | PQ spec: hybrid PQXDH establish/transcript/negotiation helpers | **done-local** | `98aa043`; unit tests green locally; no live bundle fetch; review pending |
| PQ-WS3 | PQ spec: v2 establishment / post-restore resync | **DONE (code + local suite)** | `ed1ff93` + F1–F7 fixes; 406 passed + ~1 skipped (LOCAL ONLY, reviewer's re-run 2026-11-14); final re-review returned `pass_with_observations` (see WS3-F1..F7 row); live loopback criteria NOT RUN (Docker down); two-phone not run; flag `chhaya_pq_hybrid_v1` default OFF; external review NOT commissioned; no PQ/restore claims |
| WS3-F1..F7 | PQ-spec WS3 audit findings F1–F7 (as tagged in commit messages) | **resolved locally (re-reviewed 2026-11-14: `pass_with_observations`)** | F1 `e022db8`; F2 `4d2e60b`; F7 `fecb2cf`; F4 `88ea78f`; F3 `2eeb9b9`; F5 `1c46316`; F6 `8eeff19`; unit coverage added per fix. Final re-review (corrections range `ed1ff93`..`8eeff19`, range as of HEAD; includes `2d6b9bb` and `c857be5`) returned `pass_with_observations` — F1–F7 confirmed fixed in code. Open residuals (recorded verbatim; NOT release evidence; NOT silently patched): **R1** (adoption runs BEFORE echo verification in decrypt(): markResyncPending/peer_restored writes survive an echo abort — spec/lead decision required, NOT to be silently patched); **R2** (peer_restored write-only; pre-AEAD peer_restored=1 in cross-restore branch; markResyncPending mints fresh generation when none exists); **R3** (uint64-vs-int64 session_generation spec mismatch, fails closed to corrupt). Residuals R1/R2/R3 remain open; external review still NOT commissioned |
| WS4-DELAYED-RESEED | PQ-spec WS4 Tier-1 delayed ML-KEM reseed (`c237f9d`, `1d43b8b`, `81be967`, `443f52d`) | **needs_changes** (experimental; see ponytail-audit) | Adversarial final review 2026-11-14: C1 (HIGH, spec fidelity) — ephemeral in-band offer/ct flight advertised in a trailing ratchet-header section instead of the spec's bundle-advertised `reseedKemKey` single-flight encapsulation with a `chhaya-reseed-v1` payload; the spec's "requires researcher sign-off" for ephemeral reseed KEM keys is unmet; docs/comments mislabel this as "spec §3.9 done"; `reseedKemKey` exists in the WS2 bundle parser but is never wired to the reseed; the two-flight design is inherently more complex than the spec. C2 (HIGH, availability, latent — flag OFF) — store-and-forward reordering (M1 ct arrives after M2 data) would tear down the whole v2 conversation via the v==2 AEAD hard-abort; no reorder tests; the two-flight design cannot fix this without a two-chain receiver. B1 (MEDIUM) — the `spqrEpoch = +101` bump violates the spec's "advanceEvery stays 10; reseed cadence independent". C3/C5/B2/C4/E1 — state mutation before AEAD verification; offer persistence stores on flag-off peers; dead `nextIndex`; an oversized section is a throw (not a soft-fail); a lost offer permanently stalls cadence (no timeout); the epoch-key cache retains retired keys. Reviewer re-ran: `flutter analyze lib test` clean; 422 passed / ~1 skipped; 15 reseed tests pass; static gate exit 0. Required before any flag-on: implement the spec flight (or a signed researcher-approved deviation + spec revision); fix or formally waive C2; add the missing §F tests (reorder flight, duplicate-offer dedup, multi-generation key inequality, role-lock, cache eviction); external cryptographic review. Flag `chhaya_pq_hybrid_v1` OFF (`const bool.fromEnvironment('chhaya_pq_hybrid_v1')` unset); NOT protocol-complete; NOT §3.9 satisfied; NO claim made |
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
| PQ negotiation / resync implemented + gated | **FAIL / NOT DONE** | Implemented locally behind default-OFF flag (`98aa043`, `ed1ff93`, F1–F7); live loopback NOT RUN (Docker down); two-phone not run; external review gate NOT passed; no PQ claim |
| Monitoring / alerting / SBOM / licenses | **FAIL / INCOMPLETE** | Basic metrics; license inventory missing |
| Offline large-attachment/resumable transfers | **FAIL / NOT DONE** | 256 KB inline cap; `docs/spec-media-transfer-v1.md` added 2026-11-14 (proposed, claims gated, not implemented) |
| Authenticated linking/revocation | **FAIL / NOT DONE** | Scaffolding only |
| Vault/duress/Canary safety features | **FAIL / NOT IMPLEMENTED** | — |
| Windows desktop acceptance | **FAIL / NOT DONE** | CI build only; not launched; ATL missing locally |
| Internal engineering gate (analysis + unit tests green) | **PASS (LOCAL ONLY)** | `flutter analyze` clean (2026-11-08 record, not re-run); 406 unit tests + ~1 skip (LOCAL ONLY, reviewer's re-run 2026-11-14) |

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
5. PQ-spec WS2 (`98aa043`) and WS3 (`ed1ff93`) are done-LOCAL only: re-run `56f054d`-pinned restore tests; F1–F7 were re-reviewed 2026-11-14 (`pass_with_observations`; residuals R1/R2/R3 open — R1 needs a spec/lead decision, do not patch silently); verify the live loopback resync round trip (criteria 2 and 3) once Docker is available; commission the external cryptographic review before any default-on or claim; do NOT enable `chhaya_pq_hybrid_v1` by default.
6. Deploy WS1 prekey backend to a persistent Postgres (not free tier) with re-upload runbook; re-run backend tests and CI; only then integration-test bundle pop against a real device.
7. Two-phone Android acceptance for direct messaging, restore-resume, lock/lifecycle, and calls-signaling (not media); then iOS signing + device pass; then second-phone matrix.
8. Large-attachment resumable encrypted transfers (WS3 of plan); authenticated linking/revocation (WS4); push/TURN/SFrame (WS5) — each behind its own acceptance evidence.
9. SBOM + license inventory; monitoring/alerting; production backup/restore drill evidence; dependency advisories.
10. Only when §9 is all PASS (or explicitly de-scoped by owner): tag and publish. Until then every artifact says "not release verified".

## 12. Honesty notes / what this register does NOT show

- No independent review has occurred. Green unit tests are not audits.
- The 2026-10-29 verification-package loss is unresolved; data is presumed destroyed; the cause is presumed (not device-log-proven) runner teardown.
- Working tree contains uncommitted registrant/gradle changes; the PQ spec was committed in `1274999` and `docs/spec-media-transfer-v1.md` in the same docs commit as this refresh; this register's base is `8eeff19`.
- Distribution rule: no commit may touch `.gradle/` or generated registrant files; none did — those remain uncommitted working-tree noise and are excluded from every commit in this window.
- The 2026-11-14 WS3 re-review (`pass_with_observations`) is a document/code review of the correction range, not an external cryptographic review, and does not clear any release gate; residuals R1/R2/R3 (WS3-F1..F7 row) remain open.
- Render free-tier evidence will expire 2026-11-27 regardless of this document.
