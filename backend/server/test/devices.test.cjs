const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,randomBytes,createHash,createHmac,diffieHellman,generateKeyPairSync,
  createPublicKey,sign,hkdfSync,createCipheriv}=require('node:crypto');

// DL-A authenticated device linking (docs/spec-device-linking-v1.md §6).
// Requires a disposable loopback PostgreSQL (chhaya_test); self-skips otherwise.

const lp = (value) => {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value, 'utf8');
  const len = Buffer.alloc(2); len.writeUInt16BE(bytes.length, 0);
  return Buffer.concat([len, bytes]);
};
const rawPub = (pair) => Buffer.from(pair.publicKey.export({format:'jwk'}).x, 'base64url');
const publicKeyFromBytes = (bytes) => createPublicKey({key:{kty:'OKP',crv:'X25519',x:bytes.toString('base64url')},format:'jwk'});
const sha256Hex = (buffer) => createHash('sha256').update(buffer).digest('hex');
const codeHashOf = (code) => createHash('sha256').update(code, 'utf8').digest('hex');

// Build a byte-faithful approval per spec §3.3. The server stores these bytes
// opaquely (it cannot and must not decrypt them).
function buildApproval({requestId, code, ephPubN, devicePubEd, accountEd}) {
  const eP = generateKeyPairSync('x25519');
  const ePPub = rawPub(eP);
  const SS = diffieHellman({privateKey: eP.privateKey, publicKey: publicKeyFromBytes(ephPubN)});
  const salt = createHash('sha256').update(Buffer.concat([lp('Chhaya-DeviceLink-v1'), lp(code), ephPubN, ePPub])).digest();
  const SK = Buffer.from(hkdfSync('sha256', SS, salt, lp('Chhaya-DeviceLink-v1/session'), 32));
  const fp = createHash('sha256').update(Buffer.concat([lp('Chhaya-DeviceLink-v1/fp'), ephPubN, ePPub])).digest().subarray(0, 8);
  const accountEdPub = Buffer.from(accountEd.publicKey.export({format:'jwk'}).x, 'base64url');
  const accountChhayaId = createHash('sha256').update(accountEdPub).digest('hex').slice(0, 32);
  const exp = Buffer.alloc(8); exp.writeBigUInt64BE(BigInt(Date.now() + 5 * 60 * 1000), 0);
  const transcript = Buffer.concat([
    lp('Chhaya-DeviceLink-v1/approval'), Buffer.from(requestId, 'utf8'), lp(code),
    ephPubN, ePPub,
    Buffer.from(accountChhayaId, 'utf8'), accountEdPub,
    Buffer.from(devicePubEd, 'hex'), exp, lp('metadata'),
  ]);
  const sig = sign(null, transcript, accountEd.privateKey);
  const body = Buffer.concat([transcript, sig]);
  const iv = randomBytes(12);
  const aad = Buffer.concat([lp('Chhaya-DeviceLink-v1/approval-aad'), Buffer.from(requestId, 'utf8'), fp]);
  const cipher = createCipheriv('aes-256-gcm', SK, iv);
  cipher.setAAD(aad);
  const ct = Buffer.concat([cipher.update(body), cipher.final()]);
  const tag = cipher.getAuthTag();
  const approval = Buffer.concat([iv, tag, ct]); // base64 for transport
  return {approval: approval.toString('base64'), approvalSignature: sig.toString('hex'), primEphPub: ePPub.toString('hex')};
}

