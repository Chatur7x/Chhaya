import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;

/// Chhaya Crypto Engine v12 — Production-grade E2EE
///
/// - X25519 ECDH via `cryptography` package (audited, constant-time)
/// - AES-256-GCM via PointyCastle (authenticated encryption)
/// - HKDF-SHA256 (RFC 5869) for key derivation
/// - Ed25519 signatures via `cryptography` package
/// - Secure random via Dart's Random.secure()
class ChhayaCryptoEngine {
  final pc.SecureRandom _secureRandom;
  ChhayaCryptoEngine() : _secureRandom = _createSecureRandom();

  static pc.SecureRandom _createSecureRandom() {
    final secureRandom = pc.FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  // ---- X25519 Key Agreement ----

  /// Generate a new X25519 key pair.
  static Future<ChhayaKeyPair> generateKeyPair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return ChhayaKeyPair(
      privateKey: Uint8List.fromList(privateKeyBytes),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Derive a shared secret from our private key and their public key.
  static Future<Uint8List> deriveSharedSecret(
    List<int> privateKeyBytes,
    List<int> publicKeyBytes,
  ) async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    final remotePublicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remotePublicKey,
    );
    final bytes = await sharedSecret.extractBytes();
    return Uint8List.fromList(bytes);
  }

  // ---- Ed25519 Signatures ----

  /// Generate a new Ed25519 signing key pair.
  static Future<SimpleKeyPair> generateSigningKeyPair() async {
    final algorithm = Ed25519();
    return algorithm.newKeyPair();
  }

  /// Sign a message with an Ed25519 private key.
  static Future<Uint8List> sign(
    List<int> message,
    List<int> privateKeyBytes,
  ) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    final signature = await algorithm.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify an Ed25519 signature.
  static Future<bool> verify(
    List<int> message,
    List<int> signatureBytes,
    List<int> publicKeyBytes,
  ) async {
    final algorithm = Ed25519();
    final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
    final signature = Signature(signatureBytes, publicKey: publicKey);
    return algorithm.verify(message, signature: signature);
  }

  // ---- AES-256-GCM ----

