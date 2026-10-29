import 'dart:convert';
// Android secure storage: Keystore + StrongBox preference.
//
// Purpose: store key material in the Android Keystore via encrypted
// shared preferences, preferring a StrongBox secure element when the
// device proves one exists. Ladder: StrongBox → TEE Keystore →
// software Keystore (with logged warning).
//
// Persistent native wrapping and the actual wrapping-key security level
// are provided by ChhayaSecurityPlugin. Older plaintext delegate values
// remain readable; new writes are wrapped on supported native hosts.
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

  static const _prefix='chhaya.keystore.v1:';
  @override
  Future<void> write({required String key, required String value}) async {
    String? wrapped;
    try {
      wrapped=await _channel.invokeMethod<String>('wrapSecret',{'value':base64Encode(utf8.encode(value))});
    } on MissingPluginException {
      ChhayaLog.w('Native wrapping unavailable; using encrypted platform storage',name:'SecureStorage.android');
    }
    await _delegate.write(key:key,value:wrapped==null?value:'$_prefix$wrapped');
  }

  @override
  Future<String?> read({required String key}) async {
    final value=await _delegate.read(key:key);
    if(value==null||!value.startsWith(_prefix)) { return value; }
    final plain=await _channel.invokeMethod<String>('unwrapSecret',{'value':value.substring(_prefix.length)});
    if(plain==null) { throw StateError('Keystore wrapping key unavailable'); }
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
    ChhayaLog.w('Wrapping-key security level unavailable',
        name: 'SecureStorage.android');
    return HardwareSecurityLevel.unknown;
  }
}
