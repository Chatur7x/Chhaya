# Chhaya

> **Privacy-first, end-to-end encrypted messenger. Open source.**

[![Flutter](https://img.shields.io/badge/Flutter-3.29%2B-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.7%2B-0175C2?logo=dart)](https://dart.dev)
[![Version](https://img.shields.io/badge/Version-14.0.0-green)](CHANGELOG.md)
[![CI](https://github.com/Chatur7x/Chhaya/actions/workflows/ci.yml/badge.svg)](https://github.com/Chatur7x/Chhaya/actions/workflows/ci.yml)

Chhaya is an open-source, end-to-end encrypted messenger. No phone number,
no email, no central identity — a 66-character anonymous identity with
audited cryptography, onion-routed transport, and a coercion-resistant
design. This project is community open source: free to use, modify.

---

## Features

### Privacy & Security
- **Anonymous identity** — no phone number or email required
- **End-to-end encryption** — X25519 + AES-256-GCM + Double Ratchet
- **Post-quantum hybrid key exchange** — X25519 + ML-KEM-1024 (V14)
- **Onion routing** — 3-hop circuits hide origin IP
- **Mesh networking** — BLE + Wi-Fi Aware offline messaging (V14)
- **Biometric lock** — fingerprint / face unlock, StrongBox-backed keys
- **Duress PIN** — decoy vault under coercion (V14)
- **Disappearing messages** — configurable timers
- **QR verification** — confirm contacts in person

### Communication
- Encrypted 1:1 and group chats
- Voice and peer-to-peer video calls (WebRTC)
- File sharing with decentralized chunk storage
- Typing indicators and read receipts
- Push notifications (FCM + APNs)

---

## Architecture

```
┌─────────────────────────────────────────┐
│  UI Layer (Flutter + Riverpod)          │
├─────────────────────────────────────────┤
│  Services (Auth, API, Network, Vault)   │
├─────────────────────────────────────────┤
│  Core (Crypto, Database, Models, Log)   │
├─────────────────────────────────────────┤
│  Secure Storage (Keystore / Keychain)   │
│  Encrypted DB (SQLCipher)               │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│  Backend (Node.js + TypeScript)         │
│  REST API :8443 / Signaling :8444       │
│  Onion Relay :8445 / PostgreSQL / Redis │
└─────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Flutter 3.29+, Dart 3.7+ |
| State | Riverpod 2.6 |
| Crypto (classical) | `cryptography` (X25519, Ed25519), `pointycastle` (AES-GCM, HKDF, PBKDF2) |
| Crypto (post-quantum) | ML-KEM-1024, ML-DSA-87 (V14) |
| Secure storage | `flutter_secure_storage` (Keystore / Keychain) |
| Local database | SQLCipher-encrypted SQLite |
| Calls | WebRTC (`flutter_webrtc`) |
| QR | `qr_flutter` / `mobile_scanner` (pinned 7.2.0) |
| Backend | Node.js 20, TypeScript 5.3, Express, PostgreSQL 16, Redis 7 |
| Push | `firebase-admin` (FCM + APNs) |
| Deploy | Docker + docker-compose |

---

## Project Structure

```
lib/
├── main.dart                  # App entry point
├── core/
│   ├── log.dart               # Structured app logger
│   ├── crypto/                # Engine facade + key manager
│   │   └── primitives/        # x25519, ed25519, aes_gcm, hkdf,
│   │                          # pbkdf2, sha, rng, bip39
│   ├── database/              # SQLCipher database + migrations
│   ├── models/                # ChhayaId, Contact, Message, ...
│   ├── providers/             # Riverpod providers
│   └── router/                # Route definitions
├── services/
│   ├── auth/                  # Account create / restore / backup
│   ├── api/                   # Backend REST client + sync
│   └── network/               # Onion routing, P2P, mesh (V14)
└── ui/
    ├── theme/                 # Claude Light design tokens (V14)
    ├── widgets/               # Design-system components
    └── screens/               # Onboarding, Chat, Calls, Settings, ...

backend/server/
├── src/
│   ├── index.ts, config.ts, log.ts, db.ts
│   ├── routes/                # auth, users, contacts, conversations,
│   │                          # messages, devices, push, onion (V14)
│   ├── middleware/            # auth, rateLimit, error (V14)
│   ├── signaling.ts           # WebRTC signaling :8444
│   ├── onion-relay.ts         # Onion relay :8445
│   └── push/                  # fcm, apns, tokens, topics (V14)
└── Dockerfile

test/
├── unit/crypto/               # Primitive vectors + engine tests
├── widget/                    # Widget + golden tests (V14)
└── integration/               # End-to-end flows (V14)
```

---

## Getting Started

### Prerequisites
- Flutter SDK **3.29+**, Dart SDK **3.7+**
- Android Studio / VS Code with Flutter extension
- JDK 17+ (Android builds)
- Node.js 20+ (backend only), Docker (backend deploy)

### Run the app

```bash
git clone https://github.com/Chatur7x/Chhaya.git
cd Chhaya
flutter pub get
flutter run
```

### Build release APK

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

### Run the backend

```bash
cd backend/server
npm install
cp .env.example .env   # configure secrets (never commit .env)
npm run dev
```

### Deploy with Docker

```bash
docker-compose up -d
```

---

## Security

See [SECURITY.md](SECURITY.md) for the threat model, audit status, and how
to report vulnerabilities. Do not open public issues for security bugs.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). All contributions go through
pull requests against `main`. One logical change per commit.

---

---

<p align="center">Your data belongs to you.</p>
