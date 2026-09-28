import { Request, Response, Router } from 'express';
import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';
import { createHash, randomBytes } from 'crypto';
import { getDb, query, withTransaction } from './db';
import { logger } from './log';
import { sendNewMessageNotification, sendCallNotification, registerFCMToken, subscribeToPush } from './push';
import { broadcastToUser } from './signaling';

const router = Router();

// Validation schemas
const registerSchema = z.object({
  chhayaId: z.string().length(66),
  displayName: z.string().min(1).max(100),
  publicKey: z.string().length(66),
  encryptedPrivateKey: z.string().min(1),
  recoveryPhraseHash: z.string().length(64),
  deviceId: z.string().uuid(),
  deviceName: z.string().optional(),
  platform: z.string().optional(),
  fcmToken: z.string().optional(),
});

const loginSchema = z.object({
  chhayaId: z.string().length(66),
  recoveryPhraseHash: z.string().length(64),
  deviceId: z.string().uuid(),
  deviceName: z.string().optional(),
  platform: z.string().optional(),
  fcmToken: z.string().optional(),
});

const addContactSchema = z.object({
  chhayaId: z.string().length(66),
  displayName: z.string().min(1).max(100),
});

const createConversationSchema = z.object({
  type: z.enum(['direct', 'group']),
  participantIds: z.array(z.string().uuid()).min(1),
  name: z.string().optional(),
  avatarUrl: z.string().url().optional(),
});

const sendMessageSchema = z.object({
  conversationId: z.string().uuid(),
  content: z.string().min(1).max(10000),
  messageType: z.enum(['text', 'image', 'file', 'voice', 'location']).default('text'),
  mediaUrl: z.string().url().optional(),
  mediaMeta: z.record(z.unknown()).optional(),
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

// Auth middleware
const authMiddleware = async (req: Request, res: Response, next: Function) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization header' });
  }
  const token = authHeader.substring(7);
  
  // Simple token validation - in production use JWT
  const userResult = await query('SELECT id FROM users WHERE id = $1 AND is_active = true', [token]);
  if (userResult.rows.length === 0) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  
  (req as any).userId = userResult.rows[0].id;
  next();
};

