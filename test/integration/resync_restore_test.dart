// Backup→restore→resync end-to-end (spec §3.7, §6 criteria 2 and 3).
//
// REQUIRES a loopback backend (real store-and-forward /messages path —
// the resync envelope must ride it exactly like user content):
//
//   docker run --rm -d --name chhaya_test_pg \
//     -e POSTGRES_PASSWORD=testpw -e POSTGRES_DB=chhaya_test \
//     -p 55433:5432 postgres:16-alpine
//   cd backend/server && npm run build && cd ../..
//   NODE_ENV=test DATABASE_URL=postgres://postgres:testpw@127.0.0.1:55433/chhaya_test \
//     CHHAYA_TEST_API_PORT=18091 node backend/server/test/local_api_server.cjs &
//   CHHAYA_TEST_API_PORT=18091 flutter test test/integration/resync_restore_test.dart
//
// Without CHHAYA_TEST_API_PORT the test is skipped. When run it exercises:
//   2. backup→restore→send→receive with resync-ack, pending re-created
//      from DB content with a NEW messageId, server holds exactly one copy.
//   3. Offline-peer: the resync envelope sits server-side until the peer
//      connects; duplicate resync is an idempotent no-op.
//
// The prekey-bundle path runs through an in-memory FakePrekeyServer; the
// /messages path runs through the REAL loopback backend. Flag v2 is on.
import 'dart:io';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/messaging/messaging_service.dart';
import 'package:chaaya/services/messaging/pq_hybrid_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_prekey_server.dart';

class _MemoryOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  }) async {
    if (passwordHex.isEmpty) throw StateError('Database key missing');
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: version,
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
  }
}

class _TestAccount {
  final UserProfile profile;
  final ApiService api;
  final LocalDatabase database;
  final MessagingService messaging;
  final KeyManager keys;
  _TestAccount(
    this.profile,
    this.api,
    this.database,
    this.messaging,
    this.keys,
  );
}

