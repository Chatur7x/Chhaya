# Spec: Chhaya v1 — Authenticated Device Linking (Approval, Per-Device Sessions, Revocation Propagation, Recovery)

- **Status:** Proposed spec. Not implemented. Not release-verified.
- **Date:** 2026-11-14
- **Author:** specifier (subagent) — repo `D:\Projects\PROJ16`
- **Provenance:** Closes the audit's open "must fix #2" (`docs/ponytail-audit-2026-10-29.md`, finding 2). Derived only from repo primitives and existing endpoint patterns: X25519 ECDH (`lib/core/crypto/primitives/x25519.dart`), Ed25519 signatures (`primitives/ed25519.dart`), HKDF-SHA256 (`primitives/hkdf.dart`), AES-256-GCM AEAD (`primitives/aes_gcm.dart`), the `identity_challenges`/`auth_sessions` server model (`backend/server/src/identity-proof.ts`, `session.ts`), and the `devices` tables that already exist in both stores. **No new cryptography is invented.**
- **Do not:** flip any status in `docs/feature-verification-127.csv` or `docs/delivery-checklist.md` as part of this spec or its implementation.

---

## 1. Purpose & claims policy

### 1.1 Purpose

Replace `AuthService.generateDeviceLinkCode` (which today mints a public-key QR string with no persisted private key, no approval, no sessions, no revocation) with a complete, testable authenticated enrollment protocol. Deliver:

1. **Link request** — new (unenrolled) device proves control of an ephemeral key and publishes a one-time, expiring code.
2. **Approval** — an enrolled (primary) device authenticates and authorizes the new device over an AEAD-encrypted, signature-consented channel.
3. **Per-device server sessions** — the new device gets its own server token scoped to its own device record.
4. **Revocation propagation** — revoking a device kills its sessions server-side and is reported to the owner.
5. **Safe recovery** — lost-primary remains phrase-restore only; linking is never a recovery path.

### 1.2 Claims policy (binding)

**Forbidden user-facing claims (hard-fail strings, any UI/store/marketing/README/SECURITY.md/CSV prose) until shipped AND device-tested:**

- "linked devices work", "multi-device sync", "full sync", "your messages on all devices", "desktop messaging"
- "revocation deletes data from the device" (it does not; see §3.6)
- "linking backs up your account", "linking restores messages"
- Any claim that a linked device can read, send, or sync messages (v1: impossible by construction, §3.4)

