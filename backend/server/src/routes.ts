import { Request, Response, Router, NextFunction, Express } from 'express';
import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';
import { getDb, query, withTransaction } from './db';
import { logger } from './log';
import { sendNewMessageNotification, sendCallNotification, registerFCMToken, subscribeToPush } from './push';
import { broadcastToUser } from './signaling';
import { issueIdentityChallenge, consumeIdentityChallenge } from './identity-proof';
import { authenticateToken, issueSession, hashCredential, verifyCredential } from './session';
import { getPendingCallInvites } from './call-invites';

const router = Router();
const safe = (handler: (req: Request,res: Response,next: NextFunction)=>Promise<unknown>) =>
  (req: Request,res: Response,next: NextFunction) => { void Promise.resolve(handler(req,res,next)).catch(next); };

// Validation schemas
const registerSchema = z.object({
  challengeId: z.string().uuid(),
  identityProof: z.string().regex(/^[0-9a-f]{64}$/),
  chhayaId: z.string().regex(/^05[0-9a-f]{64}$/),
  displayName: z.string().min(1).max(100),
  publicKey: z.string().regex(/^[0-9a-f]{64}$/),
  encryptedPrivateKey: z.string().min(1),
  recoveryPhraseHash: z.string().length(64),
  deviceId: z.string().uuid(),
  deviceName: z.string().optional(),
  platform: z.string().optional(),
  fcmToken: z.string().optional(),
});

const loginSchema = z.object({
  challengeId: z.string().uuid(),
  identityProof: z.string().regex(/^[0-9a-f]{64}$/),
  chhayaId: z.string().regex(/^05[0-9a-f]{64}$/),
  recoveryPhraseHash: z.string().length(64),
  deviceId: z.string().uuid(),
  deviceName: z.string().optional(),
  platform: z.string().optional(),
  fcmToken: z.string().optional(),
});

const addContactSchema = z.object({
  chhayaId: z.string().regex(/^05[0-9a-f]{64}$/),
  displayName: z.string().min(1).max(100),
});

const createConversationSchema = z.object({
  type: z.enum(['direct', 'group']),
  participantIds: z.array(z.string().uuid()).min(1).max(32),
  name: z.string().optional(),
  avatarUrl: z.string().url().optional(),
});

const sendMessageSchema = z.object({
  messageId: z.string().uuid().optional(),
  conversationId: z.string().uuid(),
  // Bounded inline encrypted attachments; JSON parser still caps the request at 1 MB.
  content: z.string().min(1).max(768 * 1024),
  messageType: z.enum(['text', 'image', 'file', 'voice', 'location']).default('text'),
  mediaUrl: z.string().url().optional(),
  mediaMeta: z.record(z.string(), z.unknown()).optional(),
  replyToId: z.string().uuid().optional(),
});

const updateSettingsSchema = z.object({
  biometricEnabled: z.boolean().optional(),
  pin: z.string().length(4).optional(),
  panicPin: z.string().length(4).optional(),
  readReceipts: z.boolean().optional(),
  disappearingDuration: z.number().min(0).max(604800).optional(),
  onionRouting: z.boolean().optional(),
  notifications: z.boolean().optional(),
});

const groupAdminSchema = z.object({ isAdmin: z.boolean() });

// Auth middleware
const authMiddleware = async (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization header' });
  }
  const token = authHeader.substring(7);

  try {
    const userId = res.locals.authenticatedUserId ?? await authenticateToken(token);
    if (!userId) return res.status(401).json({ error: 'Invalid or expired token' });
    (req as any).userId = userId;
    next();
  } catch (error) { next(error); }
};

router.post('/auth/challenge',safe(async(req:Request,res:Response)=>{
  const data=z.object({publicKey:z.string().regex(/^[0-9a-f]{64}$/),deviceId:z.string().uuid(),purpose:z.enum(['register','login'])}).parse(req.body);
  try { res.json(await issueIdentityChallenge(data.publicKey,data.deviceId,data.purpose)); }
  catch (_) { res.status(400).json({error:'Invalid identity challenge request'}); }
}));