// POST /api/v1/auth/register
router.post('/auth/register', async (req: Request, res: Response) => {
  try {
    const data = registerSchema.parse(req.body);
    
    // Check if user exists
    const existing = await query('SELECT id FROM users WHERE chhaya_id = $1', [data.chhayaId]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'User already exists' });
    }

    const userId = uuidv4();
    const now = new Date();

    await withTransaction(async (client) => {
      await client.query(
        `INSERT INTO users (id, chhaya_id, display_name, public_key, encrypted_private_key, 
          recovery_phrase_hash, device_id, created_at) 
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [userId, data.chhayaId, data.displayName, data.publicKey, data.encryptedPrivateKey, 
         data.recoveryPhraseHash, data.deviceId, now]
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

    logger.info('User registered', { userId, chhayaId: data.chhayaId });
    res.status(201).json({ userId, token: userId }); // In production, return JWT
  } catch (e) {
    if (e instanceof z.ZodError) {
      return res.status(400).json({ error: 'Invalid input', details: e.errors });
    }
    logger.error('Registration failed', { error: (e as Error).message });
    res.status(500).json({ error: 'Registration failed' });
  }
});

// POST /api/v1/auth/login
router.post('/auth/login', async (req: Request, res: Response) => {
  try {
    const data = loginSchema.parse(req.body);

    const userResult = await query(
      'SELECT id, recovery_phrase_hash FROM users WHERE chhaya_id = $1 AND is_active = true',
      [data.chhayaId]
    );

    if (userResult.rows.length === 0 || userResult.rows[0].recovery_phrase_hash !== data.recoveryPhraseHash) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const userId = userResult.rows[0].id;

    // Update device
    await query(
      `INSERT INTO devices (user_id, id, device_name, platform, fcm_token) 
       VALUES ($1, $2, $3, $4, $5) 
       ON CONFLICT (id) DO UPDATE SET 
         device_name = $3, platform = $4, fcm_token = $5, last_active_at = NOW()`,
      [userId, data.deviceId, data.deviceName || 'Device', data.platform || 'unknown', data.fcmToken || null]
    );

    if (data.fcmToken) {
      await registerFCMToken(userId, data.deviceId, data.fcmToken);
    }

    // Update last seen
    await query('UPDATE users SET last_seen_at = NOW() WHERE id = $1', [userId]);

    logger.info('User logged in', { userId });
    res.json({ userId, token: userId }); // In production, return JWT
  } catch (e) {
    if (e instanceof z.ZodError) {
      return res.status(400).json({ error: 'Invalid input', details: e.errors });
    }
    logger.error('Login failed', { error: (e as Error).message });
    res.status(500).json({ error: 'Login failed' });
  }
});

// GET /api/v1/users/me
router.get('/users/me', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const result = await query(
    `SELECT id, chhaya_id, display_name, public_key, biometric_enabled, 
     created_at, last_seen_at FROM users WHERE id = $1`,
    [userId]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
  res.json(result.rows[0]);
});

// PUT /api/v1/users/me/settings
router.put('/users/me/settings', authMiddleware, async (req: Request, res: Response) => {
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
    values.push(createHash('sha256').update(data.pin).digest('hex'));
  }
  if (data.panicPin) {
    updates.push(`panic_pin_hash = $${paramIndex++}`);
    values.push(createHash('sha256').update(data.panicPin).digest('hex'));
  }

  if (updates.length > 0) {
    updates.push('updated_at = NOW()');
    await query(`UPDATE users SET ${updates.join(', ')} WHERE id = $1`, values);
  }

  res.json({ success: true });
});

// POST /api/v1/contacts
router.post('/contacts', authMiddleware, async (req: Request, res: Response) => {
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

  await query(
    `INSERT INTO contacts (user_id, contact_id, display_name, verification_level) 
     VALUES ($1, $2, $3, 1)`,
    [userId, contactId, data.displayName]
  );

  // Create conversation
  const convoId = uuidv4();
  await withTransaction(async (client) => {
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

  res.status(201).json({ contactId, conversationId: convoId });
});

// GET /api/v1/contacts
router.get('/contacts', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const result = await query(
    `SELECT c.id, c.display_name, c.verification_level, c.is_blocked, c.created_at,
     u.chhaya_id, u.public_key, u.last_seen_at
     FROM contacts c
     JOIN users u ON u.id = c.contact_id
     WHERE c.user_id = $1 AND c.is_blocked = false
     ORDER BY c.display_name`,
    [userId]
  );
  res.json(result.rows);
});

// POST /api/v1/conversations
router.post('/conversations', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const data = createConversationSchema.parse(req.body);

  if (data.type === 'direct' && data.participantIds.length !== 1) {
    return res.status(400).json({ error: 'Direct conversation requires exactly 1 participant' });
  }

  const convoId = uuidv4();
  const allParticipants = [userId, ...data.participantIds];

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
});

// GET /api/v1/conversations
router.get('/conversations', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const result = await query(
    `SELECT c.id, c.type, c.name, c.avatar_url, c.created_at, c.updated_at,
     (SELECT json_agg(json_build_object('id', u.id, 'display_name', u.display_name, 'chhaya_id', u.chhaya_id, 'public_key', u.public_key))
      FROM conversation_participants cp
      JOIN users u ON u.id = cp.user_id
      WHERE cp.conversation_id = c.id AND cp.left_at IS NULL) as participants,
     (SELECT m.content, m.sender_id, m.sent_at, m.message_type
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
});

// POST /api/v1/messages
router.post('/messages', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const data = sendMessageSchema.parse(req.body);

  // Verify participant
  const participantCheck = await query(
    'SELECT 1 FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL',
    [data.conversationId, userId]
  );
  if (participantCheck.rows.length === 0) {
    return res.status(403).json({ error: 'Not a participant' });
  }

  const messageId = uuidv4();
  await query(
    `INSERT INTO messages (id, conversation_id, sender_id, content, message_type, media_url, media_meta, reply_to_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [messageId, data.conversationId, userId, data.content, data.messageType, 
     data.mediaUrl || null, data.mediaMeta || null, data.replyToId || null]
  );

  // Update conversation timestamp
  await query(
    'UPDATE conversations SET updated_at = NOW() WHERE id = $1',
    [data.conversationId]
  );

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
    sendNewMessageNotification(p.user_id, p.display_name, data.content.substring(0, 100), data.conversationId, messageId);
    
    // Also broadcast via signaling if online
    broadcastToUser(p.user_id, {
      type: 'new_message',
      payload: { conversationId: data.conversationId, messageId },
      from: 'server',
      timestamp: Date.now(),
    });
  }

  res.status(201).json({ messageId });
});

// GET /api/v1/messages/:conversationId
router.get('/messages/:conversationId', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { conversationId } = req.params;
  const limit = parseInt(req.query.limit as string) || 50;
  const before = req.query.before as string;

  // Verify participant
  const participantCheck = await query(
    'SELECT 1 FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL',
    [conversationId, userId]
  );
  if (participantCheck.rows.length === 0) {
    return res.status(403).json({ error: 'Not a participant' });
  }

  let queryStr = `
    SELECT m.id, m.sender_id, m.content, m.message_type, m.media_url, m.media_meta, 
           m.reply_to_id, m.sent_at, m.delivered_at, m.read_at,
           u.display_name as sender_name
    FROM messages m
    JOIN users u ON u.id = m.sender_id
    WHERE m.conversation_id = $1 AND m.is_deleted = false
  `;
  const params: any[] = [conversationId];

  if (before) {
    queryStr += ` AND m.sent_at < $${params.length + 1}`;
    params.push(before);
  }

  queryStr += ` ORDER BY m.sent_at DESC LIMIT $${params.length + 1}`;
  params.push(limit);

  const result = await query(queryStr, params);
  res.json(result.rows.reverse());
});

// POST /api/v1/messages/:messageId/read
router.post('/messages/:messageId/read', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { messageId } = req.params;

  await query(
    `UPDATE conversation_participants 
     SET last_read_at = (SELECT sent_at FROM messages WHERE id = $1)
     WHERE user_id = $2 AND conversation_id = (SELECT conversation_id FROM messages WHERE id = $1)`,
    [messageId, userId]
  );

  await query(
    'UPDATE messages SET read_at = NOW() WHERE id = $1 AND read_at IS NULL',
    [messageId]
  );

  res.json({ success: true });
});

// POST /api/v1/devices/link
router.post('/devices/link', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { deviceId, deviceName, platform, publicKey } = req.body;

  await query(
    `INSERT INTO devices (user_id, id, device_name, platform, public_key, is_linked) 
     VALUES ($1, $2, $3, $4, $5, true)
     ON CONFLICT (id) DO UPDATE SET is_linked = true, last_active_at = NOW()`,
    [userId, deviceId, deviceName || 'Linked Device', platform || 'unknown', publicKey]
  );

  res.json({ success: true });
});

// POST /api/v1/push/subscribe
router.post('/push/subscribe', authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { endpoint, keys } = req.body;

  if (!endpoint || !keys?.p256dh || !keys?.auth) {
    return res.status(400).json({ error: 'Invalid subscription' });
  }

  await subscribeToPush(userId, { endpoint, keys });
  res.json({ success: true });
});

// GET /api/v1/onion/nodes
router.get('/onion/nodes', async (req: Request, res: Response) => {
  const result = await query(
    'SELECT id, address, region, latency_ms, reliability FROM onion_nodes WHERE is_active = true'
  );
  res.json(result.rows);
});

// GET /api/v1/onion/path
router.get('/onion/path', async (req: Request, res: Response) => {
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
});

export { router as apiRouter };