import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'account_identity.dart';
import '../api/api_service.dart';
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
  }) : _crypto = crypto ?? ChhayaCryptoEngine(),
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
      publicKey: AccountIdentity.idFor(keyPair),
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
    name = name.trim();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('Display name must contain 1 to 80 characters');
    }
    if (_currentUser == null) {
      return;
    }
    final updated = _currentUser!.copyWith(displayName: name);
    await _database.saveUserProfile(updated);
    _currentUser = updated;
  }

  Future<void> logout() async {
    await ApiService().logout();
    await _database.destroy();
    await _keyManager.clearAllAccountSecrets();
    _currentUser = null;
    await _database.init(requireBiometric: false);
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
      messages.addAll(
        (await _database.getMessages(
          conversation.id,
        )).map((message) => message.toJson()),
      );
    }
    final salt = Csprng.instance.bytes(32);
    final key = ChhayaCryptoEngine.keyFromRecoveryPhrase(
      phrase.join(' '),
      salt: salt,
    );
    try {
      final payload = jsonEncode({
        'profile': profile.toJson(),
        'publicKey': base64Encode(pair.publicKey),
        'privateKey': base64Encode(pair.privateKey),
        'contacts': contacts.map((c) => c.toJson()).toList(),
        'conversations': conversations.map((c) => c.toJson()).toList(),
        'messages': messages,
      });
      return jsonEncode({
        'version': 2,
        'salt': base64Encode(salt),
        'ciphertext': await _crypto.encryptMessage(payload, key),
      });
    } finally {
      Csprng.wipe(key);
    }
  }

  Future<bool> restoreFromBackup(String backup, List<String> phrase) async {
    Uint8List? key;
    ChhayaKeyPair? importedPair;
    ChhayaKeyPair? previousPair;
    try {
      final envelope = jsonDecode(backup) as Map<String, dynamic>;
      if (envelope['version'] != 2 || phrase.length != 12) return false;
      final salt = base64Decode(envelope['salt'] as String);
      if (salt.length != 32) {
        return false;
      }
      key = ChhayaCryptoEngine.keyFromRecoveryPhrase(
        phrase.join(' '),
        salt: salt,
      );
      final payload =
          jsonDecode(
                await _crypto.decryptMessage(
                  envelope['ciphertext'] as String,
                  key,
                ),
              )
              as Map<String, dynamic>;
      final profile = UserProfile.fromJson(
        payload['profile'] as Map<String, dynamic>,
      );
      if (profile.recoveryPhrase.join(' ') != phrase.join(' ')) {
        return false;
      }
      importedPair = ChhayaKeyPair(
        publicKey: base64Decode(payload['publicKey'] as String),
        privateKey: base64Decode(payload['privateKey'] as String),
      );
      // Parse all content before modifying the current account.
      final contacts =
          (payload['contacts'] as List)
              .map((c) => Contact.fromJson(Map<String, dynamic>.from(c as Map)))
              .toList();
      final conversations =
          (payload['conversations'] as List)
              .map(
                (c) =>
                    Conversation.fromJson(Map<String, dynamic>.from(c as Map)),
              )
              .toList();
      final messages =
          (payload['messages'] as List)
              .map((m) => Message.fromJson(Map<String, dynamic>.from(m as Map)))
              .toList();
      if (importedPair.privateKey.length != 32 ||
          importedPair.publicKey.length != 32) {
        return false;
      }
      if (profile.chhayaId.publicKey != importedPair.publicKeyHex &&
          profile.chhayaId.publicKey != AccountIdentity.idFor(importedPair)) {
        return false;
      }

      final conversationIds = conversations.map((item) => item.id).toSet();
      if (conversationIds.length != conversations.length ||
          contacts.map((item) => item.id).toSet().length != contacts.length ||
          messages.map((item) => item.id).toSet().length != messages.length ||
          messages.any(
            (item) => !conversationIds.contains(item.conversationId),
          )) {
        return false;
      }

      // The authenticated backup must agree with the recovery phrase's
      // deterministic identity before any local state is changed.
      final derivedPair = await AccountIdentity.fromRecoveryPhrase(phrase);
      final matchesRecovery =
          listEquals(derivedPair.publicKey, importedPair.publicKey) &&
          listEquals(derivedPair.privateKey, importedPair.privateKey);
      Csprng.wipe(derivedPair.publicKey);
      Csprng.wipe(derivedPair.privateKey);
      if (!matchesRecovery) return false;

      previousPair = await _keyManager.getKeyPair();
      final previousPhrase = await _keyManager.getRecoveryPhrase();
      final previousId = await _keyManager.getChhayaId();
      try {
        await _keyManager.storeKeyPair(importedPair);
        await _keyManager.storeRecoveryPhrase(phrase);
        await _database.replaceAccountSnapshot(
          profile: profile,
          contacts: contacts,
          conversations: conversations,
          messages: messages,
        );
      } catch (_) {
        // Keychain/Keystore and SQLCipher are separate stores. If the SQL
        // transaction fails, restore the prior identity credentials before
        // returning so an interrupted import cannot strand the account.
        await _keyManager.clearAllKeys();
        if (previousPair != null) {
          await _keyManager.storeKeyPair(previousPair);
        }
        if (previousPhrase != null) {
          await _keyManager.storeRecoveryPhrase(previousPhrase);
        }
        if (previousId != null) {
          await _keyManager.storeChhayaId(previousId);
        }
        return false;
      }
      _currentUser = profile;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (key != null) Csprng.wipe(key);
      if (importedPair != null) {
        Csprng.wipe(importedPair.privateKey);
        Csprng.wipe(importedPair.publicKey);
      }
      if (previousPair != null) {
        Csprng.wipe(previousPair.privateKey);
        Csprng.wipe(previousPair.publicKey);
      }
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
