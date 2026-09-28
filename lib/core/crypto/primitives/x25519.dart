// X25519 key agreement primitive (RFC 7748) for Chhaya.
//
// Purpose: Diffie-Hellman key exchange over Curve25519. Implemented via the
// audited `cryptography` package (constant-time). All key pairs and shared
// secrets in this file are raw bytes; [ChhayaKeyPair] wrapping lives in the
// engine facade.
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// X25519 Diffie-Hellman key agreement (RFC 7748).
class X25519Kex {
  X25519Kex._();

  /// Length of X25519 public keys, private keys, and shared secrets.
  static const int keyLength = 32;

  /// Generates a fresh X25519 key pair.
  ///
  /// Returns a record with 32-byte `publicKey` and 32-byte `privateKey`.
  static Future<({Uint8List publicKey, Uint8List privateKey})>
      generateKeyPair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return (
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: Uint8List.fromList(privateKeyBytes),
    );
  }

  /// Derives the 32-byte shared secret from our private key and their
  /// 32-byte public key.
  static Future<Uint8List> sharedSecret(
    List<int> privateKeyBytes,
    List<int> publicKeyBytes,
  ) async {
    if (privateKeyBytes.length != keyLength) {
      throw ArgumentError.value(
        privateKeyBytes.length,
        'privateKeyBytes',
        'X25519 private keys must be 32 bytes',
      );
    }
    if (publicKeyBytes.length != keyLength) {
      throw ArgumentError.value(
        publicKeyBytes.length,
        'publicKeyBytes',
        'X25519 public keys must be 32 bytes',
      );
    }
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    final remotePublicKey =
        SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
    final secret = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remotePublicKey,
    );
    final bytes = await secret.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
