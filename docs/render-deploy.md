# Deploy Chhaya's backend to Render

The repository includes a Render Blueprint at `/render.yaml`. It creates a
Docker web service and a private PostgreSQL database in Singapore, generates
the JWT secret in Render, and connects the database without storing credentials
in Git. The API and authenticated call-signaling WebSocket share the web
service's public port (`/` and `/signaling`).

### Repair an existing service created from the repository root

The manual service in the shared Render dashboard was configured to use the
repository root as its Docker build context. Its first build failed because it
could not find a root `Dockerfile`. The repository now includes a root Dockerfile
and a narrow root `.dockerignore`, so that existing configuration can build.
Alternatively, in **Service → Settings → Build**, set **Root Directory** to
`backend/server` and keep **Dockerfile Path** as `Dockerfile`; that uses the
backend-local Dockerfile. Save the setting and trigger a deploy from the latest
commit. The dashboard's failed first deploy was for an older `main` commit, so
it will not pick up this fix until the updated commit is deployed.

For a new setup, prefer the Blueprint steps below; the Blueprint already sets
`rootDir: backend/server` and provisions its matching Postgres database.

## Create the services

1. Push this repository and branch to GitHub.
2. Sign in to Render, choose **New → Blueprint**, and connect the Chhaya repo.
3. Review the two services and the current monthly estimate before applying the
   Blueprint. The configuration uses paid, always-on plans; it does not use
   Render's expiring free Postgres database or sleeping free web service.
4. Apply the Blueprint and wait for the first deployment to pass `/health`. The
   endpoint checks PostgreSQL readiness and returns HTTP 503 if the database is
   unavailable, so Render will not route traffic to a process that cannot serve
   API requests.
5. Open the service's `https://…onrender.com/health` URL. It should return JSON
   with `"status":"ok"`.
6. In Chhaya, open **Settings → Server** and set the base URL to the service's
   HTTPS URL (no trailing slash). Call signaling uses the same host over WSS at
   `/signaling`.

At the prices currently listed, the selected web plan is $7/month and the
smallest paid 256 MB Postgres compute plan is $6/month, for an expected starting
total of about **$13/month** with the configured 1 GB database disk, before
taxes, bandwidth, storage growth, or other usage. Verify the estimate in
Render's dashboard before applying. PostgreSQL data
is durable and paid instances include Render-managed backups, but this initial
setup is a single service and single database; it is not a high-availability
production deployment. Configure and test database restore procedures before
using the server for important conversations.

## Before using it with real users

- Test account registration, restore/login, two-device messaging, reconnects,
  and calls against the deployed HTTPS/WSS origin.
- Set up Firebase credentials separately if Android push notifications are
  required. Without them, push stays disabled.
- Do not treat the server as independently audited or the app as production
  ready. Review `docs/threat-model.md` and `docs/delivery-checklist.md`.
- Keep service and database credentials in Render's environment settings; do
  not commit secrets or production account data.

The Blueprint deploys infrastructure from source; it does not create or publish
Android/iOS builds and does not configure app-store signing.