// POST /api/v1/auth/register
router.post('/auth/register', safe(async (req: Request, res: Response) => {
  try {
    const data = registerSchema.parse(req.body);
    if(!await consumeIdentityChallenge(data.challengeId,data.publicKey,data.deviceId,'register',data.identityProof)) {
      return res.status(401).json({error:'Identity proof invalid or expired'});
    }

    // Check if user exists
    const existing = await query('SELECT id FROM users WHERE chhaya_id = $1', [data.chhayaId]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'User already exists' });
    }

    if (data.chhayaId !== `05${data.publicKey}`) return res.status(400).json({error:'Identity does not match key'});
    const userId = uuidv4();
    const now = new Date();

    await withTransaction(async (client) => {
      await client.query(
        `INSERT INTO users (id, chhaya_id, display_name, public_key, encrypted_private_key,
          recovery_phrase_hash, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, data.chhayaId, data.displayName, data.publicKey, data.encryptedPrivateKey,
         hashCredential(data.recoveryPhraseHash), now]
      );

      // Register device
      await client.query(
        `INSERT INTO devices (user_id, id, device_name, platform, fcm_token, public_key)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, data.deviceId, data.deviceName || 'Primary', data.platform || 'unknown',
         data.fcmToken || null, data.publicKey]
      );
    });

    // Register FCM token if provided
    if (data.fcmToken) {
      await registerFCMToken(userId, data.deviceId, data.fcmToken);
    }

    logger.info('Account registered');
    res.status(201).json({ userId, token: await issueSession(userId) });
  } catch (e) {
    if (e instanceof z.ZodError) {
      return res.status(400).json({ error: 'Invalid input', details: e.issues });
    }
    logger.error('Registration failed');
    res.status(500).json({ error: 'Registration failed' });
  }
}));

// POST /api/v1/auth/login
router.post('/auth/login', safe(async (req: Request, res: Response) => {
  try {
    const data = loginSchema.parse(req.body);
    if(!await consumeIdentityChallenge(data.challengeId,data.chhayaId.slice(2),data.deviceId,'login',data.identityProof)) {
      return res.status(401).json({error:'Identity proof invalid or expired'});
    }

    const userResult = await query(
      'SELECT id, public_key, recovery_phrase_hash FROM users WHERE chhaya_id = $1 AND is_active = true',
      [data.chhayaId]
    );

    if (userResult.rows.length === 0 || !verifyCredential(data.recoveryPhraseHash, userResult.rows[0].recovery_phrase_hash)) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const userId = userResult.rows[0].id;

    // Update device
    const device = await query(
      `INSERT INTO devices (user_id, id, device_name, platform, fcm_token, public_key)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (id) DO UPDATE SET
         device_name = $3, platform = $4, fcm_token = $5, last_active_at = NOW()
       WHERE devices.user_id=EXCLUDED.user_id RETURNING id`,
      [userId, data.deviceId, data.deviceName || 'Device', data.platform || 'unknown', data.fcmToken || null, userResult.rows[0].public_key]
    );

    if(device.rowCount!==1) return res.status(409).json({error:'Device belongs to another account'});

    if (data.fcmToken) {
      await registerFCMToken(userId, data.deviceId, data.fcmToken);
    }

    // Update last seen
    await query('UPDATE users SET last_seen_at = NOW() WHERE id = $1', [userId]);

    logger.info('Session created');
    res.json({ userId, token: await issueSession(userId) });
  } catch (e) {
    if (e instanceof z.ZodError) {
      return res.status(400).json({ error: 'Invalid input', details: e.issues });
    }
    logger.error('Login failed');
    res.status(500).json({ error: 'Login failed' });
  }
}));

router.post('/auth/logout', authMiddleware, safe(async(req: Request,res: Response)=>{
  const {tokenHash} = await import('./session');
  await query('DELETE FROM auth_sessions WHERE token_hash=$1',[tokenHash(req.headers.authorization!.substring(7))]);
  res.json({success:true});
}));

