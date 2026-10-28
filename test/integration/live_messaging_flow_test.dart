import 'dart:io';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/messaging/messaging_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  _TestAccount(this.profile, this.api, this.database, this.messaging);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final port = int.tryParse(Platform.environment['CHHAYA_TEST_API_PORT'] ?? '');
  test(
    'Flutter clients exchange direct and group messages through the local backend',
    skip:
        port == null
            ? 'Set CHHAYA_TEST_API_PORT for the local integration backend'
            : false,
    () async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
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
        final database = LocalDatabase(
          keyManager: keys,
          opener: _MemoryOpener(),
          dbPath: inMemoryDatabasePath,
        );
        await database.init(requireBiometric: false);
        await database.saveUserProfile(profile);
        addTearDown(database.close);
        final api = ApiService.forTesting(
          storage: SecureStorageMock(),
          client: MockClient((request) async {
            final target = Uri(
              scheme: 'http',
              host: '127.0.0.1',
              port: port,
              path: request.url.path,
              query: request.url.hasQuery ? request.url.query : null,
            );
            final forwarded =
                http.Request(request.method, target)
                  ..headers.addAll(request.headers)
                  ..bodyBytes = request.bodyBytes;
            return http.Response.fromStream(await network.send(forwarded));
          }),
        );
        await api.connectAccount('https://integration.invalid', profile, keys);
        return _TestAccount(
          profile,
          api,
          database,
          MessagingService(api: api, database: database, keys: keys),
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
      final aliceContact = (await bob.database.getAllContacts()).single;
      expect(aliceContact.chhayaId.publicKey, alice.profile.chhayaId.publicKey);
      await bob.database.updateContact(aliceContact.copyWith(isVerified: true));
      final bobChat = (await bob.messaging.sync()).single;

      await alice.messaging.send(aliceChat, 'Hello from Alice');
      await bob.messaging.sync();
      expect(
        (await bob.database.getMessages(bobChat.id)).map((m) => m.content),
        contains('Hello from Alice'),
      );
      await bob.messaging.send(bobChat, 'Hello from Bob');
      await alice.messaging.sync();
      expect(
        (await alice.database.getMessages(aliceChat.id)).map((m) => m.content),
        contains('Hello from Bob'),
      );

      final charlie = await createAccount('Charlie');
      final charlieContact = await alice.api.addContact(
        chhayaId: charlie.profile.chhayaId.publicKey,
        displayName: 'Charlie',
      );
      await alice.database.addContact(
        charlieContact.copyWith(isVerified: true),
      );
      final createdGroup = await alice.api.createConversation(
        type: 'group',
        participantIds: [bob.api.userId!, charlie.api.userId!],
        name: 'Friends',
      );
      await bob.messaging.sync();
      await charlie.messaging.sync();
      final identities = {
        alice.api.userId!: alice.profile.chhayaId.publicKey,
        bob.api.userId!: bob.profile.chhayaId.publicKey,
        charlie.api.userId!: charlie.profile.chhayaId.publicKey,
      };
      for (final account in [bob, charlie]) {
        for (final contact in await account.database.getAllContacts()) {
          expect(contact.chhayaId.publicKey, identities[contact.id]);
          await account.database.updateContact(
            contact.copyWith(isVerified: true),
          );
        }
      }
      final aliceGroup = (await alice.messaging.sync()).firstWhere(
        (c) => c.id == createdGroup.id,
      );
      final bobGroup = (await bob.messaging.sync()).firstWhere(
        (c) => c.id == createdGroup.id,
      );
      await alice.messaging.send(aliceGroup, 'Hello group');
      await bob.messaging.sync();
      await charlie.messaging.sync();
      expect(
        (await bob.database.getMessages(createdGroup.id)).map((m) => m.content),
        contains('Hello group'),
      );
      expect(
        (await charlie.database.getMessages(
          createdGroup.id,
        )).map((m) => m.content),
        contains('Hello group'),
      );
      final serverGroupMessages = await alice.api.getMessages(createdGroup.id);
      expect(
        serverGroupMessages.single.content,
        isNot(contains('Hello group')),
      );
      await bob.messaging.send(bobGroup, 'Reply to group');
      await alice.messaging.sync();
      await charlie.messaging.sync();
      expect(
        (await charlie.database.getMessages(
          createdGroup.id,
        )).map((m) => m.content),
        contains('Reply to group'),
      );

      await alice.api.removeGroupParticipant(
        createdGroup.id,
        charlie.api.userId!,
      );
      final remainingGroup = (await alice.messaging.sync()).firstWhere(
        (c) => c.id == createdGroup.id,
      );
      expect(remainingGroup.participants.length, 1);
      await bob.messaging.sync();
      await alice.messaging.send(remainingGroup, 'After removal');
      await bob.messaging.sync();
      expect(
        (await bob.database.getMessages(createdGroup.id)).map((m) => m.content),
        contains('After removal'),
      );
      await expectLater(
        charlie.api.getMessages(createdGroup.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      await alice.api.logout();
      await bob.api.logout();
      await charlie.api.logout();
    },
  );
}
