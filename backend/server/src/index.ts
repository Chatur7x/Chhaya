import 'dotenv/config';
import { createServer } from 'http';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { RateLimiterMemory } from 'rate-limiter-flexible';
import { config } from './config';
import { logger } from './log';
import { initDb } from './db';
import { startSignalingServer } from './signaling';
import { startOnionRelayServer } from './onion-relay';
import { initPushNotifications } from './push';
import { registerRoutes } from './routes';
import { ZodError } from 'zod';
import { collectDefaultMetrics, register, Counter } from 'prom-client';

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
app.use(express.json({ limit: '1mb' }));

// Rate limiting
const apiLimiter = new RateLimiterMemory({
  points: config.API_RATE_LIMIT,
  duration: 60,
});
app.use(async (req, res, next) => {
  try {
    await apiLimiter.consume(req.ip || 'unknown');
    next();
  } catch {
    res.status(429).json({ error: 'Too many requests' });
  }
});

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), version: '14.0.0' });
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
  logger.error('Request failed');
  res.status(500).json({ error: 'Internal server error' });
});

// Start servers
async function start() {
  try {
    await initDb();
    initPushNotifications();
    const server = createServer(app);
    startSignalingServer(server);
    // Onion transport is not enabled until a vetted relay implementation is configured.

    server.listen(config.PORT, () => {
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

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  process.exit(0);
});

if (require.main === module) void start();
