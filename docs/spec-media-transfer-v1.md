# Spec: Chhaya — Encrypted Resumable Media Transfer ("Media Transfer v1")

- **Status:** Proposed spec. Not implemented. Not release-verified. **Do not ship or enable by default.**
- **Date:** 2026-11-09
- **Author:** specifier — repo `D:\Projects\PROJ16`
- **Workstream:** feeds release-execution-plan.md §3 (WS3) — "Replace inline-only media with encrypted resumable transfers, limits, cancellation and cleanup; verify microphone, camera and playback."
- **Register refs:** feature-register.md id 5 (Media messages — "Inline encrypted attachments limited to 256 KB"), id 65 (Per-file encryption), id 78 (Local file export), and the "Media transfers" line ("Specify encrypted resumable uploads, quotas, cancellation and cleanup"). Delivery-checklist "Photos/files" row: "Larger encrypted blob/chunk transfer; picker/export device tests" — this spec addresses the transfer design only; device tests remain checklist work.
- **Hard gates:** (1) no merge without lead/human approval; (2) no checklist or feature-verification-127.csv status changes as part of this work — those are lead/human decisions after evidence exists; (3) no user-facing claim about large-file encryption until shipped **and** device-verified (§11); (4) no independent protocol review is commissioned by this spec — the design deliberately invents no new cryptography, but composition review is still recommended before default-on (§10, §21).
- **Crypto policy:** **No new cryptography.** Everything below reuses `AesGcm` (AES-256-GCM, random 96-bit nonce, 128-bit tag, `lib/core/crypto/primitives/aes_gcm.dart`), `Sha.hash256` (SHA-256, `lib/core/crypto/primitives/sha.dart`), and the existing ratchet / `chhaya-group-key-v1` content-key-wrap pattern in `messaging_service.dart`. Any implementation step that appears to require new crypto is a spec defect — stop and ask.

---

## 1. Problem statement

All encrypted attachments today are *inline*: the file bytes (≤ 256 KB, `MessageAttachment.maxBytes = 256 * 1024`, enforced in `lib/core/models/message_attachment.dart` and `lib/services/messaging/attachment_service.dart`) are base64-embedded in the ratchet-encrypted message payload (`MessagePayload.encode`, `lib/services/messaging/message_payload.dart`). The backend `/api/v1/messages` accepts content up to 768 KB inside a 1 MB JSON parser (`backend/server/src/index.ts`, `routes.ts`). Anything larger fails at pick time.

Consequences: no photos/files above 256 KB, no resumability (an interrupted send means re-sending everything or losing the outbox entry), no quotas, no cancellation, no cleanup of partial state, no server-side retention policy for media, and no defined behavior for disappearing messages carrying media.

## 2. Context

- **Inline path (unchanged by this spec):** file → `AttachmentService.pick` (bounded stream read, ≤ 256 KB) → `MessageAttachment` (name/mime sanitized) → `MessagePayload` → ratchet (direct) or AES-GCM body + per-member `chhaya-group-key-v1` wraps (group) → `POST /api/v1/messages`. Server stores content verbatim, never sees plaintext.
- **Group sends** use a random 32-byte content key (`Csprng`), `AesGcm` body with AAD `_groupBodyAad(conversationId, messageId, senderId)`, and per-member ratchet wraps whose recipient list must equal active membership under the same DB transaction/`FOR UPDATE`.
- **Backend:** Node/Express + PostgreSQL (`backend/server/src/`). Migrations are append-only into the `migrations` array in `db.ts`, applied by `applyMigrations` (`migrations.ts`) with per-statement checksums — existing statements MUST NOT be edited. Shared fixed-window rate limiter on the `rate_limits` table with keyed-HMAC caller identifiers (`rate-limit.ts`), fail-closed (503 when unavailable), with `pruneExpiredRateLimits`. `call_invites` shows the precedent for expiring, GC'd server-side rows. `messages` has no TTL column; disappearing messages are enforced client-side only.
- **Playback temp files:** voice playback already uses `getTemporaryDirectory()` and `VoiceTemporaryFiles` sweeps `chhaya-voice-*.aac` scratch files on launch (Windows included — Windows is a legacy target; `package:path` separators must be used, never hard-coded `/`).
- **Backup:** version-2 SQLCipher export replaces profile/contacts/conversations/messages. Media bytes are never in the DB, so a media pointer in a restored payload references server state that may be gone (§9.6).
- **Free-tier constraints:** Render free HTTPS backend (subject to sleeping), free PostgreSQL (expiry recorded 2026-11-27), no paid object storage, no CDN, no new services.

## 3. Objective

Specify an implementable, testable, resumable transfer for encrypted media larger than the inline cap, covering: chunk size, per-chunk AEAD, chunk-level resume with hashes, reassembly + whole-file hash verification, a server-side blob store with retention/deletion policy, authorized access (sender + conversation members), token-bound references, quotas and per-message limits, cancellation semantics, GC of failed/expired transfers, pre-send size cap, atomic receiving-side finalization, restart/app-kill behavior for partial files, cleanup on message expiry, the group path (member-key wrap of the content key), UX states, backup/restore alignment, privacy limits, and DoS/abuse limits — without new cryptography and without new infrastructure.

## 4. Non-goals

- **No CDN, no paid resources, no new external services** (no S3, no Redis, no queue, no worker fleet). Blob storage is PostgreSQL `BYTEA` in the existing database.
- **No video streaming, no SFrame, no progressive playback.** Download-then-open, like inline attachments today.
- **No media transcoding / thumbnails server-side.** Preview after full download only.
- **No multi-device partial-transfer sync** (multi-device pairing is itself incomplete, delivery-checklist row).
- **No "keep media in backup" option** (§9.6).
- **No forward/export restrictions on group members** (§10, member theft).
- **No changes to calls, voice recording, camera capture** (release-plan §3 covers microphone/camera/playback verification; this spec only defines the transfer substrate).
- **Not a protocol review.** This spec is not independent cryptographic review.
- **No claims flip.** feature-verification-127.csv / delivery-checklist.md / SECURITY.md / README.md are not edited by this work.

## 5. Inputs used

- `docs/delivery-checklist.md` (Photos/files row, Backup/crypto notes)
- `docs/release-execution-plan.md` (workstream 3, free-tier constraint)
- `docs/version-15-status.md` (WS3 not_started; "Offline large-attachment/resumable transfers — FAIL / NOT DONE — 256 KB inline cap")
- `docs/feature-register.md` (ids 5, 65, 78; Media transfers line)
- `docs/threat-model.md` (residual risks: server sees membership/timing/sizes; disappearing messages are local-only)
- `docs/spec-pq-hybrid-resync-v1.md` (house spec format; claims-policy pattern)
- `lib/core/models/message_attachment.dart`, `lib/services/messaging/{attachment_service,messaging_service,message_payload,voice_temporary_files}.dart`, `lib/core/crypto/primitives/{aes_gcm,sha}.dart`
- `backend/server/src/{index,routes,db,migrations,rate-limit,call-invites}.ts`
- `lib/ui/screens/chat/chat_screen.dart` (pick UI, 256 KB copy)

## 6. Assumptions

