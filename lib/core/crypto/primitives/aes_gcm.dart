// AES-256-GCM authenticated encryption primitive for Chhaya.
//
// Purpose: the only symmetric cipher used for message content. AEAD gives
// confidentiality plus integrity — tampered ciphertext fails closed.
// Wire format produced here is `nonce (12B) || ciphertext || tag (16B)`.
// Nonces are random per encryption and never reused with the same key.
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'rng.dart';

/// AES-256-GCM authenticated encryption.
class AesGcm {
  AesGcm._();

  /// Required key length (256 bit).
  static const int keyLength = 32;

  /// Nonce length (96 bit). Never reuse a nonce with the same key.
  static const int nonceLength = 12;

  /// Authentication tag length (128 bit).
  static const int tagLength = 16;

  /// Tag size in bits, as required by PointyCastle AEAD parameters.
  static const int tagBits = 128;

  /// Encrypts [plaintext] with a 32-byte [key].
  ///
  /// Returns `nonce || ciphertext || tag`. A fresh random nonce is
  /// generated when [nonce] is omitted.
  static Uint8List encryptBytes(
    Uint8List key,
    Uint8List plaintext, {
    Uint8List? nonce,
    Uint8List? aad,
  }) {
    _checkKey(key);
    final iv = nonce ?? Csprng.instance.bytes(nonceLength);
    if (iv.length != nonceLength) {
      throw ArgumentError.value(
        iv.length,
        'nonce',
        'AES-GCM nonces must be 12 bytes',
      );
    }
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(key),
          tagBits,
          iv,
          aad ?? Uint8List(0),
        ),
      );
    final ciphertext = cipher.process(plaintext);
    final out = Uint8List(iv.length + ciphertext.length);
    out.setRange(0, iv.length, iv);
    out.setRange(iv.length, out.length, ciphertext);
    return out;
  }

  /// Decrypts `nonce || ciphertext || tag` with a 32-byte [key].
  ///
  /// Throws if authentication fails (wrong key, tampered data, or
  /// truncated input). Never returns unauthenticated plaintext.
  static Uint8List decryptBytes(
    Uint8List key,
    Uint8List combined, {
    Uint8List? aad,
  }) {
    _checkKey(key);
    if (combined.length < nonceLength + tagLength) {
      throw ArgumentError.value(
        combined.length,
        'combined',
        'Input too short to contain nonce and tag',
      );
    }
    final iv = combined.sublist(0, nonceLength);
    final cipherAndTag = combined.sublist(nonceLength);
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(key),
          tagBits,
          Uint8List.fromList(iv),
          aad ?? Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(cipherAndTag));
  }

  static void _checkKey(Uint8List key) {
    if (key.length != keyLength) {
      throw ArgumentError.value(
        key.length,
        'key',
        'AES-256 keys must be 32 bytes',
      );
    }
  }
}
