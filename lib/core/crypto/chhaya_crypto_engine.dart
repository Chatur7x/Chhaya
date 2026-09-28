// Chhaya Crypto Engine v14 — facade over audited primitives.
//
// Purpose: stable public crypto API for the app. All algorithms live in
// `primitives/`; this file only delegates, wraps bytes in [ChhayaKeyPair] /
// [EncryptedPayload], and owns session types until Part 4 extracts the
// ratchet. Public method signatures are unchanged from V13.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'primitives/aes_gcm.dart' as aes_gcm;
import 'primitives/bip39.dart';
import 'primitives/ed25519.dart';
import 'primitives/hkdf.dart' as hkdf;
import 'primitives/pbkdf2.dart' as pbkdf2;
import 'primitives/rng.dart';
import 'primitives/sha.dart';
import 'primitives/x25519.dart';

/// Application-facing cryptographic operations (E2EE).
///
/// - Key agreement: X25519 (RFC 7748), constant-time
/// - Signatures: Ed25519 (RFC 8032)
/// - Encryption: AES-256-GCM (AEAD)
/// - Key derivation: HKDF-SHA256 (RFC 5869), PBKDF2-HMAC-SHA256
/// - Recovery phrases: BIP-39 (128-bit entropy, 12 words)
class ChhayaCryptoEngine {
  /// Creates an engine backed by [rng] (defaults to the shared instance).
  ChhayaCryptoEngine({Csprng? rng}) : _rng = rng ?? Csprng.instance;

  final Csprng _rng;

  // ---- X25519 Key Agreement ----

  /// Generate a new X25519 key pair.
  static Future<ChhayaKeyPair> generateKeyPair() async {
    final keyPair = await X25519Kex.generateKeyPair();
    return ChhayaKeyPair(
      publicKey: keyPair.publicKey,
      privateKey: keyPair.privateKey,
    );
  }

  /// Derive a shared secret from our private key and their public key.
  static Future<Uint8List> deriveSharedSecret(
    List<int> privateKeyBytes,
    List<int> publicKeyBytes,
  ) {
    return X25519Kex.sharedSecret(privateKeyBytes, publicKeyBytes);
  }

  // ---- Ed25519 Signatures ----

  /// Generate a new Ed25519 signing key pair.
  static Future<SimpleKeyPair> generateSigningKeyPair() {
    return Ed25519Sign.generateKeyPair();
  }

  /// Sign a message with an Ed25519 private key.
  static Future<Uint8List> sign(
    List<int> message,
    List<int> privateKeyBytes,
  ) {
    return Ed25519Sign.sign(message, privateKeyBytes);
  }

  /// Verify an Ed25519 signature.
  static Future<bool> verify(
    List<int> message,
    List<int> signatureBytes,
    List<int> publicKeyBytes,
  ) {
    return Ed25519Sign.verify(message, signatureBytes, publicKeyBytes);
  }

  // ---- AES-256-GCM ----

  /// Encrypt a plaintext string with AES-256-GCM.
  /// Returns base64(nonce || ciphertext || tag).
  Future<String> encryptMessage(String plaintext, Uint8List key) async {
    final combined = aes_gcm.AesGcm.encryptBytes(
      key,
      Uint8List.fromList(utf8.encode(plaintext)),
      nonce: _rng.bytes(aes_gcm.AesGcm.nonceLength),
    );
    return base64Encode(combined);
  }

  /// Decrypt a base64-encoded AES-256-GCM ciphertext.
  /// Returns the original plaintext string. Throws on tampering.
  Future<String> decryptMessage(String encryptedBase64, Uint8List key) async {
    final combined = base64Decode(encryptedBase64);
    final decrypted = aes_gcm.AesGcm.decryptBytes(key, combined);
    return utf8.decode(decrypted);
  }

  // ---- HKDF-SHA256 (RFC 5869) ----

  /// Derive a key using HKDF-SHA256.
  static Uint8List deriveKey({
    required Uint8List inputKeyMaterial,
    required int length,
    Uint8List? salt,
    Uint8List? info,
  }) {
    return hkdf.Hkdf.deriveKey(
      inputKeyMaterial: inputKeyMaterial,
      length: length,
      salt: salt,
      info: info,
    );
  }

  // ---- Hashing ----

