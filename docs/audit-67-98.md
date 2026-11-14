# Source-based implementation assessment — feature-register rows 67–98

- Date: 2026-11-14. Scope: `docs/feature-register.md` / `docs/feature-verification-127.csv` rows 67–98 inclusive (all currently `assessment pending`; all `NOT RELEASE VERIFIED`).
- Method: read-only source inspection on this Windows dev machine (`git` HEAD `02d2800`). **This is an internal code audit, not an independent security/protocol review and not device proof.** No `release_verified` flag exists in the CSV and none was created, flipped or implied by this report. `release_status` stays `NOT RELEASE VERIFIED` for every row.
- Vocabulary for "Recommended CSV implementation_status string" matches rows 1–25 exactly: `implemented but unverified`, `partially implemented`, `not implemented` (`assessment pending` is the current placeholder and is never a passing result).
- "Acceptance gap" = what must exist before `release_verified` could ever be marked, per the feature-register shared acceptance requirements: named design + owner, protocol/data/dependency analysis where applicable, automated **and adversarial** tests, physical Android (and iOS) device evidence for applicable platforms, documented security/privacy limits, and — for crypto/protocol rows — an independent security review recorded in the delivery checklist. Windows support is a separate release decision. Device-flag and CSV flips are the maintainer's call, not this report's.
- Files not opened are marked "not inspected". Line numbers approximate.

## Encrypted vault group (67–69)

### 67 — Biometric unlock (Fingerprint / Face / Iris)
- Requirement: biometric (not device-credential) gating of the vault.
- Implementation status: **partial** (app-lock biometric gate exists; there is no vault to unlock).
- Evidence (inspected): `lib/core/database/local_database.dart` (`_localAuth`, `isBiometricAvailable()`, `getAvailableBiometrics()`, `authenticateWithBiometrics()` with `biometricOnly: false, stickyAuth: true`, `init({requireBiometric})`, `_biometricUnlocked`, `isUnlockedWithBiometrics`, `biometric_lock` settings read/write); `lib/ui/widgets/app_lock_gate.dart` (gate incl. panic-PIN branch, biometric icons at ~L359/L378); `settings_screen.dart` ('Biometric Lock' switch ~L216); `app_providers.dart` (`safeBiometricLockEnabled` fail-closed read); `pubspec.yaml` (`local_auth: ^2.3.0`); tests `test/unit/auth/app_lock_test.dart`, `app_lifecycle_lock_test.dart`, `database_test.dart` (settings persistence only). No vault UI/vault screen exists anywhere in `lib/`; `key_manager.dart` only defines a `vault/master` HKDF path constant. Iris is not separately handled; `biometricOnly:false` allows a device credential fallback, so "Iris/biometric-only" is not technically enforced.
- Acceptance gap: a vault feature must exist first (64–66 unfinished); platform biometric capability/enrollment reporting (Keystore/Enclave vs fallback), hardware-backed evidence on Pixel/iPhone, adversarial lifecycle tests (auto-lock, race, background), and independent review of the gate. Device evidence, explicit fallback semantics.
- Recommended CSV implementation_status: `partially implemented`.

### 68 — Tamper detection (SHA-256 hash)
- Requirement: detect unauthorized modification of vault contents (e.g., SHA-256 integrity check).
- Implementation status: **missing**.
- Evidence (inspected): no vault exists; no SHA-256 integrity manifest or verification for any stored user content was found under `lib/`. Partial adjacent mechanisms (not this feature): `lib/core/database/database_key.dart` (`Decrypts a field envelope. Returns null on tampering` — AES-GCM tag failure, not SHA-256); `lib/core/crypto/primitives/aes_gcm.dart` (AEAD integrity); `lib/services/network/decentralized_file_client.dart` (SHA-256 FileManifest for legacy experimental transfers — not user-facing vault, not on messaging path). `sha.dart` provides `Sha.hash256` primitive only.
- Acceptance gap: a vault + its storage lifecycle design, the hash/MAC scheme (keyed, versioned), verification/fail-closed behavior, adversarial tamper tests (bit-flip, truncation, rollback), documented limits vs memory copies, device evidence, independent review.
- Recommended CSV implementation_status: `not implemented`.

