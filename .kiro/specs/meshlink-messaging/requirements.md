# Requirements Document

## Introduction

MeshLink Messaging is the core communication layer of the Chaaya app. It provides WhatsApp-style
messaging UX over a decentralized Bluetooth Low Energy (BLE) mesh network with no internet, no
accounts, and no central servers. Every message is end-to-end encrypted using the Signal Protocol.
The system runs entirely on-device using Flutter (Dart) for cross-platform UI and Java native
modules for Android-specific hardware access.

The feature covers: one-to-one and group chat over BLE mesh, cryptographic pseudonymous identity,
public IRC-style channels, store-and-forward delivery, Signal Protocol encryption, onion routing,
anti-jamming channel hopping, voice messages, disappearing messages, dead drop messaging, and
panic wipe.

---

## Glossary

- **Mesh_Network**: The peer-to-peer BLE/WiFi Direct network formed by nearby Chaaya devices with no central router.
- **BLE**: Bluetooth Low Energy — the primary transport layer for text and small payloads (~100m range).
- **Node**: A single Chaaya device participating in the Mesh_Network.
- **Identity**: A cryptographic keypair (Ed25519) that uniquely identifies a user without requiring an account.
- **Public_Key**: The Ed25519 public key that serves as a user's persistent pseudonymous identifier.
- **Private_Key**: The Ed25519 private key stored in the device's hardware secure enclave.
- **Signal_Protocol**: The Double Ratchet + X3DH key agreement protocol providing end-to-end encryption with forward secrecy.
- **Double_Ratchet**: The Signal Protocol sub-protocol that rotates encryption keys on every message.
- **X3DH**: Extended Triple Diffie-Hellman — the Signal Protocol key agreement used to establish a shared secret on first contact.
- **Sender_Key**: A group messaging key distributed to all group members, used for efficient group encryption.
- **Onion_Router**: The component that wraps messages in layered encryption so each relay Node sees only the next hop.
- **Relay_Node**: A Mesh_Network Node that forwards encrypted messages on behalf of other Nodes.
- **Store_Forward_Queue**: A persistent queue of messages held by a Relay_Node for offline recipients.
- **Channel**: A named public chat room (e.g. `#emergency`) that any Node on the mesh can join.
- **Channel_Key**: A symmetric key derived from a channel password using Argon2, used to encrypt Channel messages.
- **Dead_Drop**: A GPS-coordinate-bound encrypted message that can only be retrieved by a Node physically within 10 metres.
- **ACK_Packet**: A small acknowledgement packet sent back to the originating Node to confirm message delivery or read status.
- **Opus_Codec**: The audio codec used to compress voice messages to approximately 6 kbps for BLE transmission.
- **Panic_Wipe**: The emergency procedure that cryptographically destroys all keys and renders all data permanently unrecoverable.
- **HMAC**: Hash-based Message Authentication Code — used for time-based channel hopping sequence computation.
- **Argon2**: A memory-hard password hashing function used to derive Channel_Keys from channel passwords.
- **Android_KeyStore**: The Android hardware-backed secure enclave used to store the Private_Key.
- **Hive_DB**: The Flutter on-device NoSQL database used for message and contact persistence.
- **Platform_Channel**: The Flutter mechanism for calling Java native modules from Dart code.
- **TTL**: Time-to-live — the maximum duration a message is held in the Store_Forward_Queue before expiry.
- **Haversine_Formula**: The spherical geometry formula used to compute the distance between two GPS coordinates.
- **Waveform**: A visual amplitude-over-time representation of a voice message audio file.

---

## Requirements

### Requirement 1: Cryptographic Identity

**User Story:** As a user, I want a cryptographic identity generated automatically on first launch,
so that I can communicate pseudonymously without creating an account or providing personal information.

#### Acceptance Criteria

1. WHEN the app is launched for the first time, THE Identity_Manager SHALL generate an Ed25519 keypair and store the Private_Key in the Android_KeyStore.
2. THE Identity_Manager SHALL derive the user's persistent identifier solely from the Public_Key.
3. WHEN the app is launched on subsequent sessions, THE Identity_Manager SHALL load the existing keypair from the Android_KeyStore without prompting the user.
4. IF the Android_KeyStore returns an error during key retrieval, THEN THE Identity_Manager SHALL display an error message and prevent app access until the error is resolved.
5. THE Identity_Manager SHALL expose the Public_Key to other Nodes via the Mesh_Network for contact discovery.
6. THE Identity_Manager SHALL NOT transmit the Private_Key outside the Android_KeyStore boundary at any time.

