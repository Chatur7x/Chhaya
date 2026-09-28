// iOS/macOS secure storage: Keychain + Secure Enclave preference.
//
// Purpose: store key material in the Apple Keychain (SEP-backed on
// modern devices) with device-only accessibility, preferring Secure
// Enclave generation for EC keys when the enclave proves available.
// Ladder: Secure Enclave → Keychain (TEE) → software (logged warning).
//
// NATIVE FOLLOW-UP (pending decision): enclave proof needs a small
// Swift handler for channel `chhaya/security` (`isSecureEnclaveAvailable`
// via kSecAttrTokenIDSecureEnclave key generation test). Until it ships,
// the probe degrades gracefully to the Keychain assumption.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../log.dart';
import 'secure_storage.dart';

/// Apple Keychain adapter with Secure Enclave preference.
class IOSSecureStorage implements SecureStorage {
  /// Creates the adapter. Pass [delegate] in tests to avoid platform
  /// channels; pass [channel] to stub the enclave probe.
  IOSSecureStorage({SecureStorage? delegate, MethodChannel? channel})
      : _delegate = delegate ??
            FlutterSecureStorageAdapter(
              const FlutterSecureStorage(
                iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock_this_device,
                ),
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
          await _channel.invokeMethod<bool>('isSecureEnclaveAvailable');
      if (available == true) {
        return HardwareSecurityLevel.secureEnclave;
      }
      return HardwareSecurityLevel.tee;
    } on MissingPluginException {
      ChhayaLog.w(
        'Secure Enclave probe unavailable (no native handler); using Keychain',
        name: 'SecureStorage.ios',
      );
      return HardwareSecurityLevel.tee;
    } catch (error) {
      ChhayaLog.w(
        'Secure Enclave probe failed; using Keychain',
        name: 'SecureStorage.ios',
        error: error,
      );
      return HardwareSecurityLevel.tee;
    }
  }
}