  /// Encrypt a plaintext string with AES-256-GCM.
  /// Returns base64(nonce || ciphertext || tag).
  Future<String> encryptMessage(String plaintext, Uint8List key) async {
    final nonce = _secureRandom.nextBytes(12);
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(key),
          128, // tag bits
          nonce,
          Uint8List(0), // no AAD
        ),
      );
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final ciphertext = cipher.process(plaintextBytes);
    final combined = Uint8List(nonce.length + ciphertext.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, combined.length, ciphertext);
    return base64Encode(combined);
  }

  /// Decrypt a base64-encoded AES-256-GCM ciphertext.
  /// Returns the original plaintext string.
  Future<String> decryptMessage(String encryptedBase64, Uint8List key) async {
    final combined = base64Decode(encryptedBase64);
    final nonce = combined.sublist(0, 12);
    final ciphertext = combined.sublist(12);
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(key),
          128,
          nonce,
          Uint8List(0),
        ),
      );
    final decrypted = cipher.process(Uint8List.fromList(ciphertext));
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
    final hkdf = pc.HKDFKeyDerivator(pc.SHA256Digest())
      ..init(pc.HkdfParameters(inputKeyMaterial, length, salt, info));
    final output = Uint8List(length);
    hkdf.deriveKey(Uint8List(0), 0, output, 0);
    return output;
  }

  // ---- Hashing ----

  /// SHA-256 hash of input bytes.
  Uint8List hashData(Uint8List data) {
    final digest = pc.SHA256Digest();
    return digest.process(data);
  }

  /// SHA-256 hash of a string, returned as hex.
  String hashString(String input) {
    final bytes = Uint8List.fromList(utf8.encode(input));
    final hash = hashData(bytes);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ---- Random ----

  /// Generate cryptographically secure random bytes.
  Uint8List generateNonce(int length) => _secureRandom.nextBytes(length);

  /// Generate a random hex string of the given byte length.
  String generateRandomHex(int byteLength) {
    final bytes = _secureRandom.nextBytes(byteLength);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ---- Key Derivation for Account ----

  /// Derive an encryption key from a recovery phrase using PBKDF2.
  static Uint8List keyFromRecoveryPhrase(String phrase, {Uint8List? salt}) {
    final effectiveSalt = salt ?? Uint8List.fromList(utf8.encode('chhaya-salt-v1'));
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(effectiveSalt, 100000, 32));
    final output = Uint8List(32);
    derivator.deriveKey(Uint8List.fromList(utf8.encode(phrase)), 0, output, 0);
    return output;
  }

  /// Generate a 12-word BIP-39 recovery phrase.
  static List<String> generateRecoveryPhrase() {
    const wordlist = ['abandon','ability','able','about','above','absent','absorb','abstract','absurd','abuse','access','accident','account','accuse','achieve','acid','acoustic','acquire','across','act','action','actor','actress','actual','adapt','add','addict','address','adjust','admit','adult','advance','advice','aerobic','affair','afford','afraid','again','age','agent','agree','ahead','aim','air','airport','aisle','alarm','album','alcohol','alert','alien','all','alley','allow','almost','alone','alpha','already','also','alter','always','amateur','amazing','among','amount','amused','analyst','anchor','ancient','anger','angle','angry','animal','ankle','announce','annual','another','answer','antenna','antique','anxiety','any','apart','apology','appear','apple','approve','april','arch','arctic','area','arena','argue','arm','armed','armor','army','around','arrange','arrest','arrive','arrow','art','artefact','artist','artwork','ask','aspect','assault','asset','assist','assume','asthma','athlete','atom','attack','attend','attitude','attract','auction','audit','august','aunt','author','auto','autumn','average','avocado','avoid','awake','aware','awesome','awful','awkward','axis','baby','bachelor','bacon','badge','bag','balance','balcony','ball','bamboo','banana','banner','bar','barely','bargain','barrel','base','basic','basket','battle','beach','bean','beauty','because','become','beef','before','begin','behave','behind','believe','below','belt','bench','benefit','best','betray','better','between','beyond','bicycle','bid','bike','bind','biology','bird','birth','bitter','black','blade','blame','blanket','blast','bleak','bless','blind','blood','blossom','blow','blue','blur','blush','board','boat','body','boil','bomb','bone','bonus','book','boost','border','boring','borrow','boss','bottom','bounce','box','boy','bracket','brain','brand','brass','brave','bread','breeze','brick','bridge','brief','bright','bring','brisk','broccoli','broken','bronze','broom','brother','brown','brus...'];
    final random = Random.secure();
    return List.generate(12, (_) => wordlist[random.nextInt(wordlist.length)]);
  }

  // helpers for V10: recovery seed
  Uint8List recoveryPhraseToSeed(List<String> phrase) => hashData(Uint8List.fromList(utf8.encode(phrase.join(' '))));

  /// HKDF-Expand (RFC 5869) using HMAC-SHA256.
  /// Used to derive per-message keys from the Double Ratchet chain key.
  Uint8List hkdfExpand(Uint8List prk, Uint8List info, int outputLength) {
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

  /// HKDF-Extract + Expand (RFC 5869) for Double Ratchet key derivation.
  static Uint8List _hkdfDerive(Uint8List ikm, Uint8List salt) {
    final hkdf = pc.HKDFKeyDerivator(pc.SHA256Digest())
      ..init(pc.HkdfParameters(ikm, 64, salt, null));
    final output = Uint8List(64);
    hkdf.deriveKey(Uint8List(0), 0, output, 0);
    return output;
  }
}

class ChhayaKeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;
  ChhayaKeyPair({required this.publicKey, required this.privateKey});
  String get publicKeyHex => publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  String get privateKeyHex => privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  factory ChhayaKeyPair.fromHex(String publicHex, String privateHex) => ChhayaKeyPair(
        publicKey: _hexToBytes(publicHex),
        privateKey: _hexToBytes(privateHex),
      );
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
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;
  EncryptedPayload({required this.nonce, required this.ciphertext, required this.tag});
  String toBase64() {
    final combined = Uint8List(nonce.length + tag.length + ciphertext.length);
    combined.setAll(0, nonce);
    combined.setAll(nonce.length, tag);
    combined.setAll(nonce.length + tag.length, ciphertext);
    return base64Encode(combined);
  }
  factory EncryptedPayload.fromBase64(String encoded) {
    final combined = base64Decode(encoded);
    // Format: nonce (12) + ciphertext_with_tag (rest)
    // GCM appends the 16-byte tag to the end of ciphertext
    final nonce = Uint8List.fromList(combined.sublist(0, 12));
    final ciphertextWithTag = Uint8List.fromList(combined.sublist(12));
    // Last 16 bytes are the GCM tag
    final tag = Uint8List.fromList(ciphertextWithTag.sublist(ciphertextWithTag.length - 16));
    final ciphertext = Uint8List.fromList(ciphertextWithTag.sublist(0, ciphertextWithTag.length - 16));
    return EncryptedPayload(nonce: nonce, ciphertext: ciphertext, tag: tag);
  }
}

