// Encrypted resumable media transfer — server-side blob store and lifecycle.
// Spec: docs/spec-media-transfer-v1.md §8 (HTTP API), §9.3 (retention/GC), §19 (codes).
//
// The server stores ciphertext bytes only. It never sees the media content key,
// file names, mime types or plaintext; those live inside the client-encrypted
// message payload. Access control is server-side conversation membership (same
// trust model as /messages) plus HMAC-bound short-lived download tokens.
//
// Feature-gated by MEDIA_TRANSFER_ENABLED (default false -> 503 feature_disabled),
// mirroring the WS1 PREKEYS_ENABLED pattern: dark landing, no claims flip.

import { createHash, createHmac, timingSafeEqual } from 'crypto';
import { Request, Response, Router, NextFunction } from 'express';
import { z } from 'zod';
import { query, withTransaction } from './db';
import { logger } from './log';
import { authenticateToken } from './session';
import { consumeIpRateLimit } from './rate-limit';
import { config } from './config';

export const MEDIA_LIMITS = {
  CHUNK_BYTES: 262144,          // 256 KiB plaintext per chunk (spec §7.2)
  WIRE_OVERHEAD: 28,            // 12-byte GCM nonce + 16-byte tag per chunk
  MAX_WIRE_CHUNK: 262172,       // 262144 + 28
  MAX_BYTES: 16777216,          // 16 MiB hard pre-send cap
  MAX_CHUNKS: 64,
  MAX_INFLIGHT_PER_USER: 3,     // state 'uploading' transfers per sender
  MAX_STAGED_BYTES: 33554432,   // 32 MiB declared in incomplete transfers per sender
  MAX_STORED_BYTES: 104857600,  // 100 MiB staged+completed per sender
  MAX_PER_CONV_PER_DAY: 50,     // completed transfers per conversation per rolling 24h
  TRANSFER_TTL_SECONDS: 3600,   // incomplete transfer staged TTL
  BLOB_RETENTION_SECONDS: 30 * 24 * 3600,
  DOWNLOAD_TOKEN_TTL_SECONDS: 300,
  CHUNK_RATE_LIMIT: 240,        // chunk PUTs per window per user (spec §7.2)
  CHUNK_RATE_WINDOW_SECONDS: 60,
  START_RATE_LIMIT: 20,         // transfer starts per window per user
  START_RATE_WINDOW_SECONDS: 3600,
  // Spec §8.6 requires a 429 for download init but names no bucket size; 120/min is conservative.
  DOWNLOAD_INIT_RATE_LIMIT: 120,
  DOWNLOAD_INIT_RATE_WINDOW_SECONDS: 60,
  GC_BATCH: 500,                // LIMIT-bounded GC rows per statement (spec §9.3)
} as const;

export const expectedTotalChunks = (sizeBytes: number): number =>
  Math.ceil(sizeBytes / MEDIA_LIMITS.CHUNK_BYTES);

// Declared plaintext size + per-chunk AEAD overhead is the maximum wire byte total.
export const expectedWireBytes = (sizeBytes: number, totalChunks: number): number =>
  sizeBytes + MEDIA_LIMITS.WIRE_OVERHEAD * totalChunks;

// ---------------------------------------------------------------------------
// Download tokens (spec §7.7, §8.6): HMAC-SHA256 bound to
// (purpose || transferId || userId || conversationId || exp), base64url.
// Same construction family as rate-limit.ts caller keys (keyed HMAC of config.JWT_SECRET).
// ---------------------------------------------------------------------------

const TOKEN_PURPOSE = 'chhaya-media-dl-v1';

export const mintDownloadToken = (
  input: { transferId: string; userId: string; conversationId: string },
  ttlSeconds: number = MEDIA_LIMITS.DOWNLOAD_TOKEN_TTL_SECONDS,
  now: Date = new Date(),
): { token: string; expiresAt: Date } => {
  const expiresAt = new Date(now.getTime() + ttlSeconds * 1000);
  const exp = Math.floor(expiresAt.getTime() / 1000);
  const payload = `${TOKEN_PURPOSE}.${input.transferId}.${input.userId}.${input.conversationId}.${exp}`;
  const mac = createHmac('sha256', config.JWT_SECRET).update(payload).digest('base64url');
  return { token: Buffer.from(`${payload}.${mac}`, 'utf8').toString('base64url'), expiresAt };
};

