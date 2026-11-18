import { query } from './db';

export interface PendingCallInvite {
  callId: string;
  conversationId: string;
  senderId: string;
  envelope: string;
  createdAt: string;
}

/** Keep only the authenticated, end-to-end encrypted offer for a short ring window. */
export async function storeCallInvite(input: {
  callId: string;
  conversationId: string;
  senderId: string;
  recipientId: string;
  envelope: string;
}): Promise<void> {
  await query(
    `INSERT INTO call_invites
       (call_id, conversation_id, sender_id, recipient_id, envelope, expires_at)
     VALUES ($1, $2, $3, $4, $5, NOW() + INTERVAL '60 seconds')
     ON CONFLICT (call_id, recipient_id) DO NOTHING`,
    [input.callId, input.conversationId, input.senderId, input.recipientId, input.envelope],
  );
}

export async function getPendingCallInvites(recipientId: string): Promise<PendingCallInvite[]> {
  const result = await query<{
    call_id: string;
    conversation_id: string;
    sender_id: string;
    envelope: string;
    created_at: Date;
  }>(
    `SELECT call_id, conversation_id, sender_id, envelope, created_at
     FROM call_invites
     WHERE recipient_id = $1 AND expires_at > NOW()
     ORDER BY created_at ASC`,
    [recipientId],
  );
  return result.rows.map((row) => ({
    callId: row.call_id,
    conversationId: row.conversation_id,
    senderId: row.sender_id,
    envelope: row.envelope,
    createdAt: row.created_at.toISOString(),
  }));
}

export async function acknowledgeCallInvite(callId: string, recipientId: string): Promise<void> {
  await query(
    'DELETE FROM call_invites WHERE call_id = $1 AND recipient_id = $2',
    [callId, recipientId],
  );
}

export async function clearCallInvites(callId: string): Promise<void> {
  await query('DELETE FROM call_invites WHERE call_id = $1', [callId]);
}

export async function purgeExpiredCallInvites(): Promise<void> {
  await query('DELETE FROM call_invites WHERE expires_at <= NOW()');
}
