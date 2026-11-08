// Adversarial delivery coverage: lost acknowledgements, commit-after-accept
// crashes, concurrent retries of one outbox row, and pinned silent-drop gaps.
// All databases are in-memory fakes; all identities are synthetic.
import 'dart:convert';
import 'dart:typed_data';

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
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory fake with a one-shot commit failure hook: simulates a crash
/// after the server accepted but before the local sent-marker is written.
class CrashOnceDatabase extends LocalDatabase {
  late UserProfile profile;
  late Conversation conversation;
  late Contact peer;
  int commitFailures = 0;
  final messages = <String, Message>{};
  final blobs = <String, String>{};

  CrashOnceDatabase withAccount({
    required String ownName,
    required ChhayaKeyPair like,
    required ChhayaKeyPair peerKey,
  }) {
    profile = UserProfile(
      chhayaId: ChhayaId.fromPublicKey('05${like.publicKeyHex}'),
      displayName: ownName,
      recoveryPhrase: const [],
      createdAt: DateTime.now(),
    );
    peer = Contact(
      id: 'bob',
      chhayaId: ChhayaId.fromPublicKey('05${peerKey.publicKeyHex}'),
      displayName: 'Bob',
      isVerified: true,
    );
    conversation = Conversation(
      id: 'conversation',
      participants: [peer],
      createdAt: DateTime.now(),
    );
    return this;
  }

  @override
  Future<UserProfile?> getUserProfile() async => profile;
  @override
  Future<List<Conversation>> getAllConversations() async => [conversation];
  @override
  Future<Contact?> getContact(String id) async => id == peer.id ? peer : null;
  @override
  int getGlobalDisappearingDuration() => 0;
  @override
  List<String> getBlockedContacts() => const [];
  @override
  Future<List<Message>> getPendingMessages(String id) async => messages.values
      .where((m) => m.conversationId == id && !m.isSent)
      .toList();
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
    if (commitFailures > 0) {
      commitFailures--;
      throw StateError('simulated crash before local sent-marker commit');
    }
    messages[message.id] = message;
    blobs.remove('outbox:${message.id}');
  }

  @override
  Future<Set<String>> getKnownMessageIds(
    String conversationId, {
    List<String>? messageIds,
  }) async =>
      const {};
  @override
  Future<Message?> getLatestMessage(String conversationId) async => null;
  @override
  Future<Message?> getMessage(String conversationId, String messageId) async =>
      messages[messageId];
  @override
  Future<List<Contact>> getAllContacts() async => [peer];
  @override
  Future<void> addContact(Contact contact) async {}
  @override
  Future<void> addConversation(Conversation value) async {
    conversation = value;
  }
}

