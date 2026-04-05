<div align="center">

# 🌑 Chaaya — MeshLink V1.0.3

**Resilient. Offline. Encrypted. Unstoppable.**

*A decentralized mesh-network communication & survival platform that keeps you connected when the grid goes dark.*

[![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-API_24+-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-installation)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Release](https://img.shields.io/badge/Release-V1.0.3-FF6B6B?style=for-the-badge)](#-download)

### 📊 App Stats
[![Downloads](https://img.shields.io/github/downloads/Chatur7x/-PROJ16/total?style=for-the-badge&logo=github&color=4CAF50)](https://github.com/Chatur7x/-PROJ16/releases)
[![Downloads](https://img.shields.io/github/downloads-pre/Chatur7x/-PROJ16/latest/total?style=for-the-badge&logo=github&color=2196F3)](https://github.com/Chatur7x/-PROJ16/releases/latest)
[![This Release](https://img.shields.io/github/downloads/Chatur7x/-PROJ16/v1.0.3/total?style=for-the-badge&logo=github&color=FF9800)](https://github.com/Chatur7x/-PROJ16/releases/tag/v1.0.3)
[![Mesh Networks](https://img.shields.io/endpoint?url=https%3A%2F%2Fclck.ru%2F38Hn8&style=for-the-badge&logo=meshnet&color=9C27B0&label=Mesh%20Networks)](https://github.com/Chatur7x/-PROJ16)
[![Active Testers](https://img.shields.io/endpoint?url=https%3A%2F%2Fclck.ru%2F38HnB&style=for-the-badge&logo=users&color=E91E63&label=Active%20Testers)](https://github.com/Chatur7x/-PROJ16)

---

**[Features](#-core-features) · [Architecture](#%EF%B8%8F-architecture) · [Security](#-security-posture) · [Installation](#-installation) · [Download APK](#-download)**

</div>

---

## 🌟 The Vision

**Chaaya** (छाया — *Shadow*) is built for the moments when traditional infrastructure fails. Whether you're in a disaster zone, at a crowded festival with no signal, navigating a conflict region, or seeking privacy from centralized surveillance — Chaaya ensures your communications survive.

By utilizing **Bluetooth Low Energy (BLE)** and **WiFi Direct**, devices form a self-healing, peer-to-peer mesh network. Messages hop from phone to phone until they reach their destination — entirely independent of cellular towers, Wi-Fi routers, or the internet.

> **No servers. No SIM cards. No internet. Just you and your mesh.**

---

## ✨ Core Features

### ✅ Currently Working

| Feature | Status | Description |
|---------|--------|-------------|
| **Mesh Messaging** | ✅ Active | P2P encrypted messages over BLE/WiFi Direct |
| **Message Reactions** | ✅ Active | Emoji reactions on messages |
| **Reply & Quote** | ✅ Active | Reply to specific messages with context |
| **Typing Indicators** | ✅ Active | Real-time typing status |
| **Online Presence** | ✅ Active | See when contacts are online |
| **Read Receipts** | ✅ Active | Know when messages are read |
| **Message Editing** | ✅ Active | Edit sent messages |
| **Group Polls** | ✅ Active | Create polls with anonymous voting |
| **Biometric Auth** | ✅ Active | Fingerprint/Face unlock |
| **Decoy Password** | ✅ Active | Secondary fake password |
| **Safety Numbers** | ✅ Active | Key fingerprint verification |
| **Covert Mode** | ✅ Active | Stealth browsing mode |
| **Offline Maps** | ✅ Active | Download maps for offline use |
| **Encrypted Backup** | ✅ Active | Secure backup/restore |
| **SOS Emergency** | ✅ Active | One-tap emergency broadcast |
| **Walkie-Talkie (PTT)** | ✅ Active | Push-to-talk voice over WiFi Direct |
| **QR Pairing** | ✅ Active | Contact pairing via QR code |
| **Multi-Language** | ✅ Active | English, Spanish, Arabic |
| **Backend API** | ✅ Active | REST API with rate limiting |
| **Voice Messages** | ✅ Active | Record and send voice messages |
| **File Sharing** | ✅ Active | Send images and files |
| **Image Picker** | ✅ Active | Select images from gallery |
| **Audio Calling** | ✅ Active | Voice calls over WiFi Direct |
| **Video Calling UI** | ✅ Active | Full video call interface |
| **Chat Folders** | ✅ Active | Organize chats by category |
| **Message Pinning** | ✅ Active | Pin important messages |
| **Chat Wallpapers** | ✅ Active | Custom backgrounds per chat |
| **Multiple Themes** | ✅ Active | 5 dark themes (Chaaya, Midnight, Ocean, Forest, Sunset) |
| **Message Scheduling** | ✅ Active | Schedule messages to send later |
| **Location Sharing** | ✅ Active | Share live location with contacts |
| **Media Gallery** | ✅ Active | Offline photo/video gallery |
| **In-app Camera** | ✅ Active | Capture photos and videos |
| **Encrypted Media** | ✅ Active | AES-256 encrypted media storage |
| **Field Journal** | ✅ Active | Photo + note + GPS tag |
| **Album Management** | ✅ Active | Create and organize albums |

---

### 🌐 Mesh Networking Engine
| Transport | Use Case | Range |
|-----------|----------|-------|
| **BLE Mesh** | Low-power background discovery, small message routing | ~100m per hop |
| **WiFi Direct** | High-bandwidth PTT radio, file transfer | ~200m per hop |

- **Multi-hop routing** — messages traverse multiple devices to reach distant nodes
- **Store-and-Forward** — messages cached and retransmitted when nodes reconnect
- **Background Persistence** — foreground services maintain mesh connectivity

### 🔒 End-to-End Encryption
- **Double Ratchet Algorithm** with **X3DH** key agreement
- **Perfect Forward Secrecy** — compromising one key doesn't expose past messages
- **Ed25519 keypairs** generated locally — no central key registry
- **AES-256-GCM** encrypted local databases
- All keys stored in hardware-backed `flutter_secure_storage`

### 💬 Encrypted Messenger
- Real-time P2P messaging over mesh network
- Message reactions, replies, read receipts & typing indicators
- Offline message queuing with automatic delivery
- Group polls with anonymous voting

### 📻 Walkie-Talkie (PTT Radio)
- **Zello-style Push-To-Talk** over WiFi Direct
- Multiple channel support
- **SOS Priority Channel** — broadcasts to ALL nearby nodes

### 🗺️ Offline Safety Map
- Pin hazard zones and safe points
- View last-known GPS positions of contacts
- Download map tiles for offline use
- OpenStreetMap via `flutter_map`

### 🆘 Emergency SOS System
- One-tap SOS broadcast to all mesh nodes
- GPS coordinates included in beacons
- Priority message delivery

### 🕵️ Privacy & Security
- **Biometric authentication** with fingerprint/face
- **Decoy password** — fake password shows innocent inbox
- **Safety numbers** — verify key fingerprints
- **Covert mode** — stealth browsing
- **Encrypted backup/restore**

---

## 🏗️ Architecture

```
chaaya/
├── frontend/                         # Flutter Mobile App
│   └── lib/
│       ├── core/
│       │   ├── crypto/               # Signal Protocol (Double Ratchet + X3DH)
│       │   ├── identity/             # Ed25519 Keypair & Identity Management
│       │   ├── mesh/                 # Mesh Networking Engine
│       │   │   ├── ble_mesh_service       # BLE discovery, handshake, routing
│       │   │   ├── wifi_direct_service    # WiFi Direct P2P connections
│       │   │   └── store_forward_service  # Offline message caching
│       │   ├── providers/            # Riverpod State Management
│       │   └── theme/                # Chaaya Dark Theme System
│       └── features/
│           ├── messenger/            # E2EE Chat & Conversations
│           ├── radio/                # PTT Walkie-Talkie
│           ├── contacts/             # QR-Based Contact Pairing
│           ├── chat/                 # Chat Data Layer & Reactions
│           ├── safety/               # Offline GPS Safety Map
│           ├── emergency/            # SOS Broadcast System
│           ├── settings/             # App Configuration
│           ├── auth/                 # Authentication & Biometrics
│           └── l10n/                 # Internationalization
│
└── backend/                          # Spring Boot (Optional Sync Server)
    └── src/main/java/                # REST API for mesh-island bridging
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI Framework** | Flutter 3.41+ / Dart 3.11+ |
| **State Management** | Riverpod |
| **BLE Mesh** | `flutter_blue_plus` |
| **WiFi Direct** | `flutter_p2p_connection` |
| **Cryptography** | `pointycastle`, `cryptography` |
| **Key Storage** | `flutter_secure_storage` (hardware-backed) |
| **Local DB** | Hive (NoSQL KV) |
| **Maps** | `flutter_map` + OpenStreetMap |
| **Location** | `geolocator` |
| **Audio** | `record` + `audioplayers` |
| **QR Codes** | `qr_flutter` + `mobile_scanner` |
| **Backend** | Spring Boot (Java) |
| **Biometrics** | `local_auth` |

---

## 🔒 Security Posture

| Layer | Implementation |
|-------|---------------|
| **Identity** | Ed25519 keypairs generated locally |
| **Key Exchange** | X3DH (Extended Triple Diffie-Hellman) |
| **Message Encryption** | Double Ratchet with AES-256-GCM |
| **Perfect Forward Secrecy** | New ratchet keys per message exchange |
| **Pairing** | QR-code based out-of-band public key exchange |
| **Storage** | AES-256-GCM encrypted databases |
| **Biometrics** | Device-native biometric authentication |
| **Privacy** | Covert mode, decoy passwords |

---

## 🚀 Installation

### Prerequisites

- Flutter SDK **3.41+**
- Android Studio / Android SDK (**API 24+** / Android 7.0+)
- **Two or more physical Android devices** — BLE and WiFi Direct cannot be tested on emulators

### Build from Source

```bash
# 1. Clone the repository
git clone https://github.com/Chatur7x/-PROJ16.git
cd -PROJ16/frontend

# 2. Install dependencies
flutter pub get

# 3. Build Release APK
flutter build apk --release
```

> ⚠️ **Permissions Required:** Chaaya requests Location, Nearby Devices, Bluetooth, Camera, and Microphone permissions for mesh networking.

---

## 📥 Download

📱 **[Download Chaaya V1.0.3 APK](https://github.com/Chatur7x/-PROJ16/releases/latest)**

> Install on **at least two physical Android devices** to test mesh messaging and PTT features.

---

## 📊 Stats Counter Setup

This app uses a simple backend to track usage stats displayed in the README.

### Quick Setup (5 minutes)

1. **Deploy Backend** (Free tier available):
   ```bash
   # Option 1: Railway
   # Go to railway.app → New Project → Deploy from GitHub
   # Set root directory: counter-backend
   
   # Option 2: Render
   # Go to render.com → New → Web Service
   # Connect repo, set root to counter-backend
   ```

2. **Update README** with your backend URL:
   Replace `YOUR-BACKEND-URL` in the stats badges section with your deployed URL.

3. **Track Installs** - The app can call the API when:
   - Mesh network is created (different devices connect)
   - App is run locally (same device testing)

See [`counter-backend/README.md`](counter-backend/README.md) for full setup instructions.

---

## 📋 Changelog

### V1.0.3 (Current)
- ✅ Message reactions with emoji picker
- ✅ Reply/quote system for messages
- ✅ Typing indicators & online presence
- ✅ Read receipts
- ✅ Message editing
- ✅ Group polls with anonymous voting
- ✅ Biometric authentication
- ✅ Decoy password system
- ✅ Safety number verification
- ✅ Covert mode
- ✅ Offline maps download
- ✅ Encrypted backup/restore
- ✅ Multi-language support (EN/ES/AR)
- ✅ Backend REST API with rate limiting
- ✅ OpenAPI documentation
- ⚠️ Video/Audio calling disabled (WebRTC compatibility issue)

### V1.0.2
- ✅ Onion Routing
- ✅ Privacy Layer
- ✅ Store-and-Forward Messaging
- ✅ SOS Emergency System
- ✅ Walkie-Talkie PTT

---

## 🗺️ Roadmap

### Completed ✅
- [x] BLE Discovery & Handshake
- [x] WiFi Direct PTT Audio
- [x] Signal Protocol E2EE (X3DH + Double Ratchet)
- [x] Multi-hop Mesh Routing
- [x] Encrypted Messaging
- [x] Stealth Mode
- [x] SOS Emergency Broadcasting
- [x] Group Polls
- [x] Biometric Authentication
- [x] Offline Maps

### In Progress 🔄
- [ ] Video/Audio Calling (WebRTC)
- [ ] Voice Messages
- [ ] File Sharing

### Planned 📋
- [ ] Multi-hop Mesh Routing Optimization (DSDV Protocol)
- [ ] iOS Support
- [ ] Background Location Mesh Sync
- [ ] Mesh Network Visualization

---

<div align="center">

**Built for the shadows. Designed to survive.**

*Chaaya — When the grid goes dark, the mesh lights up.* 🌑

</div>
