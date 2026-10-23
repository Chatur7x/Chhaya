// iOS/macOS secure storage: Keychain + Secure Enclave preference.
//
// Purpose: store key material in the Apple Keychain (SEP-backed on
// modern devices) with device-only accessibility, preferring Secure
// Enclave generation for EC keys when the enclave proves available.
// Ladder: Secure Enclave → Keychain (TEE) → software (logged warning).
//
// Native P-256 ECIES wrapping is provided by ChhayaSecurityPlugin.
// X25519/Ed25519 bytes are wrapped in Keychain, never imported into SEP.
import 'dart:convert';
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
                  accessibility: KeychainAccessibility.unlocked_this_device,
                ),
              ),
            ),
        _channel = channel ?? const MethodChannel('chhaya/security');

  final SecureStorage _delegate;
  final MethodChannel _channel;

  static const _prefix = 'chhaya.enclave.v1:';

  @override
  Future<void> write({required String key, required String value}) async {
    String? wrapped;
    try {
      wrapped = await _channel.invokeMethod<String>('wrapSecret', {
        'value': base64Encode(utf8.encode(value)),
      });
    } on MissingPluginException {
      // Older native hosts retain device-only Keychain protection.
    }
    if (wrapped == null) {
      ChhayaLog.w('Secure Enclave wrapping unavailable; using device-only Keychain',
          name: 'SecureStorage.ios');
    }
    await _delegate.write(
        key: key, value: wrapped == null ? value : '$_prefix$wrapped');
  }

  @override
  Future<String?> read({required String key}) async {
    final stored = await _delegate.read(key: key);
    if (stored == null || !stored.startsWith(_prefix)) return stored;
    // An existing encrypted envelope must never fall back to plaintext.
    final plain = await _channel.invokeMethod<String>('unwrapSecret', {
      'value': stored.substring(_prefix.length),
    });
    if (plain == null) throw StateError('Secure Enclave unwrap unavailable');
    return utf8.decode(base64Decode(plain));
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
