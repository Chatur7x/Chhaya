const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {applyMigrations} = require('../dist/migrations');

function database(rows = [], failAt) {
  const calls = [];
  let released = false;
  return {
    calls,
    get released() { return released; },
    async connect() {
      return {
        async query(sql, params) {
          calls.push({sql, params});
          if (sql === failAt) throw new Error('injected failure');
          return {rows: sql.startsWith('SELECT version') ? rows : []};
        },
        release() { released = true; },
      };
    },
  };
}

test('migrations serialize on one connection, commit and record checksums', async () => {
  const db = database();
  await applyMigrations(db, ['CREATE TABLE first_table (id INTEGER)', 'SELECT 42']);
  assert.equal(db.calls[0].sql, 'BEGIN');
  assert.match(db.calls[1].sql, /pg_advisory_xact_lock/);
  const inserts = db.calls.filter(call => call.sql.startsWith('INSERT'));
  assert.deepEqual(inserts.map(call => call.params[0]), [1, 2]);
  assert.equal(inserts[1].params[1], createHash('sha256').update('SELECT 42').digest('hex'));
  assert.equal(db.calls.at(-1).sql, 'COMMIT');
  assert.equal(db.released, true);
});

test('already applied migrations are checked and skipped', async () => {
  const statement = 'SELECT 42';
  const db = database([{version: 1, checksum: createHash('sha256').update(statement).digest('hex')}]);
  await applyMigrations(db, [statement, 'SELECT 43']);
  assert.equal(db.calls.some(call => call.sql === statement), false);
  assert.equal(db.calls.some(call => call.sql === 'SELECT 43'), true);
});

test('edited or removed applied migrations roll back before schema execution', async () => {
  for (const statements of [[], ['SELECT changed']]) {
    const db = database([{version: 1, checksum: '0'.repeat(64)}]);
    await assert.rejects(applyMigrations(db, statements), /history mismatch/);
    assert.equal(db.calls.at(-1).sql, 'ROLLBACK');
    assert.equal(db.calls.some(call => call.sql.startsWith('INSERT')), false);
    assert.equal(db.released, true);
  }
});

test('failed schema changes roll back and release their connection', async () => {
  const db = database([], 'SELECT broken');
  await assert.rejects(applyMigrations(db, ['SELECT 42', 'SELECT broken']), /injected failure/);
  assert.equal(db.calls.at(-1).sql, 'ROLLBACK');
  assert.equal(db.calls.some(call => call.sql === 'COMMIT'), false);
  assert.equal(db.released, true);
});

test('Postgres concurrent migration startup and failure rollback',
  {skip: !process.env.DATABASE_URL}, async () => {
    const {Pool} = require('pg');
    const {randomUUID} = require('node:crypto');
    const schema = `migration_test_${randomUUID().replaceAll('-', '')}`;
    const admin = new Pool({connectionString: process.env.DATABASE_URL});
    let pool;
    try {
      await admin.query(`CREATE SCHEMA ${schema}`);
      pool = new Pool({connectionString: process.env.DATABASE_URL,
        options: `-c search_path=${schema}`, max: 3});
      const initial = ['CREATE TABLE example (id INTEGER PRIMARY KEY)'];
      await Promise.all([applyMigrations(pool, initial), applyMigrations(pool, initial)]);
      assert.equal((await pool.query('SELECT * FROM schema_migrations')).rowCount, 1);
      await assert.rejects(applyMigrations(pool, [...initial,
        'ALTER TABLE example ADD COLUMN rolled_back TEXT',
        'SELECT missing_function_for_migration_test()']));
      assert.equal((await pool.query('SELECT * FROM schema_migrations')).rowCount, 1);
      assert.equal((await pool.query(`SELECT column_name FROM information_schema.columns
        WHERE table_schema=$1 AND table_name='example' AND column_name='rolled_back'`, [schema])).rowCount, 0);
      await applyMigrations(pool, [...initial, 'ALTER TABLE example ADD COLUMN recovered TEXT']);
      assert.equal((await pool.query('SELECT * FROM schema_migrations')).rowCount, 2);
      await assert.rejects(applyMigrations(pool, ['SELECT 42']), /history mismatch/);
    } finally {
      if (pool) await pool.end();
      await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
      await admin.end();
    }
  });
