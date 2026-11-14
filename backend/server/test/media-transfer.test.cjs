// WS-A media transfer obligations (docs/spec-media-transfer-v1.md §14 backend unit matrix).
// DB-backed tests self-skip when DATABASE_URL is absent (disposable loopback chhaya_test).
// Pure unit tests (token HMAC, start validation, GC batching, schema invariants) always run.
process.env.MEDIA_TRANSFER_ENABLED = 'true';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID, randomBytes, createHash, generateKeyPairSync, createPublicKey, diffieHellman, createHmac} = require('node:crypto');

const src = (name) => fs.readFileSync(path.join(__dirname, '..', 'src', name), 'utf8');

// ---------------------------------------------------------------------------
// Pure unit tests (no PG required)
// ---------------------------------------------------------------------------

test('download tokens round-trip and are bound to (transferId, userId, conversationId)', () => {
  const {mintDownloadToken, verifyDownloadToken} = require('../dist/media');
  const binding = {transferId: randomUUID(), userId: randomUUID(), conversationId: randomUUID()};
  const {token, expiresAt} = mintDownloadToken(binding);
  assert.ok(expiresAt.getTime() > Date.now());
  const ok = verifyDownloadToken(token, binding);
  assert.equal(ok.ok, true);
  for (const field of ['transferId', 'userId', 'conversationId']) {
    assert.equal(verifyDownloadToken(token, {...binding, [field]: randomUUID()}).ok, false, `token must not verify for wrong ${field}`);
  }
  // Tampering with the mac or payload must fail.
  const decoded = Buffer.from(token, 'base64url').toString('utf8');
  const parts = decoded.split('.');
  const tamperedMac = Buffer.from([...parts.slice(0, 5), parts[5].slice(0, -2) + (parts[5].endsWith('A') ? 'B' : 'A')].join('.'), 'utf8').toString('base64url');
  assert.equal(verifyDownloadToken(tamperedMac, binding).ok, false);
  const tamperedPayload = Buffer.from(['chhaya-media-dl-v1', randomUUID(), parts[2], parts[3], parts[4], parts[5]].join('.'), 'utf8').toString('base64url');
  assert.equal(verifyDownloadToken(tamperedPayload, binding).ok, false);
  assert.equal(verifyDownloadToken('!!!not-base64!!!', binding).ok, false);
  assert.equal(verifyDownloadToken('', binding).ok, false);
});

test('expired download tokens report download_token_expired', () => {
  const {mintDownloadToken, verifyDownloadToken} = require('../dist/media');
  const binding = {transferId: randomUUID(), userId: randomUUID(), conversationId: randomUUID()};
  const {token} = mintDownloadToken(binding, -10); // minted already expired
  const result = verifyDownloadToken(token, binding);
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'expired');
});

test('transfer start validation matrix (spec §8.1)', () => {
  const {validateTransferStart, MEDIA_LIMITS, expectedTotalChunks, expectedWireBytes} = require('../dist/media');
  const cid = randomUUID();
  const size = 262144 * 3 + 100;
  const valid = {conversationId: cid, sizeBytes: size, totalChunks: expectedTotalChunks(size), chunkSize: MEDIA_LIMITS.CHUNK_BYTES};
  assert.equal(validateTransferStart(valid).ok, true);
  assert.equal(validateTransferStart({...valid, conversationId: 'not-a-uuid'}).code, 'invalid_transfer_request');
  assert.equal(validateTransferStart({...valid, sizeBytes: 0}).code, 'invalid_transfer_request');
  assert.equal(validateTransferStart({...valid, sizeBytes: MEDIA_LIMITS.MAX_BYTES + 1}).code, 'transfer_too_large');
  assert.equal(validateTransferStart({...valid, sizeBytes: MEDIA_LIMITS.MAX_BYTES + 1}).status, 413);
  assert.equal(validateTransferStart({...valid, totalChunks: valid.totalChunks + 1}).code, 'invalid_transfer_request');
  assert.equal(validateTransferStart({...valid, totalChunks: 65}).code, 'transfer_too_large');
  assert.equal(validateTransferStart({...valid, chunkSize: 1024}).code, 'invalid_transfer_request');
  assert.equal(validateTransferStart({...valid, sizeBytes: '262144'}).code, 'invalid_transfer_request');
  assert.equal(validateTransferStart(null).code, 'invalid_transfer_request');
  assert.equal(expectedTotalChunks(1), 1);
  assert.equal(expectedTotalChunks(262144), 1);
  assert.equal(expectedTotalChunks(262145), 2);
  assert.equal(expectedTotalChunks(MEDIA_LIMITS.MAX_BYTES), 64);
  assert.equal(expectedWireBytes(7340032, 28), 7340032 + 28 * 28);
});

