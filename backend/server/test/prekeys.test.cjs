// Prekey validation and upload-side obligations (spec §4.2, §4.6).
// Runs against the disposable loopback Postgres (chhaya_test); DB-backed tests
// self-skip when DATABASE_URL is absent, matching the existing harness pattern.
process.env.PREKEYS_ENABLED = 'true';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, randomBytes, generateKeyPairSync, createPublicKey, diffieHellman, createHmac} = require('node:crypto');

const EC_KEY = () => randomBytes(32).toString('hex');
const PQ_KEY = () => randomBytes(1568).toString('hex'); // ML-KEM-1024 public key, 3136 hex
const SIG = () => randomBytes(64).toString('hex');
const DAY = 24 * 3600 * 1000;

const makeBundle = (x25519, over = {}) => ({
  v: 1,
  identity: {x25519, ed25519: EC_KEY()},
  signedPreKey: {keyId: randomUUID(), publicKey: EC_KEY(), signature: SIG(), notBefore: Date.now() - 1000, notAfter: Date.now() + 29 * DAY},
  pqSignedPreKey: {keyId: randomUUID(), publicKey: PQ_KEY(), signature: SIG(), notBefore: Date.now() - 1000, notAfter: Date.now() + 6 * DAY},
  oneTimePreKeys: [{keyId: randomUUID(), publicKey: EC_KEY(), signature: SIG()}],
  pqOneTimePreKeys: [{keyId: randomUUID(), publicKey: PQ_KEY(), signature: SIG()}],
  reseedKemKey: {publicKey: PQ_KEY(), signature: SIG()},
  ...over,
});

