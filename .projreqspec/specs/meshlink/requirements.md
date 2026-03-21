# Chaaya — Complete Requirements Specification

> Offline communication & survival platform — zero internet, zero cloud, zero accounts.
> Android + iOS via Flutter/Dart. Backend: Spring Boot (local).

---

## Project Overview

Chaaya turns every phone into a network node. Devices communicate directly through BLE mesh, WiFi Direct, and Morse code fallback. Every feature runs entirely on-device with no servers, no accounts, no cloud.

**Replaces**: WhatsApp, Life360, Google Photos, Google Drive, Zello, BitChat

---

## Communication Channels (Priority Order)

| # | Channel | Range | Use Case |
|---|---|---|---|
| 1 | BLE Mesh | ~100m, multi-hop relay | Text, small files, always-on |
| 2 | WiFi Direct | ~200m, peer-to-peer | Calls, video, large files |
| 3 | Morse Code | Line-of-sight | Last resort SOS (flashlight/audio) |

Auto-fallback: app picks best available channel automatically.

---

## Section 1: Messenger (35 features)

### Basic Messaging
1. One-to-one private chat
2. Group chat (up to 256 members)
3. Message sent / delivered / read receipts (clock → ✓ → ✓✓ → blue ✓✓)
4. Photo, video, audio, document sharing in chat
5. Voice messages (hold to record, inline playback)
6. Reply and quote messages
7. Message reactions (emoji)
8. Message search (local, offline — keyword, date, sender, media type)
9. Contact list (auto-discovered via mesh)
10. Last seen and online status
11. Disappearing messages (24h, 7d, custom)
12. Starred messages
13. Message forwarding
14. Broadcast list (one message to many)

