import { createHmac } from 'crypto';
import { config } from './config';
import { query } from './db';

export interface RateLimitDecision {
  allowed: boolean;
  retryAfterSeconds: number;
}

/**
 * Consume one request from a shared PostgreSQL fixed-window bucket.
 * Only a keyed HMAC of the caller identity is persisted, preventing offline
 * enumeration of the relatively small IPv4 address space from database dumps.
 */
export async function consumeIpRateLimit(
  identity: string,
  limit: number,
  durationSeconds: number,
  runQuery: typeof query = query,
): Promise<RateLimitDecision> {
  if (!identity || !Number.isInteger(limit) || limit < 1 ||
      !Number.isInteger(durationSeconds) || durationSeconds < 1) {
    throw new RangeError('Rate limit identity, limit, and window must be valid');
  }

  const key = `api:${createHmac('sha256', config.JWT_SECRET).update(identity).digest('hex')}`;
  const result = await runQuery<{ count: number | string; retry_after: number | string }>(
    `INSERT INTO rate_limits (key, count, window_start)
     VALUES ($1, 1, NOW())
     ON CONFLICT (key) DO UPDATE SET
       count = CASE
         WHEN rate_limits.window_start <= NOW() - ($2::int * INTERVAL '1 second') THEN 1
         ELSE rate_limits.count + 1
       END,
       window_start = CASE
         WHEN rate_limits.window_start <= NOW() - ($2::int * INTERVAL '1 second') THEN NOW()
         ELSE rate_limits.window_start
       END
     RETURNING count,
       GREATEST(1, CEIL(EXTRACT(EPOCH FROM
         (window_start + ($2::int * INTERVAL '1 second') - NOW()))))::int AS retry_after`,
    [key, durationSeconds],
  );
  const row = result.rows[0];
  const count = Number(row.count);
  return {
    allowed: count <= limit,
    retryAfterSeconds: Number(row.retry_after),
  };
}

/** Remove inactive buckets so changing or rotating client IPs cannot grow the table forever. */
export async function pruneExpiredRateLimits(): Promise<void> {
  await query("DELETE FROM rate_limits WHERE window_start < NOW() - INTERVAL '2 minutes'");
}
