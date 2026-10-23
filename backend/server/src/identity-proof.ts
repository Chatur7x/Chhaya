import { createPublicKey, diffieHellman, generateKeyPairSync, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'crypto';
import { query } from './db';
import { tokenHash } from './session';

export type AuthPurpose = 'register' | 'login';
export function createIdentityChallenge(publicKey: string, deviceId: string, purpose: AuthPurpose) {
  const pair = generateKeyPairSync('x25519');
  const peer = createPublicKey({ key: { kty:'OKP', crv:'X25519', x:Buffer.from(publicKey,'hex').toString('base64url') }, format:'jwk' });
  const shared = diffieHellman({ privateKey:pair.privateKey, publicKey:peer });
  try {
    if (shared.every(byte => byte === 0)) throw new Error('Invalid identity');
    const challengeId = randomUUID();
    const serverPublicKey = Buffer.from(pair.publicKey.export({format:'jwk'}).x!, 'base64url').toString('hex');
    const nonce = randomBytes(32).toString('hex');
    const context = `chhaya-auth-v1|${purpose}|${challengeId}|${deviceId}|${publicKey}|${serverPublicKey}|${nonce}`;
    const expected = createHmac('sha256',shared).update(context).digest('hex');
    return { challengeId, serverPublicKey, nonce, context, proofHash:tokenHash(expected) };
  } finally { shared.fill(0); }
}
export async function issueIdentityChallenge(publicKey:string,deviceId:string,purpose:AuthPurpose) {
  const challenge = createIdentityChallenge(publicKey,deviceId,purpose);
  await query('DELETE FROM identity_challenges WHERE expires_at<=NOW()');
  await query(`INSERT INTO identity_challenges(id,public_key,device_id,purpose,proof_hash,expires_at)
    VALUES ($1,$2,$3,$4,$5,NOW()+INTERVAL '2 minutes')`,
    [challenge.challengeId,publicKey,deviceId,purpose,challenge.proofHash]);
  const {proofHash, ...publicChallenge} = challenge;
  return publicChallenge;
}
export async function consumeIdentityChallenge(id:string,publicKey:string,deviceId:string,purpose:AuthPurpose,proof:string) {
  const result = await query(`DELETE FROM identity_challenges WHERE id=$1 AND public_key=$2 AND device_id=$3
    AND purpose=$4 AND expires_at>NOW() RETURNING proof_hash`,[id,publicKey,deviceId,purpose]);
  if(result.rowCount!==1) return false;
  return timingSafeEqual(Buffer.from(result.rows[0].proof_hash,'hex'),Buffer.from(tokenHash(proof),'hex'));
}