/// API fake that dedups exact retries the way routes.ts does: identical
/// retry (same sender, conversation, content) returns 200; conflicting
/// reuse of a messageId returns 409.
({ApiService api, List<Map<String, dynamic>> requests, Map<String, int> accepted})
makeDedupApi({required String userId, Duration delay = Duration.zero}) {
  SharedPreferences.setMockInitialValues({'user_id': userId});
  final storage = SecureStorageMock({'chhaya_auth_token': 'token'});
  final requests = <Map<String, dynamic>>[];
  final accepted = <String, int>{};
  final api = ApiService.forTesting(
    storage: storage,
    client: MockClient((request) async {
      if (delay > Duration.zero) await Future.delayed(delay);
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(data);
      final id = data['messageId'] as String;
      final isRetry = requests.length > 1;
      if (isRetry) {
        final original = requests.firstWhere((r) => r['messageId'] == id);
        final identical = original['content'] == data['content'] &&
            original['conversationId'] == data['conversationId'] &&
            original['senderId'] == data['senderId'];
        if (!identical) {
          return http.Response(
            jsonEncode({'error': 'Message identifier conflict'}),
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': id,
            'conversation_id': data['conversationId'],
            'sender_id': userId,
            'content': data['content'],
            'sent_at': DateTime.now().toIso8601String(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      accepted[id] = (accepted[id] ?? 0) + 1;
      return http.Response(
        jsonEncode({
          'id': id,
          'conversation_id': data['conversationId'],
          'sender_id': userId,
          'content': data['content'],
          'sent_at': DateTime.now().toIso8601String(),
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return (api: api, requests: requests, accepted: accepted);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server accepts but local commit crashes; retry re-sends the byte-identical '
    'envelope and converges to one stored copy',
    () async {
      final a = await ChhayaCryptoEngine.generateKeyPair();
      final b = await ChhayaCryptoEngine.generateKeyPair();
      final db = CrashOnceDatabase().withAccount(
        ownName: 'Alice',
        like: a,
        peerKey: b,
      );
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(a);
      final (:api, :requests, :accepted) = makeDedupApi(userId: 'alice');
      await api.init();
      api.setBaseUrl('https://chat.example.com');
      db.commitFailures = 1;
      final service = MessagingService(api: api, database: db, keys: keys);

      // Server accepts (201), the local sent-marker commit crashes.
      await expectLater(
        service.send(db.conversation, 'deliver me once'),
        throwsA(isA<MessageQueuedException>()),
      );
      expect(requests, hasLength(1));
      expect(db.messages.values.single.isSent, false);
      expect(db.blobs['outbox:${db.messages.keys.single}'], isNotNull);

      // Retry: the exact envelope bytes and messageId are re-sent; the
      // server dedups to the single accepted copy.
      await service.retryPending(db.conversation.id);
      expect(requests, hasLength(2));
      expect(requests[1]['messageId'], requests[0]['messageId']);
      expect(requests[1]['content'], requests[0]['content']);
      expect(accepted[requests[0]['messageId']], 1);
      expect(db.messages.values.single.isSent, true);
      expect(db.blobs['outbox:${db.messages.keys.single}'], isNull);

      // Converged: a further retry is a no-op.
      await service.retryPending(db.conversation.id);
      expect(requests, hasLength(2));
    },
  );

  test(
    'two MessagingService instances retry the same outbox row concurrently; '
    'the server admits one acceptance and stores one copy',
    () async {
      final a = await ChhayaCryptoEngine.generateKeyPair();
      final b = await ChhayaCryptoEngine.generateKeyPair();
      final db = CrashOnceDatabase().withAccount(
        ownName: 'Alice',
        like: a,
        peerKey: b,
      );
      final keys1 = KeyManager(secureBackend: SecureStorageMock());
      await keys1.storeKeyPair(a);
      final keys2 = KeyManager(secureBackend: SecureStorageMock());
      await keys2.storeKeyPair(a);
      final (:api, :requests, :accepted) =
          makeDedupApi(userId: 'alice', delay: const Duration(milliseconds: 25));
      await api.init();
      api.setBaseUrl('https://chat.example.com');
      final service1 = MessagingService(api: api, database: db, keys: keys1);
      final service2 = MessagingService(api: api, database: db, keys: keys2);

      // Seed one unsent message directly in the outbox (as an interrupted
      // send would leave it).
      const envelope = '{"v":1,"header":"aGVsbG8=","body":"d29ybGQ="}';
      await db.commitOutgoingMessage(
        SessionState(
          peerId: 'conversation:05${b.publicKeyHex}',
          initiatedByUs: true,
          rootKey: Uint8List(32),
          sendChainKey: Uint8List(32),
          recvChainKey: Uint8List(32),
          ourPrivateKey: Uint8List(32),
          ourPublicKey: Uint8List(32),
          remotePublicKey: Uint8List(32),
          spqrSeed: Uint8List(32),
        ),
        Message(
          id: 'queued-1',
          conversationId: db.conversation.id,
          senderId: 'me',
          content: 'queued',
          timestamp: DateTime.now(),
          isSent: false,
        ),
        envelope,
      );

      await Future.wait([
        service1.retryPending(db.conversation.id),
        service2.retryPending(db.conversation.id),
      ]);

      // Both may hit the wire (process-level race), but every request
      // carries the same messageId and bytes and the server admits at
      // most one acceptance.
      expect(requests, isNotEmpty);
      expect(requests.length, lessThanOrEqualTo(2));
      for (final request in requests) {
        expect(request['messageId'], 'queued-1');
        expect(request['content'], envelope);
      }
      expect(accepted['queued-1'], 1);
      expect(db.messages.values.single.isSent, true);
      expect(db.blobs['outbox:queued-1'], isNull);

      // Quiescence: neither service has anything left to send.
      await service1.retryPending(db.conversation.id);
      await service2.retryPending(db.conversation.id);
      expect(requests.length, lessThanOrEqualTo(2));
    },
  );

  test(
    'a pending message whose outbox envelope is missing is never re-sent '
    '(pinned: currently skipped without surfacing)',
    () async {
      final a = await ChhayaCryptoEngine.generateKeyPair();
      final b = await ChhayaCryptoEngine.generateKeyPair();
      final db = CrashOnceDatabase().withAccount(
        ownName: 'Alice',
        like: a,
        peerKey: b,
      );
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(a);
      final (:api, :requests, accepted: _) = makeDedupApi(userId: 'alice');
      await api.init();
      api.setBaseUrl('https://chat.example.com');
      db.messages['orphan'] = Message(
        id: 'orphan',
        conversationId: 'conversation',
        senderId: 'me',
        content: 'will never arrive',
        timestamp: DateTime.now(),
        isSent: false,
      );
      // No outbox:orphan blob is stored.
      final service = MessagingService(api: api, database: db, keys: keys);
      await service.retryPending(db.conversation.id);
      expect(requests, isEmpty);
      expect(db.messages['orphan']!.isSent, false);
    },
  );

  test(
    'sync does not store an undecryptable remote envelope (pinned: it is '
    'swallowed without surfacing)',
    () async {
      final self = await ChhayaCryptoEngine.generateKeyPair();
      final remote = await ChhayaCryptoEngine.generateKeyPair();
      final selfId = ChhayaId.fromPublicKey('05${self.publicKeyHex}');
      final peer = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${remote.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      final db = CrashOnceDatabase()
        ..profile = UserProfile(
          chhayaId: selfId,
          displayName: 'Alice',
          recoveryPhrase: const [],
          createdAt: DateTime.now(),
        )
        ..peer = peer
        ..conversation = Conversation(
          id: 'conversation',
          participants: [peer],
          createdAt: DateTime.now(),
        );
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(self);
      final garbage = Message(
        id: 'garbage-1',
        conversationId: 'conversation',
        senderId: 'bob',
        content: 'this is not an encrypted envelope',
        timestamp: DateTime.now(),
      );
      final conversation = db.conversation;
      final api = _GarbageSyncApi(conversation, [garbage]);
      final service = MessagingService(api: api, database: db, keys: keys);
      await service.sync();
      expect(db.messages.containsKey('garbage-1'), false);
    },
  );
}

class _GarbageSyncApi extends ApiService {
  _GarbageSyncApi(this.conversation, this.messages)
      : super.forTesting(
          storage: SecureStorageMock(),
          client: MockClient((_) async => http.Response('{}', 200)),
        );
  final Conversation conversation;
  final List<Message> messages;
  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => 'alice';
  @override
  Future<List<Conversation>> getConversations() async => [conversation];
  @override
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    String? before,
    String? beforeId,
  }) async =>
      messages;
}
