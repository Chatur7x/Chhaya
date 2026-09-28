import { z } from 'zod';

const envSchema = z.object({
  PORT: z.coerce.number().default(8443),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  
  // Database
  DATABASE_URL: z.string().default('postgresql://chhaya:chhaya@localhost:5432/chhaya'),
  
  // Redis
  REDIS_URL: z.string().default('redis://localhost:6379'),
  
  // Firebase
  FIREBASE_PROJECT_ID: z.string().optional(),
  FIREBASE_CLIENT_EMAIL: z.string().optional(),
  FIREBASE_PRIVATE_KEY: z.string().optional(),
  
  // Signaling
  SIGNALING_PORT: z.coerce.number().default(8444),
  
  // Onion relay
  ONION_PORT: z.coerce.number().default(8445),
  ONION_REGIONS: z.string().default('us-east,eu-west,ap-south,us-west,eu-north,ap-east,sa-east,af-south'),
  
  // Security
  JWT_SECRET: z.string().min(32).default('chhaya-dev-secret-change-in-production'),
  API_RATE_LIMIT: z.coerce.number().default(100),
  WS_RATE_LIMIT: z.coerce.number().default(50),
  
  // Monitoring
  METRICS_PORT: z.coerce.number().default(9090),
  HEALTH_CHECK_INTERVAL: z.coerce.number().default(30000),
});

export const config = envSchema.parse(process.env);

export const regions = config.ONION_REGIONS.split(',').map(r => r.trim());