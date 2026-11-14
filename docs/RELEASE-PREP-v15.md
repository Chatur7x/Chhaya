# Release prep — Version 15 preparation register (DRAFT / internal)

Date: 2026-11-14. Repo: `D:\Projects\PROJ16`. Branch/base range under review: `b42d4e5` (`b42d4e5639e871b337128a1fd6b3c05034247b82`) .. `c4b48e6` (`c4b48e69242db7090ba719ac6df0ffb26e177014`).

**Standing verdict: Version 15 is NOT ready. No gate that matters for a public release passes. Nothing in this document may be quoted as release, production, audited, or "v15 complete" wording. This is an internal evidence register, not a release note and not marketing.**

This register is an addition to, not a replacement for, `docs/version-15-status.md` (the authoritative internal evidence register) and `docs/delivery-checklist.md` / `docs/feature-verification-127.csv` (the 127-row ledger; all rows remain `NOT RELEASE VERIFIED` — grep count 127 as of the last recorded check). No checklist, CSV, or register status was flipped by this document.

## 1. What is verified (evidence, not guarantees)

| Item | Class | Evidence / limits |
|---|---|---|
| `flutter analyze` clean | static | Recorded 2026-11-08; NOT re-run in the 2026-11-14 refresh |
| `flutter test test/unit/` — 406 passed + ~1 skipped | unit | LOCAL ONLY (reviewer re-run reported 2026-11-14); no CI, device or integration evidence implied |
| `test/unit/database/interrupted_delivery_test.dart` | unit (Windows-gated) | 2 passed vs real SQLCipher files |
| Backend lint + backend tests | CI | Backend job in `.github/workflows/ci.yml` passes as of the last recorded run; 38 backend tests reported for `5d2faf1` (prekey WS1), NOT re-run in this window |
| Database backup and isolated restore drill | CI | CI workflow job present and passing as of the last recorded run; local container health + empty-schema restore drill pass. **Local/CI drill only — not a production Render drill** |
| PQC native pinned tests | CI | `.github/workflows/pqc-native.yml`: AWS-LC pinned (v5.11.0, commit `fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6`) host known-answer tests + ACVP ML-DSA checks; passing as of the last recorded run |
| Android CI build | CI | Debug + release APK compile succeed; installable test APK artifact (`Chhaya-Android-Test-APK`) uploaded; **artifact identity/signature NOT verified at last poll** |
| Windows CI build | CI | `flutter build windows --debug` succeeds; `Chhaya-Windows-Developer-Build` artifact uploaded; SQLCipher native test passed there; **app never launched against an account**; local build blocked (missing ATL) |
| iOS CI build | CI | Unsigned `Runner.app` archive builds; `Chhaya-iOS-UNSIGNED-Developer-Build` artifact uploaded; **no signing, no device, no installation, no runtime acceptance** |
| Local unit suite for v2 PQ establishment / resync (WS3) | unit | Local only; flag `chhaya_pq_hybrid_v1` default OFF; live loopback NOT RUN (Docker down) |

Do not read any row above as device, production, or audit evidence. None is.

## 2. What is NOT verified (absent, not passing)

