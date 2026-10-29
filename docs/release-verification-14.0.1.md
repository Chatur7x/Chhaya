# Chhaya 14.0.1 verification, 29 October 2026

This is a development release with a signed Android artifact. It does not close
the feature register or the independent security/device acceptance gates.

## Verified locally

- Docker Desktop engine 29.6.2 starts and runs containers. Stale runtime sockets
  prevented startup; their parent runtime directories were preserved outside the
  active paths before restart. No application/database volume was deleted. The
  same Windows socket error recurred on 29 October; the narrowly scoped recovery
  command is `powershell -File scripts/start_docker.ps1 -RepairStaleSockets`.
  Engine startup was reverified afterward; an OS/vendor root-cause fix is not claimed.
- PostgreSQL 16 backend suite: 17 passed, zero skipped, including account
  challenges, authentication, direct/group messages, idempotent retries, receipt
  timestamps, membership isolation, concurrent membership/send, rate limiting,
  migration concurrency/rollback and signaling.
- Two opt-in Flutter integration tests passed against both local Node/PostgreSQL
  and public Render HTTPS/WSS: account connection, direct messages, offline queue
  and lost-acknowledgment exact retry, service recreation, encrypted attachments,
  three-client group replies/polls and membership removal. These clients use
  separate in-memory databases; device-level messaging remains unverified.
- Flutter analysis: no issues. Full host suite in the preceding implementation
  pass: 253 passed, three environment-dependent skips, including the million-message
  ratchet fuzz test. The two live integration skips were subsequently run above;
  host SQLCipher remains unavailable; the separate native device test below passed.
- Compose API image builds and passes its database-backed container health check
  on Node 24.22.1 as uid 1000 with read-only root filesystem and dropped capabilities.
- Pixel 8a / Android 17: all three isolated native security tests pass. Measured
  wrapping level is StrongBox; tampering is rejected. SQLCipher 4.10.0 community
  rejects plain SQLite access and reopens encrypted contacts. AWS-LC 5.11.0
  self-tests, ML-KEM round-trip/rejection and ML-DSA signing/rejection pass.
  These primitive tests do not establish a live post-quantum messaging protocol.
- Native testing found a read-only platform-buffer bug in the PQ bridge; the
  bridge now copies results before wiping them, with a host regression test.
- The isolated preview installed and launched with FLAG_SECURE confirmed. Both
  existing account packages were preserved. USB subsequently disconnected, so
  a repeat startup/lifecycle check could not run.
- Targeted account, measured-storage and platform-buffer tests: 27 passed.
- Custom-format database backup and isolated PostgreSQL restore passed. This
  first drill used an empty application schema; it is not a production-data or
  mobile-account recovery drill. Five backup-operation safeguard tests pass.
- Backend dependency audit reports zero advisories after updating `qs` and
  removing unused Jest dependencies; tests use Node's built-in runner.
- Backend production CycloneDX inventory generated with 274 components. This
  inventory does not cover the Flutter/native application or replace license review.
- Branding checks pass for the existing avatar, five Android icons and 19 iOS icons.
- Android ARM64 release APK builds with version name 14.0.1/code 2 and package
  `com.chaaya.app.chaaya`. APK v2 signature verifies using the new private RSA-4096
  Chhaya signing certificate, rather than the debug certificate.

Artifact: `dist/Chhaya-14.0.1-arm64.apk` (ignored local output).

SHA-256: `e7dbcba744170e4e809cf0550726d6a801fc3b63df581d86013b99bf7329bfad`.

Public testing service: https://chhaya-ys50.onrender.com (`/health` reports
14.0.1 and database ready). Authenticated WSS was exercised by the live test.

## Hosting decision

The owner requested Render with free testing plans only. The Blueprint reflects
that limit. A free PostgreSQL 16 database was created in Singapore and expires on
27 November 2026 according to Render's dashboard. Free web services sleep when
idle; free databases have no managed backups. No paid resources are authorized.

## Unverified boundaries

Two-phone messaging, broader Android/iPhone lifecycle, calls, push, iOS native
storage/key protection and signing, deployment rollback, and independent
protocol review remain separate acceptance gates. Unimplemented roadmap features
retain their statuses in the delivery checklist and 127-feature register.

## CI evidence

- Updated backend, analysis, Flutter host tests and isolated restore drill:
  https://github.com/Chatur7x/Chhaya/actions/runs/40814153886 (passed).
- Android debug and release builds:
  https://github.com/Chatur7x/Chhaya/actions/runs/40813789033 (passed).
- Native provider harness and six ML-DSA ACVP signature-verification vectors:
  https://github.com/Chatur7x/Chhaya/actions/runs/40814153957 (passed after fixing
  an outdated workflow source-directory path).
- iOS build and host tests (unsigned distribution):
  https://github.com/Chatur7x/Chhaya/actions/runs/40813789021 (passed).
- Final 29 October HTTPS/WSS client rerun against the deployed Node 24 service:
  two passed in 23 seconds. A duplicate local full-suite run was stopped during
  the long fuzz test after the equivalent full CI suite passed; it is not counted
  as another completed local full-suite result.