  /// SHA-256 hash of input bytes.
  Uint8List hashData(Uint8List data) => Sha.hash256(data);

  /// SHA-256 hash of a string, returned as hex.
  String hashString(String input) => Sha.hashStringHex(input);

  // ---- Random ----

  /// Generate cryptographically secure random bytes.
  Uint8List generateNonce(int length) => _rng.bytes(length);

  /// Generate a random hex string of the given byte length.
  String generateRandomHex(int byteLength) => _rng.hex(byteLength);

  // ---- Key Derivation for Account ----

  /// Derive an encryption key from a recovery phrase using PBKDF2.
  static Uint8List keyFromRecoveryPhrase(String phrase, {Uint8List? salt}) {
    final effectiveSalt =
        salt ?? Uint8List.fromList(utf8.encode('chhaya-salt-v1'));
    return pbkdf2.Pbkdf2.deriveKey(
      password: Uint8List.fromList(utf8.encode(phrase)),
      salt: effectiveSalt,
    );
  }

  /// Generate a 12-word BIP-39 recovery phrase (128-bit entropy).
  static List<String> generateRecoveryPhrase() {
    return Bip39.generateMnemonic();
  }

  /// Derive a deterministic seed from a recovery phrase.
  Uint8List recoveryPhraseToSeed(List<String> phrase) =>
      hashData(Uint8List.fromList(utf8.encode(phrase.join(' '))));

  /// HKDF-Expand (RFC 5869) using HMAC-SHA256.
  /// Used to derive per-message keys from the Double Ratchet chain key.
  Uint8List hkdfExpand(Uint8List prk, Uint8List info, int outputLength) {
    return hkdf.Hkdf.expand(prk, info, outputLength);
  }

  /// HKDF-Extract + Expand (RFC 5869) for Double Ratchet key derivation.
  static Uint8List _hkdfDerive(Uint8List ikm, Uint8List salt) {
    return hkdf.Hkdf.derive64(ikm, salt);
  }
}

/// An X25519 key pair.
///
/// Call [dispose] to zeroize key material when the pair is no longer
/// needed. After disposal the hex getters return zeros.
class ChhayaKeyPair {
  /// Creates a key pair from raw public and private key bytes.
  ChhayaKeyPair({required this.publicKey, required this.privateKey});

  /// 32-byte X25519 public key.
  final Uint8List publicKey;

  /// 32-byte X25519 private key. Wiped by [dispose].
  final Uint8List privateKey;

  /// Public key as lowercase hex.
  String get publicKeyHex => Sha.hexOf(publicKey);

  /// Private key as lowercase hex. Zeros after [dispose].
  String get privateKeyHex => Sha.hexOf(privateKey);

  /// Rebuild a pair from hex strings.
  factory ChhayaKeyPair.fromHex(String publicHex, String privateHex) =>
      ChhayaKeyPair(
        publicKey: _hexToBytes(publicHex),
        privateKey: _hexToBytes(privateHex),
      );