---

### Requirement 2: BLE Mesh Transport

**User Story:** As a user, I want my device to connect to nearby Chaaya devices over BLE,
so that I can send and receive messages without internet or WiFi infrastructure.

#### Acceptance Criteria

1. WHEN the app is in the foreground or background, THE BLE_Transport SHALL continuously scan for nearby Nodes advertising the Chaaya BLE service UUID.
2. WHEN a nearby Node is discovered, THE BLE_Transport SHALL establish a BLE connection and perform a cryptographic handshake using the X3DH protocol.
3. THE BLE_Transport SHALL support simultaneous connections to up to 7 peer Nodes.
4. WHEN a BLE connection is lost, THE BLE_Transport SHALL attempt reconnection using exponential backoff with a maximum interval of 30 seconds.
5. THE BLE_Transport SHALL fragment outgoing messages into chunks of at most 512 bytes to fit BLE MTU constraints.
6. WHEN all fragments of a message are received, THE BLE_Transport SHALL reassemble them into the original message payload before delivery.
7. IF a fragment is not received within 10 seconds of the previous fragment, THEN THE BLE_Transport SHALL request retransmission of the missing fragment.

---

### Requirement 3: One-to-One Chat

**User Story:** As a user, I want to send and receive private text messages to a specific contact,
so that I can have confidential one-to-one conversations over the mesh.

#### Acceptance Criteria

1. WHEN a user sends a message to a contact, THE Chat_Engine SHALL encrypt the message using the Signal_Protocol Double_Ratchet before transmission.
2. THE Chat_Engine SHALL display messages in chronological order within a conversation thread.
3. WHEN a message is transmitted to the BLE_Transport, THE Chat_Engine SHALL display a "sent" status indicator (single tick) for that message.
4. WHEN an ACK_Packet confirming delivery is received, THE Chat_Engine SHALL update the message status to "delivered" (double tick).
5. WHEN an ACK_Packet confirming the recipient has opened the conversation is received, THE Chat_Engine SHALL update the message status to "read" (blue double tick).
6. THE Chat_Engine SHALL persist all messages to Hive_DB with the conversation's Public_Key as the partition key.
7. IF the recipient Node is not currently reachable, THEN THE Chat_Engine SHALL place the message in the Store_Forward_Queue for deferred delivery.

---

### Requirement 4: Group Chat

**User Story:** As a user, I want to create and participate in group chats with multiple contacts,
so that I can coordinate with a team over the mesh without a central server.

#### Acceptance Criteria

1. THE Group_Chat_Manager SHALL support groups of up to 256 members.
2. WHEN a group is created, THE Group_Chat_Manager SHALL generate a Sender_Key and distribute it to all current group members using individual Signal_Protocol sessions.
3. WHEN a new member joins a group, THE Group_Chat_Manager SHALL rotate the Sender_Key and distribute the new key to all members including the new member.
4. WHEN a member leaves or is removed from a group, THE Group_Chat_Manager SHALL rotate the Sender_Key and distribute the new key to all remaining members.
5. WHEN a user sends a group message, THE Group_Chat_Manager SHALL encrypt it with the current Sender_Key and relay it hop-by-hop across the Mesh_Network.
6. THE Group_Chat_Manager SHALL deliver group messages to all reachable members within the same mesh session.
7. IF a group member is offline, THEN THE Group_Chat_Manager SHALL place the message in the Store_Forward_Queue for that member.

---

### Requirement 5: Signal Protocol End-to-End Encryption

**User Story:** As a user, I want all my messages encrypted end-to-end using the Signal Protocol,
so that no relay node or eavesdropper can read my communications.

#### Acceptance Criteria

