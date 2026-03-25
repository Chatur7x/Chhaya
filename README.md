<div align="center">

# Chaaya 🌑

**Resilient. Offline. Secure.**
<br>
*A decentralized Mesh-Network Communication & Survival Platform designed to keep you connected when the grid goes dark.*

[![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Android](https://img.shields.io/badge/Android-Available-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Chatur7x/-PROJ16/releases/latest)

</div>

---

## 🌟 The Vision

**Chaaya** (Shadow) is built for the moments when traditional infrastructure fails. Whether you're in a disaster zone, at a crowded festival with no signal, or seeking privacy from centralized surveillance—Chaaya ensures your communications survive. 

By utilizing **Bluetooth Low Energy (BLE)** and **WiFi Direct**, devices form a self-healing, peer-to-peer mesh network. Messages hop from phone to phone until they reach their destination, entirely independent of cellular towers or the internet.

## ✨ Core Features

*   **🌐 True Decentralization:** No servers, no cellular network, no internet required. Devices connect directly.
*   **🔗 Multi-Transport Mesh:** 
    *   **BLE:** Low-power, continuous background discovery and small message routing.
    *   **WiFi Direct:** High-bandwidth connections for voice calls, file sharing, and video.
*   **🔒 Signal-Grade Encryption:** Every message is secured using the Double Ratchet Algorithm with X3DH, ensuring perfect forward secrecy. Your data is unreadable to anyone but the intended recipient.
*   **📻 Walkie-Talkie (PTT):** Zello-style Push-To-Talk radio interface over WiFi Direct. Includes an SOS priority channel that broadcasts instantly to all nearby nodes.
*   **🗺️ Offline Safety Map:** Shared tactical awareness. Pin hazard zones, safe points, and view the last-known locations of your mesh contacts—all stored locally.
*   **📞 Encrypted VoIP:** High-quality voice and video calls piped through direct device-to-device WiFi connections.
*   **📁 File & Media Vault:** Biometric-locked, AES-256 encrypted local storage for your sensitive documents and photos.
*   **🤖 Local AI Guardian:** On-device Llama/Gemma-powered assistant for survival guides, offline data analysis, and network diagnostics.
*   **📲 Background Persistence:** Uses foreground services and wake locks to maintain mesh connectivity even when the phone is locked.

## 🚀 Getting Started

### Prerequisites

*   Flutter SDK (3.41+)
*   Android Studio / Android SDK (API 24+)
*   **Two or more physical Android devices** (Mesh networking via BLE and WiFi Direct *cannot be tested on emulators*).

### Installation & Build

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Chatur7x/-PROJ16.git
   cd -PROJ16/frontend
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Build the Release APK:**
   ```bash
   flutter build apk --release
   ```
   *The generated APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.*

4. **Install on physical devices:**
   ```bash
   flutter install
   ```

> **⚠️ Permissions Note:** Upon first launch, Chaaya will request extensive permissions (Location, Nearby Devices, Bluetooth, Camera, Microphone). **These are strictly required** for the mesh networking hardware bridging to function.

## 📱 Try the App

You can download the latest pre-compiled Android APK directly from our releases page:

👉 **[Download Chaaya APK (Latest Release)](https://github.com/Chatur7x/-PROJ16/releases/latest)**

*(Note: Install the APK on at least two Android devices to test messaging and walkie-talkie features).*

## 🏗️ Architecture

Chaaya is built with a robust, layered architecture focusing on separation of concerns:

*   **Frontend UI:** Flutter + Riverpod for reactive state management.
*   **Networking Layer:** Custom `WifiDirectService` and `BleMeshService` handling native platform channels.
*   **Cryptography:** `SignalProtocolService` built on PointyCastle and `flutter_secure_storage`.
*   **Local Persistence:** Hive (NoSQL for Fast KV) & SQLite (Relational for Messages).
*   **Backend (Optional/Sync):** A Spring Boot Java backend exists in `../backend` for *optional* synchronization when internet access *is* available (bridging mesh islands).

## 🔒 Security Posture

*   **Identity:** Ed25519 Keypairs generated locally. No central registry.
*   **Pairing:** QR-code based public key exchange (out-of-band trust).
*   **Storage:** AES-256-GCM encrypted databases.
*   **Transit:** Double Ratchet E2EE over BLE/WiFi.

## 🗺️ Roadmap

- [x] BLE Discovery and Handshake
- [x] Basic Mesh Routing (1-hop)
- [x] WiFi Direct PTT Audio
- [ ] Multi-hop Mesh Routing Optimization (DSDV)
- [ ] iOS Connectivity (BLE only)
- [ ] Background Location Sync

## 📜 License

This project is open-source and available under the MIT License. See the [LICENSE](LICENSE) file for more information.
