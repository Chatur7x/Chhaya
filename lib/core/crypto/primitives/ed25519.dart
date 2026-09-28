// Ed25519 signature primitive (RFC 8032) for Chhaya.
//
// Purpose: deterministic digital signatures for identity verification and
// message authentication. Implemented via the audited `cryptography`
// package. Private keys are 32-byte seeds; signatures are 64 bytes.
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Ed25519 signatures (RFC 8032).
class Ed25519Sign {
  Ed25519Sign._();

  /// Length of Ed25519 seed, public key, and signature lengths.
  static const int seedLength = 32;
  static const int publicKeyLength = 32;
  static const int signatureLength = 64;

  /// Generates a fresh Ed25519 signing key pair.
  static Future<SimpleKeyPair> generateKeyPair() async {
    return Ed25519().newKeyPair();
  }

  /// Signs [message] with the 32-byte private [seed].
  static Future<Uint8List> sign(
    List<int> message,
    List<int> seed,
  ) async {
    if (seed.length != seedLength) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'Ed25519 seeds must be 32 bytes',
      );
    }
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final signature = await algorithm.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies a 64-byte [signature] over [message] with the 32-byte
  /// [publicKey]. Returns true only for valid signatures.
  static Future<bool> verify(
    List<int> message,
    List<int> signature,
    List<int> publicKey,
  ) async {
    if (signature.length != signatureLength || publicKey.length != publicKeyLength) {
      return false;
    }
    final algorithm = Ed25519();
    final pub = SimplePublicKey(publicKey, type: KeyPairType.ed25519);
    return algorithm.verify(message, signature: Signature(signature, publicKey: pub));
  }
}
