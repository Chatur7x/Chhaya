import { createHash, randomBytes } from 'crypto';
import { Request, Response, Router, NextFunction } from 'express';
import { z } from 'zod';
import { query, withTransaction } from './db';
import { logger } from './log';
import { authenticateSession, tokenHash } from './session';
import { consumeIpRateLimit } from './rate-limit';

/**
 * DL-A authenticated device linking (docs/spec-device-linking-v1.md §4).
 *
 * Server stores only public material, hashes of the one-time code, opaque AEAD
 * approval bytes and signatures over public transcripts. The raw code exists in
 * memory only for the duration of a request; no private key material, SK, or
 * plaintext approval is ever persisted (spec §4.6).
 */

export const devicesRouter = Router();
const safe = (handler: (req: Request, res: Response, next: NextFunction) => Promise<unknown>) =>
  (req: Request, res: Response, next: NextFunction) => { void Promise.resolve(handler(req, res, next)).catch(next); };

class HttpError extends Error {
  constructor(public status: number, public code: string, message?: string) {
    super(message ?? code);
  }
}

const deviceAuth = async (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization header', code: 'not_authenticated' });
  }
  try {
    const session = res.locals.authenticatedSession ?? await authenticateSession(authHeader.substring(7));
    if (!session) return res.status(401).json({ error: 'Invalid or expired token', code: 'not_authenticated' });
    (req as any).userId = session.userId;
    (req as any).deviceId = session.deviceId;
    next();
  } catch (error) { next(error); }
};

// Fail-closed per-route shared-limiter guard (same pattern as media.ts).
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

const callerIp = (req: Request): string =>
  req.ip || req.socket.remoteAddress || 'unknown';

const uuidParam = (value: unknown): value is string =>
  typeof value === 'string' && z.string().uuid().safeParse(value).success;

const hex64 = /^[0-9a-f]{64}$/;
const sha256Hex = (value: string): string =>
  createHash('sha256').update(value, 'utf8').digest('hex');

const approvalSchema = z.object({
  requestId: z.string().uuid(),
  code: z.string().min(1).max(128),
  action: z.enum(['approve', 'deny']),
  approval: z.string().regex(/^[A-Za-z0-9+/]+={0,2}$/).max(16384).optional(),
  approvalSignature: z.string().regex(/^[0-9a-f]{128}$/).optional(),
  primEphPub: z.string().regex(hex64).optional(),
});

const requestSchema = z.object({
  deviceId: z.string().uuid(),
  deviceName: z.string().trim().min(1).max(100),
  platform: z.string().trim().min(1).max(20),
  devicePublicKey: z.string().regex(hex64),
  ephemeralPublicKey: z.string().regex(hex64),
  codeHash: z.string().regex(hex64),
});

const consumeSchema = z.object({
  requestId: z.string().uuid(),
  code: z.string().min(1).max(128),
});

const audit = async (
  client: { query: (sql: string, params?: any[]) => Promise<any> } | null,
  action: string,
  userId: string | null,
  deviceId: string | null,
): Promise<void> => {
  const sql = 'INSERT INTO device_link_events(user_id, device_id, action) VALUES ($1,$2,$3)';
  if (client) await client.query(sql, [userId, deviceId, action]);
  else await query(sql, [userId, deviceId, action]);
};

// ---------------------------------------------------------------------------
// POST /devices/link/request — new (unenrolled) device registers a pending link.
// Unauthenticated; 10/hour/IP. Idempotent for a deviceId with a live pending or
// approved row (spec §4.2).
// ---------------------------------------------------------------------------
devicesRouter.post('/link/request', safe(async (req: Request, res: Response) => {
  if (!await rateLimitOrReject(res, `device-link-request:${callerIp(req)}`, 10, 3600)) return;
  const data = requestSchema.parse(req.body);

  const create = async (): Promise<{ requestId: string; expiresAt: Date; created: boolean }> => {
    for (let attempt = 0; attempt < 2; attempt++) {
      const inserted = await query<{ request_id: string; expires_at: Date }>(
        `INSERT INTO device_link_requests
           (request_id, device_id, device_name, platform, device_public_key,
            ephemeral_public_key, code_hash, state, expires_at)
         VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, 'pending', NOW() + INTERVAL '5 minutes')
         ON CONFLICT (device_id) WHERE state IN ('pending','approved') DO NOTHING
         RETURNING request_id, expires_at`,
        [data.deviceId, data.deviceName, data.platform, data.devicePublicKey,
         data.ephemeralPublicKey, data.codeHash],
      );
      if (inserted.rowCount === 1) {
        const row = inserted.rows[0];
        return { requestId: row.request_id, expiresAt: row.expires_at, created: true };
      }
      // Lost a race against a parallel request for the same deviceId: read the winner.
      const existing = await query<{ request_id: string; expires_at: Date }>(
        `SELECT request_id, expires_at FROM device_link_requests
          WHERE device_id = $1 AND state IN ('pending','approved')
          ORDER BY created_at LIMIT 1`,
        [data.deviceId],
      );
      if (existing.rowCount === 1) {
        return { requestId: existing.rows[0].request_id, expiresAt: existing.rows[0].expires_at, created: false };
      }
    }
    throw new HttpError(409, 'request_conflict');
  };

  // Idempotency probe (spec §4.2): a live pending/approved row for this deviceId
  // is returned as-is; an expired one is deleted on read and replaced.
  const existing = await query<{ request_id: string; expires_at: Date; state: string }>(
    `SELECT request_id, expires_at, state FROM device_link_requests
      WHERE device_id = $1 AND state IN ('pending','approved')
      ORDER BY created_at LIMIT 1`,
    [data.deviceId],
  );
  if (existing.rowCount === 1) {
    const row = existing.rows[0];
    if (row.expires_at.getTime() > Date.now()) {
      res.status(200).json({ requestId: row.request_id, expiresAt: row.expires_at });
      return;
    }
    await query('DELETE FROM device_link_requests WHERE request_id = $1', [row.request_id]);
  }

  const created = await create();
  if (created.created) await audit(null, 'request', null, data.deviceId);
  res.status(created.created ? 201 : 200).json({ requestId: created.requestId, expiresAt: created.expiresAt });
}));