- AS-1: Both ends of a conversation build from the same release train once this lands (media messages are undecodable by pre-change clients — see §9.5 and Risks).
- AS-2: PostgreSQL `BYTEA` storage of ≤ 100 MiB per user (quota, §7.2) is acceptable on the free tier for a test/pilot backend; if the DB cannot hold it, uploads fail closed with `413` (§8 error codes) and the inline path still works for small files.
- AS-3: The existing authenticated envelope (ratchet for direct, `chhaya-group-v1` for groups) is the key-delivery channel. The server never sees the blob content key.
- AS-4: Server-side conversation membership checks remain the authorization boundary for media access (same trust model as `/messages`); this is *not* cryptographic membership authentication (see Groups row of the checklist — unchanged).
- AS-5: Clocks on server and client may differ by minutes; token and TTL checks use server time only.
- AS-6: Deleting media bytes does not guarantee erasure from receiver devices, OS caches, screenshots, or backups — same limit as disappearing messages today. Documented, not solved.

## 7. Architecture & cryptographic design

### 7.1 Transfer model

Two paths, selected by size at pick time:

| Size | Path |
|---|---|
| 1 B – 256 KB (`MessageAttachment.maxBytes`) | **Inline** (unchanged): bytes in the encrypted payload |
| 256 KB + 1 B – 16 MiB (`spec_media_max_bytes`) | **Blob**: chunked, resumable, server-stored, referenced from the encrypted payload |

### 7.2 Constants (spec decisions, env-overridable defaults)

| Name | Value | Notes |
|---|---|---|
| `spec_chunk_bytes` | **256 KiB (262 144 B) plaintext** | Matches existing 256 KB constant; ciphertext chunk = 262 144 + 12 (nonce) + 16 (tag) = 262 172 B |
| `spec_media_max_bytes` | **16 MiB (16 777 216 B)** per file/message | Hard pre-send cap, checked before encryption starts |
| `spec_max_chunks` | **64** (`ceil(16 MiB / 256 KiB)`) | Enforced server-side at start and at complete |
| `spec_max_inflight_per_user` | **3** concurrent uploading transfers per sender | Counted across state `uploading` |
| `spec_max_staged_per_user` | **32 MiB** total bytes in incomplete transfers per sender | Declared at start; hard-enforced on actual bytes at chunk writes and complete |
| `spec_max_stored_per_user` | **100 MiB** total blob bytes (staged + completed) per sender | Quota; `413` on exceed |
| `spec_max_transfers_per_conv_per_day` | **50** completed transfers per conversation per rolling 24 h | Abuse bound on free tier |
| `spec_transfer_ttl` | **1 h** for incomplete transfers (then GC) | See §9.3 |
| `spec_blob_retention` | **30 days** after completion (then GC) | See §9.3 |
| `spec_download_token_ttl` | **5 minutes** | HMAC-bound, see §7.7 |
| `spec_chunk_rate` | **240 chunk PUTs/min/user** via shared limiter | `media:chunk:<userId>` |
| `spec_start_rate` | **20 transfer starts/hour/user** via shared limiter | `media:start:<userId>` |

### 7.3 Chunk encryption (per-chunk AEAD)

- A single random **32-byte content key** per transfer is generated by the sender with `Csprng`. It is *never* sent to the server unencrypted.
- For each chunk `i` (0-based), plaintext `p_i` (≤ 262 144 B):
  - nonce ← `Csprng.bytes(12)` (fresh per chunk; random 96-bit nonces under one key are safe at ≤ 64 chunks)
  - AAD ← UTF-8 of `jsonEncode(['chhaya-media-chunk-v1', transferId, i, totalChunks, conversationId])`
  - wire chunk ← `nonce || AES-256-GCM(contentKey, p_i, aad)` (exactly what `AesGcm.encryptBytes(..., aad:)` emits)
- **No key derivation, no counters, no new primitives.** Nonces are random, never derived.

### 7.4 Hashes and verification

| Hash | Definition | Purpose | Verified by |
|---|---|---|---|
| Chunk hash | `SHA-256(wire_chunk)` (hex, 64 chars) | Resume + integrity of stored bytes; idempotent re-upload | Server (on PUT, vs client-supplied `X-Chunk-SHA256`) and client (on GET) |
| Whole-file hash | `SHA-256(plaintext)` (hex) | Reassembly verification: correct order, completeness, no truncation/duplication | Sender (optional post-encrypt self-check) and **mandatory on receiver**, before the message is inserted |

Per-chunk AEAD already authenticates each chunk and binds its index via AAD; the whole-file hash additionally proves the reassembled byte stream is exactly the sender's file. Neither hash is keyed; neither is secret. The whole-file hash travels inside the encrypted payload; chunk hashes are exchanged with the server as non-secret integrity metadata.

### 7.5 Message payload — `mediaRef` (additive field)

`MessagePayload` gains one **optional** field. `attachment` (inline) and `mediaRef` are mutually exclusive; a payload with both is invalid.

```jsonc
{
  "content": "<caption or ''>",
  "type": "image" | "file" | "voice",
  "mediaRef": {
    "v": 1,
    "transferId": "<uuid>",
    "name": "<sanitized, ≤120 chars>",      // same rules as MessageAttachment._safeName
    "mimeType": "<sanitized>",               // same rules as _safeMime
    "sizeBytes": 7340032,                     // plaintext size, for progress UX only
    "chunkSize": 262144,
    "totalChunks": 28,
    "fileSha256": "<hex of SHA-256(plaintext)>",
    "key": "<base64 32-byte content key>"    // inside the AEAD envelope, never plaintext to server
  }
}
```

`decode` rules: if `mediaRef` is present, apply `_safeName`/`_safeMime` validation, require `v == 1`, `totalChunks` ≤ 64, `chunkSize == 262144`, `sizeBytes` ≤ `spec_media_max_bytes`, `fileSha256` matching `^[0-9a-f]{64}$`, `key` decoding to 32 bytes; reject `attachment` co-present; reject `type` `text`/`poll` with `mediaRef`. Unknown `mediaRef.v` → reject (explicit rejection, matching existing payload discipline).

### 7.6 Key delivery — direct and group

The content key travels **inside the existing encrypted payload**. No new wrapping scheme exists.

- **Direct conversation:** the payload (including `mediaRef.key`) is ratchet-encrypted to the peer exactly as any message today. Envelope auth and message-level AEAD cover the key.
- **Group conversation:** the payload is AES-256-GCM body-encrypted under a random body content key AAD'd with `_groupBodyAad(conversationId, messageId, senderId)`; the body key is wrapped per member with `prepareEncrypt(...)` in the `chhaya-group-key-v1` shape; the server enforces that the wrapper recipient set equals active membership in the same transaction (existing `/messages` group path). The media content key therefore inherits the exact member-key wrap property of the message body: a removed member cannot unwrap it; an added member cannot retroactively read it. The blob layer binds `(transferId, conversationId, index)` via AAD (§7.3). **There is deliberately no second, per-media wrap** — inventing one would duplicate the body wrap for zero security gain and would expand the review surface. The "member-key wrap of the content key" requirement is satisfied by the message-body wrap, and this document says so explicitly rather than implying a separate mechanism.
- The server stores only `size_bytes`, chunk hashes, and chunk bytes. It cannot decrypt any chunk (no content key), cannot forge a message referencing the blob (message authenticity is the ratchet/group envelope), and never sees file names.