- **No physical device acceptance is currently available.** Pixel 8a NOT currently connected (last seen 2026-10-29/30; ADB reported no device on 2026-10-30). No second phone. The verification package `com.chaaya.app.chaaya.verification` was **lost 2026-10-29** (presumed uninstalled by integration-test teardown; device logs do not independently prove it); its account is unrecoverable without the owner-held BIP-39 recovery phrase (status: **LOST, not compromised**).
- **iOS runtime, iOS signing, TestFlight/ad-hoc/App Store distribution** — none exists. No Apple account or membership has been supplied.
- **Android artifact from CI** — unverified at last poll; no release-signing of CI artifacts (CI opts into test signing only).
- **Second-device Android testing** — not done.
- **Two-phone calling / NAT / TURN / push** — not done; foreground WebRTC unit/integration evidence only; no working TURN service bundled.
- **Independent cryptographic review / protocol audit / mobile penetration test / production operations review** — NOT commissioned. This is a hard gate for any PQ or restore claim and for any final/release wording.
- **Render production / paid plan** — free tier only; the free test database at `https://chhaya-ys50.onrender.com` **expires 2026-11-27**; no owned domain, no monitored long-lived instance, no operations ownership.
- **SBOM / license inventory closure** — incomplete; root `LICENSE` file is effectively empty; project licensing intent unconfirmed. (Backend CI generates an SBOM artifact `Chhaya-Backend-SBOM`, but project-wide license closure is not done.)
- **Store listings** — none (no Play Store, no App Store; no store assets/privacy disclosures submitted).
- **Apple membership** — none.
- **Windows desktop acceptance** — CI debug build only; not launched; local ATL missing.
- **127-row ledger release verification** — 0/127 rows release-verified; all rows carry `NOT RELEASE VERIFIED`.
- **Backend deployed on persistent Postgres** — WS1 prekey backend not deployed; CI not re-run against a persistent instance; no integration evidence on Render.
- **Production backup/restore evidence** — local and CI drills only.
- **PQ (ML-KEM/ML-DSA) in the live messaging path** — not live; primitives present, flag default OFF.
- **iOS PQ vectors / Windows PQ** — pending / do not exist (Windows PQ is a stub).

## 3. Claims policy (binding, copied from SECURITY.md / PRODUCT.md / docs/version-15-status.md §2)

Allowed (with the evidence class named, per row):
- "internal review", "not release verified", "partially implemented".
- "Hybrid PQXDH session establishment (experimental)".
- "ML-KEM/ML-DSA primitives present via AWS-LC v5.11.0 (pinned commit `fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6`)" — as a primitive-availability statement only.
- Engineering-internal statements that name unit / integration / device / audit / CI class.

Forbidden (hard fail in any UI/store/marketing/README/SECURITY.md/CSV/checklist prose):
- "post-quantum secure messaging" / "quantum-safe" / "quantum-proof" — PQ is not live in messaging.
- "secure restore" / "safe restore" / "guaranteed session recovery" — restore/resync defects pinned and partly unremediated; no fix shipped for all known defects; no "secure restore" claim permitted.
- "production ready" / "final" / "v15 complete" / "audited" / "independently reviewed".
- Any multi-device semantics claim.
- Any Windows/iOS PQ availability claim.
- "military grade", "unbreakable", "zero knowledge", "anonymous", "no central server" as product guarantees (PRODUCT.md).
- Any claim that a protocol name, dependency, or design goal is evidence of a deployed protection.

Reference wording for any artifact produced from this prep: "Chhaya is an in-progress privacy-focused messenger. No independent cryptographic protocol audit, mobile penetration test or production operations review has been completed for this version." (SECURITY.md)

## 4. Release gate checklist — PASS / FAIL / UNVERIFIED (carried verbatim in status; nothing flipped to PASS)

