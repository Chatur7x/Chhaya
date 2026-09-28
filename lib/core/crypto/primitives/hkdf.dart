// HKDF-SHA256 key derivation primitive (RFC 5869) for Chhaya.
//
// Purpose: extract-and-expand key derivation. Used for session key
// derivation and Double/Triple Ratchet chain stepping.
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

/// HKDF with SHA-256 (RFC 5869).
class Hkdf {
  Hkdf._();

  /// Full extract-and-expand: derives [length] bytes from
  /// [inputKeyMaterial] with optional [salt] and [info].
  static Uint8List deriveKey({
    required Uint8List inputKeyMaterial,
    required int length,
    Uint8List? salt,
    Uint8List? info,
  }) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'Must be positive');
    }
    final hkdf = pc.HKDFKeyDerivator(pc.SHA256Digest())
      ..init(pc.HkdfParameters(inputKeyMaterial, length, salt, info));
    final output = Uint8List(length);
    hkdf.deriveKey(Uint8List(0), 0, output, 0);
    return output;
  }

  /// Ratchet step: derives exactly 64 bytes from [ikm] and [salt].
  ///
  /// The caller splits the output into two 32-byte keys (e.g. new root
  /// key and new chain key).
  static Uint8List derive64(Uint8List ikm, Uint8List salt) {
    final hkdf = pc.HKDFKeyDerivator(pc.SHA256Digest())
      ..init(pc.HkdfParameters(ikm, 64, salt, null));
    final output = Uint8List(64);
    hkdf.deriveKey(Uint8List(0), 0, output, 0);
    return output;
  }

  /// HKDF-Expand only (RFC 5869 §2.3) using HMAC-SHA256.
  ///
  /// Derives [outputLength] bytes from pseudorandom key [prk] and
  /// context [info]. Used for per-message keys from chain keys.
  static Uint8List expand(
    Uint8List prk,
    Uint8List info,
    int outputLength,
  ) {
    if (outputLength <= 0) {
      throw ArgumentError.value(
        outputLength,
        'outputLength',
        'Must be positive',
      );
    }
    final hmac = pc.HMac(pc.SHA256Digest(), 64);
    hmac.init(pc.KeyParameter(prk));

    final output = <int>[];
    var previous = <int>[];
    var counter = 1;

    while (output.length < outputLength) {
      final input = Uint8List.fromList([...previous, ...info, counter]);
      previous = hmac.process(input);
      output.addAll(previous);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, outputLength));
  }
}
