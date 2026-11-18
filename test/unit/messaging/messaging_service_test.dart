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
import 'package:chaaya/services/messaging/poll_payload.dart';

class OutboxDatabase extends LocalDatabase {
  late UserProfile profile;
  late Conversation conversation;
  late Contact peer;
  bool blocked = false;
  int globalTtlSeconds = 0;
  final messages = <String, Message>{};
  final blobs = <String, String>{};
  @override
  Future<UserProfile?> getUserProfile() async => profile;
  @override
  Future<List<Conversation>> getAllConversations() async => [conversation];
  @override
  Future<Contact?> getContact(String id) async => peer;
  @override
  int getGlobalDisappearingDuration() => globalTtlSeconds;
  @override
  List<String> getBlockedContacts() => blocked ? [peer.id] : [];
  @override
  Future<List<Message>> getMessages(String id) async =>
      messages.values.toList();
  @override
  Future<String?> loadSessionBlob(String id) async => blobs[id];
  @override
  Future<void> commitOutgoingMessage(
    SessionState state,
    Message message,
    String envelope,
  ) async {
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

class GroupHistoryDatabase extends LocalDatabase {
  late UserProfile profile;
  late Conversation conversation;
  final contacts = <String, Contact>{};
  final messages = <String, Message>{};

  @override
  Future<UserProfile?> getUserProfile() async => profile;
  @override
  Future<List<Contact>> getAllContacts() async => contacts.values.toList();
  @override
  Future<List<Conversation>> getAllConversations() async => [conversation];
  @override
  Future<List<Message>> getMessages(String conversationId) async =>
      messages.values
          .where((message) => message.conversationId == conversationId)
          .toList();
  @override
  Future<void> addContact(Contact contact) async {
    contacts[contact.id] = contact;
  }

  @override
  Future<void> addConversation(Conversation value) async {
    conversation = value;
  }

  @override
  Future<void> addMessage(Message message) async {
    messages[message.id] = message;
  }
}

class GroupHistoryApi extends ApiService {
  GroupHistoryApi(this.conversation, this.messages)
    : super.forTesting(
        storage: SecureStorageMock(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  final Conversation conversation;
  final List<Message> messages;

  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => 'self';
  @override
  Future<List<Conversation>> getConversations() async => [conversation];
  @override
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    String? before,
    String? beforeId,
  }) async => messages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a network failure preserves one message; retry reuses its exact envelope and ID',
    () async {
      SharedPreferences.setMockInitialValues({'user_id': 'alice'});
      final storage = SecureStorageMock({'chhaya_auth_token': 'token'});
      var offline = true;
      final requests = <Map<String, dynamic>>[];
      final api = ApiService.forTesting(
        storage: storage,
        client: MockClient((request) async {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(data);
          if (offline) throw http.ClientException('offline');
          return http.Response(
            jsonEncode({
              'id': data['messageId'],
              'conversation_id': data['conversationId'],
              'sender_id': 'alice',
              'content': data['content'],
              'sent_at': DateTime.now().toIso8601String(),
            }),
            201,
          );
        }),
      );
      await api.init();
      api.setBaseUrl('https://chat.example.com');
      final a = await ChhayaCryptoEngine.generateKeyPair(),
          b = await ChhayaCryptoEngine.generateKeyPair();
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(a);
      final db = OutboxDatabase();
      db.profile = UserProfile(
        chhayaId: ChhayaId.fromPublicKey('05${a.publicKeyHex}'),
        displayName: 'Alice',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      db.peer = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${b.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      db.conversation = Conversation(
        id: 'conversation',
        participants: [db.peer],
        createdAt: DateTime.now(),
      );
      final service = MessagingService(api: api, database: db, keys: keys);
      await expectLater(
        service.send(db.conversation, 'only once', replyToId: 'original'),
        throwsA(isA<MessageQueuedException>()),
      );
      expect(db.messages.length, 1);
      expect(db.messages.values.single.isSent, false);
      expect(db.messages.values.single.replyToId, 'original');
      final pending = db.messages.values.single;
      final originalWire = requests.single['content'];
      db.blocked = true;
      offline = false;
      await service.retryPending(db.conversation.id);
      expect(
        requests.length,
        1,
        reason: 'Blocking also prevents queued delivery',
      );
      db.blocked = false;
      await service.retryPending(db.conversation.id);
      expect(requests.length, 2);
      expect(requests.last['content'], originalWire);
      expect(requests.last['messageId'], pending.id);
      expect(db.messages.values.single.isSent, true);
      expect(db.blobs.containsKey('outbox:${pending.id}'), false);
      await service.retryPending(db.conversation.id);
      expect(requests.length, 2);
    },
  );

  test(
    'poll definitions and votes send encrypted; invalid votes never reach transport',
    () async {
      SharedPreferences.setMockInitialValues({'user_id': 'alice'});
      final storage = SecureStorageMock({'chhaya_auth_token': 'token'});
      final requests = <Map<String, dynamic>>[];
      final api = ApiService.forTesting(
        storage: storage,
        client: MockClient((request) async {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(data);
          return http.Response(
            jsonEncode({
              'id': data['messageId'],
              'conversation_id': data['conversationId'],
              'sender_id': 'alice',
              'content': data['content'],
              'sent_at': DateTime.now().toIso8601String(),
            }),
            201,
          );
        }),
      );
      await api.init();
      api.setBaseUrl('https://chat.example.com');
      final a = await ChhayaCryptoEngine.generateKeyPair(),
          b = await ChhayaCryptoEngine.generateKeyPair();
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(a);
      final db = OutboxDatabase();
      db.profile = UserProfile(
        chhayaId: ChhayaId.fromPublicKey('05${a.publicKeyHex}'),
        displayName: 'Alice',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      db.peer = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${b.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      db.conversation = Conversation(
        id: 'conversation',
        participants: [db.peer],
        createdAt: DateTime.now(),
      );
      final service = MessagingService(api: api, database: db, keys: keys);
      final poll = PollPayload.create(
        question: 'Private question',
        labels: ['Cafe', 'Park'],
        allowMultiple: false,
      );
      await service.send(
        db.conversation,
        poll.encode(),
        type: MessageType.poll,
      );
      expect(requests.single['content'], isNot(contains('Private question')));
      final vote = PollVote(
        pollId: poll.id,
        optionIds: [poll.options.first.id],
      );
      await service.send(
        db.conversation,
        vote.encode(),
        type: MessageType.poll,
      );
      expect(requests.length, 2);
      final invalid = PollVote(
        pollId: poll.id,
        optionIds: ['${poll.options.first.id.substring(0, 35)}0000'],
      );
      await expectLater(
        service.send(db.conversation, invalid.encode(), type: MessageType.poll),
        throwsFormatException,
      );
      expect(
        requests.length,
        2,
        reason: 'invalid vote must not enter transport',
      );
    },
  );

  test(
    'group sync shows a marker when history has no key for this device',
    () async {
      final self = await ChhayaCryptoEngine.generateKeyPair();
      final peerA = await ChhayaCryptoEngine.generateKeyPair();
      final peerB = await ChhayaCryptoEngine.generateKeyPair();
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(self);
      final now = DateTime.now();
      final selfContact = Contact(
        id: 'self',
        chhayaId: ChhayaId.fromPublicKey('05${self.publicKeyHex}'),
        displayName: 'Self',
        isVerified: true,
      );
      final alice = Contact(
        id: 'alice',
        chhayaId: ChhayaId.fromPublicKey('05${peerA.publicKeyHex}'),
        displayName: 'Alice',
        isVerified: true,
      );
      final bob = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${peerB.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      const conversationId = '11111111-1111-4111-8111-111111111111';
      const messageId = '22222222-2222-4222-8222-222222222222';
      final conversation = Conversation(
        id: conversationId,
        participants: [selfContact, alice, bob],
        isGroup: true,
        groupName: 'Friends',
        createdAt: now,
      );
      final remoteMessage = Message(
        id: messageId,
        conversationId: conversationId,
        senderId: alice.id,
        content: jsonEncode({
          'v': 1,
          'kind': 'chhaya-group-v1',
          'conversationId': conversationId,
          'messageId': messageId,
          'senderId': alice.id,
          'keys': <String, String>{},
        }),
        timestamp: now,
      );
      final db =
          GroupHistoryDatabase()
            ..profile = UserProfile(
              chhayaId: ChhayaId.fromPublicKey('05${self.publicKeyHex}'),
              displayName: 'Self',
              recoveryPhrase: const [],
              createdAt: now,
            )
            ..conversation = conversation;
      final api = GroupHistoryApi(conversation, [remoteMessage]);

      await MessagingService(api: api, database: db, keys: keys).sync();

      final marker = db.messages[messageId];
      expect(marker, isNotNull);
      expect(marker!.type, MessageType.system);
      expect(marker.content, contains('unavailable'));
      expect(marker.content, isNot(contains(remoteMessage.content)));

      // A group may shrink to two active members. The sole peer's messages
      // must still be fetched and displayed after that membership change.
      db.messages.clear();
      final twoMemberGroup = conversation.copyWith(
        participants: [selfContact, alice],
      );
      final twoMemberApi = GroupHistoryApi(twoMemberGroup, [remoteMessage]);
      await MessagingService(
        api: twoMemberApi,
        database: db,
        keys: keys,
      ).sync();
      expect(db.messages[messageId]?.content, contains('unavailable'));
    },
  );

  test(
    'per-message TTL can inherit, override, or disable the global timer',
    () async {
      SharedPreferences.setMockInitialValues({'user_id': 'alice'});
      final api = ApiService.forTesting(
        storage: SecureStorageMock({'chhaya_auth_token': 'token'}),
        client: MockClient((request) async {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': data['messageId'],
              'conversation_id': data['conversationId'],
              'sender_id': 'alice',
              'content': data['content'],
              'sent_at': DateTime.now().toIso8601String(),
            }),
            201,
          );
        }),
      );
      await api.init();
      api.setBaseUrl('https://chat.example.com');
      final a = await ChhayaCryptoEngine.generateKeyPair();
      final b = await ChhayaCryptoEngine.generateKeyPair();
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(a);
      final db = OutboxDatabase();
      db.profile = UserProfile(
        chhayaId: ChhayaId.fromPublicKey('05${a.publicKeyHex}'),
        displayName: 'Alice',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      db.peer = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${b.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      db.conversation = Conversation(
        id: 'conversation',
        participants: [db.peer],
        createdAt: DateTime.now(),
      );
      db.globalTtlSeconds = 3600;
      final service = MessagingService(api: api, database: db, keys: keys);
      await service.send(db.conversation, 'inherits global timer');
      expect(db.messages.values.last.ttl, const Duration(hours: 1));
      await service.send(
        db.conversation,
        'per-message override',
        ttl: const Duration(minutes: 3),
      );
      expect(db.messages.values.last.ttl, const Duration(minutes: 3));
      await service.send(db.conversation, 'explicitly never', disableTtl: true);
      expect(db.messages.values.last.ttl, isNull);
    },
  );
}
