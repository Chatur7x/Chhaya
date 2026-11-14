import { createHash, randomBytes, scrypt, timingSafeEqual } from 'crypto';
import { promisify } from 'util';
import { query } from './db';

export const tokenHash = (token: string): string => createHash('sha256').update(token).digest('hex');
const deriveCredential = promisify(scrypt);
export async function hashCredential(proof: string): Promise<string> {
  const salt = randomBytes(16).toString('hex');
  const derived = await deriveCredential(proof, salt, 32) as Buffer;
  return `scrypt:${salt}:${derived.toString('hex')}`;
}
export async function verifyCredential(proof: string, stored: string): Promise<boolean> {
  const [algorithm, salt, digest] = stored.split(':');
  if (algorithm !== 'scrypt' || !salt || !digest || !/^[0-9a-f]{64}$/.test(digest)) return false;
  const derived = await deriveCredential(proof, salt, 32) as Buffer;
  return timingSafeEqual(derived, Buffer.from(digest, 'hex'));
}
export async function issueSession(userId: string, deviceId?: string | null): Promise<string> {
  const token = randomBytes(32).toString('hex');
  await query(`INSERT INTO auth_sessions(token_hash,user_id,device_id,expires_at) VALUES ($1,$2,$3,NOW()+INTERVAL '30 days')`, [tokenHash(token),userId,deviceId ?? null]);
  return token;
}
export interface SessionAuth {
  userId: string;
  deviceId: string | null;
}
/**
 * Resolve a bearer token to the account and (optionally) the per-device binding.
 * A session bound to a device whose row is soft-revoked resolves to null (spec
 * §2.5/§4.3): revocation kills the device session on the caller's next request.
 * Sessions without a device binding (issued before device linking shipped) are
 * unaffected by device revocation.
 */
export async function authenticateSession(token: unknown): Promise<SessionAuth | null> {
  if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return null;
  const result = await query(`SELECT u.id AS user_id, s.device_id FROM auth_sessions s JOIN users u ON u.id=s.user_id
    LEFT JOIN devices d ON d.id = s.device_id
    WHERE s.token_hash=$1 AND s.expires_at>NOW() AND u.is_active=true
      AND (s.device_id IS NULL OR d.revoked_at IS NULL)`, [tokenHash(token)]);
  const row = result.rows[0];
  if (!row) return null;
  return { userId: row.user_id, deviceId: row.device_id ?? null };
}
export async function authenticateToken(token: unknown): Promise<string | null> {
  return (await authenticateSession(token))?.userId ?? null;
}
