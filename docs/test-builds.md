# Sharing and testing Chhaya

## Android

The Android workflow exports Chhaya-Android-Test-APK. Download and unzip the
artifact, then share app-debug.apk. This is a debug-signed test build, not a
production release. Android may require allowing installation from the app
opening the APK. A different signing certificate from an older installed
build can prevent upgrades. Back up important data before replacing an app;
uninstalling removes its data. Do not rely on this development build for
sensitive communication.

The locally built `dist/Chhaya-V14-NEW.apk` is generated with
`flutter build apk --release --target-platform android-arm64 --no-pub`, has
package name `com.chaaya.app.chaaya`, and is signed with the repository's debug
key. It is optimized in release mode, but it is still a test artifact: it has
not been signed with an owner-controlled release key or tested on a physical
device. It installs alongside the separate `com.chaaya.app.chaaya.test` app, so
the two apps have separate local accounts and databases. Its SHA-256 is recorded
in `dist/Chhaya-V14-NEW.apk.sha256`.

The Android release build requires the AWS-LC native provider build and can
take several minutes on a clean checkout. Do not infer device-level SQLCipher
or cryptographic correctness from successful compilation alone.

### Local release signing (14.0.1 and later)

Run `python scripts/setup_android_signing.py` once before a local release build.
It generates a private RSA signing key under `~/.chhaya/signing/` and an ignored
`android/key.properties`. Existing keys/configuration are preserved. Back up both
in encrypted offline storage: losing this key prevents signing compatible updates.
Neither file is committed or uploaded. A normal release build now uses this key
and refuses to silently fall back to the debug certificate. CI explicitly opts
into test signing with `CHHAYA_ALLOW_DEBUG_SIGNING=true`.

A build signed with the new key cannot update an older debug-signed installation
of the same package. Export important account data before deciding how to migrate;
uninstalling an existing app deletes its local data. Release signing establishes
artifact identity and does not establish that unfinished roadmap features work.

### Isolated Android verification

The Pixel 8a device run uses the separate package
`com.chaaya.app.chaaya.verification`, leaving both existing Chhaya packages intact.
To reproduce on a dedicated test device, set `CHHAYA_DEVICE_VERIFICATION=true`
in the build environment, then run:

```text
flutter test integration_test/native_security_test.dart -d ANDROID_DEVICE_ID
```

The test creates synthetic secrets and a temporary encrypted database in that
isolated package. It checks native wrapping/tamper rejection, reports actual key
backing, reads the native SQLCipher version, rejects plain-SQLite schema access,
reopens the encrypted database, and runs the pinned PQ primitive self-test plus
ML-KEM/ML-DSA round-trip and rejection checks. It refuses to replace an existing
account ID. Use the isolated package; never run it against an account installation.

`dist/Chhaya-14.0.1-device-preview.apk` is the ordinary app UI in that isolated
package, with the Render test origin prefilled. It is debug signed. The separately
signed release artifact is `dist/Chhaya-14.0.1-arm64.apk`.

## iPhone

The iOS workflow exports an unsigned Runner.app archive for developers.
It cannot be installed by sending the zip or renaming it to .ipa. TestFlight
and ad-hoc distribution need Apple Developer enrollment, signing and
provisioning. No Apple account or membership has been supplied for this task.
There is no signed IPA or TestFlight invitation yet. A Mac with Xcode is needed
for local Apple signing and device development.

## Two-person foreground test

1. Use the free test backend `https://chhaya-ys50.onrender.com`, or deploy
   your own backend using self-hosting.md. The free test database expires on
   27 November 2026; a sleeping server can take a minute to respond.
2. Create an account on each device and securely save its recovery words.
3. In Settings, connect both apps to the same server HTTPS origin.
4. Add the other person's full Chhaya ID. The recipient will see the conversation
   and sender identity after synchronization.
5. Both people verify the other's QR code in person, or compare the full ID over
   an independently trusted channel in Verify Contact.
6. Send a direct text message. Keep both apps open to test foreground calls.
7. Test network loss and the queued-message retry, app restart, backup/restore,
   camera/microphone denial, biometric cancellation and device lock/unlock.

Calls use WebRTC and encrypted SDP/ICE. Some networks require a private TURN
server configured with CHHAYA_TURN_URL, CHHAYA_TURN_USERNAME and
CHHAYA_TURN_PASSWORD build defines. No working TURN service is bundled.
Background ringing/CallKit/ConnectionService and mobile push integration are
not complete. The app does not claim onion/mesh transport is active.

## Remaining release gates

Two-phone and broader Android/iPhone lifecycle testing, iOS native storage/key
proof, accessibility/performance measurements, security audit, complete roadmap
features, release-key custody and Apple distribution. The isolated Pixel 8a
checks established SQLCipher and StrongBox behavior on that device only.
The repository's LICENSE file still needs the owner's licensing decision.
Successful compilation and mocked unit tests do not establish these gates.
