import { WebSocket, WebSocketServer } from 'ws';
import { createServer } from 'http';
import { config, regions } from './config';
import { logger, createChildLogger } from './log';
import { getDb, query, withTransaction } from './db';
import { v4 as uuidv4 } from 'uuid';
import { createHash, randomBytes } from 'crypto';

const log = createChildLogger({ module: 'onion-relay' });

interface OnionNode {
  id: string;
  address: string;
  publicKey: Buffer;
  region: string;
  latencyMs: number;
  reliability: number;
  isActive: boolean;
}

interface OnionPacket {
  packetId: string;
  payload: Buffer;
  layersRemaining: number;
  routePath: string[];
  createdAt: Date;
  circuitId: string;
  ttlSeconds: number;
}

interface RelayMessage {
  type: 'relay' | 'unwrap' | 'health' | 'ack';
  payload: any;
  timestamp: number;
}

const nodeCache = new Map<string, OnionNode>();

export const startOnionRelayServer = async (): Promise<WebSocketServer> => {
  await loadNodes();
  
  const server = createServer();
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    const peerId = req.socket.remoteAddress || 'unknown';
    log.debug('Onion relay connection', { peerId });

    ws.on('message', async (data) => {
      try {
        const msg: RelayMessage = JSON.parse(data.toString());
        await handleRelayMessage(ws, msg);
      } catch (e) {
        log.warn('Invalid relay message', { peerId, error: (e as Error).message });
      }
    });

    ws.on('error', (err) => log.error('Relay WebSocket error', { peerId, error: err.message }));
  });

  server.listen(config.ONION_PORT, () => {
    log.info(`Onion relay server listening on port ${config.ONION_PORT}`);
  });

  // Periodic health checks
  setInterval(healthCheckNodes, config.HEALTH_CHECK_INTERVAL);

  return wss;
};

const loadNodes = async (): Promise<void> => {
  const result = await query<OnionNode>(
    'SELECT id, address, public_key, region, latency_ms, reliability, is_active FROM onion_nodes WHERE is_active = true'
  );

  for (const row of result.rows) {
    nodeCache.set(row.id, {
      id: row.id,
      address: row.address,
      publicKey: row.public_key,
      region: row.region,
      latencyMs: row.latency_ms,
      reliability: row.reliability,
      isActive: row.is_active,
    });
  }

  log.info('Loaded onion nodes', { count: nodeCache.size });
};

const healthCheckNodes = async (): Promise<void> => {
  for (const [id, node] of nodeCache.entries()) {
    try {
      const start = Date.now();
      const ws = new WebSocket(`wss://${node.address}/health`);
      
      await new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('timeout')), 5000);
        ws.on('open', () => { clearTimeout(timeout); ws.close(); resolve(); });
        ws.on('error', (e) => { clearTimeout(timeout); reject(e); });
      });

      const latency = Date.now() - start;
      await query(
        'UPDATE onion_nodes SET latency_ms = $1, last_health_check = NOW(), reliability = LEAST(reliability + 0.01, 0.99) WHERE id = $2',
        [latency, id]
      );
      nodeCache.get(id)!.latencyMs = latency;
      nodeCache.get(id)!.reliability = Math.min(nodeCache.get(id)!.reliability + 0.01, 0.99);
    } catch (e) {
      await query(
        'UPDATE onion_nodes SET reliability = GREATEST(reliability - 0.05, 0.5), is_active = CASE WHEN reliability < 0.6 THEN false ELSE is_active END WHERE id = $1',
        [id]
      );
      const node = nodeCache.get(id)!;
      node.reliability = Math.max(node.reliability - 0.05, 0.5);
      if (node.reliability < 0.6) node.isActive = false;
      log.warn('Node health check failed', { id, error: (e as Error).message });
    }
  }
};

const handleRelayMessage = async (ws: WebSocket, msg: RelayMessage): Promise<void> => {
  switch (msg.type) {
    case 'relay':
      await handleRelay(ws, msg.payload);
      break;
    case 'unwrap':
      await handleUnwrap(ws, msg.payload);
      break;
    case 'health':
      send(ws, { type: 'ack', payload: { status: 'ok' }, timestamp: Date.now() });
      break;
  }
};

