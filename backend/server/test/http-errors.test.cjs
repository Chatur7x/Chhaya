const {test} = require('node:test');
const assert = require('node:assert/strict');
const {app} = require('../dist/index');

test('HTTP parser rejects malformed, oversized and unsupported bodies with safe client errors', async () => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  // Health bypasses the DB-backed limiter, isolating parser behavior from DB state.
  const url = `http://127.0.0.1:${server.address().port}/health`;
  try {
    for (const fixture of [
      {body: '{"private":"secret",broken', headers: {}, status: 400, error: 'Invalid request body'},
      {body: JSON.stringify({private: 'x'.repeat(1024 * 1024)}), headers: {}, status: 413, error: 'Request body too large'},
      {body: '{}', headers: {'Content-Encoding': 'unknown'}, status: 415, error: 'Unsupported request encoding'},
    ]) {
      const response = await fetch(url, {method: 'POST',
        headers: {'Content-Type': 'application/json', ...fixture.headers}, body: fixture.body});
      assert.equal(response.status, fixture.status);
      assert.deepEqual(await response.json(), {error: fixture.error});
    }
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
