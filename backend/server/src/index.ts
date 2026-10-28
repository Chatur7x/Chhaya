import 'dotenv/config';
import { createServer, type Server } from 'http';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config';
import { logger } from './log';
import { closeDb, initDb, query } from './db';
import { startSignalingServer, stopSignalingServer } from './signaling';
import { startOnionRelayServer } from './onion-relay';
import { initPushNotifications } from './push';
import { registerRoutes } from './routes';
import { ZodError } from 'zod';
import { collectDefaultMetrics, register, Counter } from 'prom-client';
import { consumeIpRateLimit, pruneExpiredRateLimits } from './rate-limit';
import { authenticateToken } from './session';

export const app = express();
app.set('trust proxy',config.TRUST_PROXY_HOPS);
collectDefaultMetrics();
const requests = new Counter({name:'chhaya_http_requests_total',help:'Completed HTTP requests',labelNames:['method','status']});
app.use((req,res,next)=>{ res.on('finish',()=>requests.inc({method:req.method,status:res.statusCode})); next(); });

// Middleware
app.use(helmet({
  contentSecurityPolicy: false, // Allow WebSocket connections
}));
app.use(cors({ origin: false }));

// Shared Postgres rate limit survives restarts and is consistent across instances.
app.use(async (req, res, next) => {
  if (req.path === '/health' || req.path === '/metrics') return next();
  try {
    // Resolve real sessions before assigning account buckets; arbitrary bearer
    // strings must not let an anonymous caller rotate through unlimited buckets.
    const authorization = req.headers.authorization;
    const userId = !req.path.startsWith('/api/v1/auth/') && authorization?.startsWith('Bearer ')
      ? await authenticateToken(authorization.substring(7)) : null;
    if (userId) res.locals.authenticatedUserId = userId;
    const decision = await consumeIpRateLimit(
      userId ? `account:${userId}` : req.ip || req.socket.remoteAddress || 'unknown',
      userId ? config.API_AUTH_RATE_LIMIT : config.API_RATE_LIMIT,
      60,
    );
    if (!decision.allowed) {
      res.set('Retry-After', String(decision.retryAfterSeconds));
      return res.status(429).json({ error: 'Too many requests' });
    }
    return next();
  } catch {
    // Fail closed: an unavailable shared limiter must not silently remove the guard.
    logger.error('Shared API rate limiter unavailable');
    return res.status(503).json({ error: 'Service temporarily unavailable' });
  }
});
// Rate limit before parsing request bodies so oversized unauthenticated posts
// cannot spend parser/allocator work before consuming their request budget.
app.use(express.json({ limit: '1mb' }));

// Health check
app.get('/health', async (_req, res) => {
  try {
    await query('SELECT 1');
    res.json({
      status: 'ok',
      database: 'ready',
      timestamp: new Date().toISOString(),
      version: '14.0.1',
    });
  } catch {
    res.status(503).json({
      status: 'unavailable',
      database: 'unavailable',
      timestamp: new Date().toISOString(),
      version: '14.0.1',
    });
  }
});

// Metrics endpoint
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.send(await register.metrics());
});

// Register API routes
registerRoutes(app);

// Error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (err instanceof ZodError) return res.status(400).json({error:'Invalid input'});
  const parserError = err as Error & { type?: string };
  if (parserError.type === 'entity.too.large') {
    return res.status(413).json({error:'Request body too large'});
  }
  if (parserError.type === 'entity.parse.failed' || parserError.type === 'request.size.invalid') {
    return res.status(400).json({error:'Invalid request body'});
  }
  if (parserError.type === 'encoding.unsupported' || parserError.type === 'charset.unsupported') {
    return res.status(415).json({error:'Unsupported request encoding'});
  }
  logger.error('Request failed');
  res.status(500).json({ error: 'Internal server error' });
});

// Start servers
let apiServer: Server | undefined;
let signalingServer: ReturnType<typeof startSignalingServer> | undefined;
let cleanupTimer: ReturnType<typeof setInterval> | undefined;
let shutdownTask: Promise<void> | undefined;
let startupTask: Promise<void> | undefined;
let shutdownRequested = false;

async function start() {
  try {
    await initDb();
    if (shutdownRequested) return;
    cleanupTimer = setInterval(() => {
      void pruneExpiredRateLimits().catch(() => {
        logger.warn('Rate limit bucket cleanup failed');
      });
    }, 5 * 60 * 1000);
    cleanupTimer.unref();
    initPushNotifications();
    apiServer = createServer(app);
    signalingServer = startSignalingServer(apiServer);
    // Onion transport is not enabled until a vetted relay implementation is configured.

    apiServer.listen(config.PORT, () => {
      logger.info(`Chhaya API server listening on port ${config.PORT}`, {
        env: config.NODE_ENV,
        signalingPath: '/signaling',
        onionPort: config.ONION_PORT,
      });
    });
  } catch (e) {
    logger.error('Failed to start server', { error: (e as Error).message });
    process.exit(1);
  }
}

async function shutdown(signal: string): Promise<void> {
  if (shutdownTask) return shutdownTask;
  shutdownRequested = true;
  shutdownTask = (async () => {
    logger.info(`${signal} received; draining backend`);
    await startupTask;
    if (cleanupTimer) clearInterval(cleanupTimer);

    const forceClose = setTimeout(() => {
      logger.warn('Backend drain deadline reached; forcing remaining connections closed');
      signalingServer?.clients.forEach((peer) => peer.terminate());
      apiServer?.closeAllConnections();
    }, 10000);
    forceClose.unref();

    try {
      if (signalingServer) await stopSignalingServer(signalingServer);
      if (apiServer?.listening) {
        await new Promise<void>((resolve, reject) => {
          apiServer!.close((error) => error ? reject(error) : resolve());
        });
      }
      await closeDb();
      clearTimeout(forceClose);
      process.exitCode = 0;
    } catch (error) {
      logger.error('Backend shutdown failed', { error: (error as Error).message });
      process.exitCode = 1;
    }
  })();
  return shutdownTask;
}

if (require.main === module) {
  process.once('SIGTERM', () => void shutdown('SIGTERM'));
  process.once('SIGINT', () => void shutdown('SIGINT'));
  startupTask = start();
}
