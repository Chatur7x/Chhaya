import { WebSocket, WebSocketServer } from 'ws';
import { createServer } from 'http';
import { config } from './config';
import { logger, createChildLogger } from './log';
import { v4 as uuidv4 } from 'uuid';
import { getDb, query } from './db';

interface SignalingMessage {
  type: 'offer' | 'answer' | 'ice-candidate' | 'join' | 'leave' | 'ping' | 'pong' | 'error';
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
}

const clients = new Map<string, ConnectedClient>();
const userClients = new Map<string, Set<string>>();

const log = createChildLogger({ module: 'signaling' });

export const startSignalingServer = (): WebSocketServer => {
  const server = createServer();
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    const clientId = uuidv4();
    log.info('New signaling connection', { clientId, ip: req.socket.remoteAddress });

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

  server.listen(config.SIGNALING_PORT, () => {
    log.info(`Signaling server listening on port ${config.SIGNALING_PORT}`);
  });

  // Periodic cleanup
  setInterval(cleanupStaleClients, 60000);

  return wss;
};

const handleMessage = async (clientId: string, ws: WebSocket, msg: SignalingMessage): Promise<void> => {
  const client = clients.get(clientId);

  switch (msg.type) {
    case 'join':
      await handleJoin(clientId, ws, msg);
      break;

    case 'offer':
    case 'answer':
    case 'ice-candidate':
      await handleWebRTCSignal(clientId, msg);
      break;

    case 'pong':
      if (client) client.lastPing = Date.now();
      break;

    default:
      log.warn('Unknown message type', { clientId, type: msg.type });
  }
};

const handleJoin = async (clientId: string, ws: WebSocket, msg: SignalingMessage): Promise<void> => {
  const { userId, deviceId, conversationId } = msg.payload;
  
  if (!userId || !deviceId) {
    send(ws, { type: 'error', payload: { message: 'Missing userId or deviceId' }, from: 'server', timestamp: Date.now() });
    ws.close();
    return;
  }

  // Verify user exists
  const userResult = await query('SELECT id FROM users WHERE id = $1', [userId]);
  if (userResult.rows.length === 0) {
    send(ws, { type: 'error', payload: { message: 'User not found' }, from: 'server', timestamp: Date.now() });
    ws.close();
    return;
  }

  const client: ConnectedClient = {
    id: clientId,
    ws,
    userId,
    deviceId,
    conversationId,
    lastPing: Date.now(),
  };

  clients.set(clientId, client);

  if (!userClients.has(userId)) {
    userClients.set(userId, new Set());
  }
  userClients.get(userId)!.add(clientId);

  // Join conversation room
  if (conversationId) {
    await query(
      'UPDATE conversation_participants SET last_active_at = NOW() WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, userId]
    );
  }

  log.info('Client joined', { clientId, userId, deviceId, conversationId });
  send(ws, { type: 'join', payload: { status: 'ok', clientId }, from: 'server', timestamp: Date.now() });
};

const handleWebRTCSignal = async (fromClientId: string, msg: SignalingMessage): Promise<void> => {
  const fromClient = clients.get(fromClientId);
  if (!fromClient) return;

  const { to, payload } = msg;
  
  if (!to) {
    // Broadcast to conversation participants
    if (fromClient.conversationId) {
      const participants = await query(
        `SELECT DISTINCT cp.user_id FROM conversation_participants cp 
         WHERE cp.conversation_id = $1 AND cp.left_at IS NULL`,
        [fromClient.conversationId]
      );

      for (const p of participants.rows) {
        const userClientIds = userClients.get(p.user_id);
        if (userClientIds) {
          for (const cid of userClientIds) {
            const targetClient = clients.get(cid);
            if (targetClient && targetClient.id !== fromClientId) {
              send(targetClient.ws, {
                type: msg.type,
                payload,
                from: fromClientId,
                to: cid,
                timestamp: Date.now(),
              });
            }
          }
        }
      }
    }
  } else {
    // Direct message
    const targetClient = clients.get(to);
    if (targetClient) {
      send(targetClient.ws, {
        type: msg.type,
        payload,
        from: fromClientId,
        to,
        timestamp: Date.now(),
      });
    }
  }
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

  log.info('Client disconnected', { clientId, userId: client.userId });
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