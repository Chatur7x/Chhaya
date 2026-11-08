// Prekey bundle fetch and atomic-pop obligations (spec §4.2–§4.6).
// Disposable loopback Postgres (chhaya_test); DB-backed tests self-skip without DATABASE_URL.
process.env.PREKEYS_ENABLED = 'true';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, randomBytes, generateKeyPairSync, createPublicKey, diffieHellman, createHmac} = require('node:crypto');

const EC_KEY = () => randomBytes(32).toString('hex');
const PQ_KEY = () => randomBytes(1568).toString('hex');
const SIG = () => randomBytes(64).toString('hex');
const DAY = 24 * 3600 * 1000;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
  const signup = async () => {
    const pair = generateKeyPairSync('x25519');
    const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
    const body = {
      chhayaId: '05' + publicKey, publicKey, displayName: 'Prekey Bundle Test',
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

// Recursively collect object keys — used to prove no private-material field leaks into responses.
const collectKeys = (value, prefix = '') => {
  if (!value || typeof value !== 'object') return [];
  return Object.entries(value).flatMap(([key, child]) => [`${prefix}${key}`, ...collectKeys(child, `${prefix}${key}.`)]);
};

test('bundle fetch returns public identity + signed keys, pops exactly one PQOPK and one OPK; second fetch falls back to last-resort with flag',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const owner = await signup();
    const peer = await signup();
    await resetBuckets([owner.userId, peer.userId]);
    const bundle = makeBundle(owner.x25519);
    assert.equal((await req('POST', '/prekeys', bundle, owner.token)).status, 200);

    const first = await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token);
    assert.equal(first.status, 200);
    assert.equal(first.data.v, 1);
    assert.equal(first.data.identity.x25519, owner.x25519);
    assert.match(first.data.identity.ed25519, /^[0-9a-f]{64}$/);
    assert.equal(first.data.signedPreKey.keyId, bundle.signedPreKey.keyId);
    assert.equal(first.data.pqSignedPreKey.keyId, bundle.pqSignedPreKey.keyId);
    assert.equal(first.data.pqOneTimePreKey.keyId, bundle.pqOneTimePreKeys[0].keyId);
    assert.equal(first.data.oneTimePreKey.keyId, bundle.oneTimePreKeys[0].keyId);
    assert.equal(first.data.lastResortUsed, false);
    assert.match(first.data.reseedKemKey.publicKey, /^[0-9a-f]{3136}$/);
    // Public response: no private-looking key names anywhere in the payload.
    const keys = collectKeys(first.data).join(' ');
    assert.doesNotMatch(keys, /private|secret|seedkey|decap/i);

    const second = await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token);
    assert.equal(second.status, 200);
    assert.equal(second.data.pqOneTimePreKey, null);
    assert.equal(second.data.oneTimePreKey, null);
    assert.equal(second.data.lastResortUsed, true);
    // Last-resort PQSPK is still served (within its window) with the flag set.
    assert.equal(second.data.pqSignedPreKey.keyId, bundle.pqSignedPreKey.keyId);
  }));

test('20 concurrent bundle fetches pop 20 distinct PQOPKs (none falls back)',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const owner = await signup();
    const peer = await signup();
    await resetBuckets([owner.userId, peer.userId]);
    const bundle = makeBundle(owner.x25519, {
      oneTimePreKeys: [],
      pqOneTimePreKeys: Array.from({length: 20}, () => ({keyId: randomUUID(), publicKey: PQ_KEY(), signature: SIG()})),
    });
    assert.equal((await req('POST', '/prekeys', bundle, owner.token)).status, 200);

    const responses = await Promise.all(
      Array.from({length: 20}, () => req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token)),
    );
    const popped = [];
    for (const r of responses) {
      assert.equal(r.status, 200);
      assert.equal(r.data.lastResortUsed, false);
      assert.ok(r.data.pqOneTimePreKey, 'expected a popped PQOPK, got last-resort');
      popped.push(r.data.pqOneTimePreKey.keyId);
    }
    assert.equal(new Set(popped).size, 20, 'concurrent fetches must pop distinct PQOPKs');
  }));

test('last-resort expired yields 409 pq_last_resort_expired; boundary is respected',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, query, resetBuckets}) => {
    const owner = await signup();
    const peer = await signup();
    await resetBuckets([owner.userId, peer.userId]);
    const bundle = makeBundle(owner.x25519, {oneTimePreKeys: [], pqOneTimePreKeys: []});
    assert.equal((await req('POST', '/prekeys', bundle, owner.token)).status, 200);

    // Move the last-resort window boundary into the near future, then past it.
    await query("UPDATE prekey_signed SET not_after = NOW() + INTERVAL '1500 milliseconds' WHERE user_id = $1 AND kind = 'pq'", [owner.userId]);
    const inWindow = await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token);
    assert.equal(inWindow.status, 200); // boundary not yet crossed: served with lastResortUsed
    await sleep(1600);
    const expired = await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token);
    assert.equal(expired.status, 409);
    assert.equal(expired.data.error, 'pq_last_resort_expired');
  }));