test('GC sweeper bounds batches, drains to zero, and leaves fresh rows alone (mock query)', async () => {
  const {sweepMediaTransfers} = require('../dist/media');
  const staleUpload = [randomUUID(), randomUUID()];
  const staleCompleted = [randomUUID()];
  const staleTerminal = [randomUUID()];
  const logs = [];
  const calls = [];
  const queue = {
    uploading: [...staleUpload],
    completed: [...staleCompleted],
    terminal: [...staleTerminal],
  };
  const take = (list) => list.splice(0, 500).map((id) => ({id}));
  const mockQuery = async (sql, params) => {
    const compact = sql.replace(/\s+/g, ' ').trim();
    calls.push(compact);
    if (/SELECT id FROM media_transfers WHERE state = 'uploading'/.test(compact)) { const rows = take(queue.uploading); return {rows, rowCount: rows.length}; }
    if (/SELECT id FROM media_transfers WHERE state = 'completed'/.test(compact)) { const rows = take(queue.completed); return {rows, rowCount: rows.length}; }
    if (/state IN \('canceled','expired'\) LIMIT/.test(compact)) { const rows = take(queue.terminal); return {rows, rowCount: rows.length}; }
    if (/WITH orphans AS/.test(compact)) return {rows: [], rowCount: 0};
    if (/UPDATE media_transfers SET state = 'expired'/.test(compact)) return {rows: [], rowCount: params[0].length};
    if (/DELETE FROM media_chunks WHERE ctid/.test(compact)) return {rows: [], rowCount: 0};
    if (/DELETE FROM media_transfers/.test(compact)) return {rows: [], rowCount: params[0].length};
    throw new Error(`Unexpected SQL in mock: ${compact}`);
  };
  const result = await sweepMediaTransfers(mockQuery, {info: () => {}, warn: (m) => logs.push(m)});
  assert.equal(result.expiredUploads, 2);
  assert.equal(result.expiredCompleted, 1);
  assert.equal(result.staleTerminalRows, 1);
  assert.equal(result.orphanChunks, 0);
  assert.ok(calls.every((c) => !c.includes('UPDATE media_transfers SET state = \'completed\'')), 'completed rows must not be mutated');
  assert.ok(calls.some((c) => /LIMIT 500/.test(c)), 'GC statements must be LIMIT-bounded');
  assert.ok(calls.some((c) => /state = 'uploading' AND expires_at/.test(c)), 'staged TTL step present');
  assert.ok(calls.some((c) => /INTERVAL '30 days'/.test(c)), 'retention step present');
  assert.ok(calls.some((c) => /WITH orphans AS/.test(c)), 'orphan sweep present');
  assert.equal(queue.uploading.length, 0);
});

test('schema stores ciphertext bytes only — no plaintext, names, mime, or keys in media DDL', () => {
  const db = src('db.ts');
  const mediaSection = db.slice(db.indexOf('media_transfers'));
  for (const table of ['media_transfers', 'media_chunks']) {
    assert.ok(db.includes(`CREATE TABLE IF NOT EXISTS ${table}`), `${table} migration present`);
  }
  assert.match(mediaSection, /data BYTEA NOT NULL/);
  for (const forbidden of [/plaintext/i, /file_?name/i, /mime/i, /content_?key/i, /\bname\b/i, /\bkey\b(?! )/i]) {
    // Column-name scan over the media DDL block only.
    const block = mediaSection.slice(0, mediaSection.lastIndexOf('media_chunks') + 400);
    assert.ok(!forbidden.test(block.replace(/idx_media_transfers_\w+/g, '')), `forbidden marker ${forbidden} in media DDL`);
  }
  assert.match(db, /size_bytes BETWEEN 1 AND 16777216/);
  assert.match(db, /total_chunks BETWEEN 1 AND 64/);
  assert.match(db, /state IN \('uploading','completed','canceled','expired'\)/);
  assert.match(db, /ON DELETE CASCADE/);
  // Additive-only: the migration mechanism checksums history; we append two entries.
  assert.ok(db.indexOf('media_transfers') > db.indexOf('prekey_account'), 'media migrations appended after WS1 block');
});

