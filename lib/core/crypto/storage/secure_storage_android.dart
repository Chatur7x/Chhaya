// Android secure storage: Keystore + StrongBox preference.
//
// Purpose: store key material in the Android Keystore via encrypted
// shared preferences, preferring a StrongBox secure element when the
// device proves one exists. Ladder: StrongBox → TEE Keystore →
// software Keystore (with logged warning).
//
// NATIVE FOLLOW-UP (pending decision): StrongBox enforcement needs a
// ~20-line Kotlin handler for channel `chhaya/security`
// (`isStrongBoxAvailable` via PackageManager.FEATURE_STRONGBOX_KEYSTORE
// plus an AndroidKeyStore AES key with setIsStrongBoxBacked(true)).
// Until that handler ships, the probe below degrades gracefully to the
// TEE assumption with a warning — the release build is unaffected.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../log.dart';
import 'secure_storage.dart';

/// Android Keystore adapter with StrongBox preference.
class AndroidSecureStorage implements SecureStorage {
  /// Creates the adapter. Pass [delegate] in tests to avoid platform
  /// channels; pass [channel] to stub the StrongBox probe.
  AndroidSecureStorage({SecureStorage? delegate, MethodChannel? channel})
      : _delegate = delegate ??
            FlutterSecureStorageAdapter(
              const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true),
              ),
            ),
        _channel = channel ?? const MethodChannel('chhaya/security');

  final SecureStorage _delegate;
  final MethodChannel _channel;

  @override
  Future<void> write({required String key, required String value}) {
    return _delegate.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _delegate.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _delegate.delete(key: key);
  }

  @override
  Future<void> deleteAll() {
    return _delegate.deleteAll();
  }

  @override
  Future<bool> containsKey({required String key}) {
    return _delegate.containsKey(key: key);
  }

  @override
  Future<HardwareSecurityLevel> securityLevel() async {
    final native = await queryNativeStorageLevel(_channel);
    if (native != null) {
      return native;
    }
    try {
      final available =
          await _channel.invokeMethod<bool>('isStrongBoxAvailable');
      if (available == true) {
        return HardwareSecurityLevel.strongBox;
      }
      // Probe answered "no StrongBox": Keystore is still hardware-backed
      // (TEE) on any device with encrypted shared preferences.
      return HardwareSecurityLevel.tee;
    } on MissingPluginException {
      ChhayaLog.w(
        'StrongBox probe unavailable (no native handler); assuming TEE Keystore',
        name: 'SecureStorage.android',
      );
      return HardwareSecurityLevel.tee;
    } catch (error) {
      ChhayaLog.w(
        'StrongBox probe failed; assuming TEE Keystore',
        name: 'SecureStorage.android',
        error: error,
      );
      return HardwareSecurityLevel.tee;
    }
  }
}