export type DownloadTokenVerification =
  | { ok: true; expiresAt: Date }
  | { ok: false; reason: 'invalid' | 'expired' };

export const verifyDownloadToken = (
  token: string,
  binding: { transferId: string; userId: string; conversationId: string },
  now: Date = new Date(),
): DownloadTokenVerification => {
  if (typeof token !== 'string' || token.length === 0 || token.length > 512) {
    return { ok: false, reason: 'invalid' };
  }
  let decoded: string;
  try {
    decoded = Buffer.from(token, 'base64url').toString('utf8');
  } catch {
    return { ok: false, reason: 'invalid' };
  }
  const parts = decoded.split('.');
  if (parts.length !== 6 || parts[0] !== TOKEN_PURPOSE) {
    return { ok: false, reason: 'invalid' };
  }
  const [, transferId, userId, conversationId, expRaw, mac] = parts;
  const exp = Number(expRaw);
  if (!/^[0-9]+$/.test(expRaw) || !Number.isSafeInteger(exp)) {
    return { ok: false, reason: 'invalid' };
  }
  const expected = createHmac('sha256', config.JWT_SECRET)
    .update([TOKEN_PURPOSE, transferId, userId, conversationId, expRaw].join('.'))
    .digest('base64url');
  const expectedBuf = Buffer.from(expected, 'utf8');
  const macBuf = Buffer.from(mac, 'utf8');
  if (expectedBuf.length !== macBuf.length || !timingSafeEqual(expectedBuf, macBuf)) {
    return { ok: false, reason: 'invalid' };
  }
  // Binding checks after HMAC verification so forged tokens learn nothing.
  if (transferId !== binding.transferId || userId !== binding.userId || conversationId !== binding.conversationId) {
    return { ok: false, reason: 'invalid' };
  }
  if (exp * 1000 <= now.getTime()) {
    return { ok: false, reason: 'expired' };
  }
  return { ok: true, expiresAt: new Date(exp * 1000) };
};

// ---------------------------------------------------------------------------
// GC sweeper (spec §9.3). Invoked helper — not its own daemon. index.ts calls
// sweepMediaTransfersSafely() from the existing maintenance interval
// (cleanupTimer, same discipline as pruneExpiredRateLimits): bounded batches,
// fail-safe, idempotent, logs row counts. Every statement carries LIMIT and the
// loops drain to zero so GC can never starve the API.
// ---------------------------------------------------------------------------

export interface SweepResult {
  expiredUploads: number;
  expiredCompleted: number;
  staleTerminalRows: number;
  orphanChunks: number;
}