| # | Gate | State | Evidence |
|---|---|---|---|
| 1 | Production signing key custody + backup | **FAIL / UNVERIFIED** | Release APK signed with private local key (14.0.1); custody/backup unverified |
| 2 | iOS device + signing | **FAIL / UNVERIFIED** | Unsigned CI artifact only |
| 3 | Second-device Android testing | **FAIL / NOT DONE** | No second phone |
| 4 | Two-phone calling / NAT / TURN / push | **FAIL / NOT DONE** | Foreground WebRTC unit/integration only |
| 5 | Independent cryptographic review | **FAIL / NOT COMMISSIONED** | Hard gate for PQ + any final claim |
| 6 | Render production resources / paid plan | **FAIL / NO-GO (budget)** | Free tier only; DB expires 2026-11-27 |
| 7 | Render backup/restore drill on production | **FAIL / UNVERIFIED** | Local/CI drills only |
| 8 | Hardware prerequisites (all) | **FAIL / UNVERIFIED** | Pixel 8a verification package lost; no current device |
| 9 | 127-row ledger release-verified | **FAIL** | 0/127 rows verified |
| 10 | PQ negotiation / resync implemented + gated | **FAIL / NOT DONE** | Implemented locally behind default-OFF flag (`98aa043`, `ed1ff93`, F1–F7); live loopback NOT RUN (Docker down); two-phone not run; external review gate NOT passed; no PQ claim |
| 11 | Monitoring / alerting / SBOM / licenses | **FAIL / INCOMPLETE** | Basic metrics; license inventory missing |
| 12 | Offline large-attachment/resumable transfers | **FAIL / NOT DONE** | 256 KB inline cap; `docs/spec-media-transfer-v1.md` is a proposed spec only (2026-11-14) — not implemented, claims gated |
| 13 | Authenticated linking/revocation | **FAIL / NOT DONE** | Scaffolding only; legacy "Revoke" UI does not revoke server sessions |
| 14 | Vault/duress/Canary safety features | **FAIL / NOT IMPLEMENTED** | — |
| 15 | Windows desktop acceptance | **FAIL / NOT DONE** | CI debug build only; not launched; local ATL missing |
| 16 | Internal engineering gate (analysis + unit tests green) | **PASS (LOCAL ONLY)** | `flutter analyze` clean (2026-11-08 record, not re-run); 406 unit tests + ~1 skip (LOCAL ONLY, reviewer re-run 2026-11-14) |

**No gate that matters for a public release passes. "Version 15" must not be tagged, shipped, or labeled final.**

## 5. Committed-session window under review (b42d4e5..c4b48e6)

Commits in range (oldest → newest):

`56f054d` adversarial retry/replay coverage (defects pinned, not fixed) · `5d2faf1` WS1 prekey bundle API (not deployed) · `98aa043` WS2 hybrid PQXDH helpers (local) · `1274999` Version 15 preparation status register + PQ spec commit · `4194a35` fail-closed unreadable lock setting · `ed1ff93` WS3 v2 establishment/resync restore wiring (flag OFF) · `2d6b9bb` fail-closed settings lock read · `e022db8` WS3 F1 legacy session persist · `4d2e60b` WS3 F2 stale flight rejection · `fecb2cf` WS3 F7 rollback coverage · `88ea78f` WS3 F4 unreadable session_generation fails closed · `2eeb9b9` WS3 F3 AEAD hard-abort · `1c46316` WS3 F5 AEAD-verified flight adoption · `8eeff19` WS3 F6 echo verification · `c857be5` media-transfer spec + WS3 close-out recorded · `29dacd2` WS3 re-review recorded (`pass_with_observations`; R1/R2/R3 open) · `02d2800` resumable media transfer backend (WS-A; spec-gated, not implemented client-side) · `e5fb360` fail-closed corrupt settings reads · `58beda5` media transfer start persists conversation_id · `eaef7ec` ledger rows 26–127 source-assessment refresh (`release_verified` unchanged) · `3b89eaa` requirements 26–127 assessment recorded · `c4b48e6` bump fast-xml-parser past GHSA-474x-hrwr-fgx4.

These are implementation and record commits. None is release evidence; none flips any checklist, CSV, or gate.

## 6. Open owner decisions (from `docs/version-15-status.md` §10, unresolved)

1. Verification-account recovery phrase custody (account unrecoverable otherwise).
2. Render paid resources — free-tier DB expires 2026-11-27 (recorded no-go absent owner decision).
3. Release signing key custody and backup.
4. Named maintainer/reviewer per feature area (none assigned).
5. Main-package (`com.chaaya.app.chaaya`, private-space user 11) preservation confirmation.
6. PQ review budget — commission external review or formally descope PQ from v15.
7. Reduced-scope honest shipping decision, if gates cannot pass by target date.

## 7. What this document is NOT

Not a release note, not a changelog entry, not a tag, not a claim of readiness, not an audit, not legal or licensing advice, and not a decision to ship. No row of the 127-row ledger was modified. No gate was changed. No license was chosen, asserted, or implied.
