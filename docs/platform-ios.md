# iOS platform foundation

Minimum deployment target: iOS 15.0. Flutter is pinned to 3.47.1.
UIScene initializes the implicit Flutter engine; plugin registration and
security channels use the application registrar messenger.

## Storage

The native security channel creates a non-exportable Secure Enclave P-256
key, gated by the device passcode and WhenUnlockedThisDeviceOnly access.
Apple Security ECIES wraps opaque app secrets before device-only Keychain
storage. X25519 and Ed25519 secrets are not stored inside the enclave.
The native level ladder is secure_enclave > keychain > software; Dart retains
its existing tee enum value for Keychain for public API compatibility.
Simulators and devices without enclave hardware use device-only Keychain,
with a Dart warning. Authentication failures never silently downgrade.
Existing unwrapped Keychain entries remain readable for compatibility;
subsequent writes use wrapping. Wrapped entries cannot be recovered after
loss of the enclave key. Hardware checks and encryption failures must be
verified on a passcode-protected physical device before release.

## Platform limits

- iOS mesh will use MultipeerConnectivity; the planned Android NAN transport
  does not provide a shared cross-platform implementation. Mesh is not
  implemented by this foundation task.
- BLE background execution is restricted. Mesh must be foreground-first and
  degrade gracefully when suspended.
- Biometrics are Face ID / Touch ID. There is no iris API or supported way
  to identify which enrolled face authenticated.
- Capture notifications cannot guarantee prevention of iOS screenshots.
  The vault must not promise that screenshots can never reach Photos.
- Push needs an Apple Developer account, provisioning, APNs credentials and
  subsequent push integration. Entitlements alone do not enable delivery.
- Privacy manifest currently declares no tracking or app-collected data.
  Reconcile it with actual backend/push data flows before store submission.
  No active-keyboard required-reason access is declared because none is used.

## CocoaPods

The locked sqflite_sqlcipher 3.4.1 podspec requires SQLCipher 4.10.0,
so Podfile uses 4.10.0 instead of the prompt's incompatible ~> 4.1.0.
FMDB/SQLCipher comes transitively from that plugin; do not add plain FMDB.
No new Dart dependency was introduced.

## Verification and release gate

Run flutter pub get, then cd ios && pod install --repo-update on macOS.
.github/workflows/ios-build.yml compiles Swift/CocoaPods using
flutter build ios --debug --no-codesign, runs analysis and tests.
Windows cannot compile the iOS target. A successful macOS job and physical
storage tests are mandatory before merge; CI being configured is not a pass.
Signed IPA, APNs registration and App Store submission belong to release F6.

References:
- https://api.flutter.dev/ios-embedder/protocol_flutter_implicit_engine_bridge-p.html
- https://developer.apple.com/documentation/security/seckeyalgorithm/eciesencryptioncofactorx963sha256aesgcm