### 69 — Send from vault (Re-encrypt with session key)
- Requirement: move a vault item into a conversation, re-encrypted with the session (ratchet) key.
- Implementation status: **missing**.
- Evidence (inspected): no vault code path, no re-encryption hook, nothing references `vault` except the `key_manager.dart` path constant and a `bip39.dart` wordlist entry. No call site sends vault content into `ratchet_message_codec.dart` envelopes.
- Acceptance gap: vault design + key lifecycle, integration with ratchet session, UI flow, adversarial tests (wrong session, replay, partial send), device verification, independent review of the plaintext exposure window.
- Recommended CSV implementation_status: `not implemented`.

## Multi-device group (70–75)

### 70 — Cross-platform pairing (Android / iOS / Windows)
- Requirement: link second device across platforms, authenticated.
- Implementation status: **scaffolded-but-unused**.
- Evidence (inspected): `lib/services/auth/auth_service.dart::generateDeviceLinkCode()` builds `Chhaya-link:<pubkey>:<linkKey>` but **stores nothing** — no private linking key persistence, no approval/transfer/session; `lib/ui/screens/settings/settings_screen.dart::_showLinkedDevices()` shows local device records with the in-UI disclaimer "Secure device linking and revocation are not available yet"; backend `backend/server/src/routes.ts` (`POST /devices/link`, insert with `is_linked=true`) and `db.ts` (`devices.is_linked` column) accept a link request with **no verification handshake**; ponytail-audit 2026-10-29 finding #2 ("Linked devices are not an enrollment protocol"); delivery-checklist: "Multi-device pairing/revocation | Incomplete enrollment scaffolding". Windows linking: no Windows runtime QA exists for any of this.
- Acceptance gap: complete authenticated enrollment protocol (expiring request, per-device keys/sessions, user approval UX), backend binding semantics reviewed, cross-platform transport (QR + payload) proven on Android/iOS/(Windows as separate decision), revocation and recovery, crypto review, two/three-device device tests.
- Recommended CSV implementation_status: `partially implemented`.

### 71 — QR-based linking (Ephemeral key exchange)
- Requirement: QR carries an ephemeral key exchange that completes a secure channel.
- Implementation status: **scaffolded-but-unused**.
- Evidence (inspected): `auth_service.dart::generateDeviceLinkCode()` generates a fresh `ChhayaCryptoEngine.generateKeyPair()` per call (ephemeral) and a QR payload with the public linking key, but the private key is discarded (never persisted/used) — no key **exchange** occurs; `qr_flutter`/`mobile_scanner` used only in `verification_screen.dart` (identity verification) and onboarding identity display; nothing scans a link QR; no link payload parser exists.
- Acceptance gap: actual ephemeral ECDH (+ transcript/binding design reviewed), persistence/one-time semantics, expiry, MitM resistance proof, device-camera tests, independent protocol review.
- Recommended CSV implementation_status: `partially implemented`.

### 72 — Cryptographic binding (Server never sees keys)
- Requirement: linking cryptographically binds devices; server sees no private keys/shared secrets.
- Implementation status: **missing**.
- Evidence (inspected): no enrollment crypto exists to bind (see 70/71); server `devices` rows store `public_key` and `is_linked` (by design public, but no binding protocol consumes them); `verification_screen.dart` only flags contacts `isVerified` locally — no device-level binding. No transcript, signature handshake or confirm-code flow anywhere in `lib/` or `backend/server/src` for device linking.
- Acceptance gap: reviewed authenticated key exchange binding both devices, server-side data-minimization audit, rejection paths, transcript binding tests, independent review.
- Recommended CSV implementation_status: `not implemented`.

### 73 — Remote revocation (Instant)
- Requirement: revoke a linked device remotely, effective immediately.
- Implementation status: **missing**.
- Evidence (inspected): no revocation endpoint/handler in `backend/server/src/routes.ts` (only `/devices/link`; `is_linked` is never set false by any route); no `revoke` in `lib/` except the settings disclaimer "Secure device linking and revocation are not available yet. The entries below are local records, not proof of linked or revoked devices." Local "blocked" UI/DB (`settings block list`) is a contact block, unrelated.
- Acceptance gap: server-side revocation propagation to sessions + signaling/messaging authorization, "instant" semantics defined and tested (kill in-flight sessions), audit log, cross-device invalidation tests, device evidence, review.
- Recommended CSV implementation_status: `not implemented`.

