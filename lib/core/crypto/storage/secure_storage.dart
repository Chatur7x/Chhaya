// Secure storage abstraction for Chhaya key material.
//
// Purpose: single interface every platform adapter implements, so the
// key manager never touches platform APIs directly. Keys must NEVER be
// stored in shared_preferences or plain files — only through this
// interface. Use [SecureStorages.platformDefault] to get the right
// adapter; use [SecureStorageMock] (mock file) in tests.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'secure_storage_android.dart';
import 'secure_storage_ios.dart';
import 'secure_storage_windows.dart';

/// Hardware backing level of a storage adapter.
///
/// Ordered weakest to strongest. `unknown` means the level could not be
/// probed (e.g. missing native handler) — callers must treat it as
/// untrusted and log a warning, never as strong.
enum HardwareSecurityLevel {
  /// Could not be determined. Treat as untrusted.
  unknown,

  /// Software-only protection (no hardware keystore proven).
  software,

  /// Hardware TEE keystore (Android Keystore, Apple Keychain on SEP).
  tee,

  /// Apple Secure Enclave (EC keys generated inside the enclave).
  secureEnclave,

  /// Android StrongBox (tamper-resistant secure element).
  strongBox,
}

/// Extension for human-readable level names (safe to log: no secrets).
extension HardwareSecurityLevelLabel on HardwareSecurityLevel {
  /// Short label, safe for logs and diagnostics.
  String get label {
    switch (this) {
      case HardwareSecurityLevel.unknown:
        return 'unknown';
      case HardwareSecurityLevel.software:
        return 'software';
      case HardwareSecurityLevel.tee:
        return 'tee';
      case HardwareSecurityLevel.secureEnclave:
        return 'secure-enclave';
      case HardwareSecurityLevel.strongBox:
        return 'strongbox';
    }
  }
}

/// Abstract secure key-value storage.
///
/// All values are opaque strings (base64 key material or JSON). The
/// interface never exposes raw bytes in logs or errors.
abstract class SecureStorage {
  /// Stores [value] under [key], overwriting any existing entry.
  Future<void> write({required String key, required String value});

  /// Reads the value for [key], or null when absent.
  Future<String?> read({required String key});

  /// Deletes [key] if present.
  Future<void> delete({required String key});

  /// Deletes every entry owned by this adapter.
  Future<void> deleteAll();

  /// Returns true when [key] exists.
  Future<bool> containsKey({required String key});

  /// Probes the hardware backing level. Never throws.
  Future<HardwareSecurityLevel> securityLevel();
}

/// Default flutter_secure_storage adapter (all platforms).
///
/// Uses encrypted shared preferences on Android and the platform
/// keystore elsewhere. Used directly on desktop/web and as the delegate
/// inside the platform adapters.
class FlutterSecureStorageAdapter implements SecureStorage {
  /// Creates an adapter around [storage] (or a default instance).
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }

  @override
  Future<void> deleteAll() {
    return _storage.deleteAll();
  }

  @override
  Future<bool> containsKey({required String key}) {
    return _storage.containsKey(key: key);
  }

  @override
  Future<HardwareSecurityLevel> securityLevel() async {
    return HardwareSecurityLevel.unknown;
  }
}

/// Queries `getStorageLevel()` on the native `chhaya/security` channel.
///
/// Returns null when the native handler is missing, outdated, or errors —
/// callers must fall back to their boolean probes. Never throws.
Future<HardwareSecurityLevel?> queryNativeStorageLevel(
    MethodChannel channel) async {
  try {
    final level = await channel.invokeMethod<String>('getStorageLevel');
    switch (level) {
      case 'strongbox':
        return HardwareSecurityLevel.strongBox;
      case 'secure-enclave':
        return HardwareSecurityLevel.secureEnclave;
      case 'tee':
        return HardwareSecurityLevel.tee;
      case 'software':
        return HardwareSecurityLevel.software;
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// Factory for the platform-appropriate adapter.
class SecureStorages {
  SecureStorages._();

  /// Returns the best adapter for the current platform.
  ///
  /// Android → Keystore (+StrongBox probe), iOS → Keychain (+Secure
  /// Enclave probe), Windows → DPAPI credential store, everything else
  /// → default adapter. Never throws.
  static SecureStorage platformDefault() {
    if (kIsWeb) {
      return FlutterSecureStorageAdapter();
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSecureStorage();
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return IOSSecureStorage();
      case TargetPlatform.windows:
        return WindowsSecureStorage();
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FlutterSecureStorageAdapter();
    }
  }
}