export const sweepMediaTransfers = async (
  queryImpl: typeof query = query,
  log: { info: (msg: string, meta?: Record<string, unknown>) => void; warn: (msg: string, meta?: Record<string, unknown>) => void } = logger,
): Promise<SweepResult> => {
  const result: SweepResult = { expiredUploads: 0, expiredCompleted: 0, staleTerminalRows: 0, orphanChunks: 0 };
  const batch = MEDIA_LIMITS.GC_BATCH;

  // 1. Uploading transfers past the staged TTL: mark expired, then delete (cascade purges chunks).
  for (;;) {
    const stale = await queryImpl(
      `SELECT id FROM media_transfers WHERE state = 'uploading' AND expires_at <= NOW() LIMIT ${batch}`);
    if (!stale.rows.length) break;
    const ids = stale.rows.map((r: { id: string }) => r.id);
    await queryImpl(
      `UPDATE media_transfers SET state = 'expired', updated_at = NOW() WHERE id = ANY($1::uuid[]) AND state = 'uploading'`,
      [ids]);
    const deleted = await queryImpl(
      `DELETE FROM media_transfers WHERE id = ANY($1::uuid[]) AND state = 'expired'`, [ids]);
    result.expiredUploads += deleted.rowCount ?? ids.length;
  }

  // 2. Completed blobs past the 30-day retention cap.
  for (;;) {
    const stale = await queryImpl(
      `SELECT id FROM media_transfers
        WHERE state = 'completed' AND completed_at <= NOW() - INTERVAL '30 days' LIMIT ${batch}`);
    if (!stale.rows.length) break;
    const ids = stale.rows.map((r: { id: string }) => r.id);
    const deleted = await queryImpl(
      `DELETE FROM media_transfers WHERE id = ANY($1::uuid[]) AND state = 'completed'`, [ids]);
    result.expiredCompleted += deleted.rowCount ?? ids.length;
  }

  // 3. Terminal rows ('canceled'/'expired') that outlived their synchronous delete.
  for (;;) {
    const stale = await queryImpl(
      `SELECT id FROM media_transfers WHERE state IN ('canceled','expired') LIMIT ${batch}`);
    if (!stale.rows.length) break;
    const ids = stale.rows.map((r: { id: string }) => r.id);
    const deleted = await queryImpl(
      `DELETE FROM media_transfers WHERE id = ANY($1::uuid[]) AND state IN ('canceled','expired')`, [ids]);
    result.staleTerminalRows += deleted.rowCount ?? ids.length;
  }

  // 4. Orphan chunk sweep (expect 0; the FK should make this impossible).
  for (;;) {
    const deleted = await queryImpl(
      `WITH orphans AS (
         SELECT mc.ctid FROM media_chunks mc
         WHERE NOT EXISTS (SELECT 1 FROM media_transfers t WHERE t.id = mc.transfer_id)
         LIMIT ${batch}
       )
       DELETE FROM media_chunks WHERE ctid IN (SELECT ctid FROM orphans)`);
    const n = deleted.rowCount ?? 0;
    if (n === 0) break;
    result.orphanChunks += n;
    if (n < batch) break;
  }

  if (result.orphanChunks > 0) {
    log.warn('Media GC removed orphan chunks', { ...result });
  }
  log.info('Media GC sweep complete', { ...result });
  return result;
};

/** Fail-safe wrapper: DB failure must skip this tick, never crash the maintenance path. */
export const sweepMediaTransfersSafely = async (): Promise<void> => {
  try {
    await sweepMediaTransfers();
  } catch (error) {
    logger.warn('Media transfer GC skipped this tick', { error: (error as Error).message });
  }
};

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

export const mediaRouter = Router();
const safe = (handler: (req: Request, res: Response, next: NextFunction) => Promise<unknown>) =>
  (req: Request, res: Response, next: NextFunction) => { void Promise.resolve(handler(req, res, next)).catch(next); };

const authMiddleware = async (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization header', code: 'not_authenticated' });
  }
  try {
    const userId = res.locals.authenticatedUserId ?? await authenticateToken(authHeader.substring(7));
    if (!userId) return res.status(401).json({ error: 'Invalid or expired token', code: 'not_authenticated' });
    (req as any).userId = userId;
    next();
  } catch (error) { next(error); }
};

const mediaGate = (res: Response): boolean => {
  if (!config.MEDIA_TRANSFER_ENABLED) {
    res.status(503).json({ error: 'feature_disabled', code: 'feature_disabled' });
    return false;
  }
  return true;
};

// Fail-closed per-route shared-limiter guard: DB failure -> 503, excess -> 429.
const rateLimitOrReject = async (
  res: Response, identity: string, limit: number, windowSeconds: number,
): Promise<boolean> => {
  let decision;
  try {
    decision = await consumeIpRateLimit(identity, limit, windowSeconds);
  } catch {
    res.status(503).json({ error: 'Service temporarily unavailable', code: 'limiter_unavailable' });
    return false;
  }
  if (!decision.allowed) {
    res.set('Retry-After', String(decision.retryAfterSeconds));
    res.status(429).json({ error: 'Too many requests', code: 'rate_limited' });
    return false;
  }
  return true;
};

const uuidParam = (value: unknown): value is string =>
  typeof value === 'string' && z.string().uuid().safeParse(value).success;

interface TransferRow {
  id: string; conversation_id: string; sender_id: string;
  size_bytes: string | number; chunk_size: number; total_chunks: number;
  state: string; created_at: Date; updated_at: Date; completed_at: Date | null; expires_at: Date;
}
const asNumber = (v: string | number): number => Number(v);

// ---- Transfer start validation (pure, unit-tested) -------------------------