test('rotation: rotated signed prekey is served immediately; previous row is retained for the grace window',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, query, resetBuckets}) => {
    const owner = await signup();
    const peer = await signup();
    await resetBuckets([owner.userId, peer.userId]);
    const original = makeBundle(owner.x25519, {oneTimePreKeys: [], pqOneTimePreKeys: []});
    assert.equal((await req('POST', '/prekeys', original, owner.token)).status, 200);

    const rotated = {signedPreKey: {...original.signedPreKey, keyId: randomUUID(), publicKey: EC_KEY(), signature: SIG()}};
    const rotateResponse = await req('POST', '/prekeys/rotate', rotated, owner.token);
    assert.equal(rotateResponse.status, 200);
    assert.equal(rotateResponse.data.signedPreKey.keyId, rotated.signedPreKey.keyId);
    assert.equal(typeof rotateResponse.data.signedPreKey.notAfter, 'number');

    const fetched = await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token);
    assert.equal(fetched.status, 200);
    assert.equal(fetched.data.signedPreKey.keyId, rotated.signedPreKey.keyId);

    // Previous row retained (7-day grace), not served to new fetches.
    const rows = await query("SELECT key_id FROM prekey_signed WHERE user_id = $1 AND kind = 'ec' ORDER BY not_before", [owner.userId]);
    assert.deepEqual(rows.rows.map((r) => r.key_id).sort(), [original.signedPreKey.keyId, rotated.signedPreKey.keyId].sort());

    // reseedKemKey rotation works and preserves the ed25519 identity row.
    const reseed = {reseedKemKey: {publicKey: PQ_KEY(), signature: SIG()}};
    assert.equal((await req('POST', '/prekeys/rotate', reseed, owner.token)).data.reseedKemKeyRotated, true);
    assert.equal((await req('POST', '/prekeys/rotate', {}, owner.token)).status, 400);

    const count = await req('GET', '/prekeys/mine/count', null, owner.token);
    assert.equal(count.status, 200);
    assert.equal(count.data.signedAgeDays.ec, 0);
    assert.equal(count.data.signedAgeDays.pq, 0);
    assert.equal(count.data.pqLastResort.present, true);
  }));

test('bundle rate limit: 61st fetch in a minute is 429 with Retry-After',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const owner = await signup();
    const peer = await signup();
    await resetBuckets([owner.userId, peer.userId]);
    const bundle = makeBundle(owner.x25519, {oneTimePreKeys: [], pqOneTimePreKeys: []});
    assert.equal((await req('POST', '/prekeys', bundle, owner.token)).status, 200);
    await resetBuckets([owner.userId, peer.userId]);

    let last;
    for (let i = 0; i < 61; i++) last = await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token);
    assert.equal(last.status, 429);
    assert.ok(last.headers.get('retry-after'), 'Retry-After header must be present');
  }));

test('upload rate limit: 31st upload in an hour is 429',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const account = await signup();
    await resetBuckets([account.userId]);
    const bundle = () => makeBundle(account.x25519, {oneTimePreKeys: [], pqOneTimePreKeys: []});
    let last;
    for (let i = 0; i < 31; i++) last = await req('POST', '/prekeys', bundle(), account.token);
    assert.equal(last.status, 429);
    assert.ok(last.headers.get('retry-after'));
  }));

test('rotate rate limit: 11th rotation in an hour is 429',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const owner = await signup();
    await resetBuckets([owner.userId]);
    assert.equal((await req('POST', '/prekeys', makeBundle(owner.x25519, {oneTimePreKeys: [], pqOneTimePreKeys: []}), owner.token)).status, 200);
    await resetBuckets([owner.userId]);
    let last;
    for (let i = 0; i < 11; i++) {
      last = await req('POST', '/prekeys/rotate', {reseedKemKey: {publicKey: PQ_KEY(), signature: SIG()}}, owner.token);
    }
    assert.equal(last.status, 429);
    assert.ok(last.headers.get('retry-after'));
  }));

test('unauthenticated requests are denied (401) on all four routes',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req}) => {
    const id = randomUUID();
    assert.equal((await req('POST', '/prekeys', {})).status, 401);
    assert.equal((await req('GET', `/prekeys/${id}/bundle`)).status, 401);
    assert.equal((await req('POST', '/prekeys/rotate', {})).status, 401);
    assert.equal((await req('GET', '/prekeys/mine/count')).status, 401);
  }));