### 7.7 References: content-addressed vs token-bound

`transferId` is a random UUID, **not** content-addressed (content addressing would let the server test blob equality across users/conversations and leak plaintext equality to anyone who can hash). Access is **token-bound**: all download chunk GETs require a short-lived download token minted by `POST /api/v1/media/downloads` and HMAC-bound to `(transferId, userId, conversationId, expiry)` using an `HMAC_JWT_SECRET`-derived HMAC (same construction as `rate-limit.ts` caller keys). Tokens expire in 5 minutes, are single-purpose, and are rejected for any other user/blob/conversation. There is no long-lived public URL. A token observed before expiry shares access — accepted limitation, bounded by the 5-minute TTL and by the fact that a leaked token yields *ciphertext*, not plaintext.

### 7.8 Upload flow (sender)

1. **Pick & pre-validate:** `AttachmentService.pick` stream read with the bound raised to `spec_media_max_bytes` when the blob path is selected; reject empty and > 16 MiB **before** any encryption (explicit size cap; the picker UX shows the cap). Generate `transferId`, content key; stream plaintext once, chunking + encrypting + hashing (single pass, one 256 KiB chunk in flight).
2. `POST /api/v1/media/transfers` → `201 { transferId, chunkSize, totalChunks, expiresAt }` (validation/quotas — see §8).
3. `PUT /api/v1/media/transfers/:id/chunks/:index` per chunk (raw body, `X-Chunk-SHA256`). Resumable: if the app is killed, the client re-queries `GET .../:id` on relaunch and skips chunks the server reports present with matching hash.
4. `POST .../:id/complete` → server verifies all chunks present, each ≤ 262 172 B, total ≤ `spec_media_max_bytes` → state `completed`. Idempotent.
5. Only now does the client create the `Message` with `mediaRef` and deliver via the existing outbox/`_deliver` path (`commitOutgoingMessage` → `POST /messages`). **A blob is never referenced by a message before `complete` succeeds.** If upload fails/cancels, there is no message and the staged blob is inert ciphertext reclaimed by GC.
6. On success, the plaintext staging buffer is wiped best-effort.

### 7.9 Download flow (receiver) — atomic finalization

1. A message arrives containing `mediaRef`. The client does **not** create any visible attachment yet. It creates a local pending-download record (§7.10) and shows a "Downloading… x/y" or "Tap to download" state on the bubble (§9.4).
2. `POST /api/v1/media/downloads { transferId }` → `{ token, totalChunks, chunkSize, sizeBytes, expiresAt }`. Membership is checked at this instant (403 otherwise — same as `/messages`).
3. `GET /api/v1/media/downloads/:id/chunks/:index` with `X-Download-Token`, one chunk at a time. Each chunk: verify chunk SHA-256 (resume aid), **then** AEAD-decrypt with AAD `['chhaya-media-chunk-v1', transferId, i, totalChunks, conversationId]`; any mismatch aborts to the retry state (never yields plaintext, never writes unverified plaintext).
4. Stream decrypted chunks to `<tmp>/chhaya-media-<messageId>.part` (same naming family as `VoiceTemporaryFiles`). **The `.part` file is never surfaced to the player/viewer.**
5. After the final chunk verifies, compute `SHA-256(plaintext)` (streamed from the `.part` file) and compare to `mediaRef.fileSha256`. Mismatch → delete `.part`, mark failed. Match → **atomic rename** `.part` → `chhaya-media-<messageId>` and insert the `Message` via the normal receive path. Only after rename+insert does the bubble flip to its media UI. **No partial delivery is ever visible**: until rename+insert, the transcript shows at most an explicit "Encrypted media — downloading/failed" placeholder, never a playable/openable attachment.
6. Restart/app-kill mid-download: on launch, the client sweeps the temp dir for `chhaya-media-*.part` files. With a persisted local record (§7.10) including a verified-chunk bitmap, resume; without one, discard the `.part` and re-download from chunk 0 (safe; chunks are idempotent). Orphan `.part` files older than 24 h are deleted unconditionally (extend the `VoiceTemporaryFiles` sweep pattern).

### 7.10 Client-side transfer state (local DB, additive)

Add `LocalDatabase` migration **v006** (next free version — see §18) creating one table:

```
media_transfers_local(
  id TEXT PRIMARY KEY,             -- transferId
  message_draft_id TEXT,           -- outbox message id once known
  direction TEXT NOT NULL,         -- 'out' | 'in'
  conversation_id TEXT NOT NULL,
  file_path TEXT NOT NULL,         -- sender: source path; receiver: .part path
  total_chunks INTEGER NOT NULL,
  chunk_size INTEGER NOT NULL,
  verified_bitmap BLOB,            -- ceil(totalChunks/8) bytes; persisted after every chunk verify
  state TEXT NOT NULL,             -- 'encrypting','uploading','failed','completed','canceled'
  error TEXT,
  updated_at INTEGER NOT NULL
)
```

Rows in `failed`/`canceled` older than 7 days are swept on launch. No existing table is altered.

## 8. HTTP API surface (all require `authMiddleware`; UTF-8 JSON unless noted)

Base path `/api/v1`. Errors keep the existing `{ "error": "<message>" }` shape plus an additive machine-readable `code`: `{ "error": "...", "code": "transfer_too_large" }`. Status codes: 400 bad request, 401 unauthenticated, 403 not a participant/sender, 404 unknown or expired (indistinguishable to non-members, by design), 409 hash/state conflict, 413 too large/quota, 429 rate limited, 503 shared-limiter unavailable, 500 otherwise.

### 8.1 `POST /media/transfers` — start