// GET /api/v1/users/me
router.get('/users/me', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const result = await query(
    `SELECT id, chhaya_id, display_name, public_key, biometric_enabled,
     created_at, last_seen_at FROM users WHERE id = $1`,
    [userId]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
  res.json(result.rows[0]);
}));

// PUT /api/v1/users/me/settings
router.put('/users/me/settings', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const data = updateSettingsSchema.parse(req.body);

  const updates: string[] = [];
  const values: any[] = [userId];
  let paramIndex = 2;

  if (data.biometricEnabled !== undefined) {
    updates.push(`biometric_enabled = $${paramIndex++}`);
    values.push(data.biometricEnabled);
  }
  if (data.pin) {
    updates.push(`pin_hash = $${paramIndex++}`);
    values.push(hashCredential(data.pin));
  }
  if (data.panicPin) {
    updates.push(`panic_pin_hash = $${paramIndex++}`);
    values.push(hashCredential(data.panicPin));
  }

  if (updates.length > 0) {
    updates.push('updated_at = NOW()');
    await query(`UPDATE users SET ${updates.join(', ')} WHERE id = $1`, values);
  }

  res.json({ success: true });
}));

// POST /api/v1/contacts
router.post('/contacts', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const data = addContactSchema.parse(req.body);

  // Find target user
  const targetResult = await query('SELECT id, public_key FROM users WHERE chhaya_id = $1', [data.chhayaId]);
  if (targetResult.rows.length === 0) {
    return res.status(404).json({ error: 'User not found' });
  }

  const contactId = targetResult.rows[0].id;
  if (contactId === userId) {
    return res.status(400).json({ error: 'Cannot add yourself' });
  }

  // Check if already contacts
  const existing = await query(
    'SELECT id FROM contacts WHERE user_id = $1 AND contact_id = $2',
    [userId, contactId]
  );
  if (existing.rows.length > 0) {
    return res.status(409).json({ error: 'Already contacts' });
  }

  // Create conversation
  const convoId = uuidv4();
  await withTransaction(async (client) => {
  await client.query(
    `INSERT INTO contacts (user_id, contact_id, display_name, verification_level)
     VALUES ($1, $2, $3, 1)`,
    [userId, contactId, data.displayName]
  );


    await client.query(
      `INSERT INTO conversations (id, type, created_by) VALUES ($1, 'direct', $2)`,
      [convoId, userId]
    );
    await client.query(
      `INSERT INTO conversation_participants (conversation_id, user_id, is_admin)
       VALUES ($1, $2, true), ($1, $3, false)`,
      [convoId, userId, contactId]
    );
  });

  res.status(201).json({ contactId, conversationId: convoId, publicKey: targetResult.rows[0].public_key });
}));

// GET /api/v1/contacts
router.get('/contacts', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const result = await query(
    `SELECT c.contact_id AS id, c.display_name, c.verification_level, c.is_blocked, c.created_at,
     u.chhaya_id, u.public_key, u.last_seen_at
     FROM contacts c
     JOIN users u ON u.id = c.contact_id
     WHERE c.user_id = $1 AND c.is_blocked = false
     ORDER BY c.display_name`,
    [userId]
  );
  res.json(result.rows);
}));

