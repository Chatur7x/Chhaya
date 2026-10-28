import { createHash } from 'crypto';
import { Pool } from 'pg';

// A transaction-scoped lock serializes startup across all API instances.
export async function applyMigrations(pool: Pool, statements: readonly string[]): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(1128812889, 1)');
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      checksum CHAR(64) NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )`);
    const applied = await client.query<{version: number; checksum: string}>(
      'SELECT version, checksum FROM schema_migrations ORDER BY version');
    for (const row of applied.rows) {
      const statement = statements[row.version - 1];
      if (statement === undefined || checksum(statement) !== row.checksum) {
        throw new Error(`Migration history mismatch at version ${row.version}`);
      }
    }
    const versions = new Set(applied.rows.map(row => row.version));
    for (let index = 0; index < statements.length; index++) {
      const version = index + 1;
      if (versions.has(version)) continue;
      await client.query(statements[index]);
      await client.query('INSERT INTO schema_migrations (version, checksum) VALUES ($1, $2)',
        [version, checksum(statements[index])]);
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

function checksum(statement: string): string {
  return createHash('sha256').update(statement).digest('hex');
}
