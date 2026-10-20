import 'dart:convert';
import 'dart:typed_data';
import 'account_identity.dart';
import '../../core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';

class AuthService {
  final ChhayaCryptoEngine _crypto;
  final KeyManager _keyManager;
  final LocalDatabase _database;

  UserProfile? _currentUser;

  AuthService({
    ChhayaCryptoEngine? crypto,
    KeyManager? keyManager,
    LocalDatabase? database,
  })  : _crypto = crypto ?? ChhayaCryptoEngine(),
        _keyManager = keyManager ?? KeyManager(),
        _database = database ?? LocalDatabase();

  UserProfile? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<void> init() async {
    await _database.init(requireBiometric: false);
    _currentUser = await _database.getUserProfile();
  }


  Future<UserProfile> createAccount({String? displayName}) async {

    final recoveryPhrase = ChhayaCryptoEngine.generateRecoveryPhrase();
    final keyPair = await AccountIdentity.fromRecoveryPhrase(recoveryPhrase);
    await _keyManager.storeKeyPair(keyPair);
    await _keyManager.storeRecoveryPhrase(recoveryPhrase);
    final chhayaId = ChhayaId(
      publicKey: AccountIdentity.idFor(keyPair), createdAt: DateTime.now());

    final profile = UserProfile(
      chhayaId: chhayaId,
      displayName: displayName ?? 'Chhaya User',
      recoveryPhrase: recoveryPhrase,
      createdAt: DateTime.now(),
    );


    await _database.saveUserProfile(profile);
    _currentUser = profile;




    return profile;
  }


  Future<UserProfile?> restoreAccount(List<String> recoveryPhrase) async {
    if (recoveryPhrase.length != 12) {
      throw ArgumentError('Recovery phrase must be exactly 12 words');
    }



    final keyPair = await AccountIdentity.fromRecoveryPhrase(recoveryPhrase);

    await _keyManager.storeKeyPair(keyPair);
    await _keyManager.storeRecoveryPhrase(recoveryPhrase);

    final chhayaId = ChhayaId(
      publicKey: AccountIdentity.idFor(keyPair),
      createdAt: DateTime.now(),
    );

    final profile = UserProfile(
      chhayaId: chhayaId,
      displayName: 'Restored User',
      recoveryPhrase: recoveryPhrase,
      createdAt: DateTime.now(),
    );

    await _database.saveUserProfile(profile);
    _currentUser = profile;

    return profile;
  }


  Future<void> updateDisplayName(String name) async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(displayName: name);
    await _database.saveUserProfile(_currentUser!);
  }


  Future<void> logout() async {
    await _keyManager.clearAllKeys();
    await _database.clearAll();
    _currentUser = null;
  }


  Future<List<String>?> getRecoveryPhrase() async {
    return _keyManager.getRecoveryPhrase();
  }



  Future<String> generateBackup() async {
    final profile = _currentUser;
    final phrase = await getRecoveryPhrase();
    final pair = await _keyManager.getKeyPair();
    if (profile == null || phrase == null || pair == null) {
      throw StateError('No account to back up');
    }
    final contacts = await _database.getAllContacts();
    final conversations = await _database.getAllConversations();
    final messages = <Map<String, dynamic>>[];
    for (final conversation in conversations) {
      messages.addAll((await _database.getMessages(conversation.id))
          .map((message) => message.toJson()));
    }
    final salt = Csprng.instance.bytes(32);
    final key = ChhayaCryptoEngine.keyFromRecoveryPhrase(phrase.join(' '), salt: salt);
    try {
      final payload = jsonEncode({
        'profile': profile.toJson(),
        'publicKey': base64Encode(pair.publicKey),
        'privateKey': base64Encode(pair.privateKey),
        'contacts': contacts.map((c) => c.toJson()).toList(),
        'conversations': conversations.map((c) => c.toJson()).toList(),
        'messages': messages,
      });
      return jsonEncode({'version': 2, 'salt': base64Encode(salt),
        'ciphertext': await _crypto.encryptMessage(payload, key)});
    } finally {
      Csprng.wipe(key);
    }
  }

  Future<bool> restoreFromBackup(String backup, List<String> phrase) async {
    Uint8List? key;
    try {
      final envelope = jsonDecode(backup) as Map<String, dynamic>;
      if (envelope['version'] != 2) return false;
      final salt = base64Decode(envelope['salt'] as String);
      if (salt.length != 32) return false;
      key = ChhayaCryptoEngine.keyFromRecoveryPhrase(phrase.join(' '), salt: salt);
      final payload = jsonDecode(await _crypto.decryptMessage(
          envelope['ciphertext'] as String, key)) as Map<String, dynamic>;
      final profile = UserProfile.fromJson(payload['profile'] as Map<String, dynamic>);
      if (profile.recoveryPhrase.join(' ') != phrase.join(' ')) return false;
      final pair = ChhayaKeyPair(publicKey: base64Decode(payload['publicKey'] as String),
          privateKey: base64Decode(payload['privateKey'] as String));
      // Parse all content before modifying the current account.
      final contacts = (payload['contacts'] as List)
          .map((c) => Contact.fromJson(Map<String, dynamic>.from(c as Map))).toList();
      final conversations = (payload['conversations'] as List)
          .map((c) => Conversation.fromJson(Map<String, dynamic>.from(c as Map))).toList();
      final messages = (payload['messages'] as List)
          .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map))).toList();
      if (pair.privateKey.length != 32 || pair.publicKey.length != 32) return false;
      if (profile.chhayaId.publicKey != pair.publicKeyHex &&
          profile.chhayaId.publicKey != AccountIdentity.idFor(pair)) return false;
      await _keyManager.storeKeyPair(pair);
      await _keyManager.storeRecoveryPhrase(phrase);
      await _database.saveUserProfile(profile);
      for (final contact in contacts) { await _database.addContact(contact); }
      for (final conversation in conversations) { await _database.addConversation(conversation); }
      for (final message in messages) { await _database.addMessage(message); }
      _currentUser = profile;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (key != null) Csprng.wipe(key);
    }
  }

  Future<String> generateDeviceLinkCode() async {
    if (_currentUser == null) {
      throw StateError('No user logged in to link devices');
    }

    final linkKeyPair = await ChhayaCryptoEngine.generateKeyPair();
    return 'Chhaya-link:${_currentUser!.chhayaId.publicKey}:${linkKeyPair.publicKeyHex}';
  }
}
