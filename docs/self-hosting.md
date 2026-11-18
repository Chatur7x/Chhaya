# Hosting the messenger backend

A running backend is required for internet messaging. No server, domain,
Apple membership, or Firebase account is bundled or provisioned by this repo.
The Docker configuration is deployment preparation, not a live service.

1. Provision a Linux server with Docker Compose and a domain pointing to it.
2. Copy .env.example to .env. Generate unique random values for both variables.
   Keep POSTGRES_PASSWORD URL-safe (letters/digits) for the connection string.
3. Obtain a trusted TLS certificate for the domain. Put fullchain.pem and
   privkey.pem in certs/ beside nginx.conf. Never commit private keys.
4. Run docker compose config, then docker compose up -d --build.
5. Check https://YOUR-DOMAIN/health. Configure the same HTTPS origin in each app.
6. Back up the PostgreSQL volume and keep the host/security updates current.

Only HTTPS is published. PostgreSQL is private to the Docker network.
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