export type StartValidation =
  | { ok: true; value: { conversationId: string; sizeBytes: number; totalChunks: number; chunkSize: number } }
  | { ok: false; status: number; code: string; error: string };

export const validateTransferStart = (body: unknown): StartValidation => {
  const schema = z.object({
    conversationId: z.string().uuid(),
    sizeBytes: z.number().int().min(1).max(MEDIA_LIMITS.MAX_BYTES),
    totalChunks: z.number().int().min(1).max(MEDIA_LIMITS.MAX_CHUNKS),
    chunkSize: z.number().int(),
  });
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    // Distinguish the headline cap violation for a stable 413.
    const raw = (body ?? {}) as Record<string, unknown>;
    if (typeof raw.sizeBytes === 'number' && raw.sizeBytes > MEDIA_LIMITS.MAX_BYTES) {
      return { ok: false, status: 413, code: 'transfer_too_large', error: 'File exceeds the 16 MiB limit' };
    }
    if (typeof raw.totalChunks === 'number' && raw.totalChunks > MEDIA_LIMITS.MAX_CHUNKS) {
      return { ok: false, status: 413, code: 'transfer_too_large', error: 'Transfer exceeds the 64-chunk limit' };
    }
    return { ok: false, status: 400, code: 'invalid_transfer_request', error: 'Invalid transfer request' };
  }
  const { conversationId, sizeBytes, totalChunks, chunkSize } = parsed.data;
  if (chunkSize !== MEDIA_LIMITS.CHUNK_BYTES) {
    return { ok: false, status: 400, code: 'invalid_transfer_request', error: 'chunkSize must equal 262144' };
  }
  if (totalChunks !== expectedTotalChunks(sizeBytes)) {
    return { ok: false, status: 400, code: 'invalid_transfer_request', error: 'totalChunks must equal ceil(sizeBytes/262144)' };
  }
  return { ok: true, value: { conversationId, sizeBytes, totalChunks, chunkSize } };
};

// POST /media/transfers — start (spec §8.1)
mediaRouter.post('/transfers', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const validation = validateTransferStart(req.body);
  if (!validation.ok) {
    return res.status(validation.status).json({ error: validation.error, code: validation.code });
  }
  if (!(await rateLimitOrReject(res, `media:start:${userId}`, MEDIA_LIMITS.START_RATE_LIMIT, MEDIA_LIMITS.START_RATE_WINDOW_SECONDS))) return;
  const { conversationId, sizeBytes, totalChunks, chunkSize } = validation.value;

  // Membership + quotas in one transaction: the conversation row lock matches
  // the /messages membership discipline; the sender advisory lock serializes
  // the sender's quota accounting across conversations (implementer's choice,
  // spec §8.1) so concurrent starts cannot overshoot staged/stored caps.
  const result = await withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 872622))', [`media:${userId}`]);
    const convo = await client.query('SELECT id FROM conversations WHERE id = $1 FOR UPDATE', [conversationId]);
    if (!convo.rows.length) return { status: 403, error: 'Not a participant', code: 'not_conversation_member' };
    const member = await client.query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL',
      [conversationId, userId]);
    if (!member.rows.length) return { status: 403, error: 'Not a participant', code: 'not_conversation_member' };

    const quota = await client.query(
      `SELECT COUNT(*) FILTER (WHERE state = 'uploading')::int AS inflight,
              COALESCE(SUM(size_bytes) FILTER (WHERE state = 'uploading'), 0)::bigint AS staged,
              COALESCE(SUM(size_bytes), 0)::bigint AS stored
         FROM media_transfers WHERE sender_id = $1`, [userId]);
    const inflight = quota.rows[0].inflight as number;
    const staged = Number(quota.rows[0].staged);
    const stored = Number(quota.rows[0].stored);
    if (inflight >= MEDIA_LIMITS.MAX_INFLIGHT_PER_USER) {
      return { status: 413, error: 'Too many concurrent uploads', code: 'quota_exceeded' };
    }
    if (staged + sizeBytes > MEDIA_LIMITS.MAX_STAGED_BYTES) {
      return { status: 413, error: 'Staged transfer byte quota exceeded', code: 'quota_exceeded' };
    }
    if (stored + sizeBytes > MEDIA_LIMITS.MAX_STORED_BYTES) {
      return { status: 413, error: 'Stored media byte quota exceeded', code: 'quota_exceeded' };
    }
    const perConv = await client.query(
      `SELECT COUNT(*)::int AS n FROM media_transfers
        WHERE conversation_id = $1 AND state = 'completed' AND completed_at > NOW() - INTERVAL '24 hours'`,
      [conversationId]);
    if ((perConv.rows[0].n as number) >= MEDIA_LIMITS.MAX_PER_CONV_PER_DAY) {
      return { status: 413, error: 'Conversation media transfer rate exceeded', code: 'conversation_rate_exceeded' };
    }

    const inserted = await client.query(
      `INSERT INTO media_transfers (conversation_id, sender_id, size_bytes, chunk_size, total_chunks, state, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'uploading', NOW() + INTERVAL '1 hour')
       RETURNING id, expires_at`,
      [conversationId, userId, sizeBytes, chunkSize, totalChunks]);
    return { status: 201, inserted: inserted.rows[0] };
  });

  if ('inserted' in result) {
    return res.status(201).json({
      transferId: result.inserted.id,
      chunkSize: MEDIA_LIMITS.CHUNK_BYTES,
      totalChunks,
      expiresAt: new Date(result.inserted.expires_at).toISOString(),
    });
  }
  return res.status(result.status).json({ error: result.error, code: result.code });
}));

