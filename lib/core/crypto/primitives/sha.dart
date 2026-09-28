// SHA-2 hashing primitives for Chhaya.
//
// Purpose: SHA-256 and SHA-512 digests plus hex encoding helpers.
// Used for fingerprints, checksums (BIP-39), and key derivation inputs.
import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

/// SHA-2 hash functions.
class Sha {
  Sha._();

  /// Computes SHA-256 over [data].
  static Uint8List hash256(Uint8List data) {
    return pc.SHA256Digest().process(data);
  }

  /// Computes SHA-512 over [data].
  static Uint8List hash512(Uint8List data) {
    return pc.SHA512Digest().process(data);
  }

  /// Computes SHA-256 over the UTF-8 encoding of [input].
  static Uint8List hash256String(String input) {
    return hash256(Uint8List.fromList(utf8.encode(input)));
  }

  /// Lowercase hex encoding of [bytes] (no 0x prefix).
  static String hexOf(Uint8List bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  /// SHA-256 of [input], returned as lowercase hex.
  static String hashStringHex(String input) {
    return hexOf(hash256String(input));
  }
}