// Global limiter runs before routes and fails closed without an initialized DB,
// so this test needs the disposable loopback database even though prekeys are off.
test('PREKEYS_ENABLED=false returns 503 feature_disabled for all four routes',
  {skip: !process.env.DATABASE_URL}, async () => {
    const {initDb, closeDb} = require('../dist/db');
    const {config} = require('../dist/config');
    const {app} = require('../dist/index');
    await initDb();
    const server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}/api/v1`;
    const previous = config.PREKEYS_ENABLED;
    config.PREKEYS_ENABLED = false;
  try {
    // Authenticated caller: authMiddleware runs before the route gate,
    // so only a valid session reaches the flag check.
    const pair = generateKeyPairSync('x25519');
    const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
    const deviceId = randomUUID();
    const challengeResponse = await fetch(`${base}/auth/challenge`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({publicKey, deviceId, purpose: 'register'}),
    });
    const challenge = await challengeResponse.json();
    const key = createPublicKey({key: {kty: 'OKP', crv: 'X25519', x: Buffer.from(challenge.serverPublicKey, 'hex').toString('base64url')}, format: 'jwk'});
    const secret = diffieHellman({privateKey: pair.privateKey, publicKey: key});
    const context = `chhaya-auth-v1|register|${challenge.challengeId}|${deviceId}|${publicKey}|${challenge.serverPublicKey}|${challenge.nonce}`;
    const registerBody = {
      challengeId: challenge.challengeId,
      identityProof: createHmac('sha256', secret).update(context).digest('hex'),
      chhayaId: '05' + publicKey, publicKey, displayName: 'Flag Off',
      encryptedPrivateKey: 'encrypted-backup', recoveryPhraseHash: randomBytes(32).toString('hex'), deviceId,
    };
    secret.fill(0);
    const registeredResponse = await fetch(`${base}/auth/register`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(registerBody),
    });
    const registered = await registeredResponse.json();
    assert.ok(registered.token, `registration failed: ${JSON.stringify(registered)}`);
    const authHeaders = {'Content-Type': 'application/json', Authorization: `Bearer ${registered.token}`};
    const responses = await Promise.all([
      fetch(`${base}/prekeys`, {method: 'POST', headers: authHeaders, body: '{}'}),
      fetch(`${base}/prekeys/${randomUUID()}/bundle`, {headers: authHeaders}),
      fetch(`${base}/prekeys/rotate`, {method: 'POST', headers: authHeaders, body: '{}'}),
      fetch(`${base}/prekeys/mine/count`, {headers: authHeaders}),
    ]);
    for (const r of responses) {
      assert.equal(r.status, 503);
      assert.equal((await r.json()).error, 'feature_disabled');
    }
  } finally {
    config.PREKEYS_ENABLED = previous;
    await new Promise((resolve) => server.close(resolve));
    await closeDb();
  }
});

test('prekey migration is additive and represents public material only',
  {skip: !process.env.DATABASE_URL}, async () => {
    const {initDb, closeDb, query} = require('../dist/db');
    await initDb();
    try {
      const tables = await query(
        `SELECT table_name FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name LIKE 'prekey_%'`);
      assert.deepEqual(tables.rows.map((r) => r.table_name).sort(),
        ['prekey_account', 'prekey_one_time', 'prekey_signed']);
      const columns = await query(
        `SELECT table_name, column_name FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name LIKE 'prekey_%'`);
      for (const row of columns.rows) {
        assert.doesNotMatch(row.column_name, /private|secret|seed(?!_kem)/i,
          `column ${row.table_name}.${row.column_name} looks like private material`);
      }
    } finally {
      await closeDb();
    }
  });

const withHarness = (fn) => async () => {
  const {initDb, closeDb, query} = require('../dist/db');
  const {config} = require('../dist/config');
  const {app} = require('../dist/index');
  await initDb();
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/v1`;
  const req = async (method, path, body, token) => {
    const r = await fetch(base + path, {
      method,
      headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
      body: body ? JSON.stringify(body) : undefined,
    });
    return {status: r.status, data: await r.json().catch(() => null), headers: r.headers};
  };
  // Register a fresh account; returns {token, userId, x25519}.
  const signup = async () => {
    const pair = generateKeyPairSync('x25519');
    const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
    const body = {
      chhayaId: '05' + publicKey, publicKey, displayName: 'Prekey Test',
      encryptedPrivateKey: 'encrypted-backup', recoveryPhraseHash: randomBytes(32).toString('hex'),
      deviceId: randomUUID(),
    };
    const challenge = await req('POST', '/auth/challenge', {publicKey, deviceId: body.deviceId, purpose: 'register'});
    assert.equal(challenge.status, 200);
    const key = createPublicKey({key: {kty: 'OKP', crv: 'X25519', x: Buffer.from(challenge.data.serverPublicKey, 'hex').toString('base64url')}, format: 'jwk'});
    const secret = diffieHellman({privateKey: pair.privateKey, publicKey: key});
    const context = `chhaya-auth-v1|register|${challenge.data.challengeId}|${body.deviceId}|${publicKey}|${challenge.data.serverPublicKey}|${challenge.data.nonce}`;
    Object.assign(body, {challengeId: challenge.data.challengeId,
      identityProof: createHmac('sha256', secret).update(context).digest('hex')});
    secret.fill(0);
    const r = await req('POST', '/auth/register', body);
    assert.equal(r.status, 201);
    return {token: r.data.token, userId: r.data.userId, x25519: body.chhayaId};
  };
  // Clear this file's prekey buckets (IP candidates cover either remoteAddress form).
  const resetBuckets = async (userIds = []) => {
    const hmac = (v) => createHmac('sha256', config.JWT_SECRET).update(v).digest('hex');
    const identities = ['127.0.0.1', '::ffff:127.0.0.1', '::1']
      .map((ip) => `prekey:bundle:ip:${ip}`)
      // Global unauthenticated IP bucket (index.ts): test files share it; clearing it
      // prevents cross-test/cross-run 429s in the fixed window.
      .concat(['127.0.0.1', '::ffff:127.0.0.1', '::1'].map((ip) => ip))
      .concat(userIds.flatMap((id) => [`prekey:upload:${id}`, `prekey:rotate:${id}`, `prekey:count:${id}`, `prekey:bundle:target:${id}`]));
    for (const identity of identities) {
      await query('DELETE FROM rate_limits WHERE key = $1', [`api:${hmac(identity)}`]);
    }
  };
  try {
    await fn({req, signup, query, resetBuckets, base});
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await closeDb();
  }
};

