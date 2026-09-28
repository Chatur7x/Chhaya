import { Pool, PoolClient, QueryResult } from 'pg';
import { config } from './config';
import { logger } from './log';

let pool: Pool | null = null;

export const initDb = async (): Promise<Pool> => {
  if (pool) return pool;

  pool = new Pool({
    connectionString: config.DATABASE_URL,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  pool.on('error', (err) => {
    logger.error('Unexpected database error', { error: err.message });
  });

  await runMigrations(pool);
  logger.info('Database initialized');
  return pool;
};

export const getDb = (): Pool => {
  if (!pool) throw new Error('Database not initialized. Call initDb() first.');
  return pool;
};

export const withTransaction = async <T>(
  callback: (client: PoolClient) => Promise<T>
): Promise<T> => {
  const client = await pool!.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
};

const runMigrations = async (p: Pool): Promise<void> => {
  const migrations = [
    `CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      chhaya_id VARCHAR(66) UNIQUE NOT NULL,
      display_name VARCHAR(100) NOT NULL,
      public_key VARCHAR(66) NOT NULL,
      encrypted_private_key BYTEA NOT NULL,
      recovery_phrase_hash VARCHAR(64) NOT NULL,
      biometric_enabled BOOLEAN DEFAULT false,
      pin_hash VARCHAR(64),
      panic_pin_hash VARCHAR(64),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW(),
      last_seen_at TIMESTAMPTZ,
      is_active BOOLEAN DEFAULT true
    )`,

    `CREATE TABLE IF NOT EXISTS contacts (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      contact_id UUID REFERENCES users(id) ON DELETE CASCADE,
      display_name VARCHAR(100) NOT NULL,
      verification_level SMALLINT DEFAULT 1,
      is_blocked BOOLEAN DEFAULT false,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(user_id, contact_id)
    )`,

    `CREATE TABLE IF NOT EXISTS conversations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      type VARCHAR(20) DEFAULT 'direct',
      name VARCHAR(100),
      avatar_url TEXT,
      created_by UUID REFERENCES users(id),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )`,

    `CREATE TABLE IF NOT EXISTS conversation_participants (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      joined_at TIMESTAMPTZ DEFAULT NOW(),
      left_at TIMESTAMPTZ,
      is_admin BOOLEAN DEFAULT false,
      UNIQUE(conversation_id, user_id)
    )`,

    `CREATE TABLE IF NOT EXISTS messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
      sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
      content TEXT NOT NULL,
      message_type VARCHAR(20) DEFAULT 'text',
      media_url TEXT,
      media_meta JSONB,
      reply_to_id UUID REFERENCES messages(id),
      sent_at TIMESTAMPTZ DEFAULT NOW(),
      delivered_at TIMESTAMPTZ,
      read_at TIMESTAMPTZ,
      is_deleted BOOLEAN DEFAULT false
    )`,

    `CREATE TABLE IF NOT EXISTS devices (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      device_name VARCHAR(100),
      platform VARCHAR(20),
      fcm_token TEXT,
      public_key VARCHAR(66) NOT NULL,
      last_active_at TIMESTAMPTZ DEFAULT NOW(),
      is_linked BOOLEAN DEFAULT false,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )`,

    `CREATE TABLE IF NOT EXISTS push_subscriptions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      endpoint TEXT NOT NULL,
      p256dh TEXT NOT NULL,
      auth TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )`,

    `CREATE TABLE IF NOT EXISTS onion_nodes (
      id VARCHAR(50) PRIMARY KEY,
      address VARCHAR(100) NOT NULL,
      public_key BYTEA NOT NULL,
      region VARCHAR(20) NOT NULL,
      latency_ms INTEGER DEFAULT 0,
      reliability DECIMAL(3,2) DEFAULT 0.95,
      is_active BOOLEAN DEFAULT true,
      last_health_check TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )`,

    `CREATE TABLE IF NOT EXISTS circuits (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      path UUID[] NOT NULL,
      status VARCHAR(20) DEFAULT 'active',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      expires_at TIMESTAMPTZ
    )`,

    `CREATE TABLE IF NOT EXISTS rate_limits (
      key VARCHAR(100) PRIMARY KEY,
      count INTEGER DEFAULT 0,
      window_start TIMESTAMPTZ DEFAULT NOW()
    )`,

    `CREATE INDEX IF NOT EXISTS idx_users_chhaya_id ON users(chhaya_id);
     CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON contacts(user_id);
     CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);
     CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, sent_at DESC);
     CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
     CREATE INDEX IF NOT EXISTS idx_devices_fcm_token ON devices(fcm_token);
     CREATE INDEX IF NOT EXISTS idx_onion_nodes_region ON onion_nodes(region, is_active);
     CREATE INDEX IF NOT EXISTS idx_circuits_user ON circuits(user_id, status);`,

    `INSERT INTO onion_nodes (id, address, public_key, region, latency_ms, reliability, is_active)
     VALUES 
       ('node_us_east_001', 'us-east.chhaya.network:8443', decode('a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef12345678', 'hex'), 'us-east', 45, 0.98, true),
       ('node_eu_west_002', 'eu-west.chhaya.network:8443', decode('b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef1234567890', 'hex'), 'eu-west', 52, 0.97, true),
       ('node_ap_south_003', 'ap-south.chhaya.network:8443', decode('c3d4e5f6789012345678901234567890abcdef1234567890abcdef1234567890ab', 'hex'), 'ap-south', 68, 0.96, true),
       ('node_us_west_004', 'us-west.chhaya.network:8443', decode('d4e5f6789012345678901234567890abcdef1234567890abcdef1234567890abcdef', 'hex'), 'us-west', 58, 0.97, true),
       ('node_eu_north_005', 'eu-north.chhaya.network:8443', decode('e5f6789012345678901234567890abcdef1234567890abcdef1234567890abcdef12', 'hex'), 'eu-north', 48, 0.98, true),
       ('node_ap_east_006', 'ap-east.chhaya.network:8443', decode('f6789012345678901234567890abcdef1234567890abcdef1234567890abcdef1234', 'hex'), 'ap-east', 72, 0.95, true),
       ('node_sa_east_007', 'sa-east.chhaya.network:8443', decode('789012345678901234567890abcdef1234567890abcdef1234567890abcdef123456', 'hex'), 'sa-east', 85, 0.94, true),
       ('node_af_south_008', 'af-south.chhaya.network:8443', decode('9012345678901234567890abcdef1234567890abcdef1234567890abcdef12345678', 'hex'), 'af-south', 95, 0.93, true)
     ON CONFLICT (id) DO UPDATE SET 
       address = EXCLUDED.address,
       public_key = EXCLUDED.public_key,
       latency_ms = EXCLUDED.latency_ms,
       reliability = EXCLUDED.reliability,
       is_active = EXCLUDED.is_active,
       last_health_check = NOW()`,
  ];

  for (const migration of migrations) {
    await p.query(migration);
  }
};

export const query = async <T = any>(text: string, params?: any[]): Promise<QueryResult<T>> => {
  const start = Date.now();
  const result = await pool!.query<T>(text, params);
  const duration = Date.now() - start;
  if (duration > 100) {
    logger.warn('Slow query', { text: text.substring(0, 100), duration, rows: result.rowCount });
  }
  return result;
};