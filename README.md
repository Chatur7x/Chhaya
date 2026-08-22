# Chhaya 🛡️

> **Privacy Redefined. Speed Perfected. Material Design.**

Chhaya is a privacy-first, end-to-end encrypted messenger inspired by Threema and Session. No phone number, no email, no central server — just a 66-character anonymous identity and military-grade encryption.

[![Flutter](https://img.shields.io/badge/Flutter-3.29%2B-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.7%2B-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ✨ Features

### 🔒 Privacy & Security
- **Anonymous identity** — no phone number or email required
- **End-to-end encryption** via AES-256-GCM + Double Ratchet
- **Onion routing** through 3 anonymous hops to hide your IP
- **Biometric lock** with fingerprint / face unlock
- **Panic PIN** — enter a special code to instantly wipe all data
- **Disappearing messages** with configurable timers
- **QR code verification** to confirm contacts in person

### 💬 Communication
- Encrypted 1:1 and group text chats
- HD voice and **peer-to-peer video calls** via WebRTC
- File sharing with decentralized chunk storage
- In-chat polls and reactions
- Typing indicators and read receipts

### 🎨 Design
- Clean **Material 3** dark UI with true-black background
- Frosted-glass cards and spring-physics animations
- 120 Hz-friendly motion and haptic feedback

---

## 📸 Screenshots

> *Add your screenshots inside `assets/screenshots/` and update the paths below.*

| Onboarding | Chats | Call | Settings |
|---|---|---|---|
| ![Onboarding](assets/screenshots/onboarding.png) | ![Chats](assets/screenshots/chats.png) | ![Call](assets/screenshots/call.png) | ![Settings](assets/screenshots/settings.png) |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│  UI Layer (Flutter + Riverpod)          │
├─────────────────────────────────────────┤
│  Services (Auth, Network, Calls, Files) │
├─────────────────────────────────────────┤
│  Core (Crypto, Database, Models)        │
├─────────────────────────────────────────┤
│  Local Storage (Hive) + Key Store       │
└─────────────────────────────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Flutter 3.29+ |
| State Management | Riverpod |
| Local Database | Hive |
| Cryptography | PointyCastle / `crypto` |
| Voice/Video Calls | WebRTC (`flutter_webrtc`) |
| QR Codes | `qr_flutter` / `mobile_scanner` |
| Biometrics | `local_auth` |
| Notifications | `flutter_local_notifications` |

---

## 📁 Project Structure

```
lib/
├── main.dart                     # App entry point
├── core/
│   ├── crypto/                   # Encryption engine & key manager
│   ├── database/                 # Hive local database
│   ├── models/                   # ChhayaId, Contact, Message, etc.
│   ├── providers/                # Riverpod state providers
│   └── router/                   # Route definitions
├── services/
│   ├── auth/                     # Account creation / restore / backup
│   └── network/                  # Onion routing, P2P calls, file client
└── ui/
    ├── screens/                  # Onboarding, Chat, Calls, Settings, etc.
    ├── theme/                    # Colors, typography, components
    └── widgets/                  # Reusable buttons, avatars, glass cards

backend/
├── node/                         # Go onion-routing relay
└── relay/                        # Rust decentralized file relay
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK **3.29+**
- Dart SDK **3.7+**
- Android Studio / VS Code with Flutter extension
- JDK 17+ (for Android builds)

### Install & Run

```bash
# Clone the repo
git clone https://github.com/Chatur7x/Chhaya.git
cd Chhaya

# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run
```

### Build APK

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```

The release APK will be generated at:

```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🖥️ Backend Servers (Optional)

```bash
# Decentralized file relay (Rust)
cd backend/relay
cargo run

# Onion routing node (Go)
cd backend/node
go run main.go
```

---

## 🔐 Security Checklist

| Feature | Description |
|---------|-------------|
| Zero-Knowledge Identity | No phone/email tied to your account |
| End-to-End Encryption | Only sender and recipient can read messages |
| Forward Secrecy | Keys rotate with every message |
| Onion Routing | Hides origin IP across 3 hops |
| Biometric Lock | Require fingerprint/face to open the app |
| Panic PIN | Instantly wipe local data |
| Disappearing Messages | Auto-delete after a set duration |
| QR Verification | Confirm contacts in person |

---

## 🤝 Contributing

Contributions are welcome. Please open an issue or pull request on [GitHub](https://github.com/Chatur7x/Chhaya).

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">Built with privacy in mind. Your data belongs to you.</p>