### 74 — Session reset on revoke (Ratchet reset)
- Requirement: revoking a device resets ratchet sessions so the removed device loses access.
- Implementation status: **missing**.
- Evidence (inspected): no revocation trigger exists (73); the repo's resync/session-generation machinery (`local_database.dart` `session_generation` dual-store kv + keystore, `session_resync_pending` marker, `messaging_service.dart` resync-on-restore, `ratchet_message_codec.dart` chaya-resync path) is keyed to **backup restore**, not to revocation, and ships default-off (`pq_hybrid_v1.dart` flag `chhaya_pq_hybrid_v1`); no test links revoke → session reset because no revoke exists.
- Acceptance gap: revocation event → per-device session invalidation across peers, new-generation handshake for remaining devices, downgrade/rollback tests, two-phone drills, independent review.
- Recommended CSV implementation_status: `not implemented`.

### 75 — Per-device push tokens (FCM / APNs)
- Requirement: each linked device receives push via its own FCM/APNs token.
- Implementation status: **scaffolded-but-unused** (server-side only; no client push integration).
- Evidence (inspected): server `backend/server/src/push.ts` (`registerFCMToken`, `removeFCMToken`, `getUserFCMTokens`, `initPushNotifications` — warns and disables without Firebase credentials; `subscribeToPush` web-push path), `db.ts` (`devices.fcm_token`, indexes), `routes.ts` (register/login paths call `registerFCMToken`; `POST /push/subscribe`). Local encrypted column `DbCols.fcmTokenEncrypted` (`schema.dart` L163, written `local_database.dart` ~L1483). **No** `firebase_messaging` in `pubspec.yaml`, zero FCM/APNs acquisition code in `lib/`, no provider credentials, `delivery-checklist`: "Push | Backend/provider scaffolding". `notification_service.dart` not inspected for token acquisition — no Firebase import found by grep.
- Acceptance gap: client FCM/APNs registration + rotation, provider credentials, background/killed-state handling, per-device targeting proof (and removal of stale tokens), privacy QA, on-device delivery on Android+iOS, review.
- Recommended CSV implementation_status: `partially implemented`.

## Backup and recovery group (76–81)

### 76 — BIP-39 recovery (12 words)
- Requirement: BIP-39 12-word recovery phrase as the account root.
- Implementation status: **implemented** (unverified end-to-end).
- Evidence (inspected): `lib/core/crypto/primitives/bip39.dart` (2048-word list, `generateMnemonic`, 12-word/128-bit path, checksum validation, `bip39_test`/vectors per audit), `chhaya_crypto_engine.dart` (`generateRecoveryPhrase`, `keyFromRecoveryPhrase` via PBKDF2-HMAC-SHA256 default 100k), `account_identity.dart` (phrase→keypair), `auth_service.dart` (`createAccount`/`restoreAccount`), settings 'Recovery Phrase' sheet, onboarding phrase flow (~L87–L125, L353–L413); `test/unit/auth/account_recovery_test.dart`. Phrase is stored unwrapped in `UserProfile`/secure storage — exposure surface needs review.
- Acceptance gap: device recovery drills on Android/iOS, secure handling/backup warnings UX, independent review of phrase storage, accessibility of the recovery flow.
- Recommended CSV implementation_status: `implemented but unverified`.

