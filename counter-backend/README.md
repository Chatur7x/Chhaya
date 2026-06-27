# Catus Chat Counter Backend

Simple backend for tracking Catus Chat mesh network statistics.

## Deploy to Railway (Free)

1. Create account at [railway.app](https://railway.app)
2. New Project → Deploy from GitHub → Select this repo
3. Set root directory to `counter-backend`
4. Deploy!

Your backend URL will be: `https://Catus Chat-counter.up.railway.app`

## Deploy to Render (Free)

1. Create account at [render.com](https://render.com)
2. New → Web Service
3. Connect GitHub repo
4. Set root directory to `counter-backend`
5. Build command: `npm install`
6. Start command: `node server.js`
7. Deploy!

## Update README Badges

After deploying, update the README badges with your backend URL:

```markdown
[![Mesh Networks](https://img.shields.io/endpoint?url=https%3A%2F%2FYOUR-RAILWAY-URL.railway.app%2Fdifferent-devices&style=for-the-badge&logo=meshnet&color=9C27B0&label=Mesh%20Networks)](https://github.com/Chatur7x/-PROJ16)
[![Active Testers](https://img.shields.io/endpoint?url=https%3A%2F%2FYOUR-RAILWAY-URL.railway.app%2Fsame-device&style=for-the-badge&logo=users&color=E91E63&label=Active%20Testers)](https://github.com/Chatur7x/-PROJ16)
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/stats` | GET | Get all counters |
| `/different-devices` | GET | Get mesh networks count |
| `/same-device` | GET | Get same device runs count |
| `/different-devices/increment` | POST | Increment mesh network count |
| `/same-device/increment` | POST | Increment same device count |

## Usage

Track different device runs (mesh networks created):
```bash
curl -X POST https://your-backend.railway.app/different-devices/increment
```

Track same device runs (local testing):
```bash
curl -X POST https://your-backend.railway.app/same-device/increment
```
