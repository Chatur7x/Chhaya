import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'crypto';
import { query } from './db';

export const tokenHash = (token: string): string => createHash('sha256').update(token).digest('hex');
export function hashCredential(proof: string): string {
  const salt = randomBytes(16).toString('hex');
  return `scrypt:${salt}:${scryptSync(proof, salt, 32).toString('hex')}`;
}
export function verifyCredential(proof: string, stored: string): boolean {
  const [algorithm, salt, digest] = stored.split(':');
  if (algorithm !== 'scrypt' || !salt || !digest || !/^[0-9a-f]{64}$/.test(digest)) return false;
  return timingSafeEqual(scryptSync(proof, salt, 32), Buffer.from(digest, 'hex'));
}
export async function issueSession(userId: string): Promise<string> {
  const token = randomBytes(32).toString('hex');
  await query(`INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES ($1,$2,NOW()+INTERVAL '30 days')`, [tokenHash(token),userId]);
  return token;
}
export async function authenticateToken(token: unknown): Promise<string | null> {
  if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return null;
  const result = await query(`SELECT u.id FROM auth_sessions s JOIN users u ON u.id=s.user_id
    WHERE s.token_hash=$1 AND s.expires_at>NOW() AND u.is_active=true`, [tokenHash(token)]);
  return result.rows[0]?.id ?? null;
}
