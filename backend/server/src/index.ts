import 'dotenv/config';
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

const app = express();

// Middleware
app.use(helmet({
  contentSecurityPolicy: false, // Allow WebSocket connections
}));
app.use(cors({ origin: true, credentials: true }));
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
  res.json({ status: 'ok', timestamp: new Date().toISOString(), version: '13.0.0' });
});

// Metrics endpoint
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send('# Metrics endpoint - integrate with prom-client\n');
});

// Register API routes
registerRoutes(app);

// Error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error('Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

// Start servers
async function start() {
  try {
    await initDb();
    initPushNotifications();
    startSignalingServer();
    await startOnionRelayServer();

    app.listen(config.PORT, () => {
      logger.info(`Chhaya API server listening on port ${config.PORT}`, {
        env: config.NODE_ENV,
        signalingPort: config.SIGNALING_PORT,
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

start();