### 77 — Encrypted backup (Master-key encrypted)
- Requirement: full encrypted local backup of account state.
- Implementation status: **partial** (encrypted backup exists; restore is provably lossy at the protocol layer).
- Evidence (inspected): `auth_service.dart::generateBackup()`/`restoreFromBackup()` (version 2 JSON, phrase+salt PBKDF2 key, AES-GCM, contacts/conversations/messages, SQLCipher transaction via `replaceAccountSnapshot`, rollback-on-failure per delivery-checklist); `test/unit/auth/backup_file_test.dart` (8 file/recovery tests, atomic rename); `test/unit/database/restore_resume_test.dart` (pins the initiator-role restore defect: byte-identical root/chains/SPQR seed, counter resets to 0); ponytail "Slice A" findings 1–3; delivery-checklist "Encrypted backup | Version 2 encrypted export…". Restore of a resumable messaging session is now possible only behind the default-off v2 resync handshake, whose live backend round trip was never run on this host (WS3 notes, dump of `test/integration/resync_restore_test.dart` skipped without `CHHAYA_TEST_API_PORT`).
- Acceptance gap: peer-coordinated fresh session generation after restore proven end-to-end (two devices), native Keychain/Keystore failure drills, device backup/restore UX, documented limits, independent protocol review.
- Recommended CSV implementation_status: `partially implemented`.

### 78 — Local file export (User location)
- Requirement: export encrypted backup to a user-chosen location.
- Implementation status: **implemented** (desktop evidence only).
- Evidence (inspected): `lib/services/auth/backup_file.dart` (`maxBytes=16MB`, `readBounded`, `pick()` stream read, `save()` — mobile saves via picker bytes, desktop writes temp-file + `rename` atomically); onboarding 'Choose backup file' (~L495–L510) and settings 'Backup' sheet with 'Save encrypted backup'; ponytail "Backup file workflow follow-up" (8 tests incl. real temp-file write, desktop overwrite-safety tests). Android/iOS picker UI acceptance not run; onboarding also accepts a pasted backup string (unreviewed surface).
- Acceptance gap: Android/iOS file-picker + save/restore device evidence, large-backup behavior, malicious-file adversarial tests, restore-UX device validation.
- Recommended CSV implementation_status: `implemented but unverified`.

### 79 — Cloud backup (optional, user-controlled)
- Requirement: optional user-controlled cloud backup.
- Implementation status: **missing**.
- Evidence (inspected): no cloud/backup-provider integration anywhere in `lib/` or `backend/` (grep: no Drive/iCloud/S3/cloud-backup code; the word "Backup" only maps to local encrypted export, settings tile 'Backup' → `_showBackup()`). No "optional/user-controlled" cloud design, no consent flow, no docs.
- Acceptance gap: explicit privacy design (zero-knowledge, user-held keys, provider boundary), user consent UX, provider integration + rotation, deletion/revocation of cloud copies, device evidence, review. (Must remain strictly optional or absent.)
- Recommended CSV implementation_status: `not implemented`.

### 80 — Account restore (From recovery phrase)
- Requirement: restore the account and its content from the 12-word phrase (+ backup).
- Implementation status: **partial** (identity restore works; resumed sessions are broken by design).
- Evidence (inspected): `auth_service.dart::restoreAccount()` and `restoreFromBackup()` (phrase→identity; backup auth against phrase-derived key; `replaceAccountSnapshot`); onboarding restore UI (L~117–L160); `account_recovery_test.dart`; ponytail Slice A pins: restored initiator replays counter 0, the non-restored peer rejects (RatchetException), sync swallows the failure (`messaging_service.dart` ~L475–L478, L536–L538), restored unsent messages stick pending forever (outbox deleted; `retryPending` skips). 2026-11-08 CSV note: "same pinned restore defect applies to any restore path". WS3 mitigates only behind default-off `chhaya_pq_hybrid_v1`, never live-tested.
- Acceptance gap: live end-to-end restore drill on two devices with v2 resync enabled (or equivalent fix), pending-message recovery after restore, user-visible failure signaling, iOS + Android device evidence, independent review.
- Recommended CSV implementation_status: `partially implemented`.

### 81 — Multi-device restore (Re-link after restore)
- Requirement: after a restore, re-link multiple devices into the account.
- Implementation status: **missing** (no re-link protocol exists).
- Evidence (inspected): no re-link flow anywhere; linking itself is scaffolding (70/71); WS3 resync (`session_generation`, resync envelope) is a **single-device** restore path and did not exercise group/multi-device resync end-to-end (WS3 notes: group criterion 9 NOT exercised); 2026-11-08 CSV note explicitly: "current implementation cannot re-link after restore".
- Acceptance gap: working authenticated re-link (70–72) first, then multi-device restore semantics (which identity keys/session generations), conflict handling across restored devices, two/three-device device drills, review.
- Recommended CSV implementation_status: `not implemented`.

