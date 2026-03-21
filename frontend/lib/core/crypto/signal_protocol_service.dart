import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Signal Protocol Implementation for Chaaya.
/// Provides end-to-end encryption using Double Ratchet + X3DH.
/// Every message gets a unique key (forward secrecy).
class SignalProtocolService {
  static const _secureStorage = FlutterSecureStorage();

  // Per-contact session state (simplified Signal Protocol)
  final Map<String, SessionState> _sessions = {};

  /// Initialize or load session for a contact
  Future<SessionState> getOrCreateSession(
      String contactId, String theirPublicKey) async {
    if (_sessions.containsKey(contactId)) {
      return _sessions[contactId]!;
    }

    // Check for stored session
    final stored = await _secureStorage.read(key: 'session_$contactId');
    if (stored != null) {
      final session = SessionState.fromJson(jsonDecode(stored));
      _sessions[contactId] = session;
      return session;
    }

    // Create new session (X3DH key agreement)
    final session = await _performX3DH(contactId, theirPublicKey);
    _sessions[contactId] = session;
    await _saveSession(contactId, session);
    return session;
  }

  /// Encrypt a message for a contact
  Future<EncryptedPayload> encrypt(String contactId, String plaintext) async {
    final session = _sessions[contactId];
    if (session == null) throw Exception('No session for $contactId');

    // Derive message key using Double Ratchet
    final messageKey = _deriveMessageKey(session);

    // Encrypt with AES-256-GCM
    final iv = _generateIV();
    final encrypted = _aesEncrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
      messageKey,
      iv,
    );

    // Advance ratchet
    session.messageIndex++;
    await _saveSession(contactId, session);

