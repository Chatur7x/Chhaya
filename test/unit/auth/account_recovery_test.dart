import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/services/auth/account_identity.dart';
import 'package:chaaya/services/auth/auth_service.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';

class MemoryAccountDatabase extends LocalDatabase {
  UserProfile? profile;
  final contacts = <Contact>[];
  final conversations = <Conversation>[];
  final messages = <Message>[];
  @override
  Future<void> saveUserProfile(UserProfile value) async { profile = value; }
  @override
  Future<List<Contact>> getAllContacts() async => contacts;
  @override
  Future<List<Conversation>> getAllConversations() async => conversations;
  @override
  Future<List<Message>> getMessages(String id) async => messages.where((m) => m.conversationId == id).toList();
  @override
  Future<void> addContact(Contact value) async { contacts.add(value); }
  @override
  Future<void> addConversation(Conversation value) async { conversations.add(value); }
  @override
  Future<void> addMessage(Message value) async { messages.add(value); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('signup phrase restores the same identity, with no demo contacts', () async {
    final originalDb = MemoryAccountDatabase();
    final original = AuthService(database: originalDb,
        keyManager: KeyManager(secureBackend: SecureStorageMock()));
    final profile = await original.createAccount(displayName: 'Alice');
    final restored = AuthService(database: MemoryAccountDatabase(),
        keyManager: KeyManager(secureBackend: SecureStorageMock()));
    final result = await restored.restoreAccount(profile.recoveryPhrase);
    expect(result!.chhayaId.publicKey, profile.chhayaId.publicKey);
    expect(profile.chhayaId.publicKey, matches(RegExp(r'^05[0-9a-f]{64}$')));
    expect(originalDb.contacts, isEmpty);
    expect(originalDb.conversations, isEmpty);
  });
  test('invalid recovery words cannot create an identity', () async {
    await expectLater(AccountIdentity.fromRecoveryPhrase(List.filled(12, 'invalid')),
        throwsArgumentError);
  });
  test('encrypted backup restores keys and message history; tampering leaves account alone', () async {
    final db = MemoryAccountDatabase();
    final keys = KeyManager(secureBackend: SecureStorageMock());
    final auth = AuthService(database: db, keyManager: keys);
    final profile = await auth.createAccount(displayName: 'Alice');
    final contact = Contact(id: 'bob', chhayaId: profile.chhayaId, displayName: 'Bob');
    db.contacts.add(contact);
    db.conversations.add(Conversation(id: 'conversation', participants: [contact], createdAt: DateTime.now()));
    db.messages.add(Message(id: 'message', conversationId: 'conversation', senderId: 'me', content: 'private history', timestamp: DateTime.now()));
    final backup = await auth.generateBackup();
    expect(backup, isNot(contains('private history')));
    final newDb = MemoryAccountDatabase();
    final newKeys = KeyManager(secureBackend: SecureStorageMock());
    final restored = AuthService(database: newDb, keyManager: newKeys);
    expect(await restored.restoreFromBackup(backup, profile.recoveryPhrase), isTrue);
    expect(newDb.messages.single.content, 'private history');
    expect(newDb.contacts.single.displayName, 'Bob');
    expect((await newKeys.getKeyPair())!.privateKey,
        (await keys.getKeyPair())!.privateKey);
    final corrupt = jsonDecode(backup) as Map<String, dynamic>;
    corrupt['ciphertext'] = 'AAAA';
    expect(await restored.restoreFromBackup(jsonEncode(corrupt), profile.recoveryPhrase), isFalse);
    expect(restored.currentUser!.chhayaId, profile.chhayaId);
    expect(newDb.messages.length, 1);
  });
}