## Offline mode group (82–88)

### 82 — Chat (BLE) (~30m range)
- Requirement: offline Bluetooth LE messaging, ~30m.
- Implementation status: **missing**.
- Evidence (inspected): no BLE plugin/dependency (`pubspec.yaml` has no `flutter_blue*`/`ble_*`); no BLE code in `lib/`; delivery-checklist: "Offline mesh | Not implemented — BLE/native transports…"; settings 'Offline mesh (unavailable)' disabled switch; feature-register row 32 (~30m offline) also unimplemented; `p2p_tunnel_service.dart` is WebRTC STUN/GSTUN only (not authenticated LAN/mesh).
- Acceptance gap: BLE transport + discovery + pairing/auth (not proximity-trust), queueing/lifecycle, cross-platform hardware (Android BLE/GATT, iOS CoreBluetooth), range/stability measurements, leak tests, review.
- Recommended CSV implementation_status: `not implemented`.

### 83 — Chat (Wi-Fi Aware) (~100m)
- Requirement: offline Wi-Fi Aware messaging (~100m, Android).
- Implementation status: **missing**.
- Evidence (inspected): no Wi-Fi Aware/NAN API usage or dependency anywhere (grep `wifi_aware|WifiAware|nearby` → only unrelated `chat_bubble` matches); delivery-checklist offline mesh: not implemented; register row 33 same.
- Acceptance gap: NAN/Wi-Fi Aware capability detection + discovery, auth handshake, transport separation from internet, Android 8+ device matrix, range evidence, review.
- Recommended CSV implementation_status: `not implemented`.

### 84 — Voice/video (LAN) (Same Wi-Fi)
- Requirement: local-network voice/video without internet.
- Implementation status: **missing**.
- Evidence (inspected): `call_service.dart` uses the authenticated WSS signaling endpoint (`{'urls':'stun:stun.l.google.com:19302'}` STUN; server-retained encrypted offers); no LAN discovery/signaling path exists; delivery-checklist: "LAN calls | Not implemented"; register row 11 (offline LAN calls) also not implemented; no mDNS.
- Acceptance gap: LAN discovery + authenticated local signaling (not open relay), NAT/permission handling, fallback semantics, two-device same-Wi-Fi evidence, review.
- Recommended CSV implementation_status: `not implemented`.

### 85 — QR contact add (Both present)
- Requirement: add a contact by scanning their QR in person.
- Implementation status: **partial** (QR identity verify exists; QR *add-contact* flow does not).
- Evidence (inspected): `lib/ui/screens/verification/verification_screen.dart` (shows `QrImageView('chhaya://identity/<id>')`, `MobileScanner` scan, match-by-`publicKey`, sets `isVerified=true`); `contacts_tab.dart` add-contact is manual Chhaya-ID entry only (`_showAddContact` → `api.addContact(chhayaId:…)`); no QR payload format for adding (only verifying existing contacts); register: "QR identity check exists; device camera testing pending".
- Acceptance gap: QR contact-add payload + import flow, camera permission + scan adversarial tests (substituted codes), device evidence, verification UX tying add→verify, review.
- Recommended CSV implementation_status: `partially implemented`.

### 86 — Vault/duress (Fully local)
- Requirement: fully-local vault + duress behavior (no network).
- Implementation status: **partial** (local panic-PIN removal exists; vault/decoy do not).
- Evidence (inspected): `settings_screen.dart::_showPanicPinSetup()` → `setPanicPin`; `local_database.dart` `getPanicPin/setPanicPin`, `app_lock_gate.dart` (panic-PIN entry → local removal); delivery-checklist: "Vault/decoy/duress | Not implemented" and "Panic PIN | Local data/key removal — physical-device validation and documented remote-copy limits" pending; threat-model: "Panic PIN removes local account data and roots only. It does not erase remote recipients or backups."; no vault exists (67–69).
- Acceptance gap: vault + decoy design and implementation, local-only guarantee (prove zero network calls, see 88), duress UX threat model, storage lifecycle, device validation, independent review.
- Recommended CSV implementation_status: `partially implemented`.

