// Disposable loopback server for the opt-in Flutter/backend integration test.
// Run only with NODE_ENV=test and a local database named chhaya_test.
const { URL } = require('node:url');
const dbUrl = new URL(process.env.DATABASE_URL || '');
const port = Number(process.env.CHHAYA_TEST_API_PORT);
if (process.env.NODE_ENV !== 'test' || !['127.0.0.1', 'localhost', '::1'].includes(dbUrl.hostname) ||
    dbUrl.pathname !== '/chhaya_test' || !Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error('Use NODE_ENV=test, a local chhaya_test database, and CHHAYA_TEST_API_PORT');
}
const { initDb, closeDb } = require('../dist/db');
const { app } = require('../dist/index');
let server;
initDb().then(() => {
  server = app.listen(port, '127.0.0.1', () => process.stdout.write('Integration API listening on loopback\n'));
}).catch(() => { process.stderr.write('Integration database unavailable\n'); process.exitCode = 1; });
async function shutdown() {
  if (server) await new Promise((resolve) => server.close(resolve));
  await closeDb();
}
process.once('SIGINT', () => { void shutdown(); });
process.once('SIGTERM', () => { void shutdown(); });