// ---------------------------------------------------------------------------
// POST /devices/link/approve — authenticated account session approves or denies.
// ---------------------------------------------------------------------------
devicesRouter.post('/link/approve', deviceAuth, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId as string;
  const data = approvalSchema.parse(req.body);

  if (data.action === 'approve') {
    if (!data.approval || !data.approvalSignature || !data.primEphPub) {
      return res.status(400).json({ error: 'approval payload required', code: 'invalid_input' });
    }
    const approvalBytes = Buffer.from(data.approval, 'base64');
    if (approvalBytes.length === 0 || approvalBytes.length > 8192) {
      return res.status(400).json({ error: 'approval payload out of bounds', code: 'invalid_input' });
    }
  }

  try {
    const outcome = await withTransaction(async (client) => {
      const result = await client.query(
        `SELECT request_id, device_id, code_hash, state, user_id, approval, approval_signature, prim_eph_pub, expires_at
           FROM device_link_requests WHERE request_id = $1 FOR UPDATE`,
        [data.requestId],
      );
      const row = result.rows[0];
      if (!row) throw new HttpError(404, 'not_found');

      if (row.expires_at.getTime() <= Date.now()) {
        // Expired pendings are deleted on read (spec §2.3/§6 #3); commit the delete.
        await client.query('DELETE FROM device_link_requests WHERE request_id = $1', [row.request_id]);
        return { expired: true as const };
      }
      if (sha256Hex(data.code) !== row.code_hash) {
        throw new HttpError(403, 'code_mismatch');
      }

      if (data.action === 'approve') {
        const approvalBytes = Buffer.from(data.approval!, 'base64');
        if (row.state === 'approved') {
          const identical = row.user_id === userId
            && row.approval && Buffer.compare(row.approval, approvalBytes) === 0
            && row.approval_signature === data.approvalSignature
            && row.prim_eph_pub === data.primEphPub;
          if (identical) return { state: 'approved' as const, idempotent: true };
          if (row.user_id && row.user_id !== userId) {
            throw new HttpError(409, 'request_already_claimed');
          }
          throw new HttpError(409, 'invalid_state');
        }
        if (row.state !== 'pending') throw new HttpError(409, 'invalid_state');
        await client.query(
          `UPDATE device_link_requests
              SET state='approved', user_id=$2, approval=$3, approval_signature=$4, prim_eph_pub=$5
            WHERE request_id=$1 AND state='pending'`,
          [row.request_id, userId, approvalBytes, data.approvalSignature, data.primEphPub],
        );
        await audit(client, 'approve', userId, row.device_id);
        return { state: 'approved' as const, idempotent: false };
      }

      // action === 'deny'
      if (row.state === 'denied') return { state: 'denied' as const, idempotent: true };
      if (row.state !== 'pending') throw new HttpError(409, 'invalid_state');
      await client.query(
        `UPDATE device_link_requests
            SET state='denied', denied_at=NOW(), user_id=$2
          WHERE request_id=$1 AND state='pending'`,
        [row.request_id, userId],
      );
      await audit(client, 'deny', userId, row.device_id);
      return { state: 'denied' as const, idempotent: false };
    });

    if ('expired' in outcome) {
      return res.status(410).json({ error: 'Link request expired', code: 'link_expired' });
    }
    if (outcome.state === 'approved') {
      res.status(200).json({ state: 'approved', idempotent: outcome.idempotent });
      return;
    }
    res.status(200).json({ state: 'denied', idempotent: outcome.idempotent });
  } catch (error) {
    if (error instanceof HttpError) {
      if (error.status === 404 && error.code === 'not_found') {
        return res.status(404).json({ error: 'Not found', code: 'not_found' });
      }
      if (error.status === 410) return res.status(410).json({ error: 'Link request expired', code: 'link_expired' });
      if (error.status === 403) return res.status(403).json({ error: 'Code mismatch', code: 'code_mismatch' });
      return res.status(error.status).json({ error: error.code, code: error.code });
    }
    throw error;
  }
}));

