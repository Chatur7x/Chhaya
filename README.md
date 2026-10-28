# Chhaya

<p align="center"><strong>A private, account-light messenger in active development.</strong><br>Flutter apps for Android and iOS, with a self-hosted messaging backend.</p>

<p align="center"><a href="https://github.com/Chatur7x/Chhaya/actions/workflows/ci.yml"><img src="https://github.com/Chatur7x/Chhaya/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <img src="https://img.shields.io/badge/Flutter-3.47%2B-02569B?logo=flutter" alt="Flutter 3.47 or newer"> <img src="https://img.shields.io/badge/status-development-orange" alt="Development status"></p>

> **Development build, not a production messenger.** Internet messaging needs a Chhaya backend that you host. Android test APKs are debug signed; no signed iOS build or store release is available. Cryptography and transport have not had an independent security audit.

## What works today

- Create or restore a local account from a recovery phrase; no phone number or email is required.
- Store local account data in SQLCipher and device secure storage.
- Send end-to-end encrypted one-to-one text messages after both people connect to the same server and verify each other's identity.
- Queue outgoing messages for retry, reply to messages, and configure local privacy settings.
- Send small encrypted attachments and voice notes. Attachments are currently limited to 256 KB.
- Place foreground WebRTC voice and video calls. Some networks need a separately configured TURN server.
- Build and run the Flutter Android and iOS targets; backend deployment files are provided for self-hosting.

## What is not ready

Group creation, member administration, encrypted polls, background call delivery and push are implemented to varying degrees, but still need cross-device acceptance testing; secure group invitation/member addition is not complete. Large/chunked file transfer, offline mesh, onion routing, sealed sender, Arke discovery, a secure vault, coercion features, and verified post-quantum messaging are not complete. See the [delivery checklist](docs/delivery-checklist.md) for implementation and evidence for each feature.

## Architecture

- **Mobile:** Flutter and Dart, with Riverpod state management.
- **Local security:** SQLCipher database, platform secure storage, X25519 identity, AES-GCM message envelopes, and a ratcheted direct-message session.
- **Backend:** Node.js and TypeScript with Express, PostgreSQL, REST endpoints, and authenticated WebSocket call signaling.
- **Deployment:** Docker Compose and Nginx configuration for self-hosting; no public Chhaya server is included.

Read the [architecture overview](docs/architecture.md), [threat model](docs/threat-model.md), [cryptography notes](docs/crypto.md), and [backend hosting guide](docs/self-hosting.md) before testing sensitive workflows.

## Run locally

Install Flutter 3.47 or newer and the Android toolchain. From the repository root, run:

<pre>flutter pub get<br>flutter run</pre>

To run the backend, use Node.js 20 or newer, configure the environment from the checked-in example, and follow [self-hosting.md](docs/self-hosting.md). Messaging will not work between devices until both apps use the same live HTTPS server.

## Verification

<pre>flutter analyze<br>flutter test<br>cd backend/server<br>npm ci<br>npm test</pre>

The full Flutter test suite includes a deliberately large ratchet fuzz test and can take several minutes. The SQLCipher at-rest proof requires a host with the native SQLCipher implementation.

## Sharing builds

See [test-builds.md](docs/test-builds.md). The Android artifact is for testing and uses a debug certificate. Installing a differently signed build may require uninstalling the prior one, which deletes that installation's local data. iOS installation requires Apple signing and provisioning.

## Project guide

| Document | Purpose |
| --- | --- |
| [Architecture](docs/architecture.md) | Implemented data flow and system boundaries |
| [Delivery checklist](docs/delivery-checklist.md) | Feature status and acceptance evidence |
| [Threat model](docs/threat-model.md) | Security assumptions and limitations |
| [Cryptography](docs/crypto.md) | Implemented primitives and protocol notes |
| [Self-hosting](docs/self-hosting.md) | Backend setup and operational requirements |
| [Render deployment](docs/render-deploy.md) | Deploy the API and PostgreSQL with Render |
| [Test builds](docs/test-builds.md) | Android/iOS test distribution and device testing |
| [Performance notes](docs/performance.md) | Android sync tuning, APK size, and measured limits |
| [Contributing](CONTRIBUTING.md) | Contribution workflow |
| [Security](SECURITY.md) | Responsible vulnerability reporting |

The repository's licensing intent also needs owner confirmation; check the [LICENSE](LICENSE) file before redistribution.

<p align="center">Built for quieter, more private conversations.</p>