**Allowed (this spec's maximum):**

- "Experimental: link another device to your Chhaya account for contacts and profile. Messages stay on the device where they were written. Not independently reviewed."
- "Revoke a linked device at any time; its access to your account ends immediately."
- Engineering/internal: "authenticated device linking v1 (per-device sessions); message sync not included"

Upgrading any claim requires shipped + two-device acceptance evidence and a lead/human decision updating `docs/delivery-checklist.md` ("Multi-device pairing/revocation" row). This spec does not pre-authorize any wording.

### 1.3 Honest scope (the "one active messaging device" rule)

Per `docs/spec-pq-hybrid-resync-v1.md` (claims policy §1.2, non-goal §7.1.1 — the reference there called §B9; same content, one active messaging device per account): v1 linking grants **account-metadata access only**. See §3.7 for exactly what syncs and what never does.

---

## 2. Threat model delta vs `docs/threat-model.md`

Base document unchanged. This section **adds**. None relax existing boundaries.

### 2.1 Enrolled vs unenrolled device

- **Unenrolled** (no approved link): no server session exists; every `/api/v1/*` call returns 401; no account data reachable. The `devices` table row may exist (pre-link registration inserts none — rows are created only at consume, §4.4).
- **Enrolled**: authenticated via a per-device token; account-metadata scope only; cryptographically incapable of producing messaging envelopes (§3.4).

### 2.2 Rogue link attempt via stolen QR

QR/code is **one-time**, **≤ 5 min expiry**, **rate-limited** at request, status, approve and consume surfaces. An attacker who photographs the QR within the window can only cause an *approval to target the victim's new device*, not to an attacker device: the approval blob is AEAD-encrypted under a key derived from the new device's ephemeral X25519 private key (§3.2). A stolen code without the ephemeral private half yields at most an unusable encrypted blob. A stolen QR + a malicious *primary* is out of scope (the user chose what to scan); the fingerprint check (§3.5) is the user-facing mitigation.

### 2.3 Replay

- Link code redeemed once; server state machine enforces `pending → approved → consumed` (§4.5); replays of consume get 409.
- Expired requests are rejected at approve and consume with 410; expired pendings are deleted on read.
- Approval payload carries `exp` and is bound to the code via the HKDF salt (§3.3); a replayed approval from a prior request fails AEAD.

### 2.4 MITM on the pairing channel

A network MITM who cannot see the QR cannot derive the ECDH secret. A MITM who *substitutes* `ephPubNew` or `primEphPub` produces a different HKDF salt ⇒ either AEAD verification fails on the new device (hard abort) or the fingerprints shown on the two screens differ (§3.5). Fail-closed; no fallback.

### 2.5 Revoked device rejoining

Revocation (§4.6) deletes the device's `auth_sessions` rows and sets `devices.revoked_at` in one transaction; subsequent calls authenticate against `auth_sessions JOIN users` with `u.is_active` AND a `revoked_at IS NULL` device check (§4.3) ⇒ 401. The device retains any data already on it (client-side residual, §3.6); it cannot re-auth, cannot re-pull contacts, cannot approve new links (approvals require an authenticated session).

### 2.6 Lost primary

Linking is **not** a recovery mechanism. Losing the only enrolled device ⇒ account access via recovery phrase restore only (existing flow, unchanged). Linked devices cannot elevate, cannot approve their own re-link, cannot recover the primary's keys. The Approve screen must state this.

### 2.7 Unchanged / residual risks (explicit)

- Server sees account IDs, device names/platforms, timing, sizes, addresses — unchanged.
- Approval channel reveals to the server *that* a link happened (metadata), and the encrypted blob size. Not solved here.
- Best-effort Dart memory wiping; ECDH/session secrets follow `Csprng.wipe` where already applied.
- Compromised unlocked device — unchanged.
- Server is semi-trusted for availability: it can withhold the approval blob (DoS, not confidentiality). Mitigation: retry is safe (idempotent, §4.5); expiry bounds the window; no silent degradation.
- Free Render testing service: sleep/expiry can silently drop pending link rows. Clients must tolerate 404/410 and fail closed. No production availability claim references Render.

---

## 3. Protocol definition

### 3.1 Actors & materials (all from repo primitives)

- **New device (N):** generates ephemeral X25519 pair `(eN_priv, eN_pub)` and a device Ed25519 keypair `(d_priv, d_pub)`. No account keys exist yet on N.
- **Primary (P)** (any authenticated session of the account, in v1 typically the phone): holds the account Ed25519 identity seed (`chhaya_identity_ed25519_seed` / derived via `KeyManager.derivePathKey('identity/ed25519')`).
- **Server:** stores only public material + hashes; issues per-device tokens; never sees plaintext approvals.

### 3.2 Request flight (N → server → P)

1. N: `POST /api/v1/devices/link/request` (unauthenticated; rate-limit 10/hour/IP, keyed-HMAC caller identity per `rate-limit.ts` pattern):
   ```json
   { "deviceId": "<uuid>", "deviceName": "My laptop", "platform": "windows",
     "devicePublicKey": "<64hex ed25519>", "ephemeralPublicKey": "<64hex x25519>",
     "codeHash": "<64hex sha256 of the 128-bit one-time code>" }
   ```
   Server stores `device_link_requests(request_id PK, device_id UNIQUE-among-pending, …, code_hash, state='pending', expires_at = NOW()+5min)` and returns `{requestId}`. Raw code never stored; `ephPub` is NULLed at consume (§4.4).
2. N displays: QR encoding `Chhaya-link-v1:{requestId}:{code}:{ephPub}:{dPub}` **and** the 6-word rendering? No — displays `code` (e.g. 8-char base32 groups) as fallback. QR content and code are one-time; screen shows "expires in 5:00".
3. P scans/enters code. P verifies syntactic validity locally, then calls `POST /api/v1/devices/link/approve` with its existing bearer token (§4.4). P **never** sees a plaintext secret from the server.

### 3.3 ECDH + approval derivation (byte-exact)

P generates its own ephemeral X25519 pair `(eP_priv, eP_pub)`. Both sides compute (N computes on approval receipt):

```
SS   = X25519(eP_priv, ephPub_N) == X25519(eN_priv, eP_pub)
salt = SHA256( LP("Chhaya-DeviceLink-v1") ‖ LP(code) ‖ eN_pub ‖ eP_pub )     # LP = length-prefixed, u16be len ‖ bytes
SK   = HKDF-SHA256(ikm=SS, salt=salt, info=LP("Chhaya-DeviceLink-v1/session"), L=32)
fp   = SHA256( LP("Chhaya-DeviceLink-v1/fp") ‖ eN_pub ‖ eP_pub )[0..8]       # 16 hex chars, shown on both screens
```

Approval payload (P → N, carried inside AEAD):

```
transcript = LP("Chhaya-DeviceLink-v1/approval") ‖ requestId ‖ code ‖ eN_pub ‖ eP_pub
           ‖ account chhayaId ‖ account Ed25519 pubkey ‖ d_pub ‖ exp (u64be ms) ‖ capabilities ("metadata")
sig        = Ed25519_sign(account_identity_ed25519_seed, transcript)
body       = LP fields exactly as above ‖ sig                                  # sig covers transcript, not body
approval   = AesGcm.encrypt(SK, body, aad = LP("Chhaya-DeviceLink-v1/approval-aad") ‖ requestId ‖ fp)
```

The Ed25519 signature authenticates *which account* approved (N learns the account pubkey from inside the AEAD; N cannot verify it against a pre-existing value — trust is bootstrapped by the QR screen showing `account chhayaId` and `fp`, which the user compares; see §3.5 and Appendix OQ-2). `sig` lets a future auditor / the new device prove P authorized this exact d_pub.

### 3.4 Design decision: device-scoped keys + server authorization (not identity-seed transfer)

**Chosen: Option B — device-scoped keys; account identity stays on the original device; the server authorizes per-device sessions.**

Rejected: Option A (ship the master seed / identity private material to N over the AEAD channel).

Justification:
- **Revocation must work.** Under A, a revoked device still holds the account root: it can decrypt old backups, derive database and identity keys forever, and impersonate the account to peers. Revocation would be theatre (§2.5 promises 401s, which A cannot deliver at the protocol layer).
- **Matches repo reality.** The server already authenticates sessions per token and the `devices` table already stores a per-device `public_key`; nothing on the client requires the account seed on two hosts. Option A would also silently widen the Windows/SQLCipher threat surface.
- **Messaging impossibility is a feature.** N holds no X25519/Ed25519 account identity and no ratchet state ⇒ N cannot produce or accept any valid messaging envelope. Server-side enforcement (§4.6) is defense in depth, not the only barrier.
- **Backups remain the recovery path.** Phrase restore re-creates the identity on any device; linking never duplicates seed material, so there is nothing extra to shred on revoke.

Cost accepted: N cannot decrypt existing history or send in any conversation. This is the honest v1 boundary (§3.7), not a bug.

**Storage at N (after consume):** `deviceId` (SQLCipher kv), `chhaya_device_ed25519_seed` (platform secure storage, same class as V13 keys), `SK` wiped immediately after decrypting+verifying the approval; `ephPub/ephPriv` wiped after use. **At P:** `(eP_priv, SK, body plaintext)` wiped after send; only the transmitted `approval` blob (AEAD) is ever stored server-side.

**On revoke (§4.6):** P's side adds `revokedAt` to the local device record; N's side wipes its device seed and clears its per-device session token on next launch (or immediately if reachable); the server deletes N's sessions and marks the row. Nothing else is destroyed.

### 3.5 Fingerprint & approval UX bounds

- Both screens show `fp` (16 hex, grouped 4-4-4-4) and N's `deviceName`. P shows "Link to \"<name>\"?"; N shows "Link to account <chhayaId[:7]>… <fp>?". One primary mismatch ⇒ abort, wipe, no server write beyond the (harmless) pendings row.
- One pending approval at a time on P; Approve button disabled until explicit tap; 5-minute countdown; auto-abort on timeout.
- Reject/deny is a first-class path: P sends `{state:'denied'}` (still authenticated, same endpoint with `action:'deny'`); N surfaces "Link declined".

### 3.6 Revocation semantics (honest)

Revocation ends **server access** (401 on all endpoints, signaling socket closed per `signaling.ts` pattern). It does **not** and cannot erase data already on N (message metadata it never received, its own logs, its own backups). UI copy: "Access ended. Data already on that device is not erased." Revocation is idempotent and audited (`device_link_events`). If N is the currently authenticated device making the revoke call: **forbidden** (must use logout/account-removal flow instead) — enforced server-side.

### 3.7 What syncs in v1 (normative)

| Surface | Syncs? | Notes |
|---|---|---|
| Contacts (names, verification flags, block list) | **Yes** | via existing account-scoped endpoints; server sees account IDs/metadata as today |
| Profile (display name) | **Yes** | existing `PATCH /profile` |
| Account settings | **Yes** | non-biometric toggles only |
| Message history / ratchet state / keys | **No** | cryptographically impossible on N (§3.4); no history fetch API is added |
| Group membership, group keys | **No** | out of scope (unchanged trusted-server model) |
| Backups | **No** | phrase-restore only |
| Anything via PQ-hybrid path | **No** | unaffected; sync rides classical account endpoints |

UI must state the "contacts/profile only, no messages" rule before linking. CSV/checklist rows for messaging and PQ are **not** moved by this work.

### 3.8 Server as semi-trusted broker

Server can: withhold/delay approval (DoS), see link metadata and timing, attempt replay of blobs (rejected by AEAD+expiry), log `codeHash` (uncrackable: 128-bit code, SHA-256). Server cannot: derive SK, forge `sig`, approve without P's authenticated session, link any device other than one holding `d_priv`.

---

## 4. Server API (`backend/server/src/`)

### 4.1 Schema (additive only — `db.ts` append-only migration; never edit existing entries)

```sql
CREATE TABLE IF NOT EXISTS device_link_requests (
  request_id UUID PRIMARY KEY,
  device_id UUID NOT NULL,              -- fresh uuid generated by N
  device_name VARCHAR(100) NOT NULL,
  platform VARCHAR(20) NOT NULL,
  device_public_key CHAR(64) NOT NULL,  -- ed25519, hex
  ephemeral_public_key CHAR(64),        -- x25519, hex; NULLed at consume
  code_hash CHAR(64) NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('pending','approved','denied','consumed','expired')),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,   -- set at approve
  approval BYTEA, approval_signature TEXT, denied_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_link_pending_device
  ON device_link_requests (device_id) WHERE state IN ('pending','approved');
CREATE TABLE IF NOT EXISTS device_link_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  device_id UUID, action TEXT NOT NULL,  -- request/approve/deny/consume/revoke
  at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;   -- soft revoke, keeps audit trail
ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS device_id UUID;     -- per-device token binding
CREATE INDEX IF NOT EXISTS idx_auth_sessions_device ON auth_sessions(device_id);
```

No existing table is rewritten; `devices.fcm_token` stays; revoked rows keep `public_key` for audit and are excluded by `revoked_at IS NULL` predicates.

### 4.2 `POST /api/v1/devices/link/request`
Request: body per §3.2. Rate-limit 10/hour/IP. Validations: uuids valid; keys 64-lowercase-hex; `expires_at` server-set (client never supplies). **Idempotent**: re-request with same `deviceId` while pending ⇒ returns existing `{requestId}` (200), no duplicate row. Errors: 400 invalid, 429 limited. Response `201 {requestId, expiresAt}`.

### 4.3 Approval authorization & token scoping
`authMiddleware` unchanged, but `authenticateToken` (`session.ts`) is extended to `SELECT u.id, s.device_id` and `issueSession(userId, deviceId?)` inserts `device_id`. All `/devices/*` endpoints additionally require `devices.revoked_at IS NULL` for the caller's device binding (revoked ⇒ 401). Approvals are authorized to **any currently enrolled session of the account** (v1 has exactly one); a future "primary-only" tightening is OQ-4. Server sets `user_id` on the pending row at approval time — the request row is bound to one account exactly once (second approve by same account ⇒ §4.5 idempotency; by another account ⇒ 409).

### 4.4 Endpoints (exact paths/methods)

| # | Method & path | Auth | Purpose |
|---|---|---|---|
| 1 | `POST /api/v1/devices/link/request` | none (RL 10/h/IP) | N registers pending link; response `{requestId, expiresAt}` |
| 2 | `POST /api/v1/devices/link/approve` | **required** (account session) | P approves or denies. Body `{requestId, code?, action:'approve'|'deny', approval?: base64, approvalSignature?: hex}`. Server: row must exist, `expires_at > NOW()`, `state='pending'`, `sha256(code) == code_hash` (deny may omit payload but not code). On approve: `state='approved'`, store blob+sig, `user_id` bound, audit event. |
| 3 | `GET /api/v1/devices/link/status/{requestId}` | none (RL 30/h/IP) | N polls. `200 {state}`; when `approved`: `{state:'approved', approval, approvalSignature, serverPublicEphemeral? no—P sends its eP_pub inside request-approve body}` (note: P includes `primEphPub` in the approve body; server stores it). When expired: `410` code `link_expired`. |
| 4 | `POST /api/v1/devices/link/consume` | none (RL 10/h/IP) | N presents `{requestId, code}`; server: row `state='approved'`, code hash match, expiry check ⇒ transaction: `state='consumed'`, `ephemeral_public_key=NULL`, **INSERT into `devices (user_id, id, device_name, platform, public_key, is_linked, created_at)`** (reuses existing register path; `ON CONFLICT (id) DO UPDATE … WHERE user_id matches` else 409), INSERT `auth_sessions(token_hash, user_id, device_id=requestId's deviceId, expires_at=NOW()+30d)`, audit. Returns `{userId, deviceId, token}`. |
| 5 | `GET /api/v1/devices` | **required** | List `{deviceId, name, platform, createdAt, lastActiveAt, isCurrent, revokedAt}` — caller's own device via `s.device_id`; revoked entries included flagged (transparency). |
| 6 | `DELETE /api/v1/devices/{deviceId}` | **required** | Revoke. Rules: `≠ caller's deviceId` (else 400 `use_logout`); row must belong to caller (`user_id` match) else 404; transaction: set `revoked_at=NOW()`, `DELETE FROM auth_sessions WHERE device_id=$1`, clear `fcm_token`, audit `revoke`. Idempotent: already revoked ⇒ `200 {revoked:true}`; re-revoke ≠ 409. |

Consume is **one-shot**: concurrent consumes race on the conditional `UPDATE … WHERE state='approved' AND expires_at > NOW() RETURNING …`; exactly one wins, loser gets 409. Concurrent approve of the same request: second approve with identical signature+payload is a `200` no-op (idempotent retry); mismatch ⇒ 409. Approve against a row approved by the *same* account with same everything ⇒ 200; different account ⇒ 409 (`request_already_claimed` — should be impossible since rows have no account until approve, but enforce).

### 4.5 Expiry & cleanup
`expires_at` always `NOW()+5min` (server-set). All reads filter expiry; a `pruneExpiredRateLimits`-style daily sweep deletes `device_link_requests` past `expires_at` + 1 day and stale `device_link_events` per retention policy (Appendix OQ-5). Approved-but-unconsumed rows expire too (N may never return; safe to re-request — new `deviceId`).

### 4.6 Store-only-public-material rule (normative)
Server rows contain only: public keys, hashes of the code, opaque AEAD bytes, signatures over public transcripts, timestamps, names. No private keys, no SK, no plaintext approval, no recovery phrase, no message keys. `code` (raw) is transient in memory only. Any PR that stores more fails review by inspection.

---

## 5. Client behavior (integration sites — **not** implemented here)

### 5.1 Files touched (expected)

- `lib/services/auth/auth_service.dart` — `generateDeviceLinkCode` **replaced** by `DeviceLinkService` (new file `lib/services/auth/device_link_service.dart`); old method deleted (not deprecated) to avoid dual paths.
- `lib/core/crypto/key_manager.dart` — additive: `generateDeviceKeyPair()`/`storeDeviceSeed`/`clearDeviceSeed` (mirror V13 naming), reuse `derivePathKey` style for `device-link/session` HKDF? No — session SK comes from the link ECDH directly (§3.3), not from master seed.
- `lib/core/database/local_database.dart` — additive migration: `devices` table gains `revoked_at` (nullable) + kv key `link_request_pending`; `getLinkedDevices()` returns `createdAt/lastSeen/revokedAt`; `removeLinkedDevice` → soft `markLinkedDeviceRevoked`.
- `lib/ui/screens/settings/settings_screen.dart` — `_showLinkedDevices` rewritten: real list (from DB), link CTA, per-row Revoke with confirm dialog; "no message sync" disclosure text (§3.7) shown before any link.
- `lib/ui/screens/settings/device_link_screen.dart` (new) — compare-`fp` screen; Approve/Deny; countdown.
- `backend/server/src/{routes.ts (or new devices.ts router), db.ts, session.ts}` — per §4.
- `lib/services/api/api_service.dart` — four new methods matching §4.4.

### 5.2 Per-device local record (KeyManager + DB)

`deviceId, name, platform, createdAt, lastSeen, revokedAt?, devicePublicKey` on both sides of the pair (P writes its own record for N at approve-time; N writes its own record at consume-time). `lastSeen` updated on any authenticated response (client-side, best effort).

### 5.3 Honesty rule in UI (binding)
Before linking, show verbatim: "Linked devices see your contacts and profile. They cannot read or send messages." Settings → Linked Devices sheet keeps the existing honest disclaimer until tests in §6 pass on device. After ship: copy changes only with the §1.2 policy and lead decision.

### 5.4 Approval / revocation UX bounds
Approval: single pending, 5-min countdown, explicit compare step, haptic+dialog confirm, no auto-approve. Revocation: confirm dialog naming the device; result refetch; empty state copy ("No devices linked yet"). Both must be reachable with screen-reader semantics matching existing settings tiles.

---

## 6. Tests (TDD — write failing tests first; hermetic; `test/` + `backend/server/test/`)

Harness pattern: two in-memory Flutter clients through the loopback Node backend + disposable `chhaya_test` PostgreSQL (as in `test/integration/live_messaging_flow_test.dart`); backend unit tests as `.cjs` mirroring existing suite.

1. **Request→approve→verify happy path** — N requests, P approves, N consumes; N then authenticates `GET /devices` → 200 and sees both devices; fingerprints match.
2. **Wrong code rejected** — approve/consume with a code that does not hash to `code_hash` ⇒ 401/403; no state change; N still pending.
3. **Expiry** — approve and consume after `expires_at` ⇒ 410; pendings deleted; N fail-closed.
4. **Replay of a redeemed code** — double consume ⇒ exactly one 200 (second 409); double approve ⇒ idempotent 200/409 per §4.4; consumed request cannot be re-approved.
5. **Revoked device rejected** — P revokes N; N's next authenticated call ⇒ 401; signaling socket path closed; N's re-consume of the same request ⇒ 409/410.
6. **Concurrent enroll / redundant approval** — two parallel approve calls with identical payload ⇒ one row transition, both 200; conflicting payload ⇒ one 200, one 409. Two pending requests for same `deviceId` ⇒ one row (partial unique index).
7. **Adversarial role confusion** — N cannot call approve (unauthenticated ⇒ 401); P cannot call consume with P's own account session to claim N's `deviceId` (code required; consume not bearer-authed); a third account's session cannot approve/consume another's pending (409/404); a revoked device cannot approve.
8. **MITM/substitution** — flipping any bit of `ephPub`/`primEphPub`/`code` in transit ⇒ AEAD or fingerprint mismatch ⇒ hard abort, no `devices` row created.
9. **Self-revocation refused** — `DELETE /devices/{ownId}` ⇒ 400; account still accessible.
10. **Audit** — `device_link_events` contains request/approve/consume/revoke in order; no secret material present in any row (scan test).

Static checks: grep gate that `auth_sessions`/`device_link_requests` contain no private-key-length blobs; `flutter analyze`; backend `npm run lint && npm test`.

---

## 7. Non-goals (explicit, binding)

1. **Message sync to the new device** — requires v2 per-device distribution + the PQ-hybrid gate; out of scope; must not be implied.
2. **Group membership/key sync** — unchanged trusted-server model; out of scope.
3. **QR-based APK/binary distribution** — linking never ships binaries.
4. **Apple Keychain / Android StrongBox specifics** — device key storage uses the same abstraction as existing keys; no new guarantees, no universal-StrongBox claim.
5. **Making this a gate for the PQ external-review** — the §7.2 PQ review gate does not block this spec's implementation; however, lead merge sign-off is still required, and no claim may exceed §1.2.
6. **Self-host/ops runbook, Render free-tier persistence** — operator concern; no production SLA implied.
7. **Multi-device ratchet/Sesame, per-device message keys, read-receipt fanout** — v2+ territory (`spec-pq-hybrid-resync-v1.md` §7.1.1).
8. **Recovery via linking** — recovery is phrase-restore only; linking is never a substitute.
9. **Revocation erasing remote data** — impossible and not attempted; copy in §3.6.
10. **No changes to `docs/feature-verification-127.csv` / `docs/delivery-checklist.md` statuses** in this work; the "Multi-device pairing/revocation" row stays unchanged.

---

## 8. External gates / review

Shipping requires: (a) §6 tests green on CI PostgreSQL; (b) one two-phone (or phone+desktop) acceptance run recorded in the ledger; (c) lead sign-off; (d) claims audit (grep forbidden strings of §1.2) = zero hits. Independent cryptographic review is **recommended** for the approval transcript (§3.3) but is not the PQ gate; if unavailable, residual risk is carried openly in claims ("not independently reviewed").

---

## 9. Rollback plan

1. Server: hide endpoints (404) or return 503; pending rows inert; `devices`/`auth_sessions` additive columns remain (harmless).
2. Client: settings sheet reverts to existing "not available yet" wording (one-line revert in `settings_screen.dart`).
3. Existing enrolled devices: their sessions remain valid until normal expiry/revocation; no downgrade of data.
4. Migrations are additive-only; **no down-migration**; never drop `revoked_at`/`device_id` columns.
5. Data preservation: contacts, conversations, messages, backups, identity keys are never inputs to link/revoke code paths except read-only context.

---

## Appendix — Open questions for review / researcher

- **OQ-1 (UX):** Fingerprint compare — 16-hex on both screens, or 6-word mapping? Product decision; blocks WS-UI polish only.
- **OQ-2 (trust bootstrap):** N cannot cryptographically pin the account pubkey before linking; spec relies on QR-screen comparison. An alternative (N fetches account pubkey via existing authenticated path — impossible pre-link) is unavailable; is compare-and-confirm sufficient for the threat model, or should N refuse to link without a verified contact out-of-band?
- **OQ-3 (per-device messaging keys):** for v2, should N receive *receive-only* wrapped conversation keys (read-only mode) before full bidirectional? Changes §3.4; deferred deliberately.
- **OQ-4 (authorization):** any enrolled session may approve in v1. Should approvals require the *primary* (first-enrolled) device? Requires a `is_primary` column + election/tie-break rules.
- **OQ-5 (audit):** retention for `device_link_events` (forever vs 90 days)?
- **OQ-6 (platform):** Windows link UX — same QR scan (webcam) or manual code entry only? (No Windows camera/QR path verified yet.)
- **OQ-7 (Idempotency scope):** approve-idempotency on exact-match payload only; should a *different* payload for an already-approved request auto-deny-and-alert instead of 409?
- **OQ-8 (rate limits):** 10/h request and 30/h status are provisional; load/abuse budget needs measurement before default-on.
- **OQ-9 (claims):** exact store-description wording allowed once shipped; current draft inherits §1.2 verbatim.
- **OQ-10 (threat):** residual — a malicious *enrolled* device can approve further links (v1 "any session approves", §4.3/OQ-4). Accept for v1 with prominent UI, or gate now?

---

## Result Contract

- **status:** `pass` (spec written; no implementation started)
- **summary:** adds §1–§9 + Appendix; locks claims policy; picks device-scoped-key design (Option B) with rejection rationale; fixes byte-level link transcript, server API (§4.4), per-device sessions via `auth_sessions.device_id`, soft-revoke semantics; TDD list in §6; honesty rule: contacts/profile only, no message sync.
- **artifacts:** `docs/spec-device-linking-v1.md` (this file only). No other files read for modification; no CI/CSV/checklist changes.
- **risks:** unreviewed novel approval transcript (mitigate via OQ review + §8); QR screenshot window; Render free-tier pending-row loss; claims-discipline depends on enforcement grep (§8).
- **next_recommended:** lead review of this spec → dispatch WS1 (backend §4) with §6 tests written RED first → WS2 (client link flow) → device acceptance → lead sign-off; CSV/checklist rows flip only then.
- **assumptions:** see reply; summarized — existing `identityChallenge`/`auth_sessions` patterns reused as-is; one active messaging device per account stands; v1 = metadata link only; no new primitives; repo conventions (hex keys, `'Chhaya-*-v1'` info strings, LP encoding) followed; fingerprint compare is sufficient to bootstrap trust pending OQ-2.

## Markers

- `decision_points`: Option B vs A (§3.4); any-session-approves vs primary-only (§4.3/OQ-4); soft-revoke vs hard-delete (§4.1/§4.6); contacts-metadata-yes/messages-no (§3.7).
- `estimated_scope`: backend ~1.5–2 days (tables, 4 endpoints, session change, audit, tests); client ~2–3 days (service, DB migration, settings UI, fingerprint screen, tests); device acceptance ~0.5 day.