// ---------------------------------------------------------------------------
// GET /devices/link/status/:requestId — unauthenticated poll for the new device.
// 30/hour/IP. Expired rows are deleted on read (spec §2.3, §4.4#3).
// ---------------------------------------------------------------------------
devicesRouter.get('/link/status/:requestId', safe(async (req: Request, res: Response) => {
  if (!await rateLimitOrReject(res, `device-link-status:${callerIp(req)}`, 30, 3600)) return;
  const { requestId } = req.params;
  if (!uuidParam(requestId)) return res.status(400).json({ error: 'Invalid request id', code: 'invalid_input' });

  const result = await query<{
    state: string; approval: Buffer | null; approval_signature: string | null;
    prim_eph_pub: string | null; expires_at: Date;
  }>(
    `SELECT state, approval, approval_signature, prim_eph_pub, expires_at
       FROM device_link_requests WHERE request_id = $1`,
    [requestId],
  );
  const row = result.rows[0];
  if (!row) return res.status(404).json({ error: 'Not found', code: 'not_found' });

  if (row.expires_at.getTime() <= Date.now()) {
    await query('DELETE FROM device_link_requests WHERE request_id = $1', [requestId]);
    return res.status(410).json({ error: 'Link request expired', code: 'link_expired' });
  }
  if (row.state === 'approved') {
    return res.status(200).json({
      state: 'approved',
      approval: row.approval ? row.approval.toString('base64') : null,
      approvalSignature: row.approval_signature,
      primEphPub: row.prim_eph_pub,
      expiresAt: row.expires_at,
    });
  }
  res.status(200).json({ state: row.state, expiresAt: row.expires_at });
}));

// ---------------------------------------------------------------------------
// POST /devices/link/consume — one-shot claim by the new device. 10/hour/IP.
// Exactly one concurrent consume wins via the conditional UPDATE (spec §4.4#4).
// ---------------------------------------------------------------------------
devicesRouter.post('/link/consume', safe(async (req: Request, res: Response) => {
  if (!await rateLimitOrReject(res, `device-link-consume:${callerIp(req)}`, 10, 3600)) return;
  const data = consumeSchema.parse(req.body);

  try {
    const outcome = await withTransaction(async (client) => {
      const result = await client.query(
        `SELECT request_id, device_id, device_name, platform, device_public_key,
                code_hash, state, user_id, expires_at
           FROM device_link_requests WHERE request_id = $1 FOR UPDATE`,
        [data.requestId],
      );
      const row = result.rows[0];
      if (!row) throw new HttpError(404, 'not_found');

      if (row.expires_at.getTime() <= Date.now()) {
        // Expired pendings are deleted on read (spec §2.3/§6 #3); commit the delete.
        await client.query('DELETE FROM device_link_requests WHERE request_id = $1', [row.request_id]);
        return { expired: true as const };
      }
      if (sha256Hex(data.code) !== row.code_hash) {
        throw new HttpError(403, 'code_mismatch');
      }
      if (row.state !== 'approved' || !row.user_id) {
        throw new HttpError(409, 'invalid_state');
      }

      // Serialize the one-time redemption: exactly one winner, losers get 409.
      const claimed = await client.query(
        `UPDATE device_link_requests
            SET state='consumed', ephemeral_public_key=NULL
          WHERE request_id=$1 AND state='approved' AND expires_at > NOW()
          RETURNING device_id, device_name, platform, device_public_key, user_id`,
        [row.request_id],
      );
      if (claimed.rowCount !== 1) throw new HttpError(409, 'invalid_state');
      const link = claimed.rows[0];

      // Register the per-device identity row, mirroring the existing register
      // path. A deviceId already bound to a different account (or already
      // revoked) cannot be claimed: 409.
      const device = await client.query(
        `INSERT INTO devices (user_id, id, device_name, platform, public_key, is_linked, created_at)
         VALUES ($1, $2, $3, $4, $5, true, NOW())
         ON CONFLICT (id) DO UPDATE
           SET device_name = EXCLUDED.device_name, platform = EXCLUDED.platform,
               is_linked = true, last_active_at = NOW()
           WHERE devices.user_id = EXCLUDED.user_id AND devices.revoked_at IS NULL
         RETURNING id`,
        [link.user_id, link.device_id, link.device_name, link.platform, link.device_public_key],
      );
      if (device.rowCount !== 1) throw new HttpError(409, 'device_conflict');

      const token = randomBytes(32).toString('hex');
      await client.query(
        `INSERT INTO auth_sessions(token_hash, user_id, device_id, expires_at)
         VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')`,
        [tokenHash(token), link.user_id, link.device_id],
      );
      await audit(client, 'consume', link.user_id, link.device_id);
      return { userId: link.user_id as string, deviceId: link.device_id as string, token };
    });

    if ('expired' in outcome) {
      return res.status(410).json({ error: 'Link request expired', code: 'link_expired' });
    }
    res.status(200).json(outcome);
  } catch (error) {
    if (error instanceof HttpError) {
      if (error.status === 404) return res.status(404).json({ error: 'Not found', code: 'not_found' });
      if (error.status === 410) return res.status(410).json({ error: 'Link request expired', code: 'link_expired' });
      if (error.status === 403) return res.status(403).json({ error: 'Code mismatch', code: 'code_mismatch' });
      return res.status(error.status).json({ error: error.code, code: error.code });
    }
    throw error;
  }
}));