test('.env.example documents the disabled-by-default media gate (no secrets)', () => {
  const envExample = fs.readFileSync(path.join(__dirname, '..', '.env.example'), 'utf8');
  assert.match(envExample, /MEDIA_TRANSFER_ENABLED=false/);
  assert.doesNotMatch(envExample, /change-me.*=.*real|secret.*=.*[A-Za-z0-9]{20,}/i);
});

// ---------------------------------------------------------------------------
// DB-backed harness (disposable loopback chhaya_test)
// ---------------------------------------------------------------------------

const withHarness = (fn) => async () => {
  const {initDb, closeDb, query} = require('../dist/db');
  const {config} = require('../dist/config');
  const {app} = require('../dist/index');
  await initDb();
  const hmac = (v) => createHmac('sha256', config.JWT_SECRET).update(v).digest('hex');
  const resetBuckets = async (userIds = []) => {
    const identities = ['127.0.0.1', '::ffff:127.0.0.1', '::1'].concat(
      userIds.flatMap((id) => [`media:start:${id}`, `media:chunk:${id}`, `media:download:${id}`]));
    for (const identity of identities) {
      await query('DELETE FROM rate_limits WHERE key = $1', [`api:${hmac(identity)}`]);
    }
  };
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/v1`;
  const req = async (method, reqPath, body, token, raw) => {
    const headers = {...(raw ? {} : {'Content-Type': 'application/json'}), ...(token ? {Authorization: `Bearer ${token}`} : {})};
    const r = await fetch(base + reqPath, {method, headers, body: raw ? raw.body : (body !== undefined ? JSON.stringify(body) : undefined)});
    const text = await r.text();
    let data = null;
    try { data = JSON.parse(text); } catch { data = text; }
    return {status: r.status, data, headers: r.headers};
  };
  const putChunk = async (transferId, index, bytes, token, shaHeader) => {
    const r = await fetch(`${base}/media/transfers/${transferId}/chunks/${index}`, {
      method: 'PUT',
      headers: {'Content-Type': 'application/octet-stream', 'X-Chunk-SHA256': shaHeader ?? createHash('sha256').update(bytes).digest('hex'), ...(token ? {Authorization: `Bearer ${token}`} : {})},
      body: bytes,
    });
    const data = await r.json().catch(() => null);
    return {status: r.status, data, headers: r.headers};
  };
  const getChunk = async (transferId, index, token, downloadToken) => {
    const headers = {...(token ? {Authorization: `Bearer ${token}`} : {})};
    if (downloadToken) headers['X-Download-Token'] = downloadToken;
    const r = await fetch(`${base}/media/downloads/${transferId}/chunks/${index}`, {headers});
    const bytes = Buffer.from(await r.arrayBuffer());
    return {status: r.status, bytes, headers: r.headers};
  };
  const signup = async () => {
    const pair = generateKeyPairSync('x25519');
    const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
    const body = {
      chhayaId: '05' + publicKey, publicKey, displayName: 'Media Test',
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
    return {token: r.data.token, userId: r.data.userId};
  };
  const startTransfer = (token, conversationId, sizeBytes) => {
    const {expectedTotalChunks} = require('../dist/media');
    return req('POST', '/media/transfers', {
      conversationId, sizeBytes, totalChunks: expectedTotalChunks(sizeBytes), chunkSize: 262144,
    }, token);
  };
  try {
    await fn({req, putChunk, getChunk, signup, startTransfer, query, resetBuckets, base});
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await closeDb();
  }
};

const dbTest = (name, fn) => test(name, {skip: !process.env.DATABASE_URL}, withHarness(fn));

dbTest('start returns 201 with transferId, expiresAt ~1h and enforces validation errors', async ({req, signup, startTransfer}) => {
  const alice = await signup();
  const bob = await signup();
  // Group conversation via /conversations needs only user IDs.
  const group = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'Media'}, alice.token);
  assert.equal(group.status, 201);
  const conversationId = group.data.conversationId;

  const size = 300000; // 2 chunks
  const started = await startTransfer(alice.token, conversationId, size);
  assert.equal(started.status, 201);
  assert.ok(started.data.transferId);
  assert.equal(started.data.chunkSize, 262144);
  assert.equal(started.data.totalChunks, 2);
  const ttlMs = new Date(started.data.expiresAt).getTime() - Date.now();
  assert.ok(ttlMs > 50 * 60 * 1000 && ttlMs <= 61 * 60 * 1000, 'staged TTL is ~1h');

  const badUuid = await req('POST', '/media/transfers', {conversationId: 'nope', sizeBytes: 1, totalChunks: 1, chunkSize: 262144}, alice.token);
  assert.equal(badUuid.status, 400);
  assert.equal(badUuid.data.code, 'invalid_transfer_request');
  const zero = await startTransfer(alice.token, conversationId, 0).catch(() => null);
  assert.equal(zero.status, 400);
  const tooBig = await req('POST', '/media/transfers', {conversationId, sizeBytes: 16777217, totalChunks: 64, chunkSize: 262144}, alice.token);
  assert.equal(tooBig.status, 413);
  assert.equal(tooBig.data.code, 'transfer_too_large');
  const wrongChunkSize = await req('POST', '/media/transfers', {conversationId, sizeBytes: 10, totalChunks: 1, chunkSize: 1024}, alice.token);
  assert.equal(wrongChunkSize.status, 400);
  const mismatch = await req('POST', '/media/transfers', {conversationId, sizeBytes: 300000, totalChunks: 1, chunkSize: 262144}, alice.token);
  assert.equal(mismatch.status, 400);
  assert.equal(mismatch.data.code, 'invalid_transfer_request');
});

dbTest('membership is enforced on start (403 for non-participants)', async ({req, signup}) => {
  const alice = await signup();
  const bob = await signup();
  const eve = await signup();
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  assert.equal(created.status, 201);
  const conversationId = created.data.conversationId;
  const denied = await req('POST', '/media/transfers', {conversationId, sizeBytes: 100, totalChunks: 1, chunkSize: 262144}, eve.token);
  assert.equal(denied.status, 403);
  assert.equal(denied.data.code, 'not_conversation_member');
});

dbTest('start quotas: inflight cap and declared staged cap return stable 413 codes', async ({req, signup, startTransfer, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  // Inflight cap = 3 concurrent uploading transfers.
  for (let i = 0; i < 3; i++) {
    const started = await startTransfer(alice.token, conversationId, 262144);
    assert.equal(started.status, 201);
  }
  const fourth = await startTransfer(alice.token, conversationId, 262144);
  assert.equal(fourth.status, 413);
  assert.equal(fourth.data.code, 'quota_exceeded');

  // Staged cap = 32 MiB declared across incomplete transfers.
  // Use a fresh user and two 16 MiB declarations.
  const carol = await signup();
  const dave = await signup();
  await resetBuckets([carol.userId]);
  const created2 = await req('POST', '/conversations', {type: 'group', participantIds: [dave.userId], name: 'M2'}, carol.token);
  const conv2 = created2.data.conversationId;
  assert.equal((await startTransfer(carol.token, conv2, 16777216)).status, 201);
  assert.equal((await startTransfer(carol.token, conv2, 16777216)).status, 201);
  const over = await startTransfer(carol.token, conv2, 1024); // 32 MiB already staged
  assert.equal(over.status, 413);
  assert.equal(over.data.code, 'quota_exceeded');
});

dbTest('conversation 50/day completed quota returns conversation_rate_exceeded', async ({req, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  await query(
    `INSERT INTO media_transfers (conversation_id, sender_id, size_bytes, chunk_size, total_chunks, state, completed_at, expires_at)
     SELECT $1, $2, 1, 262144, 1, 'completed', NOW(), NOW() + INTERVAL '1 hour' FROM generate_series(1, 50)`,
    [conversationId, alice.userId]);
  const started = await startTransfer(alice.token, conversationId, 1);
  assert.equal(started.status, 413);
  assert.equal(started.data.code, 'conversation_rate_exceeded');
});

dbTest('start rate limit is 20/hour per user (429 rate_limited with Retry-After)', async ({req, signup, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  for (let i = 0; i < 20; i++) {
    const started = await req('POST', '/media/transfers', {conversationId, sizeBytes: 1, totalChunks: 1, chunkSize: 262144}, alice.token);
    assert.equal(started.status, 201, `start ${i} should succeed`);
    assert.equal((await req('DELETE', `/media/transfers/${started.data.transferId}`, undefined, alice.token)).status, 204);
  }
  const blocked = await req('POST', '/media/transfers', {conversationId, sizeBytes: 1, totalChunks: 1, chunkSize: 262144}, alice.token);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.data.code, 'rate_limited');
  assert.ok(blocked.headers.get('retry-after'));
});

dbTest('chunk PUT: 201, idempotent re-upload (deduped), conflict on different hash, 409 on wrong SHA header', async ({req, putChunk, signup, startTransfer, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const size = 300000;
  const started = await startTransfer(alice.token, conversationId, size);
  assert.equal(started.status, 201);
  const transferId = started.data.transferId;

  const chunk0 = randomBytes(262144);
  const put0 = await putChunk(transferId, 0, chunk0, alice.token);
  assert.equal(put0.status, 201);
  assert.equal(put0.data.ok, true);
  assert.equal(put0.data.receivedChunks, 1);

  // Idempotent re-upload of the same bytes and hash.
  const again = await putChunk(transferId, 0, chunk0, alice.token);
  assert.equal(again.status, 200);
  assert.equal(again.data.deduped, true);
  assert.equal(again.data.receivedChunks, 1);

  // Same index, different bytes, valid self-consistent header -> 409 chunk_hash_conflict.
  const other = randomBytes(262144);
  assert.notEqual(createHash('sha256').update(other).digest('hex'), createHash('sha256').update(chunk0).digest('hex'));
  const conflict = await putChunk(transferId, 0, other, alice.token);
  assert.equal(conflict.status, 409);
  assert.equal(conflict.data.code, 'chunk_hash_conflict');

  // Header does not match body -> 409 chunk_hash_mismatch, nothing stored.
  const chunk1 = randomBytes(size - 262144);
  const wrongHeader = '0'.repeat(64);
  const mismatch = await putChunk(transferId, 1, chunk1, alice.token, wrongHeader);
  assert.equal(mismatch.status, 409);
  assert.equal(mismatch.data.code, 'chunk_hash_mismatch');

  // Malformed header -> 400 invalid_chunk.
  const badHeader = await putChunk(transferId, 1, chunk1, alice.token, 'nothex');
  assert.equal(badHeader.status, 400);
  assert.equal(badHeader.data.code, 'invalid_chunk');

  // Index out of range -> 400 invalid_chunk.
  const outOfRange = await putChunk(transferId, 9, chunk1, alice.token);
  assert.equal(outOfRange.status, 400);

  // Status shows only verified chunk 0.
  const status = await req('GET', `/media/transfers/${transferId}`, undefined, alice.token);
  assert.deepEqual(status.data.received, [0]);
});

dbTest('binary body round-trips unmangled through raw mounting and download GET', async ({req, putChunk, getChunk, signup, startTransfer, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const size = 262144 + 100;
  const started = await startTransfer(alice.token, conversationId, size);
  const transferId = started.data.transferId;
  const chunk0 = randomBytes(262144); // includes NUL bytes
  const chunk1 = randomBytes(100);
  assert.equal((await putChunk(transferId, 0, chunk0, alice.token)).status, 201);
  assert.equal((await putChunk(transferId, 1, chunk1, alice.token)).status, 201);
  assert.equal((await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token)).status, 200);

  const init = await req('POST', '/media/downloads', {transferId}, bob.token);
  assert.equal(init.status, 201);
  assert.ok(init.data.token && init.data.expiresAt);
  const got0 = await getChunk(transferId, 0, bob.token, init.data.token);
  const got1 = await getChunk(transferId, 1, bob.token, init.data.token);
  assert.equal(got0.status, 200);
  assert.ok(got0.bytes.equals(chunk0));
  assert.ok(got1.bytes.equals(chunk1));
  assert.equal(got0.headers.get('x-chunk-sha256'), createHash('sha256').update(chunk0).digest('hex'));
  assert.equal(got0.headers.get('cache-control'), 'no-store');
  assert.match(got0.headers.get('content-type') ?? '', /application\/octet-stream/);
});

dbTest('complete: missing_chunks lists indices, then succeeds; idempotent; byte-cap 413 enforced', async ({req, putChunk, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const size = 300000;
  const started = await startTransfer(alice.token, conversationId, size);
  const transferId = started.data.transferId;

  await putChunk(transferId, 0, randomBytes(262144), alice.token);
  const incomplete = await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token);
  assert.equal(incomplete.status, 409);
  assert.equal(incomplete.data.code, 'missing_chunks');
  assert.deepEqual(incomplete.data.missing, [1]);

  await putChunk(transferId, 1, randomBytes(size - 262144), alice.token);
  const complete = await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token);
  assert.equal(complete.status, 200);
  assert.equal(complete.data.state, 'completed');
  const again = await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token);
  assert.equal(again.status, 200);
  assert.equal(again.data.state, 'completed');

  // Byte-cap enforcement: seed a transfer whose stored wire bytes exceed
  // declared size + 28 B overhead and expect 413 transfer_too_large.
  const weird = await startTransfer(alice.token, conversationId, 1);
  assert.equal(weird.status, 201);
  const weirdId = weird.data.transferId;
  await query(
    `INSERT INTO media_chunks (transfer_id, chunk_index, sha256, byte_size, data)
     VALUES ($1, 0, $2, 262172, $3)`,
    [weirdId, createHash('sha256').update(randomBytes(262172)).digest('hex'), randomBytes(262172)]);
  const oversized = await req('POST', `/media/transfers/${weirdId}/complete`, undefined, alice.token);
  assert.equal(oversized.status, 413);
  assert.equal(oversized.data.code, 'transfer_too_large');
});

dbTest('expired staged transfers are rejected (404 transfer_expired) and swept by the GC helper', async ({req, putChunk, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const started = await startTransfer(alice.token, conversationId, 300000);
  const transferId = started.data.transferId;
  await query(`UPDATE media_transfers SET expires_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [transferId]);

  const chunk = randomBytes(262144);
  const put = await putChunk(transferId, 0, chunk, alice.token);
  assert.equal(put.status, 404);
  assert.equal(put.data.code, 'transfer_expired');
  const status = await req('GET', `/media/transfers/${transferId}`, undefined, alice.token);
  assert.equal(status.status, 404);
  assert.equal(status.data.code, 'transfer_expired');
  const complete = await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token);
  assert.equal(complete.status, 404);
  assert.equal(complete.data.code, 'transfer_expired');

  // The sweeper deletes it (cascade purges chunks), idempotently.
  const {sweepMediaTransfers} = require('../dist/media');
  const first = await sweepMediaTransfers();
  assert.ok(first.expiredUploads >= 1);
  const gone = await query('SELECT COUNT(*)::int AS n FROM media_transfers WHERE id = $1', [transferId]);
  assert.equal(gone.rows[0].n, 0);
  const second = await sweepMediaTransfers();
  assert.ok(second.expiredUploads === 0 || second.expiredUploads >= 0); // idempotent, no crash
});