1. WHEN two Nodes communicate for the first time, THE Encryption_Service SHALL perform X3DH key agreement to establish a shared secret.
2. WHEN a shared secret is established, THE Encryption_Service SHALL initialise a Double_Ratchet session for that contact pair.
3. THE Encryption_Service SHALL rotate the Double_Ratchet sending key on every outgoing message.
4. WHEN a message is received out of order, THE Encryption_Service SHALL buffer up to 1000 skipped message keys to allow decryption.
5. THE Encryption_Service SHALL delete used message keys from memory immediately after decryption.
6. IF decryption of a received message fails, THEN THE Encryption_Service SHALL discard the message and log the failure without exposing plaintext.
7. FOR ALL valid plaintext messages, encrypting then decrypting with the same Double_Ratchet session SHALL produce the original plaintext (round-trip property).

---

### Requirement 6: Store and Forward Delivery

**User Story:** As a user, I want messages sent to me while I was offline to be delivered when I
come back in range, so that I don't miss communications during connectivity gaps.

#### Acceptance Criteria

1. WHEN a Relay_Node receives a message for an offline recipient, THE Store_Forward_Service SHALL add the message to the Store_Forward_Queue with a TTL of 7 days.
2. WHEN the intended recipient Node comes in range of a Relay_Node holding queued messages, THE Store_Forward_Service SHALL transmit all queued messages for that recipient.
3. WHEN a queued message is successfully delivered, THE Store_Forward_Service SHALL remove it from the Store_Forward_Queue.
4. WHEN a message's TTL expires, THE Store_Forward_Service SHALL permanently delete it from the Store_Forward_Queue.
5. THE Store_Forward_Service SHALL store queued messages as encrypted blobs and SHALL NOT decrypt them on the Relay_Node.
6. THE Store_Forward_Service SHALL support a queue capacity of at least 500 messages per recipient.

---

### Requirement 7: Public Channels (IRC Style)

**User Story:** As a user, I want to join named public channels visible to everyone on the mesh,
so that I can broadcast to or receive from a group without pre-arranged contact lists.

#### Acceptance Criteria

1. THE Channel_Manager SHALL allow any Node to create or join a Channel identified by a human-readable name prefixed with `#`.
2. WHEN a user joins a password-protected Channel, THE Channel_Manager SHALL derive the Channel_Key from the password using Argon2 with a minimum cost factor of 65536 iterations.
3. WHEN a user sends a message to a Channel, THE Channel_Manager SHALL encrypt it with the Channel_Key and broadcast it to all reachable Nodes subscribed to that Channel.
4. WHEN a Node receives a Channel message, THE Channel_Manager SHALL decrypt it using the Channel_Key and display it in the Channel's message thread.
5. IF a Node does not possess the correct Channel_Key, THEN THE Channel_Manager SHALL discard the message without displaying an error to other users.
6. THE Channel_Manager SHALL support at least 50 simultaneously active Channels per Node.
7. THE Channel_Manager SHALL allow a user to block a specific Public_Key from a Channel, causing all messages from that Public_Key to be silently discarded.

---

### Requirement 8: Voice Messages

**User Story:** As a user, I want to record and send voice messages, so that I can communicate
quickly when typing is impractical in field conditions.

#### Acceptance Criteria

1. WHEN a user holds the voice record button, THE Voice_Message_Service SHALL begin recording audio using the device microphone.
2. WHEN the user releases the voice record button, THE Voice_Message_Service SHALL stop recording and encode the audio using the Opus_Codec at approximately 6 kbps.
3. THE Voice_Message_Service SHALL limit voice message recordings to a maximum duration of 120 seconds.
4. WHEN a voice message is encoded, THE Voice_Message_Service SHALL encrypt it using the Signal_Protocol session for the recipient before transmission.
5. WHEN a voice message is received and decrypted, THE Voice_Message_Service SHALL render a Waveform visualisation alongside playback controls in the chat thread.
6. IF the encoded voice message exceeds 512 bytes, THEN THE Voice_Message_Service SHALL fragment it using the BLE_Transport chunking mechanism before transmission.

---

### Requirement 9: Disappearing Messages

**User Story:** As a user, I want to set messages to automatically delete after a configured time,
so that sensitive conversations leave no persistent trace on either device.

#### Acceptance Criteria