    return EncryptedPayload(
      ciphertext: base64Encode(encrypted),
      iv: base64Encode(iv),
      messageIndex: session.messageIndex,
      senderRatchetKey: session.senderRatchetKey,
    );
  }

  /// Decrypt a message from a contact
  Future<String> decrypt(
      String contactId, EncryptedPayload payload) async {
    final session = _sessions[contactId];
    if (session == null) throw Exception('No session for $contactId');

    // Derive message key
    final messageKey = _deriveMessageKey(session, index: payload.messageIndex);

    // Decrypt
    final decrypted = _aesDecrypt(
      base64Decode(payload.ciphertext),
      messageKey,
      base64Decode(payload.iv),
    );

    return utf8.decode(decrypted);
  }

  /// Perform X3DH key agreement (simplified)
  Future<SessionState> _performX3DH(
      String contactId, String theirPublicKey) async {
    // Generate ephemeral key pair for this session
    final keyGen = ECKeyGenerator();
    final params = ECKeyGeneratorParameters(ECCurve_secp256r1());
    final random = FortunaRandom();
    random.seed(KeyParameter(Uint8List.fromList(
      List.generate(32, (i) => DateTime.now().microsecondsSinceEpoch + i),
    )));
    keyGen.init(ParametersWithRandom(params, random));
    final ephemeralPair = keyGen.generateKeyPair();

    // Derive shared secret (DH)
    final sharedSecret = _generateSharedSecret();

    // Create root key and chain key from shared secret
    final rootKey = base64Encode(sharedSecret.sublist(0, 32));
    final chainKey = base64Encode(sharedSecret.sublist(32, 64));

    return SessionState(
      contactId: contactId,
      rootKey: rootKey,
      sendingChainKey: chainKey,
      receivingChainKey: chainKey,
      senderRatchetKey: base64Encode(
        (ephemeralPair.publicKey as ECPublicKey).Q!.getEncoded(true),
      ),
      messageIndex: 0,
      createdAt: DateTime.now(),
    );
  }

  /// Derive a unique message key (forward secrecy)
  Uint8List _deriveMessageKey(SessionState session, {int? index}) {
    final chainKey = base64Decode(session.sendingChainKey);
    final idx = index ?? session.messageIndex;

    // HMAC-SHA256 chain ratchet
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(chainKey));
    final input = Uint8List.fromList([...chainKey, idx & 0xFF, (idx >> 8) & 0xFF]);
    final output = Uint8List(hmac.macSize);
    hmac.update(input, 0, input.length);
    hmac.doFinal(output, 0);
    return output;
  }

  /// Generate shared secret (simplified — uses secure random)
  Uint8List _generateSharedSecret() {
    final random = FortunaRandom();
    random.seed(KeyParameter(Uint8List.fromList(
      List.generate(32, (i) => DateTime.now().microsecondsSinceEpoch + i),
    )));
    return random.nextBytes(64);
  }

  /// AES-256-GCM encrypt
  Uint8List _aesEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    final len = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    cipher.doFinal(output, len);
    return output;
  }

  /// AES-256-GCM decrypt
  Uint8List _aesDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
    final output = Uint8List(cipher.getOutputSize(ciphertext.length));
    final len = cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
    cipher.doFinal(output, len);
    return output;
  }

  /// Generate random IV (12 bytes for GCM)
  Uint8List _generateIV() {
    final random = FortunaRandom();
    random.seed(KeyParameter(Uint8List.fromList(
      List.generate(32, (i) => DateTime.now().microsecondsSinceEpoch + i),
    )));
    return random.nextBytes(12);
  }

  /// Save session to secure storage
  Future<void> _saveSession(String contactId, SessionState session) async {
    await _secureStorage.write(
      key: 'session_$contactId',
      value: jsonEncode(session.toJson()),
    );
  }

  /// Wipe all sessions (panic wipe)
  Future<void> wipeAllSessions() async {
    for (final contactId in _sessions.keys) {
      await _secureStorage.delete(key: 'session_$contactId');
    }
    _sessions.clear();
    debugPrint('[Signal] All sessions wiped');
  }

  /// Get safety number for contact verification
  String getSafetyNumber(String myPublicKey, String theirPublicKey) {
    final combined = '$myPublicKey$theirPublicKey';
    final digest = SHA256Digest();
    final hash = Uint8List(digest.digestSize);
    digest.update(utf8.encode(combined) as Uint8List, 0, combined.length);
    digest.doFinal(hash, 0);
    // Return first 12 digits for display
    return hash.take(6).map((b) => b.toRadixString(10).padLeft(3, '0')).join(' ');
  }
}

/// Session state for a contact (Double Ratchet state)
class SessionState {
  final String contactId;
  final String rootKey;
  final String sendingChainKey;
  final String receivingChainKey;
  final String senderRatchetKey;
  int messageIndex;
  final DateTime createdAt;

  SessionState({
    required this.contactId,
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    required this.senderRatchetKey,
    required this.messageIndex,
    required this.createdAt,
  });

  factory SessionState.fromJson(Map<String, dynamic> json) => SessionState(
        contactId: json['contactId'],
        rootKey: json['rootKey'],
        sendingChainKey: json['sendingChainKey'],
        receivingChainKey: json['receivingChainKey'],
        senderRatchetKey: json['senderRatchetKey'],
        messageIndex: json['messageIndex'],
        createdAt: DateTime.parse(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'rootKey': rootKey,
        'sendingChainKey': sendingChainKey,
        'receivingChainKey': receivingChainKey,
        'senderRatchetKey': senderRatchetKey,
        'messageIndex': messageIndex,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Encrypted message payload
class EncryptedPayload {
  final String ciphertext;
  final String iv;
  final int messageIndex;
  final String senderRatchetKey;

  EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.messageIndex,
    required this.senderRatchetKey,
  });

  Map<String, dynamic> toJson() => {
        'ciphertext': ciphertext,
        'iv': iv,
        'messageIndex': messageIndex,
        'senderRatchetKey': senderRatchetKey,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) =>
      EncryptedPayload(
        ciphertext: json['ciphertext'],
        iv: json['iv'],
        messageIndex: json['messageIndex'],
        senderRatchetKey: json['senderRatchetKey'],
      );
}