### 87 — Message queue (30s retry)
- Requirement: queued messages retry automatically on a ~30-second schedule.
- Implementation status: **partial** (outbox + foreground retry exist; 30s schedule not established).
- Evidence (inspected): `messaging_service.dart::retryPending/retryAllPending` (~L647–L720, exact-envelope resend, outbox-gated); `chat_screen.dart::_retryPending` + 'Message queued…' SnackBar; `home_shell.dart::_scheduleNextSync()` — timer 15s (ok) / 30s (1 failure) / 60s (2+), and **30s only for unauthenticated (local-only) accounts**, not a guaranteed 30s retry cadence; tests `delivery_adversarial_test.dart` (retry convergence), register: "Outbox and foreground retry exist; 30-second schedule not established"; 2026-11-08 audit: pending-stuck-forever cases pinned.
- Acceptance gap: specified + implemented 30s (or formally re-specified) retry policy with backoff, stuck-message surfacing to the user, restart-survival tests, network-loss device drills, independent review of retry semantics.
- Recommended CSV implementation_status: `partially implemented`.

### 88 — Zero network calls (Local-Only mode verified)
- Requirement: a local-only mode in which the app makes zero network calls, verifiably.
- Implementation status: **missing** (and therefore unverifiable).
- Evidence (inspected): no local-only flag/mode in `lib/` (grep `localOnly|localMode|connectionMode|Local-Only` → no hits); no transport separation exists; server contact is unconditional (sync/poll/signaling/calls); settings exposes only 'Onion routing (unavailable)' / 'Offline mesh (unavailable)' disabled placeholders; delivery-checklist: "Local-only/Auto modes | Not implemented — Transport separation plus a test demonstrating zero internet calls in local mode" required.
- Acceptance gap: mode implementation + enforcement (HTTP/WSS/WebRTC/STUN all gated), a test/harness proving zero packets in local mode (emulator + device), UI honesty, docs, review.
- Recommended CSV implementation_status: `not implemented`.

## Customization group (89–96)

### 89 — Claude Light theme (Coral on cream)
- Requirement: light cream/coral default theme.
- Implementation status: **implemented** (device/accessibility review pending).
- Evidence (inspected): `lib/ui/theme/chhaya_theme.dart` (`materialLight`, default `MaterialApp.theme` in `main.dart`), `chhaya_colors.dart` (cream/coral palette), `chhaya_palette.dart` (scheme-derived palette used app-wide), appearance via `appearance_provider.dart` (default `ThemeMode.light`). Delivery-checklist: "Cream/coral + Departure Mono | Implemented and bundled font licenses — new-feature accessibility and physical-device review" pending; contrast/accessibility review not done.
- Acceptance gap: WCAG contrast measurement on device, large-text/reduced-motion passes, device rendering review, then checklist sign-off.
- Recommended CSV implementation_status: `implemented but unverified`.

### 90 — V13 dark theme (Optional)
- Requirement: preserved optional V13 hacker-terminal dark theme, selectable.
- Implementation status: **scaffolded-but-unused** (file exists, never wired).
- Evidence (inspected): `lib/ui/theme/chhaya_dark_theme.dart` (complete `ChhayaDarkTheme.material` — preserved V13 scheme; referenced nowhere else); `main.dart` wires `theme: materialLight`, `darkTheme: ChhayaTheme.materialDark` (the **warm** dark, not V13); `appearance_provider` offers only light/dark/system ('Warm dark'/'Warm light'); settings Appearance sheet exposes those three only; delivery-checklist: "Dark theme/customizer/icons | Legacy dark APIs, incomplete product flow | Semantic theme migration, controls and contrast checks".
- Acceptance gap: decide retain-vs-remove V13; if retained, semantic migration, user-facing control, contrast checks, device evidence — or documented removal.
- Recommended CSV implementation_status: `partially implemented`.