const handleRelay = async (ws: WebSocket, payload: any): Promise<void> => {
  const { packet, nextNodeId } = payload;
  
  if (!packet || !nextNodeId) {
    send(ws, { type: 'ack', payload: { success: false, error: 'Missing packet or nextNodeId' }, timestamp: Date.now() });
    return;
  }

  const node = nodeCache.get(nextNodeId);
  if (!node || !node.isActive) {
    send(ws, { type: 'ack', payload: { success: false, error: 'Node unavailable' }, timestamp: Date.now() });
    return;
  }

  try {
    const relayWs = new WebSocket(`wss://${node.address}/relay`);
    
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('timeout')), 10000);
      relayWs.on('open', () => { clearTimeout(timeout); resolve(); });
      relayWs.on('error', (e) => { clearTimeout(timeout); reject(e); });
    });

    relayWs.send(JSON.stringify({
      type: 'relay',
      payload: { packet, nextNodeId: packet.routePath[1] },
      timestamp: Date.now(),
    }));

    const response = await new Promise<any>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('timeout')), 15000);
      relayWs.on('message', (data) => { clearTimeout(timeout); resolve(JSON.parse(data.toString())); });
      relayWs.on('error', (e) => { clearTimeout(timeout); reject(e); });
    });

    send(ws, { type: 'ack', payload: response, timestamp: Date.now() });
    relayWs.close();
  } catch (e) {
    send(ws, { type: 'ack', payload: { success: false, error: (e as Error).message }, timestamp: Date.now() });
  }
};

const handleUnwrap = async (ws: WebSocket, payload: any): Promise<void> => {
  const { packet, nodePrivateKey } = payload;
  
  if (!packet || !nodePrivateKey) {
    send(ws, { type: 'ack', payload: { success: false, error: 'Missing packet or key' }, timestamp: Date.now() });
    return;
  }

  try {
    // In production, use the node's private key to unwrap
    // For now, simulate unwrap
    const decrypted = await unwrapLayer(packet, nodePrivateKey);
    send(ws, { type: 'ack', payload: { success: true, packet: decrypted }, timestamp: Date.now() });
  } catch (e) {
    send(ws, { type: 'ack', payload: { success: false, error: (e as Error).message }, timestamp: Date.now() });
  }
};

const unwrapLayer = async (packet: OnionPacket, privateKey: string): Promise<OnionPacket> => {
  // Simulate AES-GCM decryption
  // In production: decrypt with privateKey hash, remove nonce, return inner packet
  return {
    ...packet,
    payload: packet.payload, // Already decrypted by previous hop
    layersRemaining: packet.layersRemaining - 1,
    routePath: packet.routePath.slice(1),
  };
};

const send = (ws: WebSocket, msg: RelayMessage): void => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
};

export const getOptimalPath = (hopCount: number = 3, excludeRegion?: string): OnionNode[] => {
  const available = Array.from(nodeCache.values()).filter(n => n.isActive);
  const shuffled = [...available].sort(() => Math.random() - 0.5);
  shuffled.sort((a, b) => (a.latencyMs / a.reliability) - (b.latencyMs / b.reliability));
  
  const picked: OnionNode[] = [];
  const usedRegions = new Set<string>();
  
  for (const node of shuffled) {
    if (excludeRegion && node.region === excludeRegion) continue;
    if (usedRegions.has(node.region)) continue;
    picked.push(node);
    usedRegions.add(node.region);
    if (picked.length === hopCount) break;
  }
  
  return picked;
};

export const wrapMessage = (payload: Buffer, path: OnionNode[]): Buffer => {
  let wrapped = payload;
  
  for (let i = path.length - 1; i >= 0; i--) {
    const node = path[i];
    const key = createHash('sha256').update(node.publicKey).digest();
    const nonce = randomBytes(12);
    // In production: AES-GCM encrypt
    // wrapped = encrypt(key, nonce, wrapped);
    wrapped = Buffer.concat([nonce, wrapped]); // Simplified
  }
  
  return wrapped;
};