// POST /api/v1/conversations
router.post('/conversations', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const data = createConversationSchema.parse(req.body);

  if (data.type === 'direct' && data.participantIds.length !== 1) {
    return res.status(400).json({ error: 'Direct conversation requires exactly 1 participant' });
  }
  if (data.type === 'group' && data.participantIds.length < 2) {
    return res.status(400).json({ error: 'Group conversation requires at least 2 other participants' });
  }

  const convoId = uuidv4();
  const allParticipants = [...new Set([userId,...data.participantIds])];
  if(allParticipants.length!==data.participantIds.length+1) return res.status(400).json({error:'Duplicate or self participant'});

  // A group can only be created from the initiator's active, unblocked address book.
  const allowedContacts=await query(
    `SELECT contact_id FROM contacts WHERE user_id=$1 AND is_blocked=false AND contact_id=ANY($2::uuid[])`,
    [userId,data.participantIds]
  );
  if(allowedContacts.rows.length!==data.participantIds.length) {
    return res.status(403).json({error:'Every participant must be an active contact'});
  }

  await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO conversations (id, type, name, avatar_url, created_by)
       VALUES ($1, $2, $3, $4, $5)`,
      [convoId, data.type, data.name || null, data.avatarUrl || null, userId]
    );

    for (const pid of allParticipants) {
      await client.query(
        `INSERT INTO conversation_participants (conversation_id, user_id, is_admin)
         VALUES ($1, $2, $3)`,
        [convoId, pid, pid === userId]
      );
    }
  });

  res.status(201).json({ conversationId: convoId });
}));

// GET /api/v1/conversations
router.get('/conversations', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const result = await query(
    `SELECT c.id, c.type, c.name, c.avatar_url, c.created_at, c.updated_at, cp.is_admin,
     (SELECT json_agg(json_build_object('id', u.id, 'display_name', u.display_name, 'chhaya_id', u.chhaya_id, 'public_key', u.public_key, 'is_admin', cp.is_admin))
      FROM conversation_participants cp
      JOIN users u ON u.id = cp.user_id
      WHERE cp.conversation_id = c.id AND cp.left_at IS NULL) as participants,
     (SELECT json_build_object('id',m.id,'conversation_id',m.conversation_id,'content',m.content,'sender_id',m.sender_id,'sent_at',m.sent_at,'message_type',m.message_type)
      FROM messages m
      WHERE m.conversation_id = c.id AND m.is_deleted = false
      ORDER BY m.sent_at DESC
      LIMIT 1) as last_message,
     (SELECT COUNT(*) FROM messages m
      WHERE m.conversation_id = c.id AND m.sent_at > cp.last_read_at) as unread_count
     FROM conversations c
     JOIN conversation_participants cp ON cp.conversation_id = c.id
     WHERE cp.user_id = $1 AND cp.left_at IS NULL
     ORDER BY c.updated_at DESC`,
    [userId]
  );
  res.json(result.rows);
}));

// Group membership and roles are changed atomically. The conversation row lock
// serializes simultaneous admin actions so the last admin/member cannot race.
router.patch('/conversations/:conversationId/participants/:participantId', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId as string;
  const { isAdmin } = groupAdminSchema.parse(req.body);
  const { conversationId, participantId } = req.params;
  const result = await withTransaction(async (client) => {
    const convo = await client.query('SELECT type FROM conversations WHERE id=$1 FOR UPDATE', [conversationId]);
    if (!convo.rows.length) return { status: 404, error: 'Conversation not found' };
    if (convo.rows[0].type !== 'group') return { status: 400, error: 'Roles are only available in groups' };
    const members = await client.query(
      'SELECT user_id, is_admin FROM conversation_participants WHERE conversation_id=$1 AND left_at IS NULL FOR UPDATE',
      [conversationId],
    );
    if (!members.rows.some((m) => m.user_id === userId && m.is_admin)) return { status: 403, error: 'Group admin role required' };
    const target = members.rows.find((m) => m.user_id === participantId);
    if (!target) return { status: 404, error: 'Active participant not found' };
    if (target.is_admin && !isAdmin && members.rows.filter((m) => m.is_admin).length <= 1) {
      return { status: 409, error: 'Promote another admin before removing the last admin role' };
    }
    await client.query('UPDATE conversation_participants SET is_admin=$3 WHERE conversation_id=$1 AND user_id=$2 AND left_at IS NULL', [conversationId, participantId, isAdmin]);
    await client.query('UPDATE conversations SET updated_at=NOW() WHERE id=$1', [conversationId]);
    return { status: 200 };
  });
  if (result.error) return res.status(result.status).json({ error: result.error });
  res.json({ ok: true });
}));

router.delete('/conversations/:conversationId/participants/:participantId', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId as string;
  const { conversationId, participantId } = req.params;
  const result = await withTransaction(async (client) => {
    const convo = await client.query('SELECT type FROM conversations WHERE id=$1 FOR UPDATE', [conversationId]);
    if (!convo.rows.length) return { status: 404, error: 'Conversation not found' };
    if (convo.rows[0].type !== 'group') return { status: 400, error: 'Membership actions are only available in groups' };
    const members = await client.query(
      'SELECT user_id, is_admin FROM conversation_participants WHERE conversation_id=$1 AND left_at IS NULL FOR UPDATE',
      [conversationId],
    );
    const actor = members.rows.find((m) => m.user_id === userId);
    if (!actor) return { status: 403, error: 'Active group membership required' };
    if (participantId !== userId && !actor.is_admin) return { status: 403, error: 'Group admin role required to remove participants' };
    const target = members.rows.find((m) => m.user_id === participantId);
    if (!target) return { status: 404, error: 'Active participant not found' };
    if (members.rows.length <= 2) return { status: 409, error: 'A group must keep at least two active members' };
    if (target.is_admin && members.rows.filter((m) => m.is_admin).length <= 1) {
      return { status: 409, error: 'Promote another admin before leaving or removing the last admin' };
    }
    await client.query('UPDATE conversation_participants SET left_at=NOW() WHERE conversation_id=$1 AND user_id=$2 AND left_at IS NULL', [conversationId, participantId]);
    await client.query('UPDATE conversations SET updated_at=NOW() WHERE id=$1', [conversationId]);
    return { status: 200 };
  });
  if (result.error) return res.status(result.status).json({ error: result.error });
  res.json({ ok: true });
}));

// POST /api/v1/messages
router.post('/messages', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const data = sendMessageSchema.parse(req.body);

  const messageId = data.messageId ?? uuidv4();
  // Serialize message acceptance with group membership changes. Otherwise a
  // sender with stale membership could submit a key wrapper for a removed user.
  const result = await withTransaction(async (client) => {
    const conversation = await client.query('SELECT type FROM conversations WHERE id=$1 FOR UPDATE', [data.conversationId]);
    const members = await client.query(
      'SELECT user_id FROM conversation_participants WHERE conversation_id=$1 AND left_at IS NULL', [data.conversationId],
    );
    if (!conversation.rows.length || !members.rows.some((m) => m.user_id === userId)) {
      return { status: 403, error: 'Not a participant' };
    }
    // An exact retry of an already accepted message stays idempotent after a
    // later membership change; it does not introduce a new envelope.
    const previous = await client.query('SELECT * FROM messages WHERE id=$1', [messageId]);
    if (previous.rows.length) {
      const message = previous.rows[0];
      if (message.sender_id !== userId || message.conversation_id !== data.conversationId || message.content !== data.content) {
        return { status: 409, error: 'Message identifier conflict' };
      }
      return { status: 200, message };
    }
    if (conversation.rows[0].type === 'group') {
      let envelope: any;
      try { envelope = JSON.parse(data.content); } catch (_) { return { status: 400, error: 'Invalid group envelope' }; }
      if (!envelope || envelope.v !== 1 || envelope.kind !== 'chhaya-group-v1' ||
          envelope.conversationId !== data.conversationId || envelope.messageId !== messageId || envelope.senderId !== userId ||
          typeof envelope.body !== 'string' || !envelope.keys || typeof envelope.keys !== 'object' || Array.isArray(envelope.keys)) {
        return { status: 400, error: 'Invalid group envelope' };
      }
      const expected = members.rows.map((m) => m.user_id as string).filter((id) => id !== userId).sort();
      const recipients = Object.keys(envelope.keys).sort();
      if (recipients.length !== expected.length || recipients.some((id, i) => id !== expected[i] || typeof envelope.keys[id] !== 'string' || !envelope.keys[id])) {
        return { status: 409, error: 'Group membership changed; refresh before sending' };
      }
    }
    const inserted = await client.query(
      `INSERT INTO messages (id, conversation_id, sender_id, content, message_type, media_url, media_meta, reply_to_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (id) DO NOTHING RETURNING *`,
      [messageId, data.conversationId, userId, data.content, data.messageType, data.mediaUrl || null, data.mediaMeta || null, data.replyToId || null],
    );
    if (!inserted.rows.length) return { status: 409, error: 'Message identifier conflict' };
    await client.query('UPDATE conversations SET updated_at = NOW() WHERE id = $1', [data.conversationId]);
    return { status: 201, message: inserted.rows[0] };
  });
  if (result.error) return res.status(result.status).json({ error: result.error });
  if (result.status === 200) return res.status(200).json(result.message);

  // Get other participants for push notifications
  const otherParticipants = await query(
    `SELECT cp.user_id, u.display_name
     FROM conversation_participants cp
     JOIN users u ON u.id = cp.user_id
     WHERE cp.conversation_id = $1 AND cp.user_id != $2 AND cp.left_at IS NULL`,
    [data.conversationId, userId]
  );

  // Send push notifications
  for (const p of otherParticipants.rows) {
    void sendNewMessageNotification(p.user_id, 'Chhaya', 'New encrypted message', data.conversationId, messageId);

    // Also broadcast via signaling if online
    broadcastToUser(p.user_id, {
      type: 'new_message',
      payload: { conversationId: data.conversationId, messageId },
      from: 'server',
      timestamp: Date.now(),
    });
  }

  res.status(201).json(result.message);
}));

// GET /api/v1/messages/:conversationId
router.get('/messages/:conversationId', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { conversationId } = req.params;
  const limit = Math.max(1, Math.min(200, parseInt(req.query.limit as string) || 50));
  const before = z.string().datetime({offset:true}).optional().parse(req.query.before);
  const beforeId = z.string().uuid().optional().parse(req.query.beforeId);

  // Verify participant
  const participantCheck = await query(
    'SELECT 1 FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL',
    [conversationId, userId]
  );
  if (participantCheck.rows.length === 0) {
    return res.status(403).json({ error: 'Not a participant' });
  }

  let queryStr = `
    SELECT m.id, m.conversation_id, m.sender_id, m.content, m.message_type, m.media_url, m.media_meta,
           m.reply_to_id, m.sent_at, m.delivered_at, m.read_at,
           u.display_name as sender_name
    FROM messages m
    JOIN users u ON u.id = m.sender_id
    WHERE m.conversation_id = $1 AND m.is_deleted = false
  `;
  const params: any[] = [conversationId];

  if (beforeId) {
    queryStr += ` AND (m.sent_at,m.id) < (SELECT sent_at,id FROM messages WHERE id=$${params.length + 1} AND conversation_id=$1)`;
    params.push(beforeId);
  } else if (before) {
    queryStr += ` AND m.sent_at < $${params.length + 1}`;
    params.push(before);
  }

  queryStr += ` ORDER BY m.sent_at DESC, m.id DESC LIMIT $${params.length + 1}`;
  params.push(limit);

  const result = await query(queryStr, params);
  const pendingDelivery = result.rows
    .filter((message) => message.sender_id !== userId && !message.delivered_at)
    .map((message) => message.id);
  if (pendingDelivery.length > 0) {
    const acknowledgments = await query(
      `UPDATE messages
       SET delivered_at = NOW()
       WHERE id = ANY($1::uuid[]) AND sender_id <> $2 AND delivered_at IS NULL
       RETURNING id, delivered_at`,
      [pendingDelivery, userId],
    );
    const deliveredAt = new Map(
      acknowledgments.rows.map((row) => [row.id as string, row.delivered_at]),
    );
    for (const message of result.rows) {
      if (message.delivered_at == null && deliveredAt.has(message.id)) {
        message.delivered_at = deliveredAt.get(message.id);
      }
    }
  }
  res.json(result.rows.reverse());
}));

// POST /api/v1/messages/:messageId/read
router.post('/messages/:messageId/read', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { messageId } = req.params;
  const allowed = await query(`SELECT 1 FROM messages m JOIN conversation_participants cp
    ON cp.conversation_id=m.conversation_id WHERE m.id=$1 AND cp.user_id=$2 AND cp.left_at IS NULL`,[messageId,userId]);
  if (allowed.rowCount !== 1) return res.status(403).json({error:'Not a participant'});

  await query(
    `UPDATE conversation_participants
     SET last_read_at = GREATEST(COALESCE(last_read_at,'epoch'),(SELECT sent_at FROM messages WHERE id = $1))
     WHERE user_id = $2 AND conversation_id = (SELECT conversation_id FROM messages WHERE id = $1)`,
    [messageId, userId]
  );

  await query(
    'UPDATE messages SET read_at = NOW(), delivered_at = COALESCE(delivered_at,NOW()) WHERE id = $1 AND read_at IS NULL AND sender_id<>$2',
    [messageId,userId]
  );

  res.json({ success: true });
}));

// Pending encrypted call offers are available only to their intended recipient
// and expire after the short ring window. Answering/rejecting clears the entry.
router.get('/calls/incoming', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  res.json(await getPendingCallInvites(userId));
}));

// POST /api/v1/devices/link
router.post('/devices/link', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const {deviceId,deviceName,platform,publicKey}=z.object({deviceId:z.string().uuid(),deviceName:z.string().max(100).optional(),platform:z.string().max(30).optional(),publicKey:z.string().regex(/^[0-9a-f]{64}$/)}).parse(req.body);

  const linked=await query(
    `INSERT INTO devices (user_id, id, device_name, platform, public_key, is_linked)
     VALUES ($1, $2, $3, $4, $5, true)
     ON CONFLICT (id) DO UPDATE SET is_linked = true, last_active_at = NOW() WHERE devices.user_id=EXCLUDED.user_id RETURNING id`,
    [userId, deviceId, deviceName || 'Linked Device', platform || 'unknown', publicKey]
  );

  if(linked.rowCount!==1) return res.status(409).json({error:'Device belongs to another account'});
  res.json({ success: true });
}));

// POST /api/v1/push/subscribe
router.post('/push/subscribe', authMiddleware, safe(async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { endpoint, keys } = req.body;

  if (!endpoint || !keys?.p256dh || !keys?.auth) {
    return res.status(400).json({ error: 'Invalid subscription' });
  }

  await subscribeToPush(userId, { endpoint, keys });
  res.json({ success: true });
}));

// GET /api/v1/onion/nodes
router.get('/onion/nodes', safe(async (req: Request, res: Response) => {
  const result = await query(
    'SELECT id, address, region, latency_ms, reliability FROM onion_nodes WHERE is_active = true'
  );
  res.json(result.rows);
}));

// GET /api/v1/onion/path
router.get('/onion/path', safe(async (req: Request, res: Response) => {
  const hopCount = parseInt(req.query.hops as string) || 3;
  const excludeRegion = req.query.excludeRegion as string;

  const result = await query(
    'SELECT id, address, public_key, region, latency_ms, reliability FROM onion_nodes WHERE is_active = true'
  );

  const nodes = result.rows;
  const shuffled = [...nodes].sort(() => Math.random() - 0.5);
  shuffled.sort((a, b) => (a.latency_ms / a.reliability) - (b.latency_ms / b.reliability));

  const picked: any[] = [];
  const usedRegions = new Set<string>();

  for (const node of shuffled) {
    if (excludeRegion && node.region === excludeRegion) continue;
    if (usedRegions.has(node.region)) continue;
    picked.push(node);
    usedRegions.add(node.region);
    if (picked.length === hopCount) break;
  }

  res.json(picked);
}));

export { router as apiRouter };
export const registerRoutes = (app: Express): void => { app.use('/api/v1', router); };
