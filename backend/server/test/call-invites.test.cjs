const { test } = require('node:test');
const assert = require('node:assert/strict');
const db = require('../dist/db');
const { acknowledgeCallInvite, clearCallInvites, getPendingCallInvites, purgeExpiredCallInvites, storeCallInvite } = require('../dist/call-invites');

test('encrypted call offers are recipient-scoped, short-lived and acknowledged safely', async () => {
  const originalQuery = db.query;
  const calls = [];
  db.query = async (sql, params) => {
    calls.push({ sql, params });
    if (sql.includes('SELECT call_id')) {
      return { rows: [{
        call_id: '11111111-1111-4111-8111-111111111111',
        conversation_id: '22222222-2222-4222-8222-222222222222',
        sender_id: '33333333-3333-4333-8333-333333333333',
        envelope: 'authenticated-ciphertext',
        created_at: new Date('2026-10-24T00:00:00Z'),
      }], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  };

  try {
    await storeCallInvite({
      callId: '11111111-1111-4111-8111-111111111111',
      conversationId: '22222222-2222-4222-8222-222222222222',
      senderId: '33333333-3333-4333-8333-333333333333',
      recipientId: '44444444-4444-4444-8444-444444444444',
      envelope: 'authenticated-ciphertext',
    });
    assert.match(calls[0].sql, /NOW\(\) \+ INTERVAL '60 seconds'/);
    assert.match(calls[0].sql, /ON CONFLICT \(call_id, recipient_id\) DO NOTHING/);
    assert.equal(calls[0].params[4], 'authenticated-ciphertext');

    const pending = await getPendingCallInvites('44444444-4444-4444-8444-444444444444');
    assert.deepEqual(pending, [{
      callId: '11111111-1111-4111-8111-111111111111',
      conversationId: '22222222-2222-4222-8222-222222222222',
      senderId: '33333333-3333-4333-8333-333333333333',
      envelope: 'authenticated-ciphertext',
      createdAt: '2026-10-24T00:00:00.000Z',
    }]);
    assert.match(calls[1].sql, /recipient_id = \$1 AND expires_at > NOW\(\)/);
    assert.equal(calls[1].params[0], '44444444-4444-4444-8444-444444444444');

    await acknowledgeCallInvite('11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444');
    assert.match(calls[2].sql, /call_id = \$1 AND recipient_id = \$2/);
    await clearCallInvites('11111111-1111-4111-8111-111111111111');
    assert.match(calls[3].sql, /DELETE FROM call_invites WHERE call_id = \$1/);
    await purgeExpiredCallInvites();
    assert.match(calls[4].sql, /expires_at <= NOW\(\)/);
  } finally {
    db.query = originalQuery;
  }
});