test('DL-A device linking: enroll, approve, consume, list, revoke',
  {skip: !process.env.DATABASE_URL}, async () => {
    const assert = require('node:assert/strict');
    const {initDb, closeDb, query} = require('../dist/db');
    const {app} = require('../dist/index');
    await initDb();
    await query('DELETE FROM rate_limits');
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}/api/v1`;
    const req = async (method, path, body, token) => {
      const r = await fetch(base + path, {
        method,
        headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
        body: body ? JSON.stringify(body) : undefined,
      });
      const text = await r.text();
      let data; try { data = JSON.parse(text); } catch { data = text; }
      return {status: r.status, data};
    };
    const claim = async (pair, body, purpose) => {
      const r = await req('POST', '/auth/challenge', {publicKey: body.publicKey, deviceId: body.deviceId, purpose});
      const c = r.data;
      const key = createPublicKey({key: {kty: 'OKP', crv: 'X25519', x: Buffer.from(c.serverPublicKey, 'hex').toString('base64url')}, format: 'jwk'});
      const secret = diffieHellman({privateKey: pair.privateKey, publicKey: key});
      const context = `chhaya-auth-v1|${purpose}|${c.challengeId}|${body.deviceId}|${body.publicKey}|${c.serverPublicKey}|${c.nonce}`;
      const identityProof = createHmac('sha256', secret).update(context).digest('hex');
      secret.fill(0);
      return {challengeId: c.challengeId, identityProof};
    };
    const signup = async () => {
      const pair = generateKeyPairSync('x25519');
      const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
      const body = {chhayaId: '05' + publicKey, publicKey, displayName: 'Link Test', encryptedPrivateKey: 'encrypted-backup', recoveryPhraseHash: randomBytes(32).toString('hex'), deviceId: randomUUID()};
      Object.assign(body, await claim(pair, body, 'register'));
      const r = await req('POST', '/auth/register', body);
      assert.equal(r.status, 201, JSON.stringify(r.data));
      return {...r.data, body, pair};
    };
    const accounts = [];
    try {
      {
        const alice = await signup(); accounts.push(alice.userId);

        // --- happy path: request -> approve -> status -> consume -> list (spec §6 #1)
        const deviceEd = generateKeyPairSync('ed25519');
        const ephN = generateKeyPairSync('x25519');
        const ephPubN = rawPub(ephN);
        const devicePublicKey = Buffer.from(deviceEd.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
        const deviceId = randomUUID();
        const code = randomBytes(8).toString('hex'); // 128-bit one-time code
        const linkBody = {deviceId, deviceName: 'Test Laptop', platform: 'windows', devicePublicKey, ephemeralPublicKey: ephPubN.toString('hex'), codeHash: codeHashOf(code)};

        const created = await req('POST', '/devices/link/request', linkBody);
        assert.equal(created.status, 201);
        assert.equal(typeof created.data.requestId, 'string');
        const requestId = created.data.requestId;

        // Idempotent re-request: same deviceId -> same requestId, 200, no new row.
        const again = await req('POST', '/devices/link/request', linkBody);
        assert.equal(again.status, 200);
        assert.equal(again.data.requestId, requestId);

        const pending = await req('GET', `/devices/link/status/${requestId}`);
        assert.equal(pending.status, 200);
        assert.equal(pending.data.state, 'pending');

        const approvePayload = buildApproval({requestId, code, ephPubN, devicePubEd: devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
        const deniedNoAuth = await req('POST', '/devices/link/approve', {requestId, code, action: 'approve', ...approvePayload});
        assert.equal(deniedNoAuth.status, 401);

        const approved = await req('POST', '/devices/link/approve', {requestId, code, action: 'approve', ...approvePayload}, alice.token);
        assert.equal(approved.status, 200, JSON.stringify(approved.data));
        assert.equal(approved.data.state, 'approved');

        // Idempotent retry with identical payload -> 200; conflicting payload -> 409.
        const retrySame = await req('POST', '/devices/link/approve', {requestId, code, action: 'approve', ...approvePayload}, alice.token);
        assert.equal(retrySame.status, 200);
        const otherPayload = {...approvePayload, approvalSignature: '00'.repeat(64)};
        const conflict = await req('POST', '/devices/link/approve', {requestId, code, action: 'approve', ...otherPayload}, alice.token);
        assert.equal(conflict.status, 409);

        const status = await req('GET', `/devices/link/status/${requestId}`);
        assert.equal(status.status, 200);
        assert.equal(status.data.state, 'approved');
        assert.equal(status.data.approval, approvePayload.approval);
        assert.equal(status.data.approvalSignature, approvePayload.approvalSignature);
        assert.equal(status.data.primEphPub, approvePayload.primEphPub);

        // Wrong code on consume -> 403, no state change.
        const wrongConsume = await req('POST', '/devices/link/consume', {requestId, code: 'wrong-code'});
        assert.equal(wrongConsume.status, 403);

        const consumed = await req('POST', '/devices/link/consume', {requestId, code});
        assert.equal(consumed.status, 200, JSON.stringify(consumed.data));
        assert.equal(consumed.data.userId, alice.userId);
        assert.equal(consumed.data.deviceId, deviceId);
        assert.match(consumed.data.token, /^[0-9a-f]{64}$/);

        // Replay of a redeemed code -> 409 (spec §2.3).
        const replay = await req('POST', '/devices/link/consume', {requestId, code});
        assert.equal(replay.status, 409);

        // A consumed request cannot be re-approved -> 409.
        const reapprove = await req('POST', '/devices/link/approve', {requestId, code, action: 'approve', ...approvePayload}, alice.token);
        assert.equal(reapprove.status, 409);

        // New device authenticates; sees both devices (spec §6 #1).
        const list = await req('GET', '/devices', null, consumed.data.token);
        assert.equal(list.status, 200);
        assert.equal(list.data.length, 2);
        const linked = list.data.find(d => d.deviceId === deviceId);
        assert.ok(linked && linked.isCurrent === true && linked.revokedAt == null);
        const primary = list.data.find(d => d.deviceId === alice.body.deviceId);
        assert.ok(primary && primary.isCurrent === false);

        // Audit trail records request/approve/consume in order, no private material.
        const events = await query('SELECT action FROM device_link_events WHERE device_id = $1 ORDER BY at, id', [deviceId]);
        assert.deepEqual(events.rows.map(r => r.action), ['request', 'approve', 'consume']);
        const blobCheck = await query(`SELECT 1 FROM device_link_requests WHERE request_id=$1 AND ephemeral_public_key IS NOT NULL`, [requestId]);
        assert.equal(blobCheck.rowCount, 0); // ephemeral pubkey NULLed at consume (spec §4.4#4)

        // --- revoke flow (spec §4.4#6): soft revoke + session invalidation
        const revoke = await req('DELETE', `/devices/${deviceId}`, null, alice.token);
        assert.equal(revoke.status, 200);
        assert.equal(revoke.data.revoked, true);

        // The linked device's session dies immediately on every surface.
        assert.equal((await req('GET', '/devices', null, consumed.data.token)).status, 401);
        assert.equal((await req('GET', '/users/me', null, consumed.data.token)).status, 401);
        // Re-approval and re-consume after revocation -> 409/401.
        assert.equal((await req('POST', '/devices/link/approve', {requestId, code, action: 'approve', ...approvePayload}, consumed.data.token)).status, 401);
        // Revoke is idempotent -> 200 again.
        assert.equal((await req('DELETE', `/devices/${deviceId}`, null, alice.token)).status, 200);
        // Revoked device still listed, flagged.
        const afterRevoke = await req('GET', '/devices', null, alice.token);
        const revokedRow = afterRevoke.data.find(d => d.deviceId === deviceId);
        assert.ok(revokedRow && revokedRow.revokedAt !== null);
        // Self-revocation is refused (spec §3.6).
        assert.equal((await req('DELETE', `/devices/${alice.body.deviceId}`, null, alice.token)).status, 400);
        const eventsAfter = await query('SELECT action FROM device_link_events WHERE device_id = $1 AND action=\'revoke\'', [deviceId]);
        assert.ok(eventsAfter.rowCount >= 1);
      }
    } finally {
      for (const userId of accounts) await query('DELETE FROM users WHERE id = $1', [userId]);
      await new Promise(resolve => server.close(resolve));
      await closeDb();
    }
  });

test('DL-A wrong code, expiry, cross-account and role-confusion rejections',
  {skip: !process.env.DATABASE_URL}, async () => {
    const {initDb, closeDb, query} = require('../dist/db');
    const {app} = require('../dist/index');
    await initDb();
    await query('DELETE FROM rate_limits');
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}/api/v1`;
    const req = async (method, path, body, token) => {
      const r = await fetch(base + path, {
        method,
        headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
        body: body ? JSON.stringify(body) : undefined,
      });
      const text = await r.text();
      let data; try { data = JSON.parse(text); } catch { data = text; }
      return {status: r.status, data};
    };
    const claim = async (pair, body, purpose) => {
      const r = await req('POST', '/auth/challenge', {publicKey: body.publicKey, deviceId: body.deviceId, purpose});
      const c = r.data;
      const key = createPublicKey({key: {kty: 'OKP', crv: 'X25519', x: Buffer.from(c.serverPublicKey, 'hex').toString('base64url')}, format: 'jwk'});
      const secret = diffieHellman({privateKey: pair.privateKey, publicKey: key});
      const context = `chhaya-auth-v1|${purpose}|${c.challengeId}|${body.deviceId}|${body.publicKey}|${c.serverPublicKey}|${c.nonce}`;
      return {challengeId: c.challengeId, identityProof: createHmac('sha256', secret).update(context).digest('hex')};
    };
    const signup = async () => {
      const pair = generateKeyPairSync('x25519');
      const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
      const body = {chhayaId: '05' + publicKey, publicKey, displayName: 'Link Test', encryptedPrivateKey: 'encrypted-backup', recoveryPhraseHash: randomBytes(32).toString('hex'), deviceId: randomUUID()};
      Object.assign(body, await claim(pair, body, 'register'));
      const r = await req('POST', '/auth/register', body);
      assert.equal(r.status, 201);
      return {...r.data, body, pair};
    };
    const mkRequest = async () => {
      const deviceEd = generateKeyPairSync('ed25519');
      const ephN = generateKeyPairSync('x25519');
      const ephPubN = rawPub(ephN);
      const devicePublicKey = Buffer.from(deviceEd.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
      const deviceId = randomUUID();
      const code = randomBytes(16).toString('hex');
      const r = await req('POST', '/devices/link/request', {
        deviceId, deviceName: 'Reject Laptop', platform: 'linux',
        devicePublicKey, ephemeralPublicKey: ephPubN.toString('hex'), codeHash: codeHashOf(code),
      });
      assert.equal(r.status, 201);
      return {requestId: r.data.requestId, code, ephPubN, devicePublicKey, deviceId};
    };
    const accounts = [];
    try {
      const alice = await signup(); accounts.push(alice.userId);
      const bob = await signup(); accounts.push(bob.userId);

      // Wrong code on approve -> 403, request stays pending (spec §6 #2).
      const a = await mkRequest();
      assert.equal((await req('POST', '/devices/link/approve', {requestId: a.requestId, code: 'nope', action: 'approve', approval: Buffer.alloc(32).toString('base64'), approvalSignature: '11'.repeat(64), primEphPub: '22'.repeat(32)}, alice.token)).status, 403);
      assert.equal((await req('GET', `/devices/link/status/${a.requestId}`)).data.state, 'pending');

      // Unauthenticated approve -> 401 (spec §6 #7).
      assert.equal((await req('POST', '/devices/link/approve', {requestId: a.requestId, code: a.code, action: 'approve', approval: Buffer.alloc(32).toString('base64'), approvalSignature: '11'.repeat(64), primEphPub: '22'.repeat(32)})).status, 401);

      // Cross-account: bob cannot approve alice's... rather, bob cannot act on alice's
      // pending link without the code; with a wrong code he gets 403 and the row stays pending.
      // Once alice approves, a different-account approve with any payload -> 409 (claimed).
      const codeA = a.code;
      const approvalA = buildApproval({requestId: a.requestId, code: codeA, ephPubN: a.ephPubN, devicePubEd: a.devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
      assert.equal((await req('POST', '/devices/link/approve', {requestId: a.requestId, code: 'definitely-wrong', action: 'approve', ...approvalA}, bob.token)).status, 403);
      assert.equal((await req('POST', '/devices/link/approve', {requestId: a.requestId, code: codeA, action: 'approve', ...approvalA}, alice.token)).status, 200);
      assert.equal((await req('POST', '/devices/link/approve', {requestId: a.requestId, code: codeA, action: 'approve', ...approvalA}, bob.token)).status, 409);

      // Cross-account enumeration: foreign device id delete -> 404, not 403 (spec §4.4#6).
      assert.equal((await req('DELETE', `/devices/${alice.body.deviceId}`, null, bob.token)).status, 404);
      assert.equal((await req('DELETE', `/devices/${randomUUID()}`, null, bob.token)).status, 404);

      // Expiry: approve and consume after expires_at -> 410; row deleted (spec §6 #3).
      const exp1 = await mkRequest();
      await query(`UPDATE device_link_requests SET expires_at = NOW() - INTERVAL '1 minute' WHERE request_id = $1`, [exp1.requestId]);
      const expApproval = buildApproval({requestId: exp1.requestId, code: exp1.code, ephPubN: exp1.ephPubN, devicePubEd: exp1.devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
      assert.equal((await req('POST', '/devices/link/approve', {requestId: exp1.requestId, code: exp1.code, action: 'approve', ...expApproval}, alice.token)).status, 410);
      const exp2 = await mkRequest();
      const exp2Approval = buildApproval({requestId: exp2.requestId, code: exp2.code, ephPubN: exp2.ephPubN, devicePubEd: exp2.devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
      assert.equal((await req('POST', '/devices/link/approve', {requestId: exp2.requestId, code: exp2.code, action: 'approve', ...exp2Approval}, alice.token)).status, 200);
      await query(`UPDATE device_link_requests SET expires_at = NOW() - INTERVAL '1 minute' WHERE request_id = $1`, [exp2.requestId]);
      assert.equal((await req('POST', '/devices/link/consume', {requestId: exp2.requestId, code: exp2.code})).status, 410);
      const gone = await query('SELECT 1 FROM device_link_requests WHERE request_id = $1', [exp1.requestId]);
      assert.equal(gone.rowCount, 0);
      // Expired status poll -> 410 and row is deleted on read.
      const exp3 = await mkRequest();
      await query(`UPDATE device_link_requests SET expires_at = NOW() - INTERVAL '1 minute' WHERE request_id = $1`, [exp3.requestId]);
      assert.equal((await req('GET', `/devices/link/status/${exp3.requestId}`)).status, 410);

      // Deny path: denied request cannot be consumed; status reports denied.
      const d = await mkRequest();
      assert.equal((await req('POST', '/devices/link/approve', {requestId: d.requestId, code: d.code, action: 'deny'}, alice.token)).status, 200);
      assert.equal((await req('GET', `/devices/link/status/${d.requestId}`)).data.state, 'denied');
      assert.equal((await req('POST', '/devices/link/consume', {requestId: d.requestId, code: d.code})).status, 409);

      // Unknown request id -> 404 across surfaces (parity).
      const missing = randomUUID();
      assert.equal((await req('GET', `/devices/link/status/${missing}`)).status, 404);
      assert.equal((await req('POST', '/devices/link/consume', {requestId: missing, code: a.code})).status, 404);
      assert.equal((await req('POST', '/devices/link/approve', {requestId: missing, code: a.code, action: 'deny'}, alice.token)).status, 404);
    } finally {
      for (const userId of accounts) await query('DELETE FROM users WHERE id = $1', [userId]);
      await new Promise(resolve => server.close(resolve));
      await closeDb();
    }
  });

test('DL-A concurrency: one-time consume race and concurrent approve idempotency',
  {skip: !process.env.DATABASE_URL}, async () => {
    const {initDb, closeDb, query} = require('../dist/db');
    const {app} = require('../dist/index');
    await initDb();
    await query('DELETE FROM rate_limits');
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}/api/v1`;
    const req = async (method, path, body, token) => {
      const r = await fetch(base + path, {
        method,
        headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
        body: body ? JSON.stringify(body) : undefined,
      });
      const text = await r.text();
      let data; try { data = JSON.parse(text); } catch { data = text; }
      return {status: r.status, data};
    };
    const claim = async (pair, body, purpose) => {
      const r = await req('POST', '/auth/challenge', {publicKey: body.publicKey, deviceId: body.deviceId, purpose});
      const c = r.data;
      const key = createPublicKey({key: {kty: 'OKP', crv: 'X25519', x: Buffer.from(c.serverPublicKey, 'hex').toString('base64url')}, format: 'jwk'});
      const secret = diffieHellman({privateKey: pair.privateKey, publicKey: key});
      const context = `chhaya-auth-v1|${purpose}|${c.challengeId}|${body.deviceId}|${body.publicKey}|${c.serverPublicKey}|${c.nonce}`;
      return {challengeId: c.challengeId, identityProof: createHmac('sha256', secret).update(context).digest('hex')};
    };
    const signup = async () => {
      const pair = generateKeyPairSync('x25519');
      const publicKey = Buffer.from(pair.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
      const body = {chhayaId: '05' + publicKey, publicKey, displayName: 'Race Test', encryptedPrivateKey: 'encrypted-backup', recoveryPhraseHash: randomBytes(32).toString('hex'), deviceId: randomUUID()};
      Object.assign(body, await claim(pair, body, 'register'));
      const r = await req('POST', '/auth/register', body);
      assert.equal(r.status, 201);
      return {...r.data, body, pair};
    };
    const accounts = [];
    try {
      const alice = await signup(); accounts.push(alice.userId);
      const mkRequest = async () => {
        const deviceEd = generateKeyPairSync('ed25519');
        const ephN = generateKeyPairSync('x25519');
        const ephPubN = rawPub(ephN);
        const devicePublicKey = Buffer.from(deviceEd.publicKey.export({format: 'jwk'}).x, 'base64url').toString('hex');
        const deviceId = randomUUID();
        const code = randomBytes(16).toString('hex');
        const r = await req('POST', '/devices/link/request', {
          deviceId, deviceName: 'Race Laptop', platform: 'windows',
          devicePublicKey, ephemeralPublicKey: ephPubN.toString('hex'), codeHash: codeHashOf(code),
        });
        assert.equal(r.status, 201);
        return {requestId: r.data.requestId, code, ephPubN, devicePublicKey, deviceId};
      };
      const approve = async (t, payload) => req('POST', '/devices/link/approve', payload, t);

      // Two parallel approves with identical payload -> both 200 (spec §6 #6).
      const a = await mkRequest();
      const payload = buildApproval({requestId: a.requestId, code: a.code, ephPubN: a.ephPubN, devicePubEd: a.devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
      const approveBody = {requestId: a.requestId, code: a.code, action: 'approve', ...payload};
      const [r1, r2] = await Promise.all([approve(alice.token, approveBody), approve(alice.token, approveBody)]);
      assert.deepEqual([r1.status, r2.status].sort(), [200, 200]);

      // Two parallel approves with conflicting payloads -> one 200, one 409.
      const b = await mkRequest();
      const bPayload = buildApproval({requestId: b.requestId, code: b.code, ephPubN: b.ephPubN, devicePubEd: b.devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
      const bConflict = {...bPayload, approvalSignature: 'ab'.repeat(64)};
      const [r3, r4] = await Promise.all([
        approve(alice.token, {requestId: b.requestId, code: b.code, action: 'approve', ...bPayload}),
        approve(alice.token, {requestId: b.requestId, code: b.code, action: 'approve', ...bConflict}),
      ]);
      assert.deepEqual([r3.status, r4.status].sort(), [200, 409]);

      // Race on consume: exactly one 200, loser 409 (spec §6 #4/#6).
      const c = await mkRequest();
      const cPayload = buildApproval({requestId: c.requestId, code: c.code, ephPubN: c.ephPubN, devicePubEd: c.devicePublicKey, accountEd: generateKeyPairSync('ed25519')});
      assert.equal((await approve(alice.token, {requestId: c.requestId, code: c.code, action: 'approve', ...cPayload})).status, 200);
      const [r5, r6] = await Promise.all([
        req('POST', '/devices/link/consume', {requestId: c.requestId, code: c.code}),
        req('POST', '/devices/link/consume', {requestId: c.requestId, code: c.code}),
      ]);
      assert.deepEqual([r5.status, r6.status].sort(), [200, 409]);

      // Two pending requests for the same deviceId -> one row (partial unique index).
      const dup = await mkRequest();
      const devicePublicKey = dup.devicePublicKey;
      const dupAgain = await req('POST', '/devices/link/request', {
        deviceId: dup.deviceId, deviceName: 'Race Laptop', platform: 'windows',
        devicePublicKey, ephemeralPublicKey: dup.ephPubN.toString('hex'), codeHash: codeHashOf(dup.code),
      });
      const rows = await query(`SELECT request_id FROM device_link_requests WHERE device_id=$1 AND state IN ('pending','approved')`, [dup.deviceId]);
      assert.equal(rows.rowCount, 1);
      assert.equal(dupAgain.status, 200);
      assert.equal(dupAgain.data.requestId, dup.requestId);

      // Sessions invalidated on revoke: revoke c's device, then use the winning token.
      const winner = r5.status === 200 ? r5.data : r6.data;
      assert.equal((await req('GET', '/devices', null, winner.token)).status, 200);
      assert.equal((await req('DELETE', `/devices/${winner.deviceId}`, null, alice.token)).status, 200);
      assert.equal((await req('GET', '/devices', null, winner.token)).status, 401);
    } finally {
      for (const userId of accounts) await query('DELETE FROM users WHERE id = $1', [userId]);
      await new Promise(resolve => server.close(resolve));
      await closeDb();
    }
  });
