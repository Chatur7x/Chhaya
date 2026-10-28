# Chhaya 14.0.1 verification, 28 October 2026

This is a development release with a signed Android artifact. It does not close
the feature register or the independent security/device acceptance gates.

## Verified locally

- Docker Desktop engine 29.6.2 starts and runs containers. Stale runtime sockets
  prevented startup; their parent runtime directories were preserved outside the
  active paths before restart. No application/database volume was deleted.
- PostgreSQL 16 backend suite: 17 passed, zero skipped, including account
  challenges, authentication, direct/group messages, idempotent retries, receipt
  timestamps, membership isolation, concurrent membership/send, rate limiting,
  migration concurrency/rollback and signaling.
- Two opt-in Flutter integration tests passed against a real local Node/PostgreSQL
  server: account connection, direct messages in both directions, three-client
  group replies and messaging after member removal. Client storage in these tests
  uses separate in-memory test databases; this is not a native SQLCipher proof.
- Flutter analysis: no issues. Full host suite in the preceding implementation
  pass: 253 passed, three environment-dependent skips, including the million-message
  ratchet fuzz test. The two live integration skips were subsequently run above;
  native SQLCipher evidence remains unavailable on this host.
- Compose API image builds and passes its database-backed container health check.
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

SHA-256: `97fac2bf62501e0718f194ecb5db510614e079b136b76d650d0e6501146dcc53`.

## Hosting decision

The owner requested Render with free testing plans only. The Blueprint reflects
that limit. A free PostgreSQL 16 database was created in Singapore and expires on
27 November 2026 according to Render's dashboard. Free web services sleep when
idle; free databases have no managed backups. No paid resources are authorized.

## Unverified boundaries

Physical Android/iPhone lifecycle, calls, push, native at-rest storage, hardware
key protection, iOS signing, public deployment and rollback, and independent
protocol review remain separate acceptance gates. Unimplemented roadmap features
retain their statuses in the delivery checklist and 127-feature register.