// PUT /media/transfers/:id/chunks/:index — upload chunk (spec §8.2)
// Raw body is mounted as application/octet-stream BEFORE express.json() in index.ts.
mediaRouter.put('/transfers/:id/chunks/:index', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const { id, index: indexRaw } = req.params;
  if (!uuidParam(id)) return res.status(404).json({ error: 'Unknown transfer', code: 'transfer_not_found' });
  if (!/^[0-9]{1,2}$/.test(indexRaw)) return res.status(400).json({ error: 'Invalid chunk index', code: 'invalid_chunk' });
  const index = Number(indexRaw);
  const shaHeader = req.headers['x-chunk-sha256'];
  if (typeof shaHeader !== 'string' || !/^[0-9a-f]{64}$/.test(shaHeader)) {
    return res.status(400).json({ error: 'X-Chunk-SHA256 must be 64 lowercase hex chars', code: 'invalid_chunk' });
  }
  const body = req.body as unknown;
  if (!Buffer.isBuffer(body) || body.length < 29 || body.length > MEDIA_LIMITS.MAX_WIRE_CHUNK) {
    return res.status(400).json({ error: 'Chunk body must be 29..262172 raw bytes', code: 'invalid_chunk' });
  }
  const actualSha256 = createHash('sha256').update(body).digest('hex');
  if (actualSha256 !== shaHeader) {
    // Nothing stored; header is defense-in-depth, the server recomputes.
    return res.status(409).json({ error: 'Chunk hash mismatch', code: 'chunk_hash_mismatch' });
  }
  if (!(await rateLimitOrReject(res, `media:chunk:${userId}`, MEDIA_LIMITS.CHUNK_RATE_LIMIT, MEDIA_LIMITS.CHUNK_RATE_WINDOW_SECONDS))) return;

  const result = await withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 872622))', [`media:${userId}`]);
    const t = await client.query('SELECT * FROM media_transfers WHERE id = $1 FOR UPDATE', [id]);
    if (!t.rows.length) return { status: 404, error: 'Unknown transfer', code: 'transfer_not_found' };
    const transfer = t.rows[0] as TransferRow;
    if (transfer.sender_id !== userId) return { status: 403, error: 'Not the sender', code: 'not_sender' };
    if (transfer.state !== 'uploading') return { status: 409, error: 'Transfer is not accepting chunks', code: 'transfer_state_conflict' };
    if (new Date(transfer.expires_at).getTime() <= Date.now()) {
      return { status: 404, error: 'Transfer expired', code: 'transfer_expired' };
    }
    if (index >= transfer.total_chunks) {
      return { status: 400, error: 'Chunk index out of range', code: 'invalid_chunk' };
    }

    const existing = await client.query(
      'SELECT sha256 FROM media_chunks WHERE transfer_id = $1 AND chunk_index = $2', [id, index]);
    if (existing.rows.length) {
      if (existing.rows[0].sha256 === shaHeader) {
        const count = await client.query('SELECT COUNT(*)::int AS n FROM media_chunks WHERE transfer_id = $1', [id]);
        return { status: 200, body: { ok: true, deduped: true, receivedChunks: count.rows[0].n } };
      }
      return { status: 409, error: 'Chunk already stored with a different hash', code: 'chunk_hash_conflict' };
    }

    // Actual-bytes hard caps across the sender's transfers (spec §7.2/§8.2:
    // enforcement is on actual stored bytes, not declared sizes).
    const quota = await client.query(
      `SELECT COALESCE(SUM(c.byte_size) FILTER (WHERE mt.state = 'uploading'), 0)::bigint AS staged,
              COALESCE(SUM(c.byte_size), 0)::bigint AS stored
         FROM media_transfers mt JOIN media_chunks c ON c.transfer_id = mt.id
        WHERE mt.sender_id = $1`, [userId]);
    const staged = Number(quota.rows[0].staged);
    const stored = Number(quota.rows[0].stored);
    if (staged + body.length > MEDIA_LIMITS.MAX_STAGED_BYTES ||
        stored + body.length > MEDIA_LIMITS.MAX_STORED_BYTES) {
      return { status: 413, error: 'Stored media byte quota exceeded', code: 'quota_exceeded' };
    }

    await client.query(
      `INSERT INTO media_chunks (transfer_id, chunk_index, sha256, byte_size, data)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, index, shaHeader, body.length, body]);
    await client.query('UPDATE media_transfers SET updated_at = NOW() WHERE id = $1', [id]);
    const count = await client.query('SELECT COUNT(*)::int AS n FROM media_chunks WHERE transfer_id = $1', [id]);
    return { status: 201, body: { ok: true, receivedChunks: count.rows[0].n } };
  });

  if ('body' in result) return res.status(result.status).json(result.body);
  return res.status(result.status).json({ error: result.error, code: result.code });
}));

// GET /media/transfers/:id — status/resume (spec §8.3, sender only, no existence oracle)
mediaRouter.get('/transfers/:id', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const { id } = req.params;
  if (!uuidParam(id)) return res.status(404).json({ error: 'Unknown transfer', code: 'transfer_not_found' });

  const t = await query<TransferRow>('SELECT * FROM media_transfers WHERE id = $1', [id]);
  if (!t.rows.length) return res.status(404).json({ error: 'Unknown transfer', code: 'transfer_not_found' });
  const transfer = t.rows[0];
  if (transfer.sender_id !== userId) return res.status(404).json({ error: 'Unknown transfer', code: 'transfer_not_found' });
  if (transfer.state === 'uploading' && new Date(transfer.expires_at).getTime() <= Date.now()) {
    return res.status(404).json({ error: 'Transfer expired', code: 'transfer_expired' });
  }

  // Resume aid: only indices whose stored bytes hash to the stored value count as present.
  const chunks = await query<{ chunk_index: number; sha256: string; data: Buffer }>(
    'SELECT chunk_index, sha256, data FROM media_chunks WHERE transfer_id = $1 ORDER BY chunk_index', [id]);
  const received = chunks.rows
    .filter((row) => createHash('sha256').update(row.data).digest('hex') === row.sha256)
    .map((row) => row.chunk_index);

  return res.status(200).json({
    state: transfer.state,
    totalChunks: transfer.total_chunks,
    received,
    expiresAt: new Date(transfer.expires_at).toISOString(),
    sizeBytes: asNumber(transfer.size_bytes),
  });
}));

// POST /media/transfers/:id/complete — finalize upload (spec §8.4)
mediaRouter.post('/transfers/:id/complete', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const { id } = req.params;
  if (!uuidParam(id)) return res.status(404).json({ error: 'Unknown transfer', code: 'transfer_not_found' });

  const result = await withTransaction(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 872622))', [`media:${userId}`]);
    const t = await client.query('SELECT * FROM media_transfers WHERE id = $1 FOR UPDATE', [id]);
    if (!t.rows.length) return { status: 404, error: 'Unknown transfer', code: 'transfer_not_found' };
    const transfer = t.rows[0] as TransferRow;
    if (transfer.sender_id !== userId) return { status: 403, error: 'Not the sender', code: 'not_sender' };

    const agg = await client.query(
      `SELECT COUNT(*)::int AS chunks, COALESCE(SUM(byte_size), 0)::bigint AS bytes
         FROM media_chunks WHERE transfer_id = $1`, [id]);
    const actualBytes = Number(agg.rows[0].bytes);

    // Idempotent re-complete (spec §8.4): safe after the row flipped, before GC reclaims it.
    if (transfer.state === 'completed') {
      return { status: 200, body: { transferId: id, state: 'completed', sizeBytes: actualBytes } };
    }
    if (transfer.state !== 'uploading') {
      return { status: 409, error: 'Transfer is not in an uploadable state', code: 'transfer_state_conflict' };
    }
    if (new Date(transfer.expires_at).getTime() <= Date.now()) {
      return { status: 404, error: 'Transfer expired', code: 'transfer_expired' };
    }

    const expected = transfer.total_chunks;
    if (actualBytes > expectedWireBytes(asNumber(transfer.size_bytes), expected) ||
        actualBytes > expectedWireBytes(MEDIA_LIMITS.MAX_BYTES, MEDIA_LIMITS.MAX_CHUNKS)) {
      // Spec §8.4's literal "SUM(byte_size) ≤ declared size" cannot hold for wire
      // bytes (28 B overhead per chunk); the enforceable bound is declared + overhead.
      return { status: 413, error: 'Transfer exceeds the maximum byte size', code: 'transfer_too_large' };
    }

    // Actual-bytes stored quota, re-checked at completion (spec §8.4, R8).
    const stored = await client.query(
      `SELECT COALESCE(SUM(c.byte_size), 0)::bigint AS stored
         FROM media_transfers mt JOIN media_chunks c ON c.transfer_id = mt.id
        WHERE mt.sender_id = $1`, [userId]);
    if (Number(stored.rows[0].stored) > MEDIA_LIMITS.MAX_STORED_BYTES) {
      return { status: 413, error: 'Stored media byte quota exceeded', code: 'quota_exceeded' };
    }

    if ((agg.rows[0].chunks as number) !== expected) {
      const present = await client.query(
        'SELECT chunk_index FROM media_chunks WHERE transfer_id = $1', [id]);
      const have = new Set(present.rows.map((row: { chunk_index: number }) => row.chunk_index));
      const missing: number[] = [];
      for (let i = 0; i < expected; i++) if (!have.has(i)) missing.push(i);
      return { status: 409, error: 'Transfer is missing chunks', code: 'missing_chunks', missing };
    }

    await client.query(
      `UPDATE media_transfers SET state = 'completed', completed_at = NOW(), updated_at = NOW() WHERE id = $1`, [id]);
    return { status: 200, body: { transferId: id, state: 'completed', sizeBytes: actualBytes } };
  });

  if ('body' in result) return res.status(result.status).json(result.body);
  if (result.code === 'missing_chunks') {
    return res.status(409).json({ error: result.error, code: 'missing_chunks', missing: (result as any).missing });
  }
  return res.status(result.status).json({ error: result.error, code: result.code });
}));

// DELETE /media/transfers/:id — sender-only cancel/delete (spec §8.5)
mediaRouter.delete('/transfers/:id', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const { id } = req.params;
  if (!uuidParam(id)) return res.status(204).end();

  const t = await query('SELECT sender_id FROM media_transfers WHERE id = $1', [id]);
  if (!t.rows.length) return res.status(204).end(); // idempotent: absent -> 204
  if (t.rows[0].sender_id !== userId) {
    // Same posture as the sibling sender-only mutating routes (PUT/complete):
    // explicit 403 not_sender rather than a silent 204.
    return res.status(403).json({ error: 'Not the sender', code: 'not_sender' });
  }
  await withTransaction(async (client) => {
    await client.query('DELETE FROM media_chunks WHERE transfer_id = $1', [id]); // cascade would cover; explicit per spec §8.5
    await client.query('DELETE FROM media_transfers WHERE id = $1 AND sender_id = $2', [id, userId]);
  });
  return res.status(204).end();
}));

// POST /media/downloads — download init (spec §8.6)
mediaRouter.post('/downloads', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const parsed = z.object({ transferId: z.string().uuid() }).safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid download request', code: 'invalid_transfer_request' });
  }
  if (!(await rateLimitOrReject(res, `media:download:${userId}`, MEDIA_LIMITS.DOWNLOAD_INIT_RATE_LIMIT, MEDIA_LIMITS.DOWNLOAD_INIT_RATE_WINDOW_SECONDS))) return;
  const { transferId } = parsed.data;

  const t = await query<TransferRow>('SELECT * FROM media_transfers WHERE id = $1', [transferId]);
  if (!t.rows.length || t.rows[0].state !== 'completed') {
    return res.status(404).json({ error: 'Transfer not found', code: 'transfer_not_found' });
  }
  const transfer = t.rows[0];
  if (transfer.completed_at && new Date(transfer.completed_at).getTime() <= Date.now() - MEDIA_LIMITS.BLOB_RETENTION_SECONDS * 1000) {
    return res.status(404).json({ error: 'Transfer expired', code: 'transfer_expired' });
  }
  const isSender = transfer.sender_id === userId;
  if (!isSender) {
    const member = await query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL',
      [transfer.conversation_id, userId]);
    if (!member.rows.length) {
      return res.status(403).json({ error: 'Not a participant', code: 'not_conversation_member' });
    }
  }

  const { token, expiresAt } = mintDownloadToken({ transferId, userId, conversationId: transfer.conversation_id });
  return res.status(201).json({
    token,
    expiresAt: expiresAt.toISOString(),
    totalChunks: transfer.total_chunks,
    chunkSize: MEDIA_LIMITS.CHUNK_BYTES,
    sizeBytes: asNumber(transfer.size_bytes),
  });
}));

// GET /media/downloads/:id/chunks/:index — chunk fetch with X-Download-Token (spec §8.7)
mediaRouter.get('/downloads/:id/chunks/:index', authMiddleware, safe(async (req: Request, res: Response) => {
  if (!mediaGate(res)) return;
  const userId = (req as any).userId as string;
  const { id, index: indexRaw } = req.params;
  if (!uuidParam(id)) return res.status(404).json({ error: 'Transfer not found', code: 'transfer_not_found' });
  if (!/^[0-9]{1,2}$/.test(indexRaw)) return res.status(400).json({ error: 'Invalid chunk index', code: 'invalid_chunk' });
  const index = Number(indexRaw);

  const token = req.headers['x-download-token'];
  if (typeof token !== 'string' || !token) {
    return res.status(401).json({ error: 'Download token required', code: 'download_token_invalid' });
  }

  const t = await query<TransferRow>('SELECT * FROM media_transfers WHERE id = $1', [id]);
  if (!t.rows.length || t.rows[0].state !== 'completed') {
    return res.status(404).json({ error: 'Transfer not found', code: 'transfer_not_found' });
  }
  const transfer = t.rows[0];
  if (transfer.completed_at && new Date(transfer.completed_at).getTime() <= Date.now() - MEDIA_LIMITS.BLOB_RETENTION_SECONDS * 1000) {
    return res.status(404).json({ error: 'Transfer expired', code: 'transfer_expired' });
  }

  // Token verified before any binding is trusted (spec §8.7: v1 binds membership at init).
  const verification = verifyDownloadToken(token, { transferId: id, userId, conversationId: transfer.conversation_id });
  if (!verification.ok) {
    return res.status(401).json({
      error: verification.reason === 'expired' ? 'Download token expired' : 'Download token invalid',
      code: verification.reason === 'expired' ? 'download_token_expired' : 'download_token_invalid',
    });
  }
  if (index >= transfer.total_chunks) {
    return res.status(400).json({ error: 'Chunk index out of range', code: 'invalid_chunk' });
  }

  const chunk = await query<{ sha256: string; data: Buffer }>(
    'SELECT sha256, data FROM media_chunks WHERE transfer_id = $1 AND chunk_index = $2', [id, index]);
  if (!chunk.rows.length) {
    return res.status(404).json({ error: 'Chunk not found', code: 'chunk_not_found' });
  }

  res.set('Content-Type', 'application/octet-stream');
  res.set('X-Chunk-SHA256', chunk.rows[0].sha256);
  res.set('Cache-Control', 'no-store');
  return res.status(200).send(chunk.rows[0].data);
}));