test('upload rejects private-looking fields at any depth (422)',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const account = await signup();
    await resetBuckets([account.userId]);
    for (const mutate of [
      (b) => { b.privateKey = EC_KEY(); },
      (b) => { b.identity.private_key = EC_KEY(); },
      (b) => { b.oneTimePreKeys = [{keyId: randomUUID(), publicKey: EC_KEY(), signature: SIG(), secret: EC_KEY()}]; },
      (b) => { b.pqOneTimePreKeys = [{keyId: randomUUID(), publicKey: PQ_KEY(), signature: SIG(), seed: PQ_KEY()}]; },
      (b) => { b.decapsulationKey = PQ_KEY(); },
    ]) {
      const bundle = makeBundle(account.x25519);
      mutate(bundle);
      const r = await req('POST', '/prekeys', bundle, account.token);
      assert.equal(r.status, 422, JSON.stringify(r.data));
      assert.equal(r.data.error, 'private_material_rejected');
    }
    // Legitimate public field with a "seed" substring must NOT trip the filter.
    const ok = await req('POST', '/prekeys', makeBundle(account.x25519), account.token);
    assert.equal(ok.status, 200);
  }));

test('upload rejects malformed bundles (400)',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const account = await signup();
    const cases = [
      ['wrong version', (b) => { b.v = 2; }],
      ['short ec key', (b) => { b.signedPreKey.publicKey = EC_KEY().slice(2); }],
      ['short signature', (b) => { b.signedPreKey.signature = SIG().slice(2); }],
      ['pq public key wrong length', (b) => { b.pqSignedPreKey.publicKey = EC_KEY(); }],
      ['pq window over 7 days', (b) => { b.pqSignedPreKey.notAfter = b.pqSignedPreKey.notBefore + 8 * DAY; }],
      ['ec window over 30 days', (b) => { b.signedPreKey.notAfter = b.signedPreKey.notBefore + 31 * DAY; }],
      ['empty window', (b) => { b.signedPreKey.notAfter = b.signedPreKey.notBefore; }],
      ['unknown extra field', (b) => { b.surprise = 1; }],
      ['malformed key id', (b) => { b.signedPreKey.keyId = 'not-a-uuid'; }],
      ['uppercase hex', (b) => { b.signedPreKey.publicKey = b.signedPreKey.publicKey.toUpperCase(); }],
    ];
    for (const [name, mutate] of cases) {
      await resetBuckets([account.userId]);
      const bundle = makeBundle(account.x25519);
      mutate(bundle);
      const r = await req('POST', '/prekeys', bundle, account.token);
      assert.equal(r.status, 400, `${name}: expected 400, got ${r.status} ${JSON.stringify(r.data)}`);
    }
  }));

test('upload rejects identity not matching the caller (400)',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const account = await signup();
    const other = await signup();
    await resetBuckets([account.userId]);
    const r = await req('POST', '/prekeys', makeBundle(other.x25519), account.token);
    assert.equal(r.status, 400);
    assert.equal(r.data.error, 'identity_mismatch');
  }));

test('valid upload is idempotent: re-post inserts zero one-time rows and rotates signed in place',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, query, resetBuckets}) => {
    const account = await signup();
    await resetBuckets([account.userId]);
    const bundle = makeBundle(account.x25519);
    const first = await req('POST', '/prekeys', bundle, account.token);
    assert.equal(first.status, 200);
    assert.deepEqual(first.data.oneTimeInserted, {ec: 1, pq: 1});
    const second = await req('POST', '/prekeys', bundle, account.token);
    assert.equal(second.status, 200);
    assert.deepEqual(second.data.oneTimeInserted, {ec: 0, pq: 0});
    const signed = await query('SELECT kind, COUNT(*)::int AS n FROM prekey_signed WHERE user_id = $1 GROUP BY kind', [account.userId]);
    assert.deepEqual(Object.fromEntries(signed.rows.map((r) => [r.kind, r.n])), {ec: 1, pq: 1});
    const oneTime = await query('SELECT COUNT(*)::int AS n FROM prekey_one_time WHERE user_id = $1', [account.userId]);
    assert.equal(oneTime.rows[0].n, 2);
  }));

test('rate-limit buckets are HMAC-hashed; no raw IP is persisted',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, query, resetBuckets}) => {
    const account = await signup();
    await resetBuckets([account.userId]);
    const r = await req('POST', '/prekeys', makeBundle(account.x25519), account.token);
    assert.equal(r.status, 200);
    const rows = await query('SELECT key FROM rate_limits');
    assert.ok(rows.rowCount > 0);
    for (const row of rows.rows) {
      assert.match(row.key, /^api:[0-9a-f]{64}$/);
      assert.doesNotMatch(row.key, /127\.0\.0\.1|::1/);
    }
  }));