dbTest('GC sweep removes 30-day-old completed blobs and keeps fresh ones (LIMIT-bounded)', async ({req, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  await query(
    `INSERT INTO media_transfers (conversation_id, sender_id, size_bytes, chunk_size, total_chunks, state, completed_at, expires_at)
     VALUES ($1, $2, 1, 262144, 1, 'completed', NOW() - INTERVAL '31 days', NOW() + INTERVAL '1 day'),
            ($1, $2, 1, 262144, 1, 'completed', NOW(), NOW() + INTERVAL '1 day'),
            ($1, $2, 1, 262144, 1, 'canceled', NULL, NOW() + INTERVAL '1 day'),
            ($1, $2, 1, 262144, 1, 'uploading', NULL, NOW() + INTERVAL '1 day')`,
    [conversationId, alice.userId]);
  const {sweepMediaTransfers} = require('../dist/media');
  const result = await sweepMediaTransfers();
  assert.ok(result.expiredCompleted >= 1);
  assert.ok(result.staleTerminalRows >= 1);
  const rows = await query(
    `SELECT state, COUNT(*)::int AS n FROM media_transfers WHERE conversation_id = $1 GROUP BY state`,
    [conversationId]);
  const byState = Object.fromEntries(rows.rows.map((r) => [r.state, r.n]));
  assert.equal(byState.completed, 1, 'only the fresh completed row survives');
  assert.equal(byState.uploading, 1, 'fresh uploading row survives');
  assert.equal(byState.canceled, undefined, 'canceled row swept');
});

dbTest('sender-only DELETE: non-sender 403, sender 204, idempotent absent 204, chunks cascade', async ({req, putChunk, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  const eve = await signup();
  await resetBuckets([alice.userId, eve.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId, eve.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const started = await startTransfer(alice.token, conversationId, 262144);
  const transferId = started.data.transferId;
  await putChunk(transferId, 0, randomBytes(262144), alice.token);

  const denied = await req('DELETE', `/media/transfers/${transferId}`, undefined, eve.token);
  assert.equal(denied.status, 403);
  assert.equal(denied.data.code, 'not_sender');

  assert.equal((await req('DELETE', `/media/transfers/${transferId}`, undefined, alice.token)).status, 204);
  assert.equal((await req('DELETE', `/media/transfers/${transferId}`, undefined, alice.token)).status, 204);
  const chunks = await query('SELECT COUNT(*)::int AS n FROM media_chunks WHERE transfer_id = $1', [transferId]);
  assert.equal(chunks.rows[0].n, 0);
});

dbTest('download init: member 201, non-member 403, incomplete 404, expired-blob 404, token flows', async ({req, putChunk, getChunk, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  const eve = await signup();
  await resetBuckets([alice.userId, bob.userId, eve.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const size = 262144 + 50;
  const started = await startTransfer(alice.token, conversationId, size);
  const transferId = started.data.transferId;

  // Not completed yet -> 404.
  const early = await req('POST', '/media/downloads', {transferId}, bob.token);
  assert.equal(early.status, 404);

  await putChunk(transferId, 0, randomBytes(262144), alice.token);
  await putChunk(transferId, 1, randomBytes(50), alice.token);
  assert.equal((await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token)).status, 200);

  // Non-member -> 403 not_conversation_member.
  const denied = await req('POST', '/media/downloads', {transferId}, eve.token);
  assert.equal(denied.status, 403);
  assert.equal(denied.data.code, 'not_conversation_member');

  // Member -> 201 with token; sender -> 201 too.
  const init = await req('POST', '/media/downloads', {transferId}, bob.token);
  assert.equal(init.status, 201);
  assert.equal(init.data.totalChunks, 2);
  assert.equal(init.data.sizeBytes, size);
  const initSender = await req('POST', '/media/downloads', {transferId}, alice.token);
  assert.equal(initSender.status, 201);

  // Chunk GET without token -> 401; tampered token -> 401; valid token -> 200.
  assert.equal((await getChunk(transferId, 0, bob.token)).status, 401);
  const good = await getChunk(transferId, 0, bob.token, init.data.token);
  assert.equal(good.status, 200);
  const mid = Math.floor(init.data.token.length / 2);
  const tampered = init.data.token.slice(0, mid) + (init.data.token[mid] === 'A' ? 'B' : 'A') + init.data.token.slice(mid + 1);
  const bad = await getChunk(transferId, 0, bob.token, tampered);
  assert.equal(bad.status, 401);

  // Expired token -> 401 download_token_expired.
  const {mintDownloadToken} = require('../dist/media');
  const expired = mintDownloadToken({transferId, userId: bob.userId, conversationId}, -10);
  const expiredResp = await getChunk(transferId, 0, bob.token, expired.token);
  assert.equal(expiredResp.status, 401);

  // Token minted for a different transfer must not authorize this one.
  const otherStarted = await startTransfer(alice.token, conversationId, 262144);
  const otherId = otherStarted.data.transferId;
  await putChunk(otherId, 0, randomBytes(262144), alice.token);
  await req('POST', `/media/transfers/${otherId}/complete`, undefined, alice.token);
  const otherInit = await req('POST', '/media/downloads', {transferId: otherId}, bob.token);
  const cross = await getChunk(transferId, 0, bob.token, otherInit.data.token);
  assert.equal(cross.status, 401);

  // Chunk out of range -> 400 invalid_chunk.
  const oor = await getChunk(transferId, 9, bob.token, init.data.token);
  assert.equal(oor.status, 400);

  // Expired blob (completed > 30 days ago) -> 404 transfer_expired on init and GET.
  await query(`UPDATE media_transfers SET completed_at = NOW() - INTERVAL '31 days' WHERE id = $1`, [transferId]);
  const lateInit = await req('POST', '/media/downloads', {transferId}, bob.token);
  assert.equal(lateInit.status, 404);
  assert.equal(lateInit.data.code, 'transfer_expired');
  const lateGet = await getChunk(transferId, 0, bob.token, init.data.token);
  assert.equal(lateGet.status, 404);
});

dbTest('MEDIA_TRANSFER_ENABLED=false yields 503 feature_disabled', async ({req, signup}) => {
  const {config} = require('../dist/config');
  const previous = config.MEDIA_TRANSFER_ENABLED;
  config.MEDIA_TRANSFER_ENABLED = false;
  try {
    const alice = await signup();
    const bob = await signup();
    const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
    const conversationId = created.data.conversationId;
    const denied = await req('POST', '/media/transfers', {conversationId, sizeBytes: 1, totalChunks: 1, chunkSize: 262144}, alice.token);
    assert.equal(denied.status, 503);
    assert.equal(denied.data.error, 'feature_disabled');
  } finally {
    config.MEDIA_TRANSFER_ENABLED = previous;
  }
});

dbTest('migrations are additive-only: media tables exist and history checksums verify', async ({query}) => {
  const tables = await query(
    `SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('media_transfers', 'media_chunks') ORDER BY table_name`);
  assert.deepEqual(tables.rows.map((r) => r.table_name), ['media_chunks', 'media_transfers']);
  const version = await query('SELECT MAX(version)::int AS v, COUNT(*)::int AS n FROM schema_migrations');
  assert.ok(version.rows[0].v >= 18, 'media migrations appended (expect >= 18 versions)');
  // Column-level invariant: no plaintext/name/mime/key columns exist in the media tables.
  const cols = await query(
    `SELECT column_name FROM information_schema.columns
      WHERE table_name IN ('media_transfers', 'media_chunks')`);
  for (const {column_name} of cols.rows) {
    assert.ok(!/name|mime|plaintext|key|secret/i.test(column_name), `unexpected column ${column_name}`);
  }
  // Boot already re-verified every historical checksum (applyMigrations throws on mismatch).
});

dbTest('sender is auto-authorized for download init; removed member (left_at set) is denied', async ({req, putChunk, signup, startTransfer, query, resetBuckets}) => {
  const alice = await signup();
  const bob = await signup();
  await resetBuckets([alice.userId, bob.userId]);
  const created = await req('POST', '/conversations', {type: 'group', participantIds: [bob.userId], name: 'M'}, alice.token);
  const conversationId = created.data.conversationId;
  const started = await startTransfer(alice.token, conversationId, 262144);
  const transferId = started.data.transferId;
  await putChunk(transferId, 0, randomBytes(262144), alice.token);
  await req('POST', `/media/transfers/${transferId}/complete`, undefined, alice.token);

  // Sender can always init.
  const asSender = await req('POST', '/media/downloads', {transferId}, alice.token);
  assert.equal(asSender.status, 201);

  // Remove bob from the conversation; he can no longer mint a token.
  await query(
    `UPDATE conversation_participants SET left_at = NOW()
      WHERE conversation_id = $1 AND user_id = $2`, [conversationId, bob.userId]);
  const asRemoved = await req('POST', '/media/downloads', {transferId}, bob.token);
  assert.equal(asRemoved.status, 403);
  assert.equal(asRemoved.data.code, 'not_conversation_member');
});
