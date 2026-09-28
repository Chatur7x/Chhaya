// SQLCipher database key handling (V14 Part 3).
//
// Purpose: derive the 32-byte database key from the Part 2 key manager,
// render it as PRAGMA-safe hex, and provide the field-level AES-GCM
// envelope for content columns. The hex key is validated before use so
// it can never become a SQL injection vector.
import 'dart:convert';
import 'dart:typed_data';
import '../crypto/key_manager.dart';
import '../crypto/primitives/aes_gcm.dart';
import '../crypto/primitives/rng.dart';
import '../crypto/primitives/sha.dart';

/// Database key derivation and field envelope helpers.
class DatabaseKey {
  DatabaseKey._();

  /// 64 lowercase hex chars (32 bytes).
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Derives the database key for [userId] via the key manager.
  ///
  /// Deterministic per user, 32 bytes, never stored — re-derived on
  /// every open. Callers must wipe the result with [Csprng.wipe] when
  /// the database is closed or cleared.
  static Future<Uint8List> derive(KeyManager keyManager,
      {required String userId}) {
    return keyManager.getDatabaseKey(userId: userId);
  }

  /// Renders a 32-byte key as 64-char hex for `PRAGMA key`.
  ///
  /// Throws [ArgumentError] unless the key is exactly 32 bytes, so a
  /// malformed key can never reach SQL string building.
  static String toPragmaHex(Uint8List key) {
    if (key.length != AesGcm.keyLength) {
      throw ArgumentError.value(
        key.length,
        'key',
        'Database keys must be 32 bytes',
      );
    }
    final hex = Sha.hexOf(key);
    if (!_hex64.hasMatch(hex)) {
      throw StateError('Derived database key failed hex validation');
    }
    return hex;
  }

  /// Encrypts a UTF-8 field with the database key.
  ///
  /// Returns base64(nonce || ciphertext || tag) with a fresh CSPRNG
  /// nonce per call.
  static String encryptField(String plain, Uint8List dbKey) {
    final combined = AesGcm.encryptBytes(
      dbKey,
      Uint8List.fromList(utf8.encode(plain)),
    );
    return base64Encode(combined);
  }

  /// Decrypts a field envelope. Returns null on tampering, truncation,
  /// or undecodable input — callers skip the row, never crash.
  static String? decryptField(String? envelope, Uint8List dbKey) {
    if (envelope == null || envelope.isEmpty) {
      return null;
    }
    try {
      final combined = base64Decode(envelope);
      final plain = AesGcm.decryptBytes(dbKey, combined);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }
}
