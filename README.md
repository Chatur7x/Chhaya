<div align="center">

# 🌑 Chaaya — MeshLink V1.0.2

**Resilient. Offline. Encrypted. Unstoppable.**

*A decentralized mesh-network communication & survival platform that keeps you connected when the grid goes dark.*

[![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-API_24+-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-installation)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Release](https://img.shields.io/badge/Release-V1.0.2-FF6B6B?style=for-the-badge)](#-download)

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

### 🌐 Mesh Networking Engine
| Transport | Use Case | Range |
|-----------|----------|-------|
| **BLE Mesh** | Low-power background discovery, small message routing, device handshake | ~100m per hop |
| **WiFi Direct** | High-bandwidth voice calls, file transfer, PTT radio, video | ~200m per hop |

- **Multi-hop routing** — messages traverse multiple devices to reach distant nodes
- **Store-and-Forward** — messages are cached and retransmitted when new nodes enter range
- **Channel Hopping** — automatic frequency switching to avoid interference and detection
- **Mesh Router** — intelligent path selection with TTL-based routing tables
- **Background Persistence** — foreground services and wake locks maintain mesh connectivity even when the phone is locked

### 🔒 Signal-Grade End-to-End Encryption (E2EE)
- **Double Ratchet Algorithm** with **X3DH** key agreement — the same cryptographic foundation as Signal
- **Perfect Forward Secrecy** — compromising one key doesn't expose past messages
- **Ed25519 keypairs** generated locally — no central key registry
- **AES-256-GCM** encrypted local databases and vault storage
- All keys stored in hardware-backed `flutter_secure_storage`

### 💬 Encrypted Messenger
- Real-time P2P messaging over the mesh network
- Conversation threads with read receipts and typing indicators
- Offline message queuing with automatic delivery when peers reconnect
- Media attachments (images, files) over WiFi Direct

### 📻 Walkie-Talkie (PTT Radio)
- **Zello-style Push-To-Talk** radio interface over WiFi Direct
- Multiple channel support with channel switching
- **SOS Priority Channel** — broadcasts instantly to ALL nearby mesh nodes
- Real-time audio streaming with low-latency codec

### 📞 Encrypted Voice & Video Calling
- High-quality VoIP piped through device-to-device WiFi Direct connections
- Call UI with mute, speaker, and video toggle
- Fully encrypted — no server intermediary

### 🗺️ Offline Safety Map
- Pin **hazard zones**, safe points, and resource locations
- View **last-known GPS positions** of mesh contacts
- All data stored locally — works completely offline
- OpenStreetMap tiles via `flutter_map`

### 🤖 Local AI Guardian
- On-device **Llama/Gemma** powered assistant
- Survival guides, first-aid instructions, offline data analysis
- Network diagnostics and mesh health monitoring
- **Zero cloud dependency** — all inference runs locally

### 🕵️ Stealth & Privacy Layer
- **Hidden Inbox** — secret message vault accessible only via authentication
- **Onion Routing** — multi-layer encrypted routing that obscures sender identity
- **Path Discovery** — anonymous route selection through the mesh
- **Privacy Layer** — traffic padding and timing obfuscation to prevent analysis
- **Dead Drop Service** — asynchronous anonymous message exchange via shared mesh locations
- **Panic Wipe** — instant cryptographic erasure of all sensitive data

### 🆘 Emergency SOS System
- One-tap SOS broadcast to all mesh nodes
- GPS coordinates included in emergency beacons
- Priority message delivery — SOS packets bypass normal queue

### 📱 Contact Pairing
- **QR Code Based** — scan to exchange public keys out-of-band
- Zero-trust pairing model — no centralized contact server
- Contact verification with fingerprint comparison

### 📁 Secure Media Vault
- Biometric-locked encrypted storage
- AES-256 file encryption at rest
- Support for documents, photos, and media files

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
│       │   │   ├── mesh_router            # Multi-hop path selection
│       │   │   ├── channel_hopper         # Anti-detection frequency hopping
│       │   │   ├── store_forward_service  # Offline message caching
│       │   │   └── message_queue          # Reliable delivery queue
│       │   ├── network/              # Advanced Network Layer
│       │   │   ├── onion_router           # Multi-layer encrypted routing
│       │   │   ├── path_discovery         # Anonymous route discovery
│       │   │   ├── dead_drop_service      # Async anonymous exchange
│       │   │   ├── privacy_layer          # Traffic analysis protection
│       │   │   └── platform_channel_bridge # Native Android/iOS bridge
│       │   ├── providers/            # Riverpod State Management
│       │   ├── presentation/         # Main App Shell & Navigation
│       │   ├── theme/                # Chaaya Dark Theme System
│       │   └── notifications/        # Push & Local Notifications
│       └── features/
│           ├── messenger/            # E2EE Chat & Conversations
│           ├── radio/                # PTT Walkie-Talkie
│           ├── calling/              # Encrypted Voice/Video Calls
│           ├── contacts/             # QR-Based Contact Pairing
│           ├── chat/                 # Chat Data Layer & Domain
│           ├── safety/              # Offline GPS Safety Map
│           ├── emergency/            # SOS Broadcast System
│           ├── stealth/              # Hidden Inbox & Panic Wipe
│           ├── ai/                   # Local AI Assistant
│           ├── identity/             # Identity Setup & Display
│           ├── settings/             # App Configuration
│           └── auth/                 # Authentication Layer
│
└── backend/                          # Spring Boot (Optional Sync Server)
    └── src/main/                     # REST API for mesh-island bridging
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI Framework** | Flutter 3.41+ / Dart 3.11+ |
| **State Management** | Riverpod |
| **BLE Mesh** | `flutter_blue_plus` |
| **WiFi Direct** | `flutter_p2p_connection` + Platform Channels |
| **Cryptography** | `pointycastle`, `cryptography`, `encrypt` |
| **Key Storage** | `flutter_secure_storage` (hardware-backed) |
| **Local DB** | Hive (NoSQL KV) + SQLite (relational messages) |
| **Maps** | `flutter_map` + `latlong2` (OpenStreetMap) |
| **Location** | `geolocator` |
| **Audio** | `record` + `audioplayers` |
| **QR Codes** | `qr_flutter` + `mobile_scanner` |
| **Backend** | Spring Boot (Java) — optional sync server |

---

## 🔒 Security Posture

| Layer | Implementation |
|-------|---------------|
| **Identity** | Ed25519 keypairs generated locally — no central registry |
| **Key Exchange** | X3DH (Extended Triple Diffie-Hellman) |
| **Message Encryption** | Double Ratchet with AES-256-GCM |
| **Perfect Forward Secrecy** | New ratchet keys per message exchange |
| **Pairing** | QR-code based out-of-band public key exchange |
| **Storage** | AES-256-GCM encrypted databases |
| **Transit** | E2EE over BLE / WiFi Direct — zero plaintext on the wire |
| **Anonymity** | Onion routing with multi-layer encryption |
| **Anti-Analysis** | Traffic padding, timing obfuscation, channel hopping |
| **Emergency** | Panic wipe — cryptographic key destruction |

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

# 4. Install on physical devices
flutter install
```

The generated APK will be at:
```
frontend/build/app/outputs/flutter-apk/Chaaya-Release-V1.0.2.apk
```

> ⚠️ **Permissions Required:** Chaaya requests Location, Nearby Devices, Bluetooth, Camera, and Microphone permissions. These are **strictly required** for mesh networking hardware bridging to function.

---

## 📥 Download

Grab the latest pre-compiled APK:

👉 **[Download Chaaya V1.0.2 APK](https://github.com/Chatur7x/-PROJ16/releases/latest)**

> Install the APK on **at least two physical Android devices** to test mesh messaging, walkie-talkie, and calling features.

---

## 📋 What's New in V1.0.2 — MeshLink

This release introduces the **MeshLink architecture** — a complete overhaul of the networking and privacy stack:

### 🆕 New in V1.0.2
- ✅ **Onion Routing** — multi-layer encrypted routing to obscure sender identity
- ✅ **Path Discovery** — anonymous route selection through the mesh
- ✅ **Dead Drop Service** — asynchronous anonymous message exchange
- ✅ **Privacy Layer** — traffic padding and timing obfuscation
- ✅ **Channel Hopping** — automatic frequency switching for anti-detection
- ✅ **Store-and-Forward** — offline message caching with auto-delivery
- ✅ **Hidden Inbox (Stealth Mode)** — secret vault for sensitive conversations
- ✅ **Panic Wipe** — instant cryptographic destruction of all data
- ✅ **Platform Channel Bridge** — native Android hardware integration
- ✅ **SOS Emergency System** — one-tap broadcast with GPS coordinates
- ✅ **Encrypted Voice/Video Calling** — P2P calls over WiFi Direct
- ✅ **Local AI Guardian** — on-device survival assistant
- ✅ **Complete Signal Protocol** — full X3DH + Double Ratchet implementation

### 🔄 Improved
- ⬆️ BLE Mesh Service — enhanced discovery and auto-reconnection
- ⬆️ WiFi Direct Service — improved stability and bandwidth handling
- ⬆️ Message Queue — reliable delivery with retry logic
- ⬆️ Mesh Router — smarter TTL-based multi-hop path selection
- ⬆️ Theme System — polished dark UI with gradient accents

---

## 🗺️ Roadmap

- [x] BLE Discovery & Handshake
- [x] WiFi Direct PTT Audio
- [x] Signal Protocol E2EE (X3DH + Double Ratchet)
- [x] Multi-hop Mesh Routing
- [x] Onion Routing & Privacy Layer
- [x] Store-and-Forward Messaging
- [x] Stealth Mode & Panic Wipe
- [x] Encrypted Calling (Voice + Video)
- [x] Local AI Assistant
- [x] SOS Emergency Broadcasting
- [ ] Multi-hop Mesh Routing Optimization (DSDV Protocol)
- [ ] iOS Support (BLE mesh only)
- [ ] Background Location Mesh Sync
- [ ] Group Mesh Chat Rooms
- [ ] Mesh Network Visualization Dashboard

---

## 📄 License

------
---

<div align="center">

**Built for the shadows. Designed to survive.**

*Chaaya — When the grid goes dark, the mesh lights up.* 🌑

</div>
