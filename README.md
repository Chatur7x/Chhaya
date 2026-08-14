# Chhaya - The Secure Messenger

> Privacy Redefined. Speed Perfected. Apple-Grade Design.

Chhaya is a secure messaging app that keeps your conversations private. It combines the best features of Threema (clean design, large file sharing) and Session (decentralized network, anonymous identity).

---

## What is Chhaya?

Chhaya is an app for sending messages, making calls, and sharing files. Everything is encrypted, so only you and the person you are talking to can see your messages. No one else - not even us - can read them.

### Key Features

**Privacy & Security**
- No phone number or email needed - your identity is a 66-character code
- All messages are encrypted with military-grade encryption
- Messages route through 3 anonymous servers to hide your location
- Messages can self-destruct after a set time
- Fingerprint or face unlock to open the app
- Enter a special PIN to instantly delete all data

**Communication**
- Send text messages to individuals or groups (up to 256 people)
- Make voice and video calls
- Send files up to 100MB
- Create polls in group chats
- See when someone is typing or has read your message

**Design**
- Beautiful Apple-style interface
- Smooth animations at 120 frames per second
- True black background for battery savings
- Frosted glass effects

---

## How It Works

### Creating an Account
1. Open the app
2. Tap "Create Account"
3. A 66-character identity code is generated for you
3. You get 12 recovery words - write them down!
4. You are ready to use the app

### Sending a Message
1. Open a chat
2. Type your message
3. Message is encrypted (locked with a secret key)
4. Message goes through 3 anonymous servers
5. Only the recipient can unlock and read it

### Making a Call
1. Open a chat
2. Tap the call button
3. Your devices connect directly
4. Audio/video streams peer-to-peer (no server)

---

## Tech Stack

| Part | Technology |
|------|------------|
| App | Flutter (works on Android, iOS, Windows) |
| State | Riverpod (manages app data) |
| Database | Hive (stores messages locally) |
| Encryption | AES-256-GCM + Double Ratchet |
| Calls | WebRTC (peer-to-peer) |
| Onion Server | Go language |
| File Server | Rust language |

---

## Project Structure

```
lib/
  main.dart                    - App entry point
  core/
    crypto/                    - Encryption engine
    database/                  - Local storage
    models/                    - Data structures
    providers/                 - State management
    router/                    - Screen navigation
  services/
    auth/                      - Account management
    network/                   - Onion routing, calls, files
    notification/              - Notification banners
  ui/
    screens/                   - All app screens
    theme/                     - Colors and styles
    widgets/                   - Reusable components
backend/
  node/                        - Go onion routing server
  relay/                       - Rust file storage server
```

---

## Getting Started

### Prerequisites
- Flutter SDK 3.29 or higher
- Dart SDK 3.7 or higher
- Android Studio or VS Code

### Install and Run

```bash
# Get dependencies
flutter pub get

# Run on device
flutter run

# Build APK
flutter build apk --release
```

### Run Backend Servers (Optional)

```bash
# File storage server (Rust)
cd backend/relay
cargo run

# Onion routing server (Go)
cd backend/node
go run main.go
```

---

## Security Features

| Feature | What It Does |
|---------|--------------|
| Zero Knowledge Identity | No phone/email needed |
| End-to-End Encryption | Only you and recipient can read |
| Forward Secrecy | Old messages stay safe |
| Onion Routing | Hides your IP address |
| Biometric Lock | Fingerprint/face unlock |
| Panic PIN | Special code wipes all data |
| Disappearing Messages | Auto-delete after time |
| QR Verification | Verify contacts in person |

---

## Dependencies

| Package | Purpose |
|---------|---------|
| flutter_riverpod | State management |
| pointycastle | Encryption algorithms |
| crypto | Hashing functions |
| hive | Local database |
| flutter_webrtc | Voice/video calls |
| qr_flutter | Generate QR codes |
| mobile_scanner | Scan QR codes |
| local_auth | Biometric authentication |
| flutter_local_notifications | Notification banners |
| file_picker | Select files |

---


---

## Contact

GitHub: [Chatur7x](https://github.com/Chatur7x)

---

Built with security in mind. Your privacy matters.