  /// Overwrites the private key bytes with zeros in place.
  void dispose() {
    Csprng.wipe(privateKey);
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// Encrypted payload with nonce, ciphertext, and authentication tag.
class EncryptedPayload {
  /// Creates a payload from its three parts.
  EncryptedPayload(
      {required this.nonce, required this.ciphertext, required this.tag});

  /// 12-byte nonce.
  final Uint8List nonce;

  /// Ciphertext bytes (without tag).
  final Uint8List ciphertext;

  /// 16-byte authentication tag.
  final Uint8List tag;

  /// Serializes as base64(nonce || tag || ciphertext).
  String toBase64() {
    final combined = Uint8List(nonce.length + tag.length + ciphertext.length);
    combined.setAll(0, nonce);
    combined.setAll(nonce.length, tag);
    combined.setAll(nonce.length + tag.length, ciphertext);
    return base64Encode(combined);
  }

  /// Parses a payload previously produced by [AesGcm] wire format
  /// (nonce || ciphertext || tag, with the tag appended by GCM).
  factory EncryptedPayload.fromBase64(String encoded) {
    final combined = base64Decode(encoded);
    // Format: nonce (12) + ciphertext_with_tag (rest)
    // GCM appends the 16-byte tag to the end of ciphertext
    final nonce = Uint8List.fromList(combined.sublist(0, 12));
    final ciphertextWithTag = Uint8List.fromList(combined.sublist(12));
    // Last 16 bytes are the GCM tag
    final tag = Uint8List.fromList(ciphertextWithTag
        .sublist(ciphertextWithTag.length - aes_gcm.AesGcm.tagLength));
    final ciphertext = Uint8List.fromList(ciphertextWithTag.sublist(
        0, ciphertextWithTag.length - aes_gcm.AesGcm.tagLength));
    return EncryptedPayload(nonce: nonce, ciphertext: ciphertext, tag: tag);
  }
}

/// Double Ratchet session state for a single peer.
///
/// NOTE (Part 4): this type moves to `lib/core/crypto/ratchet/` with the
/// Triple Ratchet upgrade. Kept here in Part 1 so existing callers and
/// tests keep compiling.
class DoubleRatchetSession {
  /// Creates a session for [peerId] with a shared [rootKey].
  DoubleRatchetSession({
    required this.peerId,
    required this.rootKey,
    required this.dhrsKeyPair,
    this.sendingChainKey,
    this.receivingChainKey,
    this.dhriPublicKey,
  });

  /// Remote peer identifier.
  final String peerId;

  /// Current root key (32 bytes).
  Uint8List rootKey;

  /// Active sending chain key, if established.
  Uint8List? sendingChainKey;

  /// Active receiving chain key, if established.
  Uint8List? receivingChainKey;

  /// Our current DH ratchet key pair.
  ChhayaKeyPair dhrsKeyPair;

  /// Their current DH ratchet public key, if known.
  Uint8List? dhriPublicKey;

  /// Advances the sending chain and returns the message key.
  ({Uint8List messageKey, Uint8List newChainKey}) ratchetSendChain() {
    if (sendingChainKey == null) {
      throw StateError('Sending chain key not initialized');
    }
    final hmacInput = Uint8List.fromList([0x01, ...sendingChainKey!]);
    final derived = ChhayaCryptoEngine._hkdfDerive(sendingChainKey!, hmacInput);
    final messageKey = derived.sublist(0, 32);
    final newChainKey = derived.sublist(32, 64);
    sendingChainKey = newChainKey;
    return (messageKey: messageKey, newChainKey: newChainKey);
  }

  /// Advances the receiving chain and returns the message key.
  ({Uint8List messageKey, Uint8List newChainKey}) ratchetReceiveChain() {
    if (receivingChainKey == null) {
      throw StateError('Receiving chain key not initialized');
    }
    final hmacInput = Uint8List.fromList([0x01, ...receivingChainKey!]);
    final derived =
        ChhayaCryptoEngine._hkdfDerive(receivingChainKey!, hmacInput);
    final messageKey = derived.sublist(0, 32);
    final newChainKey = derived.sublist(32, 64);
    receivingChainKey = newChainKey;
    return (messageKey: messageKey, newChainKey: newChainKey);
  }

  /// Performs a DH ratchet step against a new remote public key.
  Future<void> performDhRatchetStep(
      Uint8List newRemoteDhPublicKey, ChhayaCryptoEngine engine) async {
    dhriPublicKey = newRemoteDhPublicKey;
    final sharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(
        dhrsKeyPair.privateKey, dhriPublicKey!);
    final derived = ChhayaCryptoEngine._hkdfDerive(rootKey, sharedSecret);
    rootKey = derived.sublist(0, 32);
    receivingChainKey = derived.sublist(32, 64);
    dhrsKeyPair = await ChhayaCryptoEngine.generateKeyPair();
    final newSharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(
        dhrsKeyPair.privateKey, dhriPublicKey!);
    final derivedSend = ChhayaCryptoEngine._hkdfDerive(rootKey, newSharedSecret);
    rootKey = derivedSend.sublist(0, 32);
    sendingChainKey = derivedSend.sublist(32, 64);
    Csprng.wipe(sharedSecret);
    Csprng.wipe(newSharedSecret);
  }

  /// HKDF-Expand (RFC 5869) using HMAC-SHA256.
  /// Used to derive per-message keys from the Double Ratchet chain key.
  Uint8List hkdfExpand(Uint8List prk, Uint8List info, int outputLength) {
    return hkdf.Hkdf.expand(prk, info, outputLength);
  }
}