Auth: caller ∈ active participants of `conversationId` (same membership query as `/messages`).
Body:
```jsonc
{ "conversationId": "<uuid>",
  "sizeBytes": 7340032,       // REQUIRED; 1..spec_media_max_bytes (plaintext size; enforced on actual bytes too)
  "totalChunks": 28,          // REQUIRED; must equal ceil(sizeBytes/262144)
  "chunkSize": 262144 }       // REQUIRED; must equal spec_chunk_bytes
```
Server: validates types/ranges; rejects cap violations; checks quotas (inflight ≤ 3, staged ≤ 32 MiB after this transfer, stored ≤ 100 MiB, conversation ≤ 50/day) inside one transaction (same `FOR UPDATE` membership-lock discipline as `/messages`, or an advisory lock on the sender quota row — implementer's choice, documented in the PR). Inserts `media_transfers` state `uploading`, `expires_at = now()+1h`.
`201 → { "transferId": "<uuid>", "chunkSize": 262144, "totalChunks": 28, "expiresAt": "..." }`
Errors: 400 `invalid_transfer_request` · 403 `not_conversation_member` · 413 `transfer_too_large` / `quota_exceeded` / `conversation_rate_exceeded` · 429 `rate_limited` · 503 `limiter_unavailable`

### 8.2 `PUT /media/transfers/:id/chunks/:index` — upload chunk (raw bytes)

Headers: `Content-Type: application/octet-stream`, `X-Chunk-SHA256: <hex>`.
Raw body ≤ 262 172 B — mounted with `express.raw({ limit: '262300b', type: 'application/octet-stream' })` **before** the global 1 MB `express.json()` middleware (implementation note; current global parser would reject/corrupt binary otherwise).
Server: transfer must exist, belong to caller, state `uploading`, `expires_at > now()`; `index` ∈ `[0, totalChunks)`; recompute SHA-256 of the body; mismatch → `409 chunk_hash_mismatch` (nothing stored). If the chunk row exists: same hash → `200 { ok: true, deduped: true }`; different hash → `409 chunk_hash_conflict`. Else `INSERT` into `media_chunks` and touch `updated_at`, while hard-enforced byte quota ≤ `spec_max_stored_per_user` and ≤ `spec_max_staged_per_user` across the user's transfers (actual bytes, not declared) → `413 quota_exceeded`. Each accepted PUT counts against limiter `media:chunk:<userId>` (240/min).
`201 → { "ok": true, "receivedChunks": <n> }`
Errors: 400 `invalid_chunk` · 403 `not_sender` · 404 `transfer_not_found` / `transfer_expired` · 409 `chunk_hash_mismatch` / `chunk_hash_conflict` / `transfer_state_conflict` · 413 `quota_exceeded` · 429 `rate_limited`

### 8.3 `GET /media/transfers/:id` — status/resume (sender only)

`200 → { "state": "uploading", "totalChunks": 28, "received": [0,1,2,7], "expiresAt": "...", "sizeBytes": 7340032 }`
`received` lists indices whose stored bytes match the stored hash (indices suffice for resume). Non-sender → 404 (no existence oracle). Unknown/expired → 404.

### 8.4 `POST /media/transfers/:id/complete` — finalize upload (sender only)

One transaction: transfer `uploading`, not expired; exactly `totalChunks` chunk rows present; each `byte_size` ≤ 262 172; `SUM(byte_size)` ≤ declared size and ≤ `spec_media_max_bytes`; flip state → `completed`, set `completed_at`. Idempotent: already `completed` → `200`. Missing chunks → `409 missing_chunks` with body `{ "error": "...", "code": "missing_chunks", "missing": [3, 9] }`.
`200 → { "transferId": "...", "state": "completed", "sizeBytes": <actual> }`
**Note:** the server cannot verify `fileSha256` (no plaintext); whole-file verification is receiver-side only (§7.4, §7.9 step 5).
Errors: 403 `not_sender` · 404 `transfer_not_found` / `transfer_expired` · 409 `transfer_state_conflict` / `missing_chunks` · 413 `transfer_too_large`

### 8.5 `DELETE /media/transfers/:id` — cancel/delete

Auth: sender only, any state. Deletes chunk rows then the transfer (cascade). Idempotent: absent transfer → `204`. Success → `204`. This is exactly the cancel path for an in-progress upload (§9.2). Deleting a `completed` blob also immediately revokes receiver access — intended for the "sender withdraws file" case.

### 8.6 `POST /media/downloads` — download init

Auth: caller ∈ active participants of the transfer's conversation, or is the sender. Transfer must be `completed` and not older than `spec_blob_retention` (from `completed_at`). Mints token `HMAC_SHA256(HMAC_JWT_SECRET, 'chhaya-media-dl-v1' || transferId || userId || conversationId || exp)`, base64url, 5-minute TTL.
`201 → { "token": "<base64url>", "expiresAt": "...", "totalChunks": 28, "chunkSize": 262144, "sizeBytes": 7340032 }`
Errors: 403 `not_conversation_member` · 404 `transfer_not_found` / `transfer_expired` (410 semantics via 404) · 429 `rate_limited`

### 8.7 `GET /media/downloads/:id/chunks/:index` — download chunk

Header `X-Download-Token: <token>` (header, not query param — avoids logs/referer leakage). Server validates HMAC, purpose string, expiry, `userId` == caller, binding to `transferId` and conversation; enforces that the caller is *still* an active member at GET time? No — v1 binds membership at init only (see OQ-4); per-chunk re-check would cost one membership query per 256 KiB and races either way. Bytes out with `Content-Type: application/octet-stream`, `X-Chunk-SHA256: <hex>`, `Cache-Control: no-store`.
**No HTTP `Range` support**: the chunk is the atomic unit; byte-range resume *inside* a chunk saves nothing at 256 KiB. This is the documented equivalent of "range/complete": per-chunk atomic GET + client-side whole-file verification replaces byte ranges, and no server-side completion marker is written (it would add a DB row per download and serve no correctness function). If a future reviewer insists on a completion call, `POST /media/downloads/:id/complete` → `204` reserved — **not in v1**.
Errors: 401 `download_token_invalid` / `download_token_expired` · 403 `not_conversation_member` (only if init-time binding is later strengthened — see OQ-4; v1 returns 401 for bad tokens) · 404 `transfer_not_found` / `transfer_expired` / `chunk_not_found`

### 8.8 Not provided (deliberate)

No list endpoint, no admin purge endpoint, no public/signed-URL mode, no `HEAD` (use init), no `Range` (8.7), no `complete` (8.7). Rationale recorded so reviewers don't re-add them reflexively.

## 9. Lifecycle, cleanup, quotas

### 9.1 Message send with media (atomic from the app's point of view)

Blob upload completes → message (with `mediaRef`) is created and delivered via the existing outbox path with exact-envelope retry semantics. If delivery fails after blob completion, the outbox retries the **message** only — never re-uploads chunks. The blob sits `completed` until TTL GC or sender delete.

### 9.2 Cancellation semantics

- **Sender cancels before message send:** client stops chunk loop → `DELETE /media/transfers/:id` → delete local `.part`/staging → mark local record `canceled` → snackbar "Transfer canceled". **No message is created; the server blob is gone.**
- **Sender cancels after message sent** (via media-message actions, a new overflow action): blob deleted; receivers get `404 transfer_not_found` on next download; bubble shows "Withdrawn by sender" (terminal, no Retry). Message row remains as placeholder — identical UX to an expired disappearing message.
- **Receiver cancels a download:** stop chunk loop → delete `.part` → mark local record `canceled`. Server blob untouched (other members may still download; for 1:1 the sender's copy is unaffected).
- **App killed mid-transfer:** treated as "failed", not canceled; resume per §7.9 step 6 (download) or §7.8 step 3 (upload, via `GET .../:id`). A "Resume" affordance appears on the failed bubble.
- **Message TTL expiry (disappearing messages):** local expiry deletes the local media file and the outbox/pending record, and — if the expiring device holds an active session — issues a best-effort `DELETE /media/transfers/:id` **as the sender** only. Receivers cannot delete another user's blob (403 by design, §8.5 sender-only); receiver-side expiry deletes only the local copy. **The server cannot map TTL → blob** because TTL lives inside the ciphertext; server-side blob deletion is therefore time-based (§9.3), not TTL-based. This mirrors the threat-model disappearing-message limit (remote copies not guaranteed) and is documented as such — no UI may imply otherwise.
- **Cancel vs GC race:** a `canceled` row is deleted synchronously in `DELETE`; the sweeper (§9.3) is belt-and-braces and idempotent.

### 9.3 Server-side retention & GC (sweeper)

A bounded interval task in `index.ts` (every `MEDIA_GC_INTERVAL_MS`, default 600 000 ms, jittered; DB failure → skip and log, same discipline as `pruneExpiredRateLimits`):

1. `UPDATE media_transfers SET state='expired' WHERE state='uploading' AND expires_at <= now()` — then `DELETE` those rows (cascade purges chunks).
2. `DELETE FROM media_transfers WHERE state='completed' AND completed_at <= now() - (spec_blob_retention)` — 30-day cap, cascade chunks.
3. `DELETE FROM media_transfers WHERE state IN ('canceled','expired')` (normally already gone via §8.5).
4. Orphan sweep: `DELETE FROM media_chunks WHERE transfer_id NOT IN (SELECT id FROM media_transfers)` — expect 0 rows; log if not.
5. Each step `LIMIT`-bounded (e.g., 500 rows per statement, loop until 0) so GC never starves the API; log row counts at `info`.

Conversation deletion cascades blobs via `media_transfers.conversation_id → conversations(id) ON DELETE CASCADE`; account deletion cascades via `sender_id → users(id) ON DELETE CASCADE`.

### 9.4 UX states (chat screen; copy is spec-proposed, final copy is WS-C)

- **Picking:** file picker unchanged; size > 256 KB and ≤ 16 MiB → blob path; > 16 MiB → snackbar "Choose a file up to 16 MB." (explicit pre-send cap, no network touched).
- **Sending:** bubble shows progress ring + "Sending… 42%" + **Cancel** (§9.2). After `complete` + `_deliver`, bubble flips to the normal media bubble.
- **Send retry:** existing outbox retry reuses `mediaRef`; upload is **not** repeated.
- **Incoming, not yet downloaded:** bubble shows "📎 Encrypted media · 7.3 MB — Tap to download" (name/mime unknown until decrypt of the referenced message — tap first). Actually: message decrypts first (it's tiny), so name/size are known before the blob is fetched; the bubble may show the sanitized name with "Tap to download". Bytes are fetched only on tap.
- **Downloading:** "Downloading… 12/28 · Cancel" (bytes from the local file size vs totalChunks). On failure: "Download failed — Retry". On withdrawn/expired: "File unavailable (expired or withdrawn by sender)" — terminal.
- **Interrupted transfer:** on app launch with `uploading`/`failed` rows in `media_transfers_local`, a non-blocking banner appears in the affected chat: "Interrupted transfer — Resume / Discard". Discard calls `DELETE` if sender-side.
- **Voice notes:** unchanged (inline today; large voice files flow through the blob path automatically by size).
- **One-time notice:** first media message send shows "Large files expire from the server after 30 days." (honest retention disclosure; see Risks).

### 9.5 Compatibility / migration from the 256 KB inline path

- Inline path stays byte-identical for ≤ 256 KB (no behavior change; voice notes unaffected).
- `MessagePayload.decode` gains the optional `mediaRef`; **old clients** receiving such a message fail decoding (`attachment == null` for `image`/`file`/`voice` → existing `FormatException`) and render nothing — the current behavior for bad payloads. Acceptable per AS-1; flagged in release notes and Risks.
- No server `messages` columns change; legacy `media_url`/`media_meta` remain unused (they are unencrypted and server-visible; do **not** repurpose them).
- Delivery checklist "Photos/files" row stays unchanged by this work; `version-15-status.md` WS3 moves to in-progress only when code lands, and to verified only after device evidence — out of scope for this spec.

### 9.6 Backup/restore alignment

Backups (SQLCipher export) contain the message row with its `mediaRef` — **pointer only, never bytes**. After a restore: messages whose blobs still exist server-side (not expired/withdrawn) download fine; messages whose blobs are gone render the terminal "File unavailable" state. Honest ceiling without encrypting-then-embedding bytes. **v1 does not back up media bytes** (would recreate the 256 KB problem at 100× the size). The restore UX documentation task rides in WS-C: one honest paragraph in backup docs, no feature. No claim that "restore brings your files back".

## 10. Threat model delta (vs `docs/threat-model.md`)

Base document's assets, boundaries, residual risks and required gates are unchanged except where stated. The server is **not** trusted with plaintext, keys, or file names.

- **Malicious server.** Sees: account IDs, conversation membership, timing, chunk counts, wire sizes, exact plaintext **size** per file (no padding in v1 — SD-3), transfer frequency. Cannot: read content (no content key), forge chunk or message (AEAD/ratchet), bind blob → name (names live in the ciphertext payload), inflate storage silently (actual-bytes quota enforcement), or retain beyond its own policy after deletion signals (sweeper + explicit DELETE). **Availability attacks** (blob deletion/withholding/corruption) are possible and indistinguishable from network failure → clients fail closed to "Download failed", never to plaintext or partial render.
- **Member theft / malicious group member.** Any member holds the body content key and can unwrap the blob content key (it rides inside that body), decrypt the file, and re-share it out of band. AEAD cannot prevent this; it is the file-sharing model, identical to inline attachments today. Disappearing messages do not revoke already-downloaded copies. No UI may imply otherwise.
- **Expired links / token replay.** Tokens: 5-minute TTL, HMAC-bound to user+transfer+conversation, verified per chunk request; no list endpoint, no CDN, no anonymous GET, header-only transport, `Cache-Control: no-store`. A pre-expiry leak yields ciphertext only. After expiry the token is useless for this or any other endpoint.
- **Truncation / reorder / splice / cross-transfer replay.** AAD binds `(purpose, transferId, index, totalChunks, conversationId)` — chunks cannot be replayed across transfers, reordered, duplicated, or truncated undetected; whole-file SHA-256 catches any residual inconsistency. Server-side `X-Chunk-SHA256` is defense-in-depth for transport corruption, not a security boundary.
- **Quota/DoS on free tier.** 16 MiB/file, ≤ 64 chunks, ≤ 3 inflight, ≤ 32 MiB staged, ≤ 100 MiB stored per user, ≤ 50 completed/conversation/day, 1 h staged TTL, 30-day retention, 240 chunk-PUTs/min and 20 starts/hr via the **existing keyed-HMAC shared limiter** (fail-closed 503), chunk route isolated from the JSON parser, GC `LIMIT`-bounded, storage = `BYTEA` in the existing DB (no new process, no new credentials). Worst case ≈ 100 MiB/user + inflight; ops must watch free-DB size (manual note, not automation).
- **Log hygiene:** `X-Download-Token` travels in headers; WS-A5 verifies `nginx.conf`/proxy logging does not record it (same class of check as call-invite/privacy review).
- **Traffic analysis:** unmitigated (existing residual risk; no onion/mesh). Exact size leaks (SD-3).
- **Backup replay of dead media refs:** yields failed-download UX, not plaintext, not crash (§9.6).
- **Membership race at download:** init-time membership check; a member removed *after* init but before all chunks are fetched retains already-fetched bytes (consistent with `/messages` semantics and unavoidable without per-chunk membership checks — OQ-4). Consistent, documented.

**Review flag:** the composition (AEAD-per-chunk + AAD index binding + payload-carried key + token-bound fetch + receiver-side whole-file verify) reuses reviewed primitives but is a **new composition**. It requires no new cryptography to implement, but an external composition review is recommended before any default-on/claim language — the same bar the inline path faces, not higher.

## 11. Claims policy (binding)

Until the feature is implemented, loopback-tested **and device-verified**, all of the following are forbidden in UI, code comments, README/SECURITY/CHANGELOG, checklist/CSV/register prose, store listings and release notes:

- "end-to-end encrypted large files / attachments / media" (any variant)
- "encrypted file sharing" (unqualified) · "secure media transfer" (unqualified)
- "resumable encrypted transfers work" (before shipped) · "your files are encrypted like WhatsApp/Signal" (any comparison)
- "large files are encrypted end-to-end" · any wording implying media enjoys the same verified guarantees as text chat
- "expired files are deleted everywhere" / any disappearing-message overclaim
- "server stores your files encrypted at rest, it can't read them" (allowed **only** with "the server stores ciphertext; it holds no key; availability is not guaranteed")

Allowed before device verification: "Encrypted resumable media transfer (experimental) — large attachments are encrypted on device and uploaded in chunks; not device-verified; no production-readiness claim."

Checklist/CSV statuses flip only by lead/human decision with evidence; this spec flips nothing. House pattern: `docs/spec-pq-hybrid-resync-v1.md` §1.2.

## 12. Auto-forecast

- **estimated_scope:** large (> 400 lines across backend + Flutter + tests; ~700–900 lines total)
- **affected_files:**
  - Backend: `backend/server/src/db.ts` (append 2 migrations), `backend/server/src/index.ts` (raw-body mounting + GC interval), new `backend/server/src/media.ts`, `backend/server/test/` (new media tests), `nginx.conf` (log note)
  - Flutter: `lib/core/models/message_payload.dart`, `lib/core/models/message.dart` (no column change expected — verify), `lib/core/models/message_attachment.dart` (export shared validators), `lib/services/messaging/attachment_service.dart`, new `lib/services/messaging/media_transfer_service.dart`, `lib/core/database/` (v006 migration), `lib/services/messaging/voice_temporary_files.dart` (reuse/mirror sweep), `lib/ui/screens/chat/chat_screen.dart` (+ small new widget files)
  - Docs: this file; one honest backup-docs paragraph; no other edits
- **suggested_phases:** WS-A (backend) → WS-B (client core) → WS-C (UI + loopback + ledger). Each phase independently reviewable. Behind a disabled-by-default flag `CHHAYA_MEDIA_TRANSFER` if the lead wants dark landing; without the flag, the 256 KB cap stays.

## 13. Requirements & acceptance criteria

- **R1** Files ≤ 256 KB continue through the inline path byte-identically (existing attachment tests unchanged and passing).
- **R2** Files > 256 KB and ≤ 16 MiB transfer as ≤ 64 chunks of ≤ 262 172 wire bytes; > 16 MiB rejected pre-encryption with zero network calls.
- **R3** Chunk AEAD AAD binds purpose/transferId/index/totalChunks/conversationId; swapping indices, transfers, or conversations fails decryption (unit test).
- **R4** Resume: kill after k verified chunks → relaunch → only missing/failed chunks re-transferred; verified bitmap persisted per chunk.
- **R5** Receiver verifies whole-file SHA-256 before any visible/playable media UI; on mismatch, `.part` deleted and failed state rendered.
- **R6** Sender cancel ⇒ server blob + chunks gone (single DELETE round-trip); no message created; blob unrecoverable via API.
- **R7** Non-member and removed-group-member: 403 on init; bad/expired token: 401; expired blob: 404.
- **R8** Quotas enforced at start (declared) and at chunk writes/complete (actual bytes); stable 413 `code`s.
- **R9** Uncompleted transfers GC'd within 1 h + one GC interval; completed blobs GC'd after 30 d; GC `LIMIT`-bounded, logs counts.
- **R10** Backup contains no media bytes (inspection test with a plaintext canary); restore with missing blob renders failed state, no crash.
- **R11** Disappearing-message expiry deletes local media file + best-effort sender-side server DELETE; server failure logged, not fatal.
- **R12** Windows temp-path handling via `package:path`; `chhaya-media-*.part` sweep unit-tested with injected temp dir (mirror `VoiceTemporaryFiles`).
- **R13** No new cryptographic primitives/constructions (diff review: only `AesGcm`, `Sha`, `Csprng`).
- **R14** Zero forbidden claims (§11) in the diff; checklist/CSV untouched.
- **R15** Backend migrations additive only (`git diff db.ts` shows appends only); existing checksums intact (boot against pre-change DB snapshot passes).

## 14. Test plan

**Unit (Flutter, `test/`):**
- Chunk roundtrip: encrypt → decrypt → bytes equal; wrong AAD index/transferId/conversationId/purpose rejected; truncated/tampered chunk rejected (byte flip, cut tag).
- Whole-file: SHA-256 pass/fail; shuffled verified chunks → hash fail; duplicate chunk index rejected by bitmap.
- `MessagePayload` with `mediaRef`: roundtrip OK; co-present `attachment` rejected; bad mime/name/`v`/key-length/`fileSha256` rejected; `text`/`poll` + `mediaRef` rejected.
- Pre-send cap: stream bound throws > 16 MiB; path selection (inline vs blob) by size.
- Cancel: uploading → cancel → DELETE called (fake API), local files gone, record `canceled`; receiver cancel mirror; sender-withdraw after send → terminal bubble state.
- Expiry: local TTL expiry deletes file + record; best-effort server DELETE invoked only for sender-side records (fake API records call); server failure tolerated.
- GC sweep: orphan `.part` older than 24 h removed on launch (injected clock + dir).
- Windows path handling: backslash-path sweep test.
- Backup: exported bytes contain `mediaRef` marker and **zero** occurrences of a known plaintext canary.
- Interrupted resume: fake API dropping after k chunks → relaunch logic requests exactly the missing indices (bitmap-driven).

**Unit (backend, `backend/server/test/`):**
- `POST /media/transfers`: validation matrix (bad uuid, size 0, > cap, totalChunks ≠ ceil, wrong chunkSize), quota 413s, membership 403, start-rate 429.
- Chunk PUT: hash mismatch 409; idempotent re-upload 200 deduped; conflict 409; `byte_size` limit; raw-body mounting (binary body round-trips unmangled).
- Complete: `missing_chunks` lists indices; idempotent 200; expired 404; hard byte quota 413.
- Download init: member 201; non-member 403; expired blob 404; token verify unit tests (HMAC/expiry/binding/wrong user).
- Chunk GET: bad token 401; wrong user 401; bytes + `X-Chunk-SHA256` match stored hash.
- GC: seeded stale rows removed; fresh rows and other users' rows untouched; `LIMIT` respected.
- Migrations: additive-only — apply on snapshot of pre-change DB, boot, checksums intact.

**Integration (loopback, NOT device-verified):**
- Direct roundtrip vs local PostgreSQL: two accounts; 5 MB synthetic file → blob path → transfer → B receives, downloads, verifies, widget renders media bubble; decrypted bytes equal source.
- Group roundtrip: 3 members; transfer; member removed mid-upload → init 403 for removed member; remaining members unaffected (reuse existing group integration harness in `test/integration/`).
- Interrupted: client stub killed after k/10 chunks → resume → server `media_chunks` count and bytes match exactly (no duplicate-byte growth).
- Cancel end-to-end; expiry/GC end-to-end with injected clock.
- Load sanity (manual, not CI): 64-chunk/16 MiB transfer against constrained instance — timing recorded in ledger, no thresholds asserted.

**Not in scope:** real phones, iOS/Android lifecycle, Windows desktop playback QA, network shaping on-device — any claim of device verification is forbidden here. The ledger records "device verification: NOT RUN".

## 15. Verification ledger template (append results; never pre-fill passes)

```markdown
| Step | Command / environment | Result | Date | Device? |
|---|---|---|---|---|
| flutter analyze | `flutter analyze` | … | … | n/a |
| Flutter unit tests | `flutter test test/media_transfer_*.dart` | … | … | n/a |
| Backend build+test | `cd backend/server && npm run build && npm test` | … | … | n/a |
| Additive-migration boot | apply on pre-change DB snapshot | … | … | n/a |
| Loopback roundtrip (direct) | `test/integration/media_transfer_loopback_test.dart` vs local PG | … | … | no |
| Loopback roundtrip (group) | same harness, 3 members + removal | … | … | no |
| Interrupted-transfer resume | … | … | … | no |
| Cancel/expiry/GC | … | … | … | no |
| Quota/DoS bounds | unit + loopback | … | … | no |
| Windows temp sweep | `flutter test` on Windows | … | … | no |
| Claims-string scan | `git grep -iE 'e2e.*large|encrypted large files|…'` | … | … | n/a |
| Android device acceptance | Pixel 8a, isolated account | NOT RUN | — | yes |
| iOS device acceptance | — | NOT RUN | — | yes |
```

## 16. Risks

- **Free-tier DB capacity:** 100 MiB/user × many users exhausts the free PostgreSQL — pilot/test only until persistence policy changes; expiry of the free DB (2026-11-27) wipes all blobs.
- **30-day retention silently orphans live message refs:** senders cannot be told per-file without UX cost — WS-C ships a one-time honest disclosure; risk of user surprise remains.
- **Old-client interop:** media messages undecodable pre-change (§9.5); requires both ends on the new build.
- **Group membership race between init and per-chunk GETs:** accepted (init-time check only — OQ-4); removed members keep already-fetched bytes.
- **GC deletes blobs referenced by live messages after 30 d** — accepted, documented (§9.3, §9.6).
- **Exact size + timing metadata visible to server** — accepted (SD-3); consistent with existing threat model.
- **Flag roll-out:** if released without `CHHAYA_MEDIA_TRANSFER` discipline, 16 MiB transfers appear before UX polish lands — mitigation: disabled-by-default flag until WS-C acceptance pass.
- **`X-Chunk-SHA256` spoofing gains nothing** (server recomputes; mismatch stores nothing) — noted against reviewer confusion.

## 17. Atomic tasks / vertical slices

### WS-A — Backend: storage, quotas, lifecycle
Paths: `backend/server/src/db.ts` (append migrations), new `backend/server/src/media.ts`, `backend/server/src/index.ts` (raw-route mount + GC interval), `backend/server/test/`, `nginx.conf` (log-hygiene check).

1. A1. Append two migrations (§18 DDL) — additive only; existing checksums untouched.
2. A2. Implement §8 routes in `media.ts`; mount chunk raw route **before** `express.json()`; wire shared limiter keys `media:start:` / `media:chunk:`.
3. A3. GC sweeper (bounded, interval, fail-safe, injected-clock testable) — §9.3.
4. A4. Membership + sender-only checks reusing the `/messages` query shape; tests for 401/403/404/409/413/429/503.
5. A5. Verify proxy config does not log `X-Download-Token` (review-only).

### WS-B — Client core: crypto, state, resume
Paths: `lib/core/models/`, `lib/core/database/`, `lib/services/messaging/`.

1. B1. `mediaRef` in `MessagePayload` + validation (§7.5); shared validators exported from `message_attachment.dart`.
2. B2. `MediaTransferService`: single-pass chunk+encrypt+hash; resumable upload; `downloadToFile` with per-chunk verify + `.part` + atomic rename + whole-file check; cancel API.
3. B3. Local DB v006 `media_transfers_local` (§18); launch sweep for `.part`/orphans; TTL-expiry hook (local delete + best-effort sender-side server DELETE).
4. B4. Outbox integration: message delivered only after `complete`; retry reuses `mediaRef` (no re-upload).

### WS-C — UI & verification
Paths: `lib/ui/screens/chat/chat_screen.dart`, new widget files, `test/integration/`, `test/`.

1. C1. Pick flow: blob-path selection, 16 MiB pre-cap dialog, progress bubble + Cancel, failure/Retry, interrupted-transfer banner, tap-to-download, one-time 30-day-retention notice, "Withdrawn by sender" terminal state.
2. C2. Loopback integration tests: direct + group + member-removed-mid-upload + resume-after-kill + cancel/expiry (§14). Not device tests.
3. C3. Fill the §15 ledger; claims-string scan; one honest backup-docs paragraph; README/SECURITY/checklist/CSV **untouched**.

## 18. Data model deltas (additive only)

**Backend — append to the `migrations` array in `backend/server/src/db.ts`** (never edit existing entries; `applyMigrations` checksums historical statements; `migrations.ts` untouched). New versions N+1 and N+2:

```sql
-- N+1: media_transfers
CREATE TABLE IF NOT EXISTS media_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  size_bytes BIGINT NOT NULL CHECK (size_bytes BETWEEN 1 AND 16777216),
  chunk_size INTEGER NOT NULL CHECK (chunk_size = 262144),
  total_chunks INTEGER NOT NULL CHECK (total_chunks BETWEEN 1 AND 64),
  state TEXT NOT NULL CHECK (state IN ('uploading','completed','canceled','expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_media_transfers_sender_state
  ON media_transfers (sender_id, state);
CREATE INDEX IF NOT EXISTS idx_media_transfers_expiry
  ON media_transfers (expires_at);
CREATE INDEX IF NOT EXISTS idx_media_transfers_conversation
  ON media_transfers (conversation_id);
```

```sql
-- N+2: media_chunks
CREATE TABLE IF NOT EXISTS media_chunks (
  transfer_id UUID NOT NULL REFERENCES media_transfers(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL CHECK (chunk_index BETWEEN 0 AND 63),
  sha256 CHAR(64) NOT NULL,
  byte_size INTEGER NOT NULL CHECK (byte_size BETWEEN 29 AND 262172),
  data BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (transfer_id, chunk_index)
);
```

`byte_size` lower bound 29 = minimum wire chunk (12 nonce + 16 tag + ≥1 plaintext byte). `chunk_size = 262144` is pinned in the CHECK so the cap can only be relaxed by a new migration (deliberate). No `messages` column touched. No backfill. Rollback = new forward migration dropping both tables + client revert; never edit history.

**Client — SQLCipher migration v006** (or next free version) creating `media_transfers_local` per §7.10. Additive; no existing table altered.

## 19. Error codes (stable `code` values)

`invalid_transfer_request` (400) · `invalid_chunk` (400) · `not_conversation_member` (403) · `not_sender` (403) · `not_authenticated` (401) · `download_token_invalid` (401) · `download_token_expired` (401) · `transfer_not_found` (404) · `transfer_expired` (404; terminal — clients render "unavailable") · `chunk_not_found` (404) · `missing_chunks` (409; body lists indices) · `chunk_hash_mismatch` (409) · `chunk_hash_conflict` (409) · `transfer_state_conflict` (409) · `message_identifier_conflict` (409, existing) · `transfer_too_large` (413) · `quota_exceeded` (413) · `conversation_rate_exceeded` (413) · `rate_limited` (429) · `limiter_unavailable` (503) · `internal_error` (500)

## 20. Open questions

- **OQ-1.** Auto-download on unmetered networks for small images, or tap-to-download always in v1? (Spec defaults to tap-to-download; UX decision for lead.)
- **OQ-2.** 30-day retention vs. message lifetime — product intent for "pinned media survives"? v1 has no server-side pin hook (server cannot see pins; they'd need a client signal at blob level). Product decision needed.
- **OQ-3.** Mirror anything into legacy `media_url`/`media_meta` for server observability? (Spec says no — unencrypted and redundant; confirm with lead.)
- **OQ-4.** Group semantics when a member is removed after download-init but before all chunks are fetched — accept (v1) or re-check membership per chunk (one query per 256 KiB)?
- **OQ-5.** Does the legacy Windows target ship in the same release train? If yes, R12 + WS-C sweep tests are binding; if excluded, note in ledger.
- **OQ-6.** Quota sign-off on 16 MiB cap and 100 MiB stored/user for the free-tier pilot (§7.2).
- **OQ-7.** `POST /media/transfers` idempotency: client-generated `transferId` + re-POST returning `409 transfer_state_conflict` (spec behavior) — acceptable, or add an idempotency-key header?

## 21. What would be "new cryptography" (none) vs. needs review

- **Not new crypto (reuse; no added review burden beyond existing gates):** per-chunk AES-256-GCM with random nonces; SHA-256 chunk/whole-file hashes (non-keyed integrity); HMAC-SHA256 download tokens (same construction as `rate-limit.ts` caller keys); content-key delivery inside the ratchet/group envelope; AAD strings as authenticated (not secret) encodings.
- **Needs review before claims (not before implementation):** the **composition** — payload-carried media key + ciphertext blob storage + token-bound fetch + receiver-side whole-file verify. No new primitive, but a composition/implementation review is recommended (parallel to the pending inline-path review). External review remains a release gate per project style, not an implementation blocker.
- **Would be new crypto (do NOT do):** HKDF-derived per-chunk keys (unnecessary — one key + random nonce at ≤ 64 chunks); content addressing by key/hash of blob; encryption under conversation traffic keys; password/PIN-based blob keys; "encrypted CDN token" constructions; PUF/biometric key binding. Any of these appearing in implementation = stop and escalate.
- **Not cryptography at all (reviewed as code):** quotas, GC, TTLs, retention, token binding (access control logic), membership checks.

---

## Task Contract

- **objective:** Implement WS-A/B/C (§17) so a > 256 KB and ≤ 16 MiB file round-trips edge-to-edge encrypted and resumable through the Chhaya backend, with the inline path untouched below 256 KB — without new cryptography.
- **success_criteria:** R1–R15 all pass; §14 unit + loopback tests green; §15 ledger filled with commands and "device verification: NOT RUN"; zero forbidden claims (§11); checklist/CSV untouched.
- **non_goals:** §4 in full (no CDN, no paid infra, no SFrame/streaming, no transcoding, no multi-device sync, no media bytes in backup, no forward/export controls, no claims flip).
- **assumptions:** AS-1..AS-6; free-tier pilot only (AS-2, Risks); membership check (not cryptographic membership proof) is the access boundary (AS-4).
- **open_questions:** OQ-1..OQ-7 (OQ-1 and OQ-6 block UX sign-off, not implementation start).
- **accepted_tradeoffs:** server sees exact file sizes (SD-3); 30-day retention can orphan live message refs; tap-to-download only; media bytes not backed up; token replay within 5 min shares ciphertext only; removed members keep bytes fetched before removal; old clients cannot decode media messages; exact-size metadata leak.
- **validation:** §14 commands (`flutter analyze`, `flutter test`, `npm run build && npm test`, additive-migration boot, claims scan); §15 ledger artifacts.
- **ask_abort_triggers:** any step appears to require new crypto (§21); any request to edit checklist/CSV/README/SECURITY or to make large-file E2E claims; migration checksum mismatch on existing entries; free-tier DB capacity exceeded in tests; OQ-4 resolved contrary to this spec without lead sign-off; implementation drift making media messages decode differently across platforms.

## Result Contract

- **status:** pass (spec delivered; implementation not started, by design)
- **summary:** `docs/spec-media-transfer-v1.md` specifies the encrypted resumable media transfer that lifts the 256 KB inline cap: 256 KiB chunking with per-chunk AES-256-GCM (random nonces, AAD-bound indices), server-verified SHA-256 chunk resume, receiver-side whole-file SHA-256 verification with atomic `.part`→final rename (no partial-download visibility), additive-only PostgreSQL `BYTEA` blob store (`media_transfers`/`media_chunks` — explicit "additive only" migration notes), sender+member authorization with HMAC-bound 5-minute download tokens, quotas/DoS bounds on free-tier infra, cancellation semantics, GC/TTL sweeper, group delivery via the existing `chhaya-group-key-v1` message-body key wrap (no second wrap, no new crypto), inline path kept for ≤ 256 KB, UX states incl. interrupted-transfer resume, backup/restore alignment, claims policy, WS-A/B/C with affected paths, verification ledger template, and a claims policy forbidding "e2e-encrypts large files" until shipped + device-verified.
- **artifacts:** `docs/spec-media-transfer-v1.md` (this file only). No other file modified; nothing implemented; no CSV/checklist/status change.
- **next_recommended:** lead/human review of §7.2 constants, OQ-1/OQ-4/OQ-6/OQ-7, and WS slicing; then delegate WS-A to developer (smallest slice first). Device verification and any claims flip remain lead/human decisions.
- **risks:** free-tier DB capacity; 30-day retention orphaning live refs; new composition needs external review before claims; old-client interop. See §16.
- **skill_resolution:** used security-and-hardening (boundary validation, quotas, rate limits, file-upload rules, log hygiene), api-and-interface-design (endpoint contracts, uniform error codes, additive-only evolution, no Range/head for a reason), test-driven-development (unit/integration split; loopback-not-device; red-first guidance), documentation-and-adrs (decisions + honest limits recorded inline; claims policy). No Skill Resolution block was provided with the handoff; fell back to the global available-skills list as instructed. Not used: browser (no UI to verify), oak-enrich-task (full spec authored directly from handoff requirements).

implementation_decisions_count: 12 (inline path retained ≤ 256 KB; 256 KiB chunks; 16 MiB cap; 64-chunk max; BYTEA-in-Postgres storage; token-bound non-content-addressed references; no Range/no complete endpoint; media key inside payload body wrap; 30-day retention; no media bytes in backup; tap-to-download v1; invisible-until-verified atomic finalization)
testing_decisions_count: 8 (unit AEAD/hash/resume/cancel/expiry matrix; payload-validation matrix; backend route/quota/token matrix; additive-migration checksum boot test; loopback direct roundtrip; loopback group + member-removed-mid-upload; interrupted-resume; claims scan — device verification explicitly excluded)
slices_defined: 3 (WS-A backend, WS-B client core, WS-C UI+verification)
