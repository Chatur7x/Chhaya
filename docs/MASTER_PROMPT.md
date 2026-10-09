# Chhaya V14 — Master Execution Prompt

Repo: https://github.com/Chatur7x/Chhaya

Rules: One task = one branch = one PR = one report. Stop after each.

## Frozen stack

Flutter 3.47.1 / Dart 3.13+, Riverpod 2.6, cryptography ^2.7.0,
pointycastle ^3.9.1, flutter_secure_storage, sqflite_sqlcipher,
shared_preferences 2.2.0 PINNED, mobile_scanner 7.2.0 PINNED,
Node.js 20, TypeScript 5.3, Express 4.18, PostgreSQL 16, Redis 7,
Docker + Nginx, Claude Light (#D97757 on #F5F4EF),
fonts: Inter + Tiempos + DEPΛ2TɄRE_MONO v1.500

## Absolute rules

1. Never touch main directly. Branch → PR → wait.
2. Never force-push. Never amend pushed commits.
3. Never merge your own PR.
4. Extend, don't rewrite. Preserve public APIs.
5. No new deps without approval.
6. No keys/PII in logs.
7. All SQL parameterized.
8. Zero analyzer issues before reporting.
9. All tests pass before reporting.
10. Stop after each report.

## Task queue

| ID | Task | Branch |
|---|---|---|
| 0 | android-build CI fix | `ci/android-sdk-setup` |
| 1 | Local database (SQLCipher) | `part-03-local-database` |
| 2 | Crypto primitives | — |
| 3 | Triple ratchet (Double + SPQR) | `part-04-triple-ratchet` |
| 4 | Post-quantum hybrid KEX | `part-05-pqc-hybrid` |
| 5 | Claude Light tokens | `part-06-claude-light-tokens` |
| 6 | UI widgets | `part-07-widgets` |
| 7 | Screens (Claude Light rebuild) | `part-08-screens` |
| 8 | Backend API restructure | `part-09-backend-api` |
| 9 | WebSocket + onion relay | `part-10-ws-onion` |
| 10 | Push notifications | `part-11-push` |
| 11 | Arke handshake + shadow codes | `part-12-arke` |
| 12 | Mesh networking | `part-13-mesh` |
| 13 | Vault + duress | `part-14-vault-duress` |
| F1–F8 | Docs, a11y, perf, pentest prep, audit prep, Play Store, launch, ops | see below |

### Part 7 — UI widgets

Branch `part-07-widgets`.

Widgets: `chhaya_button.dart`, `chhaya_card.dart`, `chhaya_input.dart`,
`chhaya_chat_bubble.dart`, `chhaya_avatar.dart`, `chhaya_pressable.dart`,
`chhaya_notification_overlay.dart`, `chhaya_bottom_nav.dart`,
`chhaya_app_bar.dart`.

Acceptance: themeable via the token layer with zero hardcoded values,
haptics on primary actions, no visible Material/Cupertino defaults,
tappables ≥ 44×44 dp, zero analyzer issues. No golden tests — see
`decisions/no-golden-tests.md`.

### Part 8 — Screens (Claude Light rebuild)

Branch `part-08-screens`, from refreshed main after Part 7 merges.

Screens: `onboarding/`, `chat_list/`, `chat/`, `contacts/contacts_tab.dart`,
`profile/`, `verification/`, `calls/calls_tab.dart`, `calls/call_screen.dart`,
`settings/`, `home/home_shell.dart`.

Rules: replace V13 hacker-terminal styling with Claude Light; preserve all
functional behaviour; navigation via `chhaya_router.dart` only; no inline
colours (tokens only); no inline text styles (tokens only); Part 7 widgets
exclusively; remove leftover V13 styling.

Acceptance: behaviour test per screen (no goldens); responsive at phone
360–430 dp, tablet 600–900 dp, desktop 1200 dp+; a11y audit pass (semantics,
44×44 targets); Part 6 guard test passes; navigation via router; zero
analyzer issues.

### Part 9 — Backend API

Branch `part-09-backend-api`.

Restructure via `git mv` into `routes/`, `middleware/`, `types/`. Install
`pg`, `redis`, `express-rate-limit`, and `-D @types/pg`.

17 endpoints: auth register/login, users/me + settings, contacts list/create,
conversations list/create, messages list/create/read, devices/link,
push/subscribe, onion nodes/path, `/health`, `/metrics`.

Acceptance: all endpoints implemented with integration tests; rate limiting
works; no SQL injection (parameterized only); structured JSON logs with no
PII; `/health` 200 and `/metrics` Prometheus; zero TS strict errors.

### Part 10 — WebSocket + onion relay

Branch `part-10-ws-onion`. `signaling.ts` (8444), `onion-relay.ts` (8445),
types for signaling message / onion packet / onion node / circuit.

Acceptance: 10K concurrent signaling connections; 3-hop circuits
end-to-end; 10-minute circuit lifetime with auto-renew; region diversity
enforced; no plaintext relay logs.

### Part 11 — Push notifications

Branch `part-11-push`. `push/{fcm,apns,tokens,topics}.ts` + tests.

Acceptance: FCM and APNs functional; daily stale-token cleanup; no metadata
leaks in payloads; "no push" mode documented (Tor + TAP heartbeat).

### Part 12 — Arke handshake + shadow codes

Branch `part-12-arke`. `services/contact/{arke_handshake,shadow_code,
qr_generator,qr_scanner}.dart`; `backend/server/src/arke/{matchmaker,
shadow_pool}.ts`. Replace the demo pubkey at `contacts_tab.dart:182-183`
with a real Arke handshake; remove the placeholder entirely.

Acceptance: server cannot link two users; shadow codes rotate every 60 s and
are single-use; QR scan works offline; handshake Byzantine fault tolerant.
**Ready-for-audit item.**

### Part 13 — Mesh networking

Branch `part-13-mesh`. `services/network/mesh/{ble_mesh,wifi_aware,
relay_election,mesh_router}.dart`.

Acceptance: two devices communicate offline; deterministic relay election;
seamless fallback to internet; battery < 5%/hour; tested Android 12+ / iOS 15+.

### Part 14 — Vault + duress

Branch `part-14-vault-duress`. `services/vault/{encrypted_vault,
screenshot_interceptor,duress_pin,duress_iris,canary_protocol,
dead_mans_switch}.dart`; `services/defense/{anti_peek,gaze_detection,
face_detection}.dart`.

Acceptance: screenshots never reach the gallery; vault unlock requires
biometric/iris; duress PIN shows decoy UI; CANARY silently alerts contacts;
auto-blank on second face; SHA-256 tamper detection.
**Ready-for-audit item.**

## Polish phase F1–F8 (one PR each)

| ID | Task | Branch |
|---|---|---|
| F1 | `docs/complete` — architecture, threat-model, crypto-spec, protocol, onion-routing, mesh, duress, faq | `docs/complete` |
| F2 | `a11y/audit` — screen readers, contrast, targets, reduced motion, text scaling, RTL; a11y tests in CI | `a11y/audit` |
| F3 | `perf/benchmarks` — crypto, ratchet, DB, onion, mesh, startup → `docs/benchmarks.md` | `perf/benchmarks` |
| F4 | `security/pentest-prep` — `docs/pentest-checklist.md` | `security/pentest-prep` |
| F5 | `security/audit-prep` — freeze v14.0.0-rc1, SBOM, primitive docs, test vectors, verification scripts, audit scope; contact Trail of Bits / Cure53 / NCC Group | `security/audit-prep` |
| F6 | `release/play-store` — icon, feature graphic, screenshots, descriptions, privacy policy, data safety, rating, deletion flow, signed APK | `release/play-store` |
| F7 | `release/launch` — README, Discussions, Sponsors, CODE_OF_CONDUCT, templates, release notes, launch posts | `release/launch` |
| F8 | `ops/monitoring` — self-hosted Sentry, opt-in analytics, Grafana, email + Telegram alerting, runbook | `ops/monitoring` |

## Report format (every task)

- **Branch:** `<name>` @ `<commit>`
- **PR URL:** `<link>`
- **Files created/modified:** list with counts
- **Test results:** analyze / test / APK build / TS strict
- **Deviations:** none, or list with reason
- **Blockers:** none, or list
- **Questions:** none, or list
- **Ready for external audit:** yes/no — Parts 4, 5, 12, 14
- **Next task queued:** name

STOP — await approval.

## Human-only tasks (agent must not attempt)

- Open every PR (agent reports URL; human opens)
- Merge every PR (agent never merges)
- File the GitHub Security Advisory
- Update the Chaaya-V1.0.4 release notes
- Sign the release APK
- Contact external auditors
- Publish to the Play Store

## Decisions on record

- [`decisions/pqc-library.md`](decisions/pqc-library.md) — pure-Dart `pqcrypto`
- [`decisions/no-golden-tests.md`](decisions/no-golden-tests.md) — behaviour assertions only
- [`decisions/loadtest-location.md`](decisions/loadtest-location.md) — toolkit under `backend/server/loadtest/`