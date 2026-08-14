# Chhaya - Complete Code Explanation

This file explains every part of the Chhaya app code in simple English.

---

## Project Overview

Chhaya is a secure messaging app. It uses encryption to keep your messages private. The app works on Android, iOS, and Windows.

---

## File Structure

```
lib/
  main.dart                          - App starts here
  core/
    crypto/
      chhaya_crypto_engine.dart      - Encryption and decryption
      key_manager.dart               - Save and load secret keys
    database/
      local_database.dart            - Save messages and contacts locally
    models/
      chhaya_id.dart                 - User identity (public key)
      contact.dart                   - Contact person data
      conversation.dart              - Chat conversation data
      message.dart                   - Single message data
      user_profile.dart              - Your profile data
    providers/
      app_providers.dart             - State management (Riverpod)
    router/
      chhaya_router.dart             - Screen navigation
  services/
    auth/
      auth_service.dart              - Login, signup, logout
    network/
      onion_router_service.dart      - Hide your IP address
      p2p_tunnel_service.dart        - Voice and video calls
      decentralized_file_client.dart - Send large files
    notification/
      notification_service.dart      - Show notifications
  ui/
    screens/
      onboarding/                    - Welcome and signup screens
      home/                          - Main app shell (tabs)
      chat_list/                     - List of all chats
      chat/                          - Single chat screen
      call/                          - Voice/video call screen
      contacts/                      - Contact list
      profile/                       - User profile screen
      settings/                      - App settings
      verification/                  - QR code verification
    theme/
      chhaya_theme.dart              - Colors, fonts, spacing
    widgets/
      avatar_widget.dart             - User avatar circle
      chhaya_button.dart             - Styled buttons
      glass_container.dart           - Frosted glass effect
      notification_overlay.dart      - In-app notification banner
backend/
  node/                              - Go server for onion routing
  relay/                             - Rust server for file storage
```

---

## Core Layer Explanation

### chhaya_crypto_engine.dart

This is the heart of security. It does:

1. **Key Generation**: Creates a pair of keys (public and private) using random numbers. The public key is shared with others. The private key stays secret.

2. **Encryption**: Takes your message and a shared secret. Produces encrypted data that only the other person can read. Uses AES-256-GCM algorithm.

3. **Decryption**: Takes encrypted data and the same shared secret. Produces the original message.

4. **Shared Secret**: Combines your private key with their public key to create a secret both of you know.

5. **Hashing**: Uses SHA-256 to turn any data into a fixed 32-byte value.

6. **Recovery Phrase**: Generates 12 random words. If you lose your phone, you can use these words to get your account back.

7. **Double Ratchet**: A special protocol that changes encryption keys with every message. If someone steals one key, they cannot read old messages.

### key_manager.dart

Saves your secret keys to the phone's storage. Uses SharedPreferences (simple key-value storage). Stores:
- Public key
- Private key
- Recovery phrase (12 words)

### local_database.dart

Uses Hive (a fast NoSQL database) to save data locally on your phone. Stores:
- Messages (all your chat messages)
- Contacts (people you talk to)
- Conversations (chat threads)
- User profile (your account info)
- Settings (preferences)

Also handles biometric authentication (fingerprint/face unlock).

### Models

**chhaya_id.dart**: Your identity. A 66-character hexadecimal string. No phone number or email needed.

**contact.dart**: A person you can talk to. Has:
- Name
- ChhayaId (their public key)
- Verification level (1=unverified, 2=some trust, 3=fully verified)
- Online status

**conversation.dart**: A chat thread. Has:
- List of participants
- Last message
- Unread message count
- Created time
- Pinned status

**message.dart**: A single message. Has:
- Content (the text)
- Sender ID
- Timestamp
- Read status
- Delivered status

**user_profile.dart**: Your account. Has:
- Your ChhayaId
- Display name
- Recovery phrase
- Created time

---

## Services Layer Explanation

### auth_service.dart

Handles account operations:

1. **createAccount()**: Generates a key pair, creates a recovery phrase, saves your profile, and adds some demo contacts.

2. **restoreAccount()**: Takes 12 words and recreates your account from them.

3. **logout()**: Deletes all your data from the phone.

4. **generateBackup()**: Creates an encrypted file with all your data. You can save this file somewhere safe.

5. **restoreFromBackup()**: Takes the backup file and your recovery phrase to restore everything.

6. **generateDeviceLinkCode()**: Creates a code to link another device to your account.

### onion_router_service.dart