1. THE Disappearing_Message_Service SHALL support disappear timers of 24 hours, 7 days, and a user-defined duration between 1 minute and 30 days.
2. WHEN a disappearing message is stored in Hive_DB, THE Disappearing_Message_Service SHALL record a `disappear_at` timestamp alongside the message.
3. WHEN the current time exceeds a message's `disappear_at` timestamp, THE Disappearing_Message_Service SHALL delete the message record and overwrite its storage location with random bytes.
4. THE Disappearing_Message_Service SHALL run a background expiry check at intervals of no more than 60 seconds.
5. WHEN a disappearing message is deleted, THE Disappearing_Message_Service SHALL remove it from the UI without requiring a manual refresh.
6. THE Disappearing_Message_Service SHALL apply the same disappear timer to both the sender's and recipient's copies of the message.

---

### Requirement 10: Onion Routing Over Mesh

**User Story:** As a user, I want my messages routed through multiple relay nodes with layered
encryption, so that no single relay node can determine both the sender and the recipient.

#### Acceptance Criteria

1. WHEN a message is sent via onion routing, THE Onion_Router SHALL wrap the message in a separate encryption layer for each Relay_Node in the selected path using libsodium.
2. THE Onion_Router SHALL select a relay path of at least 3 hops for onion-routed messages.
3. WHEN a Relay_Node receives an onion-routed message, THE Relay_Node SHALL decrypt only its own outer layer and forward the remaining payload to the next hop.
4. THE Onion_Router SHALL ensure that each Relay_Node in the path knows only the identity of the immediately preceding and immediately following Node.
5. WHEN the final Relay_Node in the path receives the message, THE Onion_Router SHALL deliver the fully decrypted inner payload to the recipient.
6. IF any Relay_Node in the path is unreachable, THEN THE Onion_Router SHALL select an alternative path and retransmit the message.

---

### Requirement 11: Anti-Jamming Channel Hopping

**User Story:** As a user, I want the communication channel to change automatically on a shared
schedule, so that targeted radio jamming cannot disrupt my conversations.

#### Acceptance Criteria

1. WHEN two Nodes share a session secret, THE Channel_Hopper SHALL independently compute the next BLE advertising channel using HMAC applied to the shared secret concatenated with the current Unix timestamp truncated to 5-second intervals.
2. THE Channel_Hopper SHALL hop to the next computed channel every 5 seconds.
3. WHEN both Nodes compute the channel sequence from the same shared secret and timestamp, THE Channel_Hopper SHALL produce identical channel sequences on both devices (deterministic property).
4. THE Channel_Hopper SHALL support a channel pool of at least 37 BLE advertising channels.
5. IF a computed channel is currently occupied or blocked, THEN THE Channel_Hopper SHALL advance to the next channel in the computed sequence without interrupting the 5-second hop cycle.

---

### Requirement 12: No Metadata Leakage

**User Story:** As a user, I want relay nodes to be unable to infer communication patterns from
my messages, so that traffic analysis cannot reveal who is talking to whom.

#### Acceptance Criteria

1. THE Privacy_Layer SHALL pad all outgoing messages to a fixed size of 512 bytes before encryption and transmission.
2. WHEN a message is forwarded by a Relay_Node, THE Privacy_Layer SHALL apply a random delay between 100 milliseconds and 2000 milliseconds before forwarding.
3. THE Privacy_Layer SHALL transmit dummy encrypted packets at random intervals to prevent traffic analysis based on silence periods.
4. THE Privacy_Layer SHALL ensure that Relay_Nodes receive only encrypted blobs with no plaintext headers identifying the sender or recipient.
5. WHEN a message is padded to 512 bytes, THE Privacy_Layer SHALL strip the padding upon decryption to restore the original message (round-trip property).

---

### Requirement 13: Dead Drop Messaging

**User Story:** As a user, I want to leave a message tied to a GPS location that only someone
physically present at that location can retrieve, so that I can communicate covertly using
location as the access credential.

#### Acceptance Criteria

1. WHEN a user creates a Dead_Drop, THE Dead_Drop_Service SHALL encrypt the message with a key derived from the GPS coordinates rounded to 5 decimal places.
2. THE Dead_Drop_Service SHALL broadcast the encrypted Dead_Drop payload across the Mesh_Network without revealing the target coordinates in plaintext.
3. WHEN a Node receives a Dead_Drop payload, THE Dead_Drop_Service SHALL compute the distance between the Node's current GPS coordinates and the Dead_Drop coordinates using the Haversine_Formula.
4. WHEN the computed distance is 10 metres or less, THE Dead_Drop_Service SHALL decrypt and display the Dead_Drop message to the user.
5. WHEN the computed distance exceeds 10 metres, THE Dead_Drop_Service SHALL discard the Dead_Drop payload without displaying any content.
6. THE Dead_Drop_Service SHALL require GPS accuracy of 10 metres or better before attempting Dead_Drop decryption.

