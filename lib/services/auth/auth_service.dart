import 'dart:convert';
import 'dart:typed_data';
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

    final keyPair = _crypto.generateKeyPair();
    await _keyManager.storeKeyPair(keyPair);


    final recoveryPhrase = _crypto.generateRecoveryPhrase();
    await _keyManager.storeRecoveryPhrase(recoveryPhrase);


    final chhayaId = ChhayaId(
      publicKey: keyPair.publicKeyHex,
      createdAt: DateTime.now(),
    );


    final profile = UserProfile(
      chhayaId: chhayaId,
      displayName: displayName ?? 'Chhaya User',
      recoveryPhrase: recoveryPhrase,
      createdAt: DateTime.now(),
    );


    await _database.saveUserProfile(profile);
    _currentUser = profile;


    await _populateMockData(keyPair.publicKeyHex);

    return profile;
  }


  Future<void> _populateMockData(String ownPublicKey) async {
    final contacts = [
      Contact(
        id: 'contact_priya',
        chhayaId: ChhayaId.fromPublicKey('5f7b3c2a8d1e4c9b3a7d2e5f9a1b4c8d6e2f7a3b5c9d1e4f8a6b2c7d3e5f9a12'),
        displayName: 'Priya Sharma',
        verificationLevel: 3,
        isOnline: true,
      ),
      Contact(
        id: 'contact_arjun',
        chhayaId: ChhayaId.fromPublicKey('2e8d1e4c9b3a7d2e5f9a1b4c8d6e2f7a3b5c9d1e4f8a6b2c7d3e5f9a1b4c8d62'),
        displayName: 'Arjun Mehta',
        verificationLevel: 2,
        isOnline: true,
      ),
      Contact(
        id: 'contact_neha',
        chhayaId: ChhayaId.fromPublicKey('b3c7d2e5f9a1b4c8d6e2f7a3b5c9d1e4f8a6b2c7d3e5f9a1b4c8d6e2f7a3b5c9'),
        displayName: 'Neha Gupta',
        verificationLevel: 1,
        isOnline: false,
      ),
      Contact(
        id: 'contact_rahul',
        chhayaId: ChhayaId.fromPublicKey('f8a6b2c7d3e5f9a1b4c8d6e2f7a3b5c9d1e4f8a6b2c7d3e5f9a1b4c8d6e2f7a3'),
        displayName: 'Rahul Kapoor',
        verificationLevel: 2,
        isOnline: false,
      ),
    ];

    for (final contact in contacts) {
      await _database.addContact(contact);
    }

    final now = DateTime.now();

    final convo1Id = 'convo_priya';
    final messages1 = [
      Message(
        id: 'm1_1',
        conversationId: convo1Id,
        senderId: contacts[0].id,
        content: 'Hey! How are you?',
        timestamp: now.subtract(const Duration(minutes: 10)),
        isRead: true,
        isDelivered: true,
      ),
      Message(
        id: 'm1_2',
        conversationId: convo1Id,
        senderId: 'me',
        content: 'I\'m great, thanks! Working on the Chhaya crypto module.',
        timestamp: now.subtract(const Duration(minutes: 9)),
        isRead: true,
        isDelivered: true,
      ),
      Message(
        id: 'm1_3',
        conversationId: convo1Id,
        senderId: contacts[0].id,
        content: 'Oh nice! How\'s the onion routing coming along?',
        timestamp: now.subtract(const Duration(minutes: 8)),
        isRead: true,
        isDelivered: true,
      ),
      Message(
        id: 'm1_4',
        conversationId: convo1Id,
        senderId: 'me',
        content: 'The 3-hop routing is working. Latency is around 200ms per message.',
        timestamp: now.subtract(const Duration(minutes: 7)),
        isRead: true,
        isDelivered: true,
      ),
      Message(
        id: 'm1_5',
        conversationId: convo1Id,
        senderId: contacts[0].id,
        content: 'Hey! Did you check the new build?',
        timestamp: now.subtract(const Duration(minutes: 2)),
        isRead: false,
        isDelivered: true,
      ),
    ];

    for (final msg in messages1) {
      await _database.addMessage(msg);
    }

    final convo1 = Conversation(
      id: convo1Id,
      participants: [contacts[0]],
      lastMessage: messages1.last,
      unreadCount: 1,
      createdAt: now.subtract(const Duration(minutes: 10)),
    );
    await _database.addConversation(convo1);

    final convo2Id = 'convo_arjun';
    final messages2 = [
      Message(
        id: 'm2_1',
        conversationId: convo2Id,
        senderId: contacts[1].id,
        content: 'The encryption module is ready.',
        timestamp: now.subtract(const Duration(hours: 1)),
        isRead: true,
        isDelivered: true,
      ),
    ];
    for (final msg in messages2) {
      await _database.addMessage(msg);
    }
    final convo2 = Conversation(
      id: convo2Id,
      participants: [contacts[1]],
      lastMessage: messages2.last,
      unreadCount: 0,
      createdAt: now.subtract(const Duration(hours: 1)),
    );
    await _database.addConversation(convo2);
  }


  Future<UserProfile?> restoreAccount(List<String> recoveryPhrase) async {
    if (recoveryPhrase.length != 12) {
      throw ArgumentError('Recovery phrase must be exactly 12 words');
    }



    final phraseString = recoveryPhrase.join(' ');
    final phraseBytes = phraseString.codeUnits;
    final deterministicSeed = _crypto.hashData(
      Uint8List.fromList(phraseBytes),
    );

    final keyPair = ChhayaKeyPair(
      publicKey: _crypto.hashData(deterministicSeed),
      privateKey: deterministicSeed,
    );

    await _keyManager.storeKeyPair(keyPair);
    await _keyManager.storeRecoveryPhrase(recoveryPhrase);

    final chhayaId = ChhayaId(
      publicKey: keyPair.publicKeyHex,
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
    if (_currentUser == null) {
      throw StateError('Cannot generate backup: No user logged in');
    }

    final phrase = await getRecoveryPhrase();
    if (phrase == null) {
      throw StateError('Cannot generate backup: Recovery phrase not found');
    }


    final seedBytes = phrase.join(' ').codeUnits;
    final derivedSecret = _crypto.hashData(Uint8List.fromList(seedBytes));


    final contacts = await _database.getAllContacts();
    final conversations = await _database.getAllConversations();

    final payloadJson = {
      'profile': _currentUser!.toJson(),
      'contactsCount': contacts.length,
      'conversationsCount': conversations.length,
      'exportedAt': DateTime.now().toIso8601String(),
    };


    final encrypted = _crypto.encryptMessage(
      jsonEncode(payloadJson),
      derivedSecret,
    );

    return encrypted.toBase64();
  }


  Future<bool> restoreFromBackup(String backupBase64, List<String> recoveryPhrase) async {
    try {
      final seedBytes = recoveryPhrase.join(' ').codeUnits;
      final derivedSecret = _crypto.hashData(Uint8List.fromList(seedBytes));

      final payload = EncryptedPayload.fromBase64(backupBase64);
      final decryptedJsonString = _crypto.decryptMessage(payload, derivedSecret);

      final data = jsonDecode(decryptedJsonString) as Map<String, dynamic>;
      final profileMap = data['profile'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(profileMap);


      final deterministicSeed = _crypto.hashData(Uint8List.fromList(seedBytes));
      final keyPair = ChhayaKeyPair(
        publicKey: _crypto.hashData(deterministicSeed),
        privateKey: deterministicSeed,
      );
      await _keyManager.storeKeyPair(keyPair);
      await _keyManager.storeRecoveryPhrase(recoveryPhrase);


      await _database.saveUserProfile(profile);
      _currentUser = profile;


      await _populateMockData(keyPair.publicKeyHex);

      return true;
    } catch (_) {
      return false;
    }
  }



  Future<String> generateDeviceLinkCode() async {
    if (_currentUser == null) {
      throw StateError('No user logged in to link devices');
    }

    final linkKeyPair = _crypto.generateKeyPair();
    return 'Chhaya-link:${_currentUser!.chhayaId.publicKey}:${linkKeyPair.publicKeyHex}';
  }
}
