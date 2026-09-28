// In-memory secure storage for tests ONLY.
//
// Purpose: [SecureStorage] implementation backed by a plain map so unit
// tests and CI (no hardware, no platform channels) can exercise the key
// manager. Never use in production — values are NOT encrypted here.
import 'package:flutter/foundation.dart';
import 'secure_storage.dart';

/// In-memory [SecureStorage]. Test-only.
@visibleForTesting
class SecureStorageMock implements SecureStorage {
  /// Creates an empty mock, optionally prefilled with [seed].
  SecureStorageMock([Map<String, String>? seed]) {
    if (seed != null) {
      _entries.addAll(seed);
    }
  }

  final Map<String, String> _entries = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _entries[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _entries[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _entries.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _entries.clear();
  }

  @override
  Future<bool> containsKey({required String key}) async {
    return _entries.containsKey(key);
  }

  @override
  Future<HardwareSecurityLevel> securityLevel() async {
    return HardwareSecurityLevel.unknown;
  }
}