// ---------------------------------------------------------------------------
// GET /devices — list the account's devices, revoked rows included (flagged).
// ---------------------------------------------------------------------------
devicesRouter.get('/', deviceAuth, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId as string;
  const callerDeviceId = (req as any).deviceId as string | null;
  const result = await query<{
    id: string; device_name: string | null; platform: string | null;
    created_at: Date; last_active_at: Date | null; revoked_at: Date | null;
  }>(
    `SELECT id, device_name, platform, created_at, last_active_at, revoked_at
       FROM devices WHERE user_id = $1 ORDER BY created_at`,
    [userId],
  );
  res.status(200).json(result.rows.map((row) => ({
    deviceId: row.id,
    name: row.device_name,
    platform: row.platform,
    createdAt: row.created_at,
    lastActiveAt: row.last_active_at,
    isCurrent: callerDeviceId !== null && row.id === callerDeviceId,
    revokedAt: row.revoked_at,
  })));
}));

// ---------------------------------------------------------------------------
// DELETE /devices/:deviceId — soft revoke; sessions invalidated in one
// transaction; idempotent (already revoked -> 200 {revoked:true}).
// ---------------------------------------------------------------------------
devicesRouter.delete('/:deviceId', deviceAuth, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId as string;
  const callerDeviceId = (req as any).deviceId as string | null;
  const { deviceId } = req.params;
  if (!uuidParam(deviceId)) return res.status(400).json({ error: 'Invalid device id', code: 'invalid_input' });

  if (callerDeviceId && callerDeviceId === deviceId) {
    return res.status(400).json({ error: 'Cannot revoke the device you are calling from; use logout', code: 'use_logout' });
  }

  const result = await query<{ id: string; user_id: string; revoked_at: Date | null }>(
    'SELECT id, user_id, revoked_at FROM devices WHERE id = $1',
    [deviceId],
  );
  const row = result.rows[0];
  // 404 parity: foreign or nonexistent devices are indistinguishable.
  if (!row || row.user_id !== userId) {
    return res.status(404).json({ error: 'Not found', code: 'not_found' });
  }
  if (row.revoked_at) return res.status(200).json({ revoked: true });

  await withTransaction(async (client) => {
    const updated = await client.query(
      `UPDATE devices SET revoked_at = NOW(), fcm_token = NULL
        WHERE id = $1 AND revoked_at IS NULL`,
      [deviceId],
    );
    if (updated.rowCount === 1) {
      await client.query('DELETE FROM auth_sessions WHERE device_id = $1', [deviceId]);
      await audit(client, 'revoke', userId, deviceId);
    }
  });
  res.status(200).json({ revoked: true });
}));

/**
 * Maintenance sweep (spec §4.5): delete link requests more than a day past
 * expiry and stale audit events. Retention for device_link_events is not
 * settled by the spec (OQ-5); 90 days is a conservative bound, adjustable.
 * Fail-safe: errors are logged and skipped, never fatal.
 */
export const sweepDeviceLinkRequests = async (): Promise<void> => {
  await query(`DELETE FROM device_link_requests WHERE expires_at < NOW() - INTERVAL '1 day'`);
  await query(`DELETE FROM device_link_events WHERE at < NOW() - INTERVAL '90 days'`);
};
export const sweepDeviceLinkRequestsSafely = async (): Promise<void> => {
  try {
    await sweepDeviceLinkRequests();
  } catch (error) {
    logger.warn('Device link sweep skipped this tick', { error: (error as Error).message });
  }
};