Hides your IP address by routing messages through 3 servers:

1. Your message goes to Server 1
2. Server 1 forwards to Server 2
3. Server 2 forwards to Server 3
4. Server 3 delivers to the recipient

Each server only knows the previous and next server, not the full path. Messages are padded to 512 bytes to prevent size analysis.

### p2p_tunnel_service.dart

Handles voice and video calls using WebRTC (peer-to-peer). Devices connect directly without going through a server.

### decentralized_file_client.dart

Sends large files by:
1. Splitting the file into 10MB chunks
2. Encrypting each chunk
3. Sending chunks to different servers
4. Receiver reassembles the file

---

## UI Layer Explanation

### Theme (chhaya_theme.dart)

Defines the look of the app:
- **Colors**: True black background (#000000), blue accent, white text
- **Typography**: SF Pro font family (Apple style)
- **Spacing**: Consistent padding and margins
- **Animations**: Spring physics for smooth transitions
- **Haptics**: Vibration feedback on button presses

### Screens

**Onboarding**: Welcome screen, features explanation, account creation with QR code.

**Home Shell**: 4 tabs - Chats, Calls, Contacts, Settings.

**Chat List**: Shows all conversations. Search, swipe to delete, long press to pin.

**Chat Screen**: Send and receive messages. Supports:
- Text messages
- File attachments
- Voice messages
- Disappearing messages (auto-delete after time)
- Reactions (like/dislike)
- Polls

**Call Screen**: Voice and video calls. Has mute, speaker, video toggle, and voice changer.

**Settings**: App preferences, recovery phrase viewer, linked devices, encrypted backup, biometric lock, panic PIN.

**Verification**: QR code to verify someone's identity in person.

### Widgets

**AvatarWidget**: Circle with user initials and gradient border.

**ChhayaButton**: Styled button with gradient or glass effect.

**GlassContainer**: Frosted glass effect using backdrop blur.

**NotificationOverlay**: In-app notification banner that slides down.

---

## Backend Explanation

### Go Onion Node (backend/node/)

A lightweight server that forwards encrypted packets:
- Receives encrypted packets
- Removes one layer of encryption
- Forwards to the next server or delivers to recipient
- Tracks statistics (received, forwarded, dropped)

### Rust Swarm Relay (backend/relay/)

A server that stores encrypted file chunks:
- Accepts encrypted chunks from users
- Stores them temporarily (24 hours)
- Serves chunks to recipients when requested
- Auto-deletes expired chunks

---

## How Messages Flow

1. You type a message
2. Message is encrypted with AES-256-GCM
3. Encrypted message goes through 3 onion servers
4. Each server removes one encryption layer
5. Message reaches the recipient
6. Recipient decrypts with their private key
7. Message appears in their chat

---

## How Calls Work

1. You tap "Call" button
2. App creates a peer-to-peer connection using WebRTC
3. Audio/video streams directly between devices
4. No server involved in the actual call
5. Voice can be obfuscated for extra privacy

---

## Security Features

1. **Zero Knowledge**: No phone number or email required
2. **End-to-End Encryption**: Only you and the recipient can read messages
3. **Forward Secrecy**: Old messages stay safe even if keys are stolen
4. **Onion Routing**: Your IP address is hidden
5. **Biometric Lock**: Fingerprint or face to unlock app
6. **Panic PIN**: Enter a special code to wipe all data
7. **Disappearing Messages**: Auto-delete after set time
8. **QR Verification**: Verify contacts in person

---

## Dependencies Explained

- **flutter_riverpod**: Manages app state (which screen is active, user data)
- **pointycastle**: Provides encryption algorithms
- **crypto**: Provides hashing functions
- **hive**: Fast local database
- **flutter_webrtc**: Peer-to-peer voice/video calls
- **qr_flutter**: Generate QR codes
- **mobile_scanner**: Scan QR codes
- **local_auth**: Biometric authentication
- **flutter_local_notifications**: Show notification banners
- **file_picker**: Select files to send

---

## How to Run

1. Install Flutter SDK
2. Run `flutter pub get` to install dependencies
3. Run `flutter run` to start the app
4. For backend: `cd backend/relay && cargo run` (Rust)
5. For backend: `cd backend/node && go run main.go` (Go)

---

## Summary

Chhaya is a secure messenger that protects your privacy. It uses strong encryption, hides your identity, and stores everything locally on your phone. The code is organized into layers: crypto (security), database (storage), services (business logic), and UI (what you see).
