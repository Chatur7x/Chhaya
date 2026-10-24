import { WebSocket, WebSocketServer } from 'ws';
import { createServer, type Server } from 'http';
import { config } from './config';
import { logger, createChildLogger } from './log';
import { v4 as uuidv4 } from 'uuid';
import { getDb, query } from './db';
import { authenticateToken } from './session';

interface SignalingMessage {
  type: 'offer' | 'answer' | 'ice-candidate' | 'join' | 'leave' | 'ping' | 'pong' | 'error' | 'new_message' | 'call-end' | 'typing';
  payload: any;
  from: string;
  to?: string;
  timestamp: number;
}

interface ConnectedClient {
  id: string;
  ws: WebSocket;
  userId: string;
  deviceId: string;
  conversationId?: string;
  lastPing: number;
  sessionToken: string;
  lastTypingSignalAt: number;
}

const clients = new Map<string, ConnectedClient>();
const userClients = new Map<string, Set<string>>();

const log = createChildLogger({ module: 'signaling' });

export const startSignalingServer = (sharedServer?: Server): WebSocketServer => {
  const server = sharedServer ?? createServer();
  const wss = new WebSocketServer({
    server,
    maxPayload: 65536,
    ...(sharedServer ? { path: '/signaling' } : {}),
  });

  wss.on('connection', (ws, req) => {
    const clientId = uuidv4();
    log.info('Signaling connection opened');

    ws.on('message', async (data) => {
      try {
        const msg: SignalingMessage = JSON.parse(data.toString());
        await handleMessage(clientId, ws, msg);
      } catch (e) {
        log.warn('Invalid signaling message', { clientId, error: (e as Error).message });
        send(ws, { type: 'error', payload: { message: 'Invalid message format' }, from: 'server', timestamp: Date.now() });
      }
    });

    ws.on('close', () => handleDisconnect(clientId));
    ws.on('error', (err) => log.error('WebSocket error', { clientId, error: err.message }));

    // Heartbeat
    const pingInterval = setInterval(() => {
      const client = clients.get(clientId);
      if (!client || Date.now() - client.lastPing > 30000) {
        clearInterval(pingInterval);
        handleDisconnect(clientId);
        return;
      }
      send(ws, { type: 'ping', payload: {}, from: 'server', timestamp: Date.now() });
    }, 15000);

    ws.on('close', () => clearInterval(pingInterval));
  });

  if (!sharedServer) {
    server.listen(config.SIGNALING_PORT, () => {
      log.info(`Signaling server listening on port ${config.SIGNALING_PORT}`);
    });
  } else {
    log.info('Signaling server attached to the shared HTTP listener at /signaling');
  }

  // Periodic cleanup
  const cleanup=setInterval(cleanupStaleClients,60000);
  wss.on('close',()=>{
    clearInterval(cleanup);
    if (!sharedServer) server.close();
  });

  return wss;
};

/** Stop accepting signaling clients, close active peers, then force-close stragglers. */
export async function stopSignalingServer(wss: WebSocketServer): Promise<void> {
  const peers = [...wss.clients];
  const forceClose = setTimeout(() => {
    for (const peer of peers) peer.terminate();
  }, 5000);
  forceClose.unref();

  try {
    const closed = new Promise<void>((resolve) => {
      wss.close(() => resolve());
    });
    for (const peer of peers) {
      if (peer.readyState === WebSocket.OPEN) {
        peer.close(1001, 'Server shutting down');
      } else {
        peer.terminate();
      }
    }
    await closed;
  } finally {
    clearTimeout(forceClose);
  }
}

const handleMessage = async (clientId: string, ws: WebSocket, msg: SignalingMessage): Promise<void> => {
  const client = clients.get(clientId);
  if(client && await authenticateToken(client.sessionToken)!==client.userId) { ws.close(1008,'Session expired'); return; }

  switch (msg.type) {
    case 'join':
      await handleJoin(clientId, ws, msg);
      break;

    case 'offer':
    case 'answer':
    case 'ice-candidate':
    case 'call-end':
      await handleWebRTCSignal(clientId, msg);
      break;

    case 'typing':
      await handleTypingSignal(clientId, msg);
      break;

    case 'pong':
      if (client) client.lastPing = Date.now();
      break;

    default:
      log.warn('Unknown message type', { clientId, type: msg.type });
  }
};

