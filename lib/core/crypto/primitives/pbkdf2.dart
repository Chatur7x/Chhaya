// PBKDF2-HMAC-SHA256 key derivation primitive for Chhaya.
//
// Purpose: stretches low-entropy secrets (recovery phrases, PINs) into
// encryption keys. The 100k iteration count is the V13 baseline; ratchet
// and session keys use HKDF instead (see hkdf.dart).
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

/// PBKDF2 with HMAC-SHA256.
class Pbkdf2 {
  Pbkdf2._();

  /// Default iteration count for account key derivation.
  static const int defaultIterations = 100000;

  /// Default derived key length (256 bit).
  static const int defaultLength = 32;

  /// Derives a key from [password] bytes and [salt].
  static Uint8List deriveKey({
    required Uint8List password,
    required Uint8List salt,
    int iterations = defaultIterations,
    int length = defaultLength,
  }) {
    if (iterations <= 0) {
      throw ArgumentError.value(
        iterations,
        'iterations',
        'Must be positive',
      );
    }
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'Must be positive');
    }
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, iterations, length));
    final output = Uint8List(length);
    derivator.deriveKey(password, 0, output, 0);
    return output;
  }
}