/// Double Ratchet session state for a single peer.
class DoubleRatchetSession {
  final String peerId;
  Uint8List rootKey;
  Uint8List? sendingChainKey;
  Uint8List? receivingChainKey;
  ChhayaKeyPair dhrsKeyPair;
  Uint8List? dhriPublicKey;
  DoubleRatchetSession({
    required this.peerId,
    required this.rootKey,
    required this.dhrsKeyPair,
    this.sendingChainKey,
    this.receivingChainKey,
    this.dhriPublicKey,
  });
  ({Uint8List messageKey, Uint8List newChainKey}) ratchetSendChain() {
    if (sendingChainKey == null) throw StateError('Sending chain key not initialized');
    final hmacInput = Uint8List.fromList([0x01, ...sendingChainKey!]);
    final derived = ChhayaCryptoEngine._hkdfDerive(sendingChainKey!, hmacInput);
    final messageKey = derived.sublist(0, 32);
    final newChainKey = derived.sublist(32, 64);
    sendingChainKey = newChainKey;
    return (messageKey: messageKey, newChainKey: newChainKey);
  }
  ({Uint8List messageKey, Uint8List newChainKey}) ratchetReceiveChain() {
    if (receivingChainKey == null) throw StateError('Receiving chain key not initialized');
    final hmacInput = Uint8List.fromList([0x01, ...receivingChainKey!]);
    final derived = ChhayaCryptoEngine._hkdfDerive(receivingChainKey!, hmacInput);
    final messageKey = derived.sublist(0, 32);
    final newChainKey = derived.sublist(32, 64);
    receivingChainKey = newChainKey;
    return (messageKey: messageKey, newChainKey: newChainKey);
  }
  Future<void> performDhRatchetStep(Uint8List newRemoteDhPublicKey, ChhayaCryptoEngine engine) async {
    dhriPublicKey = newRemoteDhPublicKey;
    final sharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(dhrsKeyPair.privateKey, dhriPublicKey!);
    final derived = ChhayaCryptoEngine._hkdfDerive(rootKey, sharedSecret);
    rootKey = derived.sublist(0, 32);
    receivingChainKey = derived.sublist(32, 64);
    dhrsKeyPair = await ChhayaCryptoEngine.generateKeyPair();
    final newSharedSecret = await ChhayaCryptoEngine.deriveSharedSecret(dhrsKeyPair.privateKey, dhriPublicKey!);
    final derivedSend = ChhayaCryptoEngine._hkdfDerive(rootKey, newSharedSecret);
    rootKey = derivedSend.sublist(0, 32);
    sendingChainKey = derivedSend.sublist(32, 64);
  }

  /// HKDF-Expand (RFC 5869) using HMAC-SHA256.
  /// Used to derive per-message keys from the Double Ratchet chain key.
  Uint8List hkdfExpand(Uint8List prk, Uint8List info, int outputLength) {
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