test('cross-account: unknown target 404 with non-enumerating body; uploader identity cannot bind another account; counts do not leak',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const alice = await signup();
    const bob = await signup();
    await resetBuckets([alice.userId, bob.userId]);
    // Unknown target (well-formed uuid) and malformed id both return the same body.
    const unknown = await req('GET', `/prekeys/${randomUUID()}/bundle`, null, alice.token);
    assert.equal(unknown.status, 404);
    assert.equal(unknown.data.error, 'prekey_bundle_unavailable');
    const malformed = await req('GET', '/prekeys/not-a-uuid/bundle', null, alice.token);
    assert.equal(malformed.status, 404);
    assert.equal(malformed.data.error, 'prekey_bundle_unavailable');
    // Known user without an uploaded bundle is indistinguishable from unknown.
    const noBundle = await req('GET', `/prekeys/${bob.userId}/bundle`, null, alice.token);
    assert.equal(noBundle.status, 404);
    assert.equal(noBundle.data.error, 'prekey_bundle_unavailable');

    assert.equal((await req('POST', '/prekeys', makeBundle(alice.x25519), alice.token)).status, 200);
    // Bob's counts are unaffected by Alice's upload.
    const bobCount = await req('GET', '/prekeys/mine/count', null, bob.token);
    assert.equal(bobCount.status, 200);
    assert.deepEqual(bobCount.data, {
      ecOneTime: 0, pqOneTime: 0,
      pqLastResort: {present: false, notAfter: null},
      signedAgeDays: {ec: null, pq: null},
    });
  }));

test('mine/count is accurate after uploads and pops',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, resetBuckets}) => {
    const owner = await signup();
    const peer = await signup();
    await resetBuckets([owner.userId, peer.userId]);
    const bundle = makeBundle(owner.x25519, {
      oneTimePreKeys: Array.from({length: 3}, () => ({keyId: randomUUID(), publicKey: EC_KEY(), signature: SIG()})),
      pqOneTimePreKeys: Array.from({length: 2}, () => ({keyId: randomUUID(), publicKey: PQ_KEY(), signature: SIG()})),
    });
    assert.equal((await req('POST', '/prekeys', bundle, owner.token)).status, 200);
    let count = await req('GET', '/prekeys/mine/count', null, owner.token);
    assert.equal(count.data.ecOneTime, 3);
    assert.equal(count.data.pqOneTime, 2);

    assert.equal((await req('GET', `/prekeys/${owner.userId}/bundle`, null, peer.token)).status, 200);
    count = await req('GET', '/prekeys/mine/count', null, owner.token);
    assert.equal(count.data.ecOneTime, 2);
    assert.equal(count.data.pqOneTime, 1);
    assert.equal(count.data.pqLastResort.present, true);
    assert.equal(typeof count.data.pqLastResort.notAfter, 'number');
  }));

test('stored rows contain no private material (column and value inspection)',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup, query, resetBuckets}) => {
    const owner = await signup();
    await resetBuckets([owner.userId]);
    assert.equal((await req('POST', '/prekeys', makeBundle(owner.x25519), owner.token)).status, 200);

    for (const table of ['prekey_signed', 'prekey_one_time', 'prekey_account']) {
      const columns = await query(
        `SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1`, [table]);
      for (const row of columns.rows) assert.doesNotMatch(row.column_name, /private|secret|seed(?!_kem)/i);
    }
    const signed = await query('SELECT public_key, signature FROM prekey_signed WHERE user_id = $1', [owner.userId]);
    for (const row of signed.rows) {
      assert.ok([64, 3136].includes(row.public_key.length));
      assert.equal(row.signature.length, 128);
    }
    const oneTime = await query('SELECT public_key, signature FROM prekey_one_time WHERE user_id = $1', [owner.userId]);
    for (const row of oneTime.rows) {
      assert.ok([64, 3136].includes(row.public_key.length));
      assert.equal(row.signature.length, 128);
    }
    const account = await query('SELECT ed25519_public_key, reseed_kem_public_key, reseed_kem_signature FROM prekey_account WHERE user_id = $1', [owner.userId]);
    assert.equal(account.rows[0].ed25519_public_key.length, 64);
    assert.equal(account.rows[0].reseed_kem_public_key.length, 3136);
    assert.equal(account.rows[0].reseed_kem_signature.length, 128);
  }));

test('store-and-forward: resync-type envelope round-trips unchanged through post/fetch (opaque content)',
  {skip: !process.env.DATABASE_URL}, withHarness(async ({req, signup}) => {
    const alice = await signup();
    const bob = await signup();
    const contact = await req('POST', '/contacts', {chhayaId: bob.x25519, displayName: 'Bob'}, alice.token);
    assert.equal(contact.status, 201);
    const conversationId = contact.data.conversationId;

    const resyncEnvelope = JSON.stringify({type: 'chhaya-resync-v1', restore_generation: randomUUID(), session_generation: 41, reason: 'restore', v: 1});
    const posted = await req('POST', '/messages', {conversationId, content: resyncEnvelope, messageType: 'text'}, alice.token);
    assert.equal(posted.status, 201);

    const inbox = await req('GET', `/messages/${conversationId}`, null, bob.token);
    assert.equal(inbox.status, 200);
    const messages = Array.isArray(inbox.data) ? inbox.data : inbox.data.messages;
    const match = messages.find((m) => m.content === resyncEnvelope);
    assert.ok(match, 'resync envelope must arrive byte-identical and opaque to the server');
  }));
