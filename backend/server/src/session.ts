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
