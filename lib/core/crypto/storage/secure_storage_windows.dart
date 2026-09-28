// Windows secure storage: DPAPI credential store (per-user scope).
//
// Purpose: store key material via the Windows Credential Manager, which
// encrypts with DPAPI under the current user's logon secret. Scope is
// inherently per-user: another Windows account on the same machine
// cannot decrypt these entries. No native handler is required.
import 'secure_storage.dart';

/// Windows Credential Manager (DPAPI, per-user scope) adapter.
class WindowsSecureStorage implements SecureStorage {
  /// Creates the adapter. Pass [delegate] in tests to avoid platform
  /// channels.
  WindowsSecureStorage({SecureStorage? delegate})
      : _delegate = delegate ?? FlutterSecureStorageAdapter();

  final SecureStorage _delegate;

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
    // DPAPI user-scope encryption is software-backed by design.
    return HardwareSecurityLevel.software;
  }
}