---

### Requirement 14: Panic Wipe

**User Story:** As a user, I want to instantly destroy all cryptographic keys and data with a
physical gesture, so that my communications become permanently unrecoverable under duress.

#### Acceptance Criteria

1. WHEN the power button is pressed three times within 1.5 seconds, THE Panic_Wipe_Service SHALL initiate the wipe sequence immediately.
2. WHEN the wipe sequence is initiated, THE Panic_Wipe_Service SHALL delete all keys from the Android_KeyStore within 1 second.
3. WHEN the wipe sequence is initiated, THE Panic_Wipe_Service SHALL overwrite all Hive_DB message records with random bytes before deletion.
4. WHEN the wipe sequence is initiated, THE Panic_Wipe_Service SHALL delete all Channel_Keys and session state from memory and persistent storage.
5. WHEN the wipe sequence completes, THE Panic_Wipe_Service SHALL render all previously stored messages permanently unrecoverable without the destroyed keys.
6. WHEN the wipe sequence completes, THE Panic_Wipe_Service SHALL restart the app in a clean first-launch state as if no data was ever stored.
7. IF the Android_KeyStore deletion call returns an error, THEN THE Panic_Wipe_Service SHALL retry the deletion up to 3 times before displaying a critical failure alert.

---

### Requirement 15: Message Persistence and Local Storage

**User Story:** As a user, I want my messages stored locally on my device, so that I can read
conversation history without any network connection.

#### Acceptance Criteria

1. THE Storage_Service SHALL persist all sent and received messages to Hive_DB with fields for: message ID, sender Public_Key, recipient Public_Key or Channel name, ciphertext, plaintext, timestamp, delivery status, and `disappear_at`.
2. THE Storage_Service SHALL encrypt the Hive_DB database file at rest using AES-256-GCM with a key stored in the Android_KeyStore.
3. WHEN the app is opened, THE Storage_Service SHALL load the most recent 50 messages per conversation for display without loading the full history.
4. WHEN a user scrolls to the top of a conversation, THE Storage_Service SHALL load the next 50 messages in reverse chronological order (pagination).
5. THE Storage_Service SHALL support full-text search across all stored message plaintexts using an indexed query returning results within 500 milliseconds for a database of up to 100,000 messages.

---

### Requirement 16: Message Search

**User Story:** As a user, I want to search my message history by keyword, date, sender, and
media type, so that I can quickly find specific conversations or content.

#### Acceptance Criteria

1. THE Search_Service SHALL index all decrypted message plaintexts in a local full-text search index stored in Hive_DB.
2. WHEN a user submits a search query, THE Search_Service SHALL return matching messages ranked by relevance within 500 milliseconds.
3. THE Search_Service SHALL support filtering search results by: sender Public_Key, date range, and message type (text, voice, media).
4. WHEN a search result is tapped, THE Search_Service SHALL navigate to the message's position within its conversation thread.
5. THE Search_Service SHALL update the search index within 1 second of a new message being stored.

---

### Requirement 17: Flutter–Java Platform Channel Bridge

**User Story:** As a developer, I want Flutter Dart code to invoke Android Java native modules
for BLE, KeyStore, and panic wipe operations, so that hardware-specific features are accessible
from the cross-platform UI layer.

#### Acceptance Criteria

1. THE Platform_Channel_Bridge SHALL expose a named method channel `com.chaaya.meshlink/ble` for all BLE scan, advertise, connect, and data transfer operations.
2. THE Platform_Channel_Bridge SHALL expose a named method channel `com.chaaya.meshlink/keystore` for all Android_KeyStore key generation, retrieval, and deletion operations.
3. THE Platform_Channel_Bridge SHALL expose a named method channel `com.chaaya.meshlink/panic` for the Panic_Wipe_Service trigger.
4. WHEN a Platform_Channel method call returns an error from the Java layer, THE Platform_Channel_Bridge SHALL propagate the error as a typed Dart exception with a descriptive message.
5. THE Platform_Channel_Bridge SHALL complete all method channel calls within 5 seconds or return a timeout error to the Dart caller.