### 91 — DEP?2T?RE_MONO i.e. Departure Mono (Technical font)
- Requirement: Departure Mono as the technical/display face (name mangled in register).
- Implementation status: **implemented** (coverage needs review).
- Evidence (inspected): `assets/fonts/DepartureMono-Regular.otf` + `OFL-DepartureMono.txt` bundled; `pubspec.yaml` `fonts:` declares `DepartureMono`; `chhaya_typography.dart` (`_displayFontFamily`, `_monoFontFamily = 'DepartureMono'`); license registered in `main.dart` LicenseRegistry; `chhaya_theme.dart` display scale uses it. Usage coverage outside display/mono roles not audited ("typography coverage needs review" per register).
- Acceptance gap: typography coverage audit (all surfaces), rendering on target devices, license inventory completion (root license effectively empty — ponytail/checklist), accessibility review.
- Recommended CSV implementation_status: `implemented but unverified`.

### 92 — Inter + Tiempos (Body + display)
- Requirement: Inter for body, Tiempos for display.
- Implementation status: **partial** (Inter present; Tiempos absent entirely).
- Evidence (inspected): `assets/fonts/Inter-Variable.ttf` + OFL; `pubspec.yaml` Inter declared; `chhaya_typography.dart` `_fontFamily = 'Inter'` (body), display mapped to `DepartureMono` — **Tiempos is bundled nowhere** (grep `Tiempos` in `lib/` → no matches; no Tiempos asset/license). Apple platforms proxy to CupertinoSystemDisplay/Text via `forPlatform()`.
- Acceptance gap: either license+bundle Tiempos and wire display roles (with license attribution), or formally re-spec display face; contrast/device review; license inventory.
- Recommended CSV implementation_status: `partially implemented`.

### 93 — Full color picker (Custom themes)
- Requirement: user-defined custom color themes via a full picker.
- Implementation status: **missing**.
- Evidence (inspected): no color-picker dependency or code (grep `ColorPicker|colorPicker|customTheme` → no hits); settings exposes only three ThemeModes; `chhaya_palette.dart` computes scheme-derived colors, not user-overridable parameters.
- Acceptance gap: product/privacy design for custom themes (contrast enforcement, persistence, export/share?), implementation + accessible defaults, device evidence, review.
- Recommended CSV implementation_status: `not implemented`.

### 94 — App icon variants (Multiple)
- Requirement: multiple selectable app icons.
- Implementation status: **missing**.
- Evidence (inspected): single launcher icon set only — Android `res/mipmap-*/ic_launcher.png`, iOS `AppIcon.appiconset` (all required sizes, one variant), no `activity-alias`/`alternateIcon` (grep: none); branding checklist verifies one identity only ("Custom coral chat-bubble/crescent … Android launcher icons, all iOS app icon sizes"); no settings control for icons.
- Acceptance gap: icon variant artwork + export, Android adaptive aliases / iOS `setAlternateIconName`, selection UI, store-asset implications, device evidence.
- Recommended CSV implementation_status: `not implemented`.

### 95 — Proxy support (SOCKS5/HTTP/HTTPS)
- Requirement: route traffic through SOCKS5/HTTP/HTTPS proxies.
- Implementation status: **missing**.
- Evidence (inspected): no proxy configuration anywhere — no `findProxy`, no proxy deps (`pubspec.yaml`: plain `http`, `dio`, `web_socket_channel`, `flutter_webrtc`); server has only `app.set('trust proxy', config.TRUST_PROXY_HOPS)` (TLS-termination concern, not a client feature); delivery-checklist "Proxy modes | Incomplete — HTTP/WebSocket/WebRTC routing behavior, DNS and leak tests" but **no source evidence of any implementation was found** (checklist wording likely refers to planned scope); settings/UI contain no proxy controls.
- Acceptance gap: define scope (per-transport: REST/WSS/WebRTC/TURN), authenticated proxy config + DNS/leak protection, tests (incl. WebRTC — notoriously leaky), device evidence, review.
- Recommended CSV implementation_status: `not implemented`.

