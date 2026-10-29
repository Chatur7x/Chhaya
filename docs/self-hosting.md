# Hosting the messenger backend

A running backend is required for internet messaging. The free testing service
is https://chhaya-ys50.onrender.com; its free database expires on 27 November
2026. Apple membership and Firebase registration are not provisioned. Follow
these steps for a separately operated deployment.

1. Provision a Linux server with Docker Compose and a domain pointing to it.
2. Copy .env.example to .env. Generate unique random values for both variables.
   Keep POSTGRES_PASSWORD URL-safe (letters/digits) for the connection string.
3. Obtain a trusted TLS certificate for the domain. Put fullchain.pem and
   privkey.pem in certs/ beside nginx.conf. Never commit private keys.
4. Run docker compose config, then docker compose up -d --build.
5. Check https://YOUR-DOMAIN/health. Configure the same HTTPS origin in each app.
6. Back up the PostgreSQL volume and keep the host/security updates current.

Only HTTPS is published. PostgreSQL is private to the Docker network.
Anonymous requests use a shared per-IP limit (`API_RATE_LIMIT`, default 100/minute).
Authenticated messaging requests use a verified per-account limit
(`API_AUTH_RATE_LIMIT`, default 600/minute), shared across that account's devices.
This keeps independent users on the same Wi-Fi from consuming one another's
messaging budgets. Authentication endpoints retain the anonymous IP limit;
invalid bearer tokens cannot create new account buckets. Both limits fail closed
if the shared database is unavailable.
WebSocket signaling uses `/signaling` on the same TLS origin and API listener. Metrics are blocked
at the public proxy. Onion transport is disabled pending a vetted implementation.
Push delivery is not operational: Firebase credentials, platform app registration,
and native token/permission handling are not configured in this repository.
Foreground messaging sync and WebSocket signaling work without push while the app
is active; native background call ringing is not supported yet.

## Verification

Backend: npm ci, npm test in backend/server. The HTTP integration suite requires
DATABASE_URL pointing to a dedicated PostgreSQL database. CI supplies PostgreSQL 16.
Tests create and delete isolated accounts. Do not point tests at a production DB.
No claim of load-test capacity or external security audit is made.

Opt-in Flutter verification can also target a dedicated HTTPS testing service:
set `CHHAYA_TEST_API_ORIGIN` to its HTTPS origin and run the two
`test/integration/live_*_test.dart` files. Remote mode uses real TLS validation
and checks authenticated WSS. It creates synthetic test accounts and conversation
history on that service; use a testing deployment, not a database with real users.

## Schema upgrades and rollback

Startup applies append-only, checksummed migrations in one PostgreSQL transaction.
A transaction-scoped advisory lock serializes concurrent API startups. Failed
migrations roll back before the API begins accepting connections. Previously
applied migration text must not be edited or removed: startup rejects a checksum
mismatch. Existing installations adopt the history on their first upgraded startup
by executing the existing idempotent schema statements transactionally.

Back up before deploying. An older server cannot start against a migration history
newer than it understands. Rollback may require restoring the pre-upgrade database;
do not assume an application-image rollback reverses schema or data changes.

## Backup and isolated restore drill

From the repository root with the configured Compose database running:

```text
python scripts/database_ops.py backup D:/secure-backups/chhaya-before-upgrade.dump
python scripts/database_ops.py restore-drill D:/secure-backups/chhaya-before-upgrade.dump
```

Choose an appropriate private backup path on your host. Backup files use PostgreSQL
custom format and refuse to overwrite existing files. They contain account metadata
and are not encrypted by this script; encrypt them for off-host storage and restrict
access. Only restore trusted backups.

The drill starts PostgreSQL 16 in a uniquely named container with no network, exposed
ports or production volumes. It restores all objects in one transaction, checks core
tables, then removes the container and its temporary data. It never restores into
the configured production database. Retain the command output and date as drill
evidence. This verifies database restoration, not mobile account/session recovery.

## Windows Docker startup recovery

Start installed Docker Desktop with `powershell -File scripts/start_docker.ps1`.
If its logs specifically report an inaccessible Windows AF_UNIX runtime socket
under `Docker/run` or `docker-secrets-engine`, use
`powershell -File scripts/start_docker.ps1 -RepairStaleSockets`. This stops Docker
Desktop, preserves those two runtime directories under dated names, and restarts
it. It does not reset Docker, remove volumes, or alter WSL disks. Verify
`docker version`, then run `docker compose up -d --wait postgres chhaya-api`.
The nginx service additionally requires your trusted TLS certificate files.
