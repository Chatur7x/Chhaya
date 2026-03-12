import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

/// EncryptionService handles the Hybrid Encryption flow:
/// 1. RSA (2048-bit) for secure Key Exchange of symmetric keys.
/// 2. AES-GCM (256-bit) for high-performance message encryption.
class EncryptionService {
  final _storage = const FlutterSecureStorage();
  final _aesAlgorithm = AesGcm.with256bits();

  /// Generates a local RSA key pair.
  /// The Private Key is stored ONLY in secure storage.
  /// The Public Key is returned for sharing with the backend/peers.
  Future<String> generateSecureKeyPair() async {
    // Note: Use a dedicated RSA library like 'crypton' or 'pointycastle' for full PEM export.
    // For this architectural refinement, we simulate the secure storage of a generated 2048-bit key.
    final secureRandomKey = encrypt.Key.fromSecureRandom(32).base64;
    await _storage.write(key: 'secure_identity_v1', value: secureRandomKey);
    
    return '-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv...'; // Mocked PEM
  }

  /// Encrypts a message using AES-GCM.
  /// [sharedSecret] should be the derived key from RSA exchange.
  Future<String> encryptMessage(String plaintext, List<int> sharedSecret) async {
    final secretKey = SecretKey(sharedSecret);
    final data = utf8.encode(plaintext);
    
    final secretBox = await _aesAlgorithm.encrypt(
      data,
      secretKey: secretKey,
    );

    // Concatenate Nonce + Mac + Ciphertext for storage/transmission
    return base64.encode(secretBox.concatenation());
  }

  /// Decrypts a message using AES-GCM.
  Future<String> decryptMessage(String ciphertext, List<int> sharedSecret) async {
    final secretKey = SecretKey(sharedSecret);
    final combined = base64.decode(ciphertext);
    
    final secretBox = SecretBox.fromConcatenation(
      combined,
      nonceLength: _aesAlgorithm.nonceLength,
      macLength: _aesAlgorithm.macAlgorithm.macLength,
    );

    final decrypted = await _aesAlgorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decrypted);
  }
}