const handleJoin = async (clientId: string, ws: WebSocket, msg: SignalingMessage): Promise<void> => {
  const { deviceId, conversationId, token } = msg.payload;
  const userId = await authenticateToken(token);
  
  if (!userId || !deviceId) {
    send(ws, { type: 'error', payload: { message: 'Missing userId or deviceId' }, from: 'server', timestamp: Date.now() });
    ws.close();
    return;
  }

  // Verify authenticated account exists
  const userResult = await query('SELECT id FROM users WHERE id = $1', [userId]);
  if (userResult.rows.length === 0) {
    send(ws, { type: 'error', payload: { message: 'User not found' }, from: 'server', timestamp: Date.now() });
    ws.close();
    return;
  }

  // Verify room membership before joining, including direct signaling.
  if (conversationId) {
    const membership = await query('SELECT 1 FROM conversation_participants WHERE conversation_id=$1 AND user_id=$2 AND left_at IS NULL',[conversationId,userId]);
    if (membership.rowCount !== 1) { ws.close(1008, 'Not a participant'); return; }

    await query(
      'UPDATE conversation_participants SET last_active_at = NOW() WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, userId]
    );
  }


  const client: ConnectedClient = {
    id: clientId,
    ws,
    userId,
    deviceId,
    conversationId,
    lastPing: Date.now(),
    sessionToken: token,
    lastTypingSignalAt: 0,
  };

  clients.set(clientId, client);

  if (!userClients.has(userId)) {
    userClients.set(userId, new Set());
  }
  userClients.get(userId)!.add(clientId);

  log.info('Authenticated signaling client joined');
  send(ws, { type: 'join', payload: { status: 'ok', clientId }, from: 'server', timestamp: Date.now() });
};

const handleTypingSignal = async (clientId: string, msg: SignalingMessage): Promise<void> => {
  const client = clients.get(clientId);
  const conversationId = msg.payload?.conversationId;
  const active = msg.payload?.active;
  if (!client || typeof conversationId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(conversationId) ||
      typeof active !== 'boolean') return;

  const now = Date.now();
  if (now - client.lastTypingSignalAt < (active ? 500 : 100)) return;
  client.lastTypingSignalAt = now;

  // Typing is ephemeral direct-chat metadata only. Never persist it and never
  // fan it out to groups; the recipient is derived from verified membership.
  const membership = await query(
    `SELECT user_id FROM conversation_participants
     WHERE conversation_id=$1 AND left_at IS NULL`,
    [conversationId],
  );
  if (membership.rows.length !== 2) return;
  const members = membership.rows.map((row) => String(row.user_id));
  if (!members.includes(client.userId)) return;
  const recipient = members.find((id) => id !== client.userId);
  if (!recipient) return;

  broadcastToUser(recipient, {
    type: 'typing',
    payload: { conversationId, active },
    from: client.userId,
    to: recipient,
    timestamp: now,
  });
};

const handleWebRTCSignal = async (fromClientId: string, msg: SignalingMessage): Promise<void> => {
  const fromClient = clients.get(fromClientId);
  if (!fromClient) return;

  const {to,payload}=msg;
  if(typeof to!=='string'||typeof payload?.conversationId!=='string'||typeof payload?.callId!=='string') return;
  const allowed=await query(`SELECT user_id FROM conversation_participants
    WHERE conversation_id=$1 AND user_id=ANY($2::uuid[]) AND left_at IS NULL`,
    [payload.conversationId,[fromClient.userId,to]]);
  if(allowed.rows.length!==2) return;
  broadcastToUser(to,{type:msg.type,payload,from:fromClient.userId,to,timestamp:Date.now()});

};

const handleDisconnect = (clientId: string): void => {
  const client = clients.get(clientId);
  if (!client) return;

  clients.delete(clientId);
  
  const userSet = userClients.get(client.userId);
  if (userSet) {
    userSet.delete(clientId);
    if (userSet.size === 0) userClients.delete(client.userId);
  }

  log.info('Signaling client disconnected');
};

const cleanupStaleClients = (): void => {
  const now = Date.now();
  for (const [clientId, client] of clients.entries()) {
    if (now - client.lastPing > 60000) {
      client.ws.close();
      handleDisconnect(clientId);
    }
  }
};

const send = (ws: WebSocket, msg: SignalingMessage): void => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
};

export const broadcastToUser = (userId: string, msg: SignalingMessage): void => {
  const userClientIds = userClients.get(userId);
  if (!userClientIds) return;

  for (const clientId of userClientIds) {
    const client = clients.get(clientId);
    if (client) send(client.ws, msg);
  }
};

export const getConnectedUsers = (): string[] => Array.from(userClients.keys());