### 96 — Connection toggle (Online/Local/Auto)
- Requirement: user-selectable Online / Local-Only / Auto connectivity.
- Implementation status: **missing**.
- Evidence (inspected): no toggle exists (grep `ConnectionMode|connection_toggle|localMode|autoMode` → no hits); delivery-checklist: "Local-only/Auto modes | Not implemented"; register: "Connection toggle | Not implemented" (only register row with explicit 'Not implemented' here, confirmed).
- Acceptance gap: depends on 88; define transport matrix per mode, auto-mode heuristics + UI truthfulness, tests incl. airplane-mode drills, device evidence.
- Recommended CSV implementation_status: `not implemented`.

## UI and accessibility group (97–98)

### 97 — Spring physics (Critically damped)
- Requirement: motion built on critically damped springs.
- Implementation status: **implemented** (unverified for feel/accessibility).
- Evidence (inspected): `lib/ui/theme/chhaya_theme.dart` `ChhayaSprings` (`standard` stiffness 170 / damping 26.0 — critical ≈ 2√(k·m) ≈ 26.08, i.e. critically damped; `momentum` damping 20.8 underdamped; `sheet` 220/23.7 ≈ critical), `criticalCurve = Curves.easeOutExpo`; `lib/ui/widgets/pressable.dart` (`SpringBack` — `SpringSimulation`, press scale 0.97); `lib/ui/theme/chhaya_motion.dart` (`SwipeReply` settle via `SpringSimulation(ChhayaSprings.standard …)`); `MessageEntrance` uses easeOutBack (not a spring). Accessibility: `ChhayaMotion.reduced()` zero-motion fallback exists and is applied in press/motion paths.
- Acceptance gap: motion review on device (consistency, no overshoot regressions), reduced-motion conformance testing, frame-timing evidence; then checklist sign-off.
- Recommended CSV implementation_status: `implemented but unverified`.

### 98 — Message send animation (Slide+scale+sweep+check)
- Requirement: send animation combining slide, scale, sweep and checkmark.
- Implementation status: **partial**.
- Evidence (inspected): `lib/ui/theme/chhaya_motion.dart::MessageEntrance` — fade + translate(10px) + scale(0.96→1) with `easeOutBack` over 360 ms, used for incoming/sent bubbles (`chat_screen.dart` L~1268) and route transitions; send button is a static `arrow_upward_rounded` icon with spinner while `_sending`; **no sweep or checkmark animation, no slide/scale choreography on send**; status glyphs (sent/delivered/read) shown as plain text/icons elsewhere. `Pressable` provides generic press spring only.
- Acceptance gap: full send choreography implemented + reduced-motion variant, performance evidence on low-end devices, UX review, device sign-off.
- Recommended CSV implementation_status: `partially implemented`.

## Cross-cutting notes

- **Internal audit vs independent review:** everything above is a single-engineer source read. No independent cryptographic, protocol or device-level review has covered rows 67–98; the delivery checklist's "External audit | Not commissioned" stands. No row in 67–98 is releasable on this evidence.
- **Shared blockers spanning rows:** the vault doesn't exist (67–69, 86); authenticated device enrollment doesn't exist (70–74, 81, 75 client-side); restore protocol defect pinned (77, 80, 81); no local-only transport separation (88, 96); offline transports absent (82–84). These are design+build work, not checkbox fixes.
- **Current CSV state:** every 67–98 row reads `implementation_status=assessment pending` with `assessment_evidence="No complete source-to-acceptance assessment recorded yet"` (distinguishing 77/78/80/81, whose evidence columns carry 2026-11-08 notes). This report supplies the missing assessment but does **not** authorize CSV edits, `release_status` changes, or merge; those remain maintainer actions on `codex/` branches.
- **Not inspected / not run:** no source outside `lib/`, `backend/server/src`, `test/`, `assets/`, `android/ios` configs was executed; no tests were run; no device was attached; `notification_service.dart`, `stego_service.dart`, onion/decentralized legacy code, Windows registry/DPAPI paths, and CI workflows were read only as listed. `ponytail-audit-2026-10-29.md`, `delivery-checklist.md`, `threat-model.md`, `feature-register.md`, and `feature-verification-127.csv` were read in full.