### BitChat Style
15. No account / no phone number required
16. Pseudonymous identity (username + Ed25519 keypair)
17. Public channels (IRC style, e.g. #emergency, #camp-alpha)
18. Channel passwords
19. Store and forward messaging (relay nodes hold for offline recipients)
20. Mesh relay routing (multi-hop, up to 7 hops)
21. No metadata leakage on relay nodes (encrypted blobs only)
22. Decentralized channel moderation (block by public key)

### Advanced
23. Signal Protocol E2E encryption (Double Ratchet + X3DH)
24. Forward secrecy (per-message key rotation)
25. Group sender keys (rotated regularly)
26. Onion routing over mesh (multi-layer encryption per hop)
27. On-device AI assistant (offline quantized LLM — emergency guidance)
28. Anti-jamming channel hopping (FHSS-inspired, shared key sequence)
29. Live mesh network visualizer (nodes, signal, hop paths)
30. Dead drop location messaging (GPS-bound encrypted message pickup)
31. Panic wipe (triple power press — crypto key destruction)
32. Decoy PIN / fake empty app
33. Compressed media transfer for low-bandwidth
34. Priority message queue (SOS messages jump the queue)
35. Message inbox with timestamps, delivery status, device ID

---

## Section 2: Walkie-Talkie (12 features)

1. Push-to-talk (PTT) over BLE / WiFi
2. Named channels (#team-alpha, #rescue-ops, #family)
3. Priority broadcast (interrupts all audio on all devices)
4. Squelch noise filter (threshold-based)
5. Roger beep confirmation tone
6. Radio callsign identity (e.g. ALPHA-1, BRAVO-3)
7. Transmission history log (who, channel, time, duration)
8. Multi-channel monitoring (2 channels at once)
9. Scramble mode (encrypted voice — channel key required)
10. Repeater mode (receive and rebroadcast to extend range)
11. SOS over PTT (broadcast distress on all channels)
12. Channel password protection

---

## Section 3: Contacts & Calls (32 features)

### Pairing
1. QR code pairing (scan to connect)
2. One-time cryptographic handshake (Ed25519)
3. Permanent local contact storage
4. Auto-reconnect when in range (silent, background)

### Texting
5. SMS-style text messages over mesh
6. Auto channel selection (BLE → WiFi → Morse)
7. Message queue when contact out of range
8. Delivered and read receipts
9. Disappearing messages per contact
10. Broadcast message to contact group

### Calling
11. Voice calls over WiFi Direct / BLE
12. Video calls over WiFi Direct (WebRTC)
13. Call history log (caller, duration, timestamp, channel)
14. Auto-answer on SOS call (open mic)
15. Mute, speaker, hold controls
16. Call quality indicator (shows active channel)

### Contact Management
17. Unified contact card (all channels in one place)
18. Contact status (nearby=green, relay=yellow, unreachable=gray)
19. Contact groups (Family, Team, Emergency)
20. Share contact via QR code
21. Trusted contact ring (5 emergency contacts)
22. Contact-level encryption keys (unique per pair)
23. Contact verification (safety numbers — like Signal)
24. Contact backup (encrypted export/import)
25. Stealth contacts (hidden inbox + secondary PIN)
26. Block contact (drops all messages silently)

### Routing
27. Relay through mutual contacts (encrypted E2E)
28. Auto channel fallback
29. Offline contact sync across mesh
30. Hop count display per contact
31. Battery level sharing per contact
32. Shared contact card (username + public key + device ID)

---

## Section 4: Safety & Location — Life360 Style (20 features)

### Core
1. Real-time GPS location sharing over mesh (30–60s updates)
2. Offline map with pre-cached OpenStreetMap tiles
3. 24-hour location history with animated trail playback
4. Named places (Home, Base, Camp, School)
5. Arrival / departure alerts (enter/exit geofence)
6. Circle groups (mutual location sharing)
7. Check-in with status message (one tap)
8. Last known location (when out of mesh range)
9. Battery level sharing per contact on map
10. SOS alert (GPS + battery + 60-sec audio recording)

### Premium Replicated Offline
11. Crash detection (accelerometer + gyroscope)
12. Driver safety score (speed, braking, turns)
13. Roadside assistance auto-alert (10 min stationary)
14. Danger zone alerts (pre-loaded map polygons)
15. Stolen device mode (silent GPS broadcast every 60s)
16. Panic button (shake 3 times → SOS + audio + live location)
17. Safe route suggestion (offline terrain + danger zones)
18. Private mode (pause sharing, no notification to others)
19. Location spoofing detection (flag warning)
20. Wellness check (auto-ping if no activity for 2 hours)

---

## Section 5: Media Vault — Google Photos Style (25 features)

### Basic
1. In-app camera (photo + video, up to 60s recommended)
2. Auto GPS + timestamp + device ID tagging
3. Offline gallery (date / location / type view)
4. Photo sharing over BLE mesh
5. Video sharing over WiFi Direct
6. Field journal (photo + text note + GPS pin)
7. Incident report builder (bundle photos + videos + notes + GPS)
8. Album creation and management
9. Bulk select and share
10. Local delete with confirmation

### Advanced
11. AES-256 encrypted storage
12. Public/private keypair per user
13. Biometric gallery lock (fingerprint / face)
14. Image compression for BLE transfer (5–15 KB thumbnails)
15. Progressive loading (thumbnail → full resolution)
16. Video keyframe extraction (low-bandwidth transfer)
17. On-device AI auto-tagging (TFLite — fire, flood, vehicle, injury, etc.)
18. Smart search across all synced devices
19. Offline face grouping (cluster by person, no cloud)
20. Scene and object detection (Emergency, Landscape, People, Document)
21. Auto-sync when devices come in range
22. Delta sync (only new/changed files)
23. Sync priority queue (text → thumbnail → full image → video)
24. Duplicate detection and merge
25. Shared album across mesh group

---

## Section 6: File Vault — Google Drive Style (30 features)

### Basic
1. Local file storage (all file types)
2. Folder creation, rename, move, delete (nested)
3. File preview (PDF, image, text, audio)
4. File sharing over BLE mesh
5. File sharing over WiFi Direct
6. Shared group folder (all mesh members read/write)
7. File search by name, type, date, tag
8. Bulk select and share
9. File tagging
10. Recycle bin with restore

### Advanced
11. Chunked file transfer (20 KB for BLE)
12. Transfer resume (interrupted → resume from last chunk)
13. Per-chunk checksum verification
14. AES-256 file encryption
15. End-to-end encrypted sharing (recipient's public key)
16. Group shared key for folder access
17. Encrypted file metadata
18. Full-text search inside documents (SQLite FTS5)
19. Background indexing of new files
20. Auto-sync when devices come in range
21. Delta sync (hash-based, only changed files)
22. Conflict detection + dual-version save
23. Sync priority queue (small → large)
24. Sync history log
25. Offline CRDT-based collaborative editing (Yjs)
26. Markdown editor built in
27. Version history with rollback
28. Storage usage dashboard
29. Per-folder storage limits
30. Auto-compression of old files

---

## Section 7: Emergency Broadcast System (7 features)

1. Admin-issued alert hops across all relay nodes
2. Bypasses silent mode — full screen alert, vibrate
3. Alert categories (evacuate, shelter-in-place, medical, all-clear)
4. Acknowledgement tracking per recipient
5. Countdown timers on alerts
6. Auto-translation of alerts
7. Dead man's switch (re-broadcast if admin goes offline)

---

## Section 8: Offline Navigation (8 features)

1. Pre-cached OpenStreetMap tile rendering (no internet)
2. Turn-by-turn navigation (offline computed)
3. Waypoint creation, naming, and navigation
4. Terrain analysis (elevation profile, slope gradient)
5. Search-and-rescue grid overlay (divided numbered sectors)
6. Dead reckoning when GPS lost (speed + heading estimation)
7. Route sharing with contacts
8. Star navigation guide (navigational stars by orientation + date/time)

---

## Section 9: Health & Medical Module (6 features)

1. Searchable offline first-aid manual (by symptom)
2. Medical profile per contact (blood type, allergies, medications)
3. On-device AI symptom checker
4. Triage system (colour-coded mass casualty tags)
5. Medication reminders (configurable schedule)
6. Vital signs log (track measurements over time)

---

## Section 10: Encrypted Voice Radio (5 features)

1. Full-duplex voice conferencing (up to 10 simultaneous)
2. AI noise cancellation (RNNoise, on-device)
3. Hotword detection for hands-free SOS (no screen needed)
4. Voice message transcription (Whisper-tiny, on-device)
5. Voice scrambler

---

## Section 11: Mesh Internet Sharing (3 features)

1. Share found WiFi to all mesh devices
2. Emergency message bandwidth priority
3. Per-device data usage tracking

---

## Section 12: Covert & Security Mode (6 features)

1. Calculator disguise UI (fully functional calculator)
2. Duress PIN → decoy app with fake chats
3. EXIF metadata scrubbing from all shared photos
4. Air gap mode (QR-only communication, zero radio)
5. Traffic analysis resistance (dummy encrypted packets + random delays)
6. Panic wipe (crypto key destruction < 1 second)

---

## Section 13: Community & Coordination (7 features)

1. Task assignment with status tracking (synced over mesh)
2. Shared resource inventory (log, update, query supplies)
3. Offline voting (cast + tally on reconnect)
4. Shift scheduling with role assignments
5. Bulletin board (announcements visible to all mesh members)
6. Chain of command roles (determines broadcast admin privileges)
7. Headcount system (safe / missing / injured status)

---

## Section 14: Device as Infrastructure (4 features)

1. Permanent relay node mode (no user interaction needed)
2. Store-and-forward for offline contacts (up to 72 hours)
3. Signal strength heatmap mapping
4. Low battery graceful handoff + notification

---

## Section 15: Offline AI Assistant (6 features)

1. Offline language translation (NLLB-200 model)
2. Plant/animal identification from photos (TFLite)
3. Emergency procedure guidance (pre-loaded knowledge base)
4. Weather prediction (barometric sensor data)
5. Searchable survival guides (shelter, water, fire, navigation)
6. Conversational AI (tiny on-device LLM)

---

## Section 16: Advanced Security (5 features)

1. IMSI catcher detection (anomalous cellular behaviour alerts)
2. RF fingerprinting (identify unknown devices)
3. Traffic analysis resistance (dummy packets + timing randomization)
4. Tamper detection (app integrity verification)
5. Anti-jamming channel hopping (FHSS-inspired)

---

## Section 17: Network Infrastructure Layer (5 features)

1. Onion routing (layered encryption, each relay sees only next hop)
2. Live mesh visualizer (connected devices, signal, relay paths)
3. Dead drop messaging (GPS-bound async pickup)
4. Uniform message padding (anti size-based analysis)
5. Timing delay randomization (anti timing correlation)

---

## Total Feature Count

| Section | Features |
|---|---|
| 1. Messenger | 35 |
| 2. Walkie-Talkie | 12 |
| 3. Contacts & Calls | 32 |
| 4. Safety & Location | 20 |
| 5. Media Vault | 25 |
| 6. File Vault | 30 |
| 7. Emergency Broadcast | 7 |
| 8. Offline Navigation | 8 |
| 9. Health & Medical | 6 |
| 10. Encrypted Voice Radio | 5 |
| 11. Mesh Internet Sharing | 3 |
| 12. Covert & Security | 6 |
| 13. Community & Coordination | 7 |
| 14. Device as Infrastructure | 4 |
| 15. Offline AI | 6 |
| 16. Advanced Security | 5 |
| 17. Network Layer | 5 |
| **TOTAL** | **216** |

---

## Security Model — 7 Layers

| Layer | What | Technology |
|---|---|---|
| 1 | Hardware keys | Android Keystore / iOS Secure Enclave |
| 2 | Signal Protocol | Double Ratchet + X3DH (per-message forward secrecy) |
| 3 | AES-256-GCM | Files, DB records, photos encrypted at rest |
| 4 | Database encryption | PostgreSQL + pgcrypto (row-level) |
| 5 | Onion routing | Multi-layer encrypted mesh relay |
| 6 | Traffic analysis resistance | Dummy packets + timing randomization |
| 7 | Panic wipe | Crypto key destruction < 1s, mathematically unrecoverable |

---

## Tech Stack

### Mobile (Flutter)

| Component | Technology |
|---|---|
| Framework | Flutter 3.x / Dart |
| State | Riverpod |
| HTTP | Dio |
| Local DB | Hive + SQLite (FTS5) |
| Secure storage | flutter_secure_storage |
| BLE | flutter_blue_plus |
| WiFi Direct | flutter_p2p_connection |
| WebRTC | flutter_webrtc |
| Maps | flutter_map + OpenStreetMap |
| GPS | geolocator |
| Camera | camera + image_picker |
| Encryption | pointycastle (Signal) + encrypt (AES-256) |
| Audio | just_audio + record |
| ML | tflite_flutter |
| CRDT | y_crdt |
| QR | qr_flutter + mobile_scanner |

### Backend (Local Spring Boot)

| Component | Technology |
|---|---|
| Framework | Spring Boot 3.2 / Java 17 |
| Real-time | WebSocket (STOMP) |
| Database | PostgreSQL 16 + pgcrypto |
| Cache | Redis 7 |
| Auth | JWT (jjwt) + Ed25519 signatures |
| ORM | Spring Data JPA |
| Security | Spring Security |

---

## Design System

| Token | Value |
|---|---|
| Background | #0D0F14 |
| Surface | #161B22 |
| Glass | rgba(255,255,255,0.05) + blur |
| Accent | #6C63FF (electric purple) |
| BLE indicator | #3B82F6 (blue) |
| WiFi indicator | #10B981 (green) |
| SOS / danger | #EF4444 (red) |
| Safe / online | #10B981 (green) |
| Text primary | #F1F5F9 |
| Text secondary | #94A3B8 |
| Font | Inter 400/500/600 |
| Mono | JetBrains Mono |

---

## Build Phases

| Phase | What | Time |
|---|---|---|
| 1 | BLE mesh, identity, QR pairing, basic chat, backend | 4 weeks |
| 2 | PTT, voice calls, WiFi Direct, Signal encryption | 4 weeks |
| 3 | GPS sharing, offline maps, circles, SOS, safety | 4 weeks |
| 4 | Media vault, file vault, chunked transfer, sync | 4 weeks |
| 5 | Video calls, AI, CRDT editing, emergency broadcast, navigation, health | 6 weeks |
| 6 | Covert mode, panic wipe, onion routing, morse code, coordination | 4 weeks |
| **Total** | **Complete app** | **~26 weeks** |