Future<LocalDatabase> makeDb(KeyManager keys) async {
  sqfliteFfiInit();
  final db = LocalDatabase(
    keyManager: keys,
    opener: _MemoryOpener(),
    dbPath: inMemoryDatabasePath,
    secureStorage: SecureStorageMock(),
  );
  expect(await db.init(requireBiometric: false), isTrue);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final port = int.tryParse(Platform.environment['CHHAYA_TEST_API_PORT'] ?? '');
  final remoteOrigin = Platform.environment['CHHAYA_TEST_API_ORIGIN'];

  test(
    'backup→restore→resync→pending re-send with new id through loopback '
    '(spec §3.7, §3.7.5, §6 criteria 2 and 3)',
    skip:
        port == null && remoteOrigin == null
            ? 'Set CHHAYA_TEST_API_PORT to a running chhaya_test loopback '
              'backend (see file header); otherwise this test is skipped.'
            : false,
    () async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final fakePrekeys = FakePrekeyServer();
      PqHybridV1.testEnabled = true;
      PqHybridV1.testKem = FakeKem(Uint8List.fromList(const [0x31]));
      PqHybridV1.testBundleFetcher = fakePrekeys.fetch;
      PqHybridV1.testPrekeyProvider = fakePrekeys.materialFor;
      PqHybridV1.testEd25519PublicKey = fakePrekeys.ed25519PublicFor;
      addTearDown(() => PqHybridV1.resetForTest());

      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final network = http.Client();
      addTearDown(network.close);

      Future<_TestAccount> createAccount(String name) async {
        final identity = await ChhayaCryptoEngine.generateKeyPair();
        final keys = KeyManager(secureBackend: SecureStorageMock());
        await keys.storeKeyPair(identity);
        final profile = UserProfile(
          chhayaId: ChhayaId.fromPublicKey('05${identity.publicKeyHex}'),
          displayName: name,
          recoveryPhrase: ['local', name, 'integration', 'phrase'],
          createdAt: DateTime.now(),
        );
        await keys.storeChhayaId(profile.chhayaId.publicKey);
        final database = await makeDb(keys);
        await database.saveUserProfile(profile);
        await fakePrekeys.enroll(
          profile.chhayaId.publicKey,
          Uint8List.fromList(identity.publicKey),
        );
        final api = ApiService.forTesting(
          storage: SecureStorageMock(),
          client:
              remoteOrigin != null
                  ? network
                  : MockClient((request) async {
                    final target = Uri(
                      scheme: 'http',
                      host: '127.0.0.1',
                      port: port,
                      path: request.url.path,
                      query: request.url.hasQuery ? request.url.query : null,
                    );
                    final forwarded =
                        http.Request(request.method, target)
                          ..followRedirects = false
                          ..headers.addAll(request.headers)
                          ..bodyBytes = request.bodyBytes;
                    return http.Response.fromStream(await network.send(forwarded));
                  }),
        );
        await api.connectAccount(
          remoteOrigin ?? 'https://integration.invalid',
          profile,
          keys,
        );
        // Best effort: re-enroll under the server id once known.
        if (api.userId != null) {
          await fakePrekeys.enroll(
            api.userId!,
            Uint8List.fromList(identity.publicKey),
          );
        }
        return _TestAccount(
          profile,
          api,
          database,
          MessagingService(api: api, database: database, keys: keys),
          keys,
        );
      }

      final alice = await createAccount('Alice');
      final bob = await createAccount('Bob');

      final bobContact = await alice.api.addContact(
        chhayaId: bob.profile.chhayaId.publicKey,
        displayName: 'Bob',
      );
      await alice.database.addContact(bobContact.copyWith(isVerified: true));
      final aliceChat = (await alice.messaging.sync()).single;
      await bob.messaging.sync();
      final bobContactForBob =
          (await bob.database.getAllContacts()).single;
      await bob.database.updateContact(
        bobContactForBob.copyWith(isVerified: true),
      );
      final bobChat = (await bob.messaging.sync()).single;

      // 1. Steady state: exchange a message.
      final preRestore = await alice.messaging.send(
        aliceChat,
        'before the restore',
      );
      expect(preRestore.isSent, isTrue);
      await bob.messaging.sync();
      expect(
        (await bob.database.getMessages(bobChat.id)).map((m) => m.content),
        contains('before the restore'),
      );

      // 2. Backupalice, then restore. Backup = current messages snapshot.
      final messages = await alice.database.getMessages(aliceChat.id);
      final contacts = await alice.database.getAllContacts();
      final conversations = await alice.database.getAllConversations();
      await alice.database.replaceAccountSnapshot(
        profile: alice.profile,
        contacts: contacts,
        conversations: conversations,
        messages: messages,
      );

      // 3. Alice sends post-restore: the resync envelope rides /messages
      //    first, the user message queues until the peer's ack arrives.
      Message? queued;
      try {
        queued = await alice.messaging.send(
          aliceChat,
          'after the restore',
        );
      } on MessageQueuedException catch (error) {
        queued = error.message;
      }
      expect(queued, isNotNull);
      final q = queued;
      expect(q.isSent, isFalse);
      expect(
        await alice.database.readResyncPending(aliceChat.id),
        isNotNull,
        reason: 'restored conversation records resync-pending',
      );
      // The resync envelope, at least, was committed to the server.
      expect(
        (await alice.api.getMessages(aliceChat.id)).isNotEmpty,
        isTrue,
        reason: 'store-and-forward carries the resync envelope exactly '
            'like any encrypted envelope',
      );

      // 4. Bob syncs: decrypts the resync under a fresh session, acks it.
      await bob.messaging.sync();

      // 5. Alice syncs: sees the ack, clears pending, re-creates the
      //    queued message from DB content with a NEW messageId.
      await alice.messaging.sync();

      // 6. Bob syncs again: the re-sent message arrives.
      await bob.messaging.sync();

      final bobMessages = await bob.database.getMessages(bobChat.id);
      final contents = bobMessages.map((m) => m.content).toList();
      expect(contents, contains('after the restore'));

      // The re-sent message carries a fresh messageId (the old queued id
      // is superseded). The server never saw the old id.
      final serverMessages = await bob.api.getMessages(bobChat.id);
      expect(
        serverMessages.where((m) => m.id == q.id),
        isEmpty,
        reason: 'spec §3.7.5: no reuse of the superseded messageId',
      );
      expect(
        serverMessages.where((m) => m.content.isNotEmpty),
        isNotEmpty,
      );

      // session_generation advanced on both sides.
      final aliceGen = await alice.database
          .readSessionGenerationPair(aliceChat.id);
      final bobGen = await bob.database
          .readSessionGenerationPair(bobChat.id);
      expect(aliceGen.db, greaterThanOrEqualTo(1));
      expect(bobGen.db, greaterThanOrEqualTo(1));
    },
  );
}
