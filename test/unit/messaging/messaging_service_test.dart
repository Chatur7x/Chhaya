import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/messaging/messaging_service.dart';

class OutboxDatabase extends LocalDatabase {
  late UserProfile profile;
  late Conversation conversation;
  late Contact peer;
  bool blocked = false;
  final messages = <String, Message>{};
  final blobs = <String, String>{};
  @override
  Future<UserProfile?> getUserProfile() async => profile;
  @override
  Future<List<Conversation>> getAllConversations() async => [conversation];
  @override
  Future<Contact?> getContact(String id) async => peer;
  @override
  int getGlobalDisappearingDuration() => 0;
  @override
  List<String> getBlockedContacts() => blocked ? [peer.id] : [];
  @override
  Future<List<Message>> getMessages(String id) async => messages.values.toList();
  @override
  Future<String?> loadSessionBlob(String id) async => blobs[id];
  @override
  Future<void> commitOutgoingMessage(SessionState state, Message message, String envelope) async {
    messages[message.id] = message;
    blobs[state.peerId] = jsonEncode(state.toJson());
    blobs['outbox:${message.id}'] = envelope;
  }
  @override
  Future<void> commitMessageSent(Message message) async {
    messages[message.id] = message;
    blobs.remove('outbox:${message.id}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a network failure preserves one message; retry reuses its exact envelope and ID', () async {
    SharedPreferences.setMockInitialValues({'user_id': 'alice'});
    final storage = SecureStorageMock({'chhaya_auth_token': 'token'});
    var offline = true;
    final requests = <Map<String, dynamic>>[];
    final api = ApiService.forTesting(storage: storage, client: MockClient((request) async {
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(data);
      if (offline) throw http.ClientException('offline');
      return http.Response(jsonEncode({'id': data['messageId'], 'conversation_id': data['conversationId'],
        'sender_id': 'alice', 'content': data['content'], 'sent_at': DateTime.now().toIso8601String()}), 201);
    }));
    await api.init();
    api.setBaseUrl('https://chat.example.com');
    final a = await ChhayaCryptoEngine.generateKeyPair(), b = await ChhayaCryptoEngine.generateKeyPair();
    final keys = KeyManager(secureBackend: SecureStorageMock());
    await keys.storeKeyPair(a);
    final db = OutboxDatabase();
    db.profile = UserProfile(chhayaId: ChhayaId.fromPublicKey('05${a.publicKeyHex}'),
      displayName: 'Alice', recoveryPhrase: const [], createdAt: DateTime.now());
    db.peer = Contact(id: 'bob', chhayaId: ChhayaId.fromPublicKey('05${b.publicKeyHex}'), displayName: 'Bob', isVerified: true);
    db.conversation = Conversation(id: 'conversation', participants: [db.peer], createdAt: DateTime.now());
    final service = MessagingService(api: api, database: db, keys: keys);
    await expectLater(service.send(db.conversation, 'only once', replyToId: 'original'),
      throwsA(isA<MessageQueuedException>()));
    expect(db.messages.length, 1);
    expect(db.messages.values.single.isSent, false);
    expect(db.messages.values.single.replyToId, 'original');
    final pending = db.messages.values.single;
    final originalWire = requests.single['content'];
    db.blocked = true;
    offline = false;
    await service.retryPending(db.conversation.id);
    expect(requests.length, 1, reason: 'Blocking also prevents queued delivery');
    db.blocked = false;
    await service.retryPending(db.conversation.id);
    expect(requests.length, 2);
    expect(requests.last['content'], originalWire);
    expect(requests.last['messageId'], pending.id);
    expect(db.messages.values.single.isSent, true);
    expect(db.blobs.containsKey('outbox:${pending.id}'), false);
    await service.retryPending(db.conversation.id);
    expect(requests.length, 2);
  });
}
