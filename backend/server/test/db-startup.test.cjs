const {test} = require('node:test');
const assert = require('node:assert/strict');
const pg = require('pg');

let instances = [];
let beginGate;
let fail = false;
class FakePool {
  constructor() { this.ended = false; instances.push(this); }
  on() {}
  async connect() {
    return {
      async query(sql) {
        if (sql === 'BEGIN') {
          if (beginGate) await beginGate;
          if (fail) throw new Error('database unavailable');
        }
        return {rows: []};
      },
      release() {},
    };
  }
  async end() { this.ended = true; }
}
pg.Pool = FakePool;
const db = require('../dist/db');

test('concurrent database initialization never exposes an unmigrated pool', async () => {
  let unblock;
  beginGate = new Promise(resolve => { unblock = resolve; });
  const first = db.initDb();
  const second = db.initDb();
  assert.equal(instances.length, 1);
  assert.throws(() => db.getDb(), /not initialized/);
  unblock();
  try {
    const [one, two] = await Promise.all([first, second]);
    assert.equal(one, two);
    assert.equal(db.getDb(), one);
  } finally {
    beginGate = undefined;
    await db.closeDb();
  }
  assert.equal(instances[0].ended, true);
});

test('failed database initialization disposes the pool and allows a fresh retry', async () => {
  instances = [];
  fail = true;
  await assert.rejects(db.initDb(), /database unavailable/);
  assert.equal(instances[0].ended, true);
  assert.throws(() => db.getDb(), /not initialized/);
  fail = false;
  try {
    const recovered = await db.initDb();
    assert.equal(instances.length, 2);
    assert.equal(recovered, instances[1]);
  } finally {
    await db.closeDb();
  }
});
