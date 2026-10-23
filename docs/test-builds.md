# Sharing and testing Chhaya

## Android

The Android workflow exports Chhaya-Android-Test-APK. Download and unzip the
artifact, then share app-debug.apk. This is a debug-signed test build, not a
production release. Android may require allowing installation from the app
opening the APK. A different signing certificate from an older installed
build can prevent upgrades. Back up important data before replacing an app;
uninstalling removes its data. Do not rely on this development build for
sensitive communication.

## iPhone

The iOS workflow exports an unsigned Runner.app archive for developers.
It cannot be installed by sending the zip or renaming it to .ipa. TestFlight
and ad-hoc distribution need Apple Developer enrollment, signing and
provisioning. No Apple account or membership has been supplied for this task.
There is no signed IPA or TestFlight invitation yet. A Mac with Xcode is needed
for local Apple signing and device development.

## Two-person foreground test

1. Deploy the backend using self-hosting.md. A server/domain and trusted TLS
   certificate must be provisioned separately; none is running for this project.
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

Physical Android/iPhone testing, native at-rest encryption proof, secure enclave
and StrongBox behavior, accessibility/performance measurements, security audit,
complete roadmap features, production Android signing and Apple distribution.
The repository's LICENSE file still needs the owner's licensing decision.
Successful compilation and mocked unit tests do not establish these gates.
