import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import { config } from './config';
import { logger } from './log';
import { applyMigrations } from './migrations';

let pool: Pool | null = null;
let initializing: Promise<Pool> | null = null;

export const initDb = async (): Promise<Pool> => {
  if (initializing) return initializing;
  if (pool) return pool;

  const candidate = new Pool({
    connectionString: config.DATABASE_URL,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  candidate.on('error', (err) => {
    logger.error('Unexpected database error', { error: err.message });
  });

  initializing = (async () => {
    try {
      await runMigrations(candidate);
      pool = candidate;
      logger.info('Database initialized');
      return candidate;
    } catch (error) {
      await candidate.end().catch(() => undefined);
      throw error;
    } finally {
      initializing = null;
    }
  })();
  return initializing;
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
      recovery_phrase_hash TEXT NOT NULL,
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

    `CREATE TABLE IF NOT EXISTS call_invites (
      call_id UUID NOT NULL,
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      envelope TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '60 seconds'),
      PRIMARY KEY (call_id, recipient_id)
    )`,
    `CREATE INDEX IF NOT EXISTS idx_call_invites_recipient_expiry
       ON call_invites(recipient_id, expires_at)`,

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

    `ALTER TABLE users ALTER COLUMN recovery_phrase_hash TYPE TEXT;
     ALTER TABLE users ALTER COLUMN pin_hash TYPE TEXT;
     ALTER TABLE users ALTER COLUMN panic_pin_hash TYPE TEXT;
     ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ DEFAULT 'epoch';
     ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ DEFAULT NOW();`,
    `CREATE TABLE IF NOT EXISTS identity_challenges (
      id UUID PRIMARY KEY, public_key CHAR(64) NOT NULL, device_id UUID NOT NULL,
      purpose TEXT NOT NULL, proof_hash CHAR(64) NOT NULL, expires_at TIMESTAMPTZ NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS auth_sessions (
      token_hash CHAR(64) PRIMARY KEY, user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      expires_at TIMESTAMPTZ NOT NULL
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
     CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON rate_limits(window_start);
     CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
     CREATE INDEX IF NOT EXISTS idx_devices_fcm_token ON devices(fcm_token);
     CREATE INDEX IF NOT EXISTS idx_onion_nodes_region ON onion_nodes(region, is_active);
     CREATE INDEX IF NOT EXISTS idx_circuits_user ON circuits(user_id, status);`,

    // WS1 prekey infrastructure (docs/spec-pq-hybrid-resync-v1.md §4.1). Public material only.
    // prekey_account carries the account-level public material the bundle contract needs
    // (ed25519 identity key + reseedKemKey); the spec's two-table sketch had no home for them.
    `CREATE TABLE IF NOT EXISTS prekey_signed (
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('ec','pq')),
      key_id UUID NOT NULL,
      public_key TEXT NOT NULL,
      signature TEXT NOT NULL,
      not_before TIMESTAMPTZ NOT NULL,
      not_after TIMESTAMPTZ NOT NULL,
      is_last_resort BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, kind, key_id)
    );
     CREATE TABLE IF NOT EXISTS prekey_one_time (
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('ec','pq')),
      key_id UUID NOT NULL,
      public_key TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, kind, key_id)
    );
     CREATE TABLE IF NOT EXISTS prekey_account (
      user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      ed25519_public_key TEXT NOT NULL,
      reseed_kem_public_key TEXT NOT NULL,
      reseed_kem_signature TEXT NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
     CREATE INDEX IF NOT EXISTS idx_prekey_one_time_pop
       ON prekey_one_time (user_id, kind, created_at);`,
    // WS-A media transfer (docs/spec-media-transfer-v1.md §18). Additive only.
    // Ciphertext-only blob store: chunks arrive AEAD-encrypted with a client-held
    // content key; the server stores size/hash/bytes and holds no key material,
    // no file names and no plaintext. Additive-only; never edit existing entries.
    `CREATE TABLE IF NOT EXISTS media_transfers (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      size_bytes BIGINT NOT NULL CHECK (size_bytes BETWEEN 1 AND 16777216),
      chunk_size INTEGER NOT NULL CHECK (chunk_size = 262144),
      total_chunks INTEGER NOT NULL CHECK (total_chunks BETWEEN 1 AND 64),
      state TEXT NOT NULL CHECK (state IN ('uploading','completed','canceled','expired')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ,
      expires_at TIMESTAMPTZ NOT NULL
    );
     CREATE INDEX IF NOT EXISTS idx_media_transfers_sender_state
       ON media_transfers (sender_id, state);
     CREATE INDEX IF NOT EXISTS idx_media_transfers_expiry
       ON media_transfers (expires_at);
     CREATE INDEX IF NOT EXISTS idx_media_transfers_conversation
       ON media_transfers (conversation_id);`,

    `CREATE TABLE IF NOT EXISTS media_chunks (
      transfer_id UUID NOT NULL REFERENCES media_transfers(id) ON DELETE CASCADE,
      chunk_index INTEGER NOT NULL CHECK (chunk_index BETWEEN 0 AND 63),
      sha256 CHAR(64) NOT NULL,
      byte_size INTEGER NOT NULL CHECK (byte_size BETWEEN 29 AND 262172),
      data BYTEA NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (transfer_id, chunk_index)
    );`,

    // DL-A authenticated device linking (docs/spec-device-linking-v1.md §4.1). Additive only.
    // Server stores public material, code hashes, opaque AEAD bytes and signatures over public
    // transcripts; never plaintext approvals, SK, or any private key material. The spec sketch
    // omitted a column for P's ephemeral X25519 public key, but §4.4#3 requires the server to
    // store it at approve time and hand it back on the status poll (N needs it for the ECDH),
    // so `prim_eph_pub` is included here (additive column inside this new table).
    `CREATE TABLE IF NOT EXISTS device_link_requests (
      request_id UUID PRIMARY KEY,
      device_id UUID NOT NULL,
      device_name VARCHAR(100) NOT NULL,
      platform VARCHAR(20) NOT NULL,
      device_public_key CHAR(64) NOT NULL,
      ephemeral_public_key CHAR(64),
      code_hash CHAR(64) NOT NULL,
      state TEXT NOT NULL CHECK (state IN ('pending','approved','denied','consumed','expired')),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      approval BYTEA,
      approval_signature TEXT,
      prim_eph_pub CHAR(64),
      denied_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL
    );
     CREATE UNIQUE INDEX IF NOT EXISTS uq_device_link_pending_device
       ON device_link_requests (device_id) WHERE state IN ('pending','approved');
     CREATE INDEX IF NOT EXISTS idx_device_link_requests_user
       ON device_link_requests (user_id);
     CREATE TABLE IF NOT EXISTS device_link_events (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      device_id UUID,
      action TEXT NOT NULL,
      at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
     CREATE INDEX IF NOT EXISTS idx_device_link_events_device
       ON device_link_events (device_id, at);
     CREATE INDEX IF NOT EXISTS idx_device_link_events_user
       ON device_link_events (user_id, at);
     ALTER TABLE devices ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;
     ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS device_id UUID REFERENCES devices(id) ON DELETE CASCADE;
     CREATE INDEX IF NOT EXISTS idx_auth_sessions_device ON auth_sessions(device_id);`,

  ];

  await applyMigrations(p, migrations);
};

export const query = async <T extends QueryResultRow = any>(text: string, params?: any[]): Promise<QueryResult<T>> => {
  const start = Date.now();
  const result = await pool!.query<T>(text, params);
  const duration = Date.now() - start;
  if (duration > 100) {
    logger.warn('Slow query', { text: text.substring(0, 100), duration, rows: result.rowCount });
  }
  return result;
};
export async function closeDb(): Promise<void> { await pool?.end(); pool = null; }
