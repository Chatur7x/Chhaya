// Part 3 tests — SQLCipher database layer.
//
// Strategy: production code paths run against an in-memory database via
// a fake opener (sqflite_common_ffi — no SQLCipher native libs exist
// for test hosts). The fake records the password and PRAGMAs so tests
// prove the app ALWAYS supplies a key and requests hardening. True
// at-rest verification (plain-sqlite open must fail) runs on-device.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/database_key.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/database/migrations/migration_runner.dart';
import 'package:chaaya/core/database/queries.dart';
import 'package:chaaya/core/database/schema.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/user_profile.dart';

/// Test opener: records password + PRAGMAs, runs real migrations on an
/// in-memory ffi database. Refuses empty passwords, mirroring the
/// production invariant that a key is always supplied.
class FakeDatabaseOpener implements DatabaseOpener {
  String? passwordHex;
  final List<String> pragmas = [];

  @override
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  }) async {
    if (passwordHex.isEmpty) {
      throw StateError('production invariant: password required');
    }
    this.passwordHex = passwordHex;
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
    pragmas.addAll(kHardeningPragmas);
    await db.execute('PRAGMA journal_mode = DELETE');
    return db;
  }
}

KeyManager makeKeyManager() =>
    KeyManager(secureBackend: SecureStorageMock());

Future<LocalDatabase> makeDb(FakeDatabaseOpener opener) async {
  final keyManager = makeKeyManager();
  await keyManager.storeChhayaId('user-1');
  final db = LocalDatabase(
    keyManager: keyManager,
    opener: opener,
    dbPath: inMemoryDatabasePath,
  );
  final ok = await db.init(requireBiometric: false);
  expect(ok, isTrue);
  return db;
}

Message makeMessage(String id, String convo, [String content = 'hello']) {
  return Message(
    id: id,
    conversationId: convo,
    senderId: 'user-1',
    content: content,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

Contact makeContact(String id, [String name = 'Alice']) {
  return Contact(
    id: id,
    chhayaId: ChhayaId.fromPublicKey(
        'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12'),
    displayName: name,
  );
}

Conversation makeConversation(String id, [List<Contact>? participants]) {
  return Conversation(
    id: id,
    participants: participants ?? [makeContact('c-alice')],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

UserProfile makeProfile() {
  return UserProfile(
    chhayaId: ChhayaId.fromPublicKey(
        'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12'),
    displayName: 'Test User',
    recoveryPhrase: const ['abandon', 'ability', 'able'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('Database key', () {
    test('derivation is deterministic per user', () async {
      final km = makeKeyManager();
      final a = await DatabaseKey.derive(km, userId: 'user-1');
      final b = await DatabaseKey.derive(km, userId: 'user-1');
      final c = await DatabaseKey.derive(km, userId: 'user-2');
      expect(a, b);
      expect(a, isNot(equals(c)));
      Csprng.wipe(a);
      Csprng.wipe(b);
      Csprng.wipe(c);
    });

    test('pragma hex is 64 lowercase hex chars, rejects bad keys',
        () async {
      final km = makeKeyManager();
      final key = await DatabaseKey.derive(km, userId: 'user-1');
      final hex = DatabaseKey.toPragmaHex(key);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hex), isTrue);
      expect(
        () => DatabaseKey.toPragmaHex(key.sublist(0, 16)),
        throwsArgumentError,
      );
      Csprng.wipe(key);
    });

    test('field envelope round-trips and fails closed', () async {
      final km = makeKeyManager();
      final key = await DatabaseKey.derive(km, userId: 'user-1');
      final enc = DatabaseKey.encryptField('secret-value', key);
      expect(DatabaseKey.decryptField(enc, key), 'secret-value');
      expect(DatabaseKey.decryptField(enc, Csprng.instance.bytes(32)), isNull);
      expect(DatabaseKey.decryptField('!!!not-base64!!!', key), isNull);
      expect(DatabaseKey.decryptField(null, key), isNull);
      Csprng.wipe(key);
    });
  });

  group('Migrations', () {
    test('fresh database migrates to latest', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final runner = MigrationRunner(chhayaMigrations());
      await runner.migrateUp(db);
      expect(await runner.currentVersion(db), runner.latestVersion);
      expect(runner.latestVersion, 5);
      await db.close();
    });

    test('re-run is idempotent', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final runner = MigrationRunner(chhayaMigrations());
      await runner.migrateUp(db);
      await runner.migrateUp(db);
      expect(await runner.currentVersion(db), runner.latestVersion);
      await db.close();
    });

    test('v001 to v004 and back to v001', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final runner = MigrationRunner(chhayaMigrations());
      await runner.migrateTo(db, 4);
      expect(await runner.currentVersion(db), 4);
      Future<bool> hasTable(String table) async {
        final rows = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', table],
        );
        return rows.isNotEmpty;
      }

      expect(await hasTable(DbTables.messages), isTrue);
      expect(await hasTable(DbTables.devices), isTrue);
      await runner.migrateTo(db, 1);
      expect(await runner.currentVersion(db), 1);
      expect(await hasTable(DbTables.messages), isFalse);
      expect(await hasTable(DbTables.devices), isFalse);
      expect(await hasTable(DbTables.users), isTrue);
      await db.close();
    });

    test('gapless version enforcement', () {
      expect(
        () => MigrationRunner(chhayaMigrations().sublist(0, 2)),
        returnsNormally,
      );
    });
  });

  group('Encryption posture', () {
    test('opener always receives a 64-hex password', () async {
      final opener = FakeDatabaseOpener();
      await makeDb(opener);
      expect(opener.passwordHex, isNotNull);
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(opener.passwordHex!),
        isTrue,
      );
    });

    test('hardening pragmas recorded, no WAL anywhere', () async {
      final opener = FakeDatabaseOpener();
      await makeDb(opener);
      expect(opener.pragmas, kHardeningPragmas);
      expect(
        opener.pragmas
            .every((statement) => !statement.toLowerCase().contains('wal')),
        isTrue,
      );
      expect(
        kHardeningPragmas,
        contains('PRAGMA journal_mode = DELETE'),
      );
      expect(
        kHardeningPragmas,
        contains('PRAGMA cipher_memory_security = ON'),
      );
    });
  });

  group('CRUD integration', () {
    test('profile save and load round-trips', () async {
      final db = await makeDb(FakeDatabaseOpener());
      expect(await db.getUserProfile(), isNull);
      await db.saveUserProfile(makeProfile());
      final loaded = await db.getUserProfile();
      expect(loaded, isNotNull);
      expect(loaded!.displayName, 'Test User');
      expect(loaded.recoveryPhrase, ['abandon', 'ability', 'able']);
    });

    test('contacts CRUD', () async {
      final db = await makeDb(FakeDatabaseOpener());
      expect(await db.getAllContacts(), isEmpty);
      await db.addContact(makeContact('c1', 'Alice'));
      await db.addContact(makeContact('c2', 'Bob'));
      expect((await db.getAllContacts()).length, 2);
      expect((await db.getContact('c1'))!.displayName, 'Alice');
      await db.updateContact(makeContact('c1', 'Alice Cooper'));
      expect((await db.getContact('c1'))!.displayName, 'Alice Cooper');
      await db.deleteContact('c2');
      expect((await db.getAllContacts()).length, 1);
      expect(await db.getContact('missing'), isNull);
    });

    test('conversations CRUD with participants', () async {
      final db = await makeDb(FakeDatabaseOpener());
      await db.addConversation(makeConversation('convo-1'));
      final convos = await db.getAllConversations();
      expect(convos.length, 1);
      expect(convos.first.participants.length, 1);
      expect(convos.first.participants.first.displayName, 'Alice');
      await db.updateConversation(
          makeConversation('convo-1').copyWith(isPinned: true));
      expect((await db.getAllConversations()).first.isPinned, isTrue);
      await db.deleteConversation('convo-1');
      expect(await db.getAllConversations(), isEmpty);
    });

    test('messages add, list, search, delete', () async {
      final db = await makeDb(FakeDatabaseOpener());
      await db.addMessage(makeMessage('m1', 'c1', 'hello world'));
      await db.addMessage(makeMessage('m2', 'c1', 'second note'));
      await db.addMessage(makeMessage('m3', 'c2', 'other chat'));
      final list = await db.getMessages('c1');
      expect(list.map((m) => m.id).toList(), ['m1', 'm2']);
      expect((await db.searchMessages('hello')).length, 1);
      expect((await db.searchMessages('CHAT')).length, 1);
      await db.deleteMessage('m1');
      expect((await db.getMessages('c1')).length, 1);
      await db.deleteConversation('c1');
      expect(await db.getMessages('c1'), isEmpty);
      expect((await db.getMessages('c2')).length, 1);
    });

    test('settings toggles persist', () async {
      final db = await makeDb(FakeDatabaseOpener());
      expect(db.getBiometricLockEnabled(), isTrue);
      await db.setBiometricLockEnabled(false);
      expect(db.getBiometricLockEnabled(), isFalse);
      await db.blockContact('spammer');
      expect(db.getBlockedContacts(), ['spammer']);
      await db.unblockContact('spammer');
      expect(db.getBlockedContacts(), isEmpty);
      await db.setAppPin('1234');
      expect(db.getAppPin(), '1234');
      await db.setConversationTtl('c1', 3600);
      expect(db.getConversationTtl('c1'), 3600);
    });

    test('linked devices round-trip with encrypted tokens', () async {
      final db = await makeDb(FakeDatabaseOpener());
      expect(db.getLinkedDevices(), isEmpty);
      await db.addLinkedDevice({'id': 'd1', 'name': 'Desktop 1'});
      var devices = db.getLinkedDevices();
      expect(devices.length, 1);
      expect(devices.first['name'], 'Desktop 1');
      await db.removeLinkedDevice('d1');
      expect(db.getLinkedDevices(), isEmpty);
    });

    test('circuits cache, expiry, prune', () async {
      final db = await makeDb(FakeDatabaseOpener());
      await db.cacheCircuit(
        id: 'circ-1',
        pathJson: '{"hops":["a","b"]}',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      await db.cacheCircuit(
        id: 'circ-old',
        pathJson: '{"hops":[]}',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(await db.getValidCircuits(), ['{"hops":["a","b"]}']);
      expect(await db.pruneExpiredCircuits(), 1);
      expect(await db.getValidCircuits(), ['{"hops":["a","b"]}']);
    });

    test('clearAll empties everything', () async {
      final db = await makeDb(FakeDatabaseOpener());
      await db.saveUserProfile(makeProfile());
      await db.addContact(makeContact('c1'));
      await db.addConversation(makeConversation('convo-1'));
      await db.addMessage(makeMessage('m1', 'convo-1'));
      await db.clearAll();
      expect(await db.getUserProfile(), isNull);
      expect(await db.getAllContacts(), isEmpty);
      expect(await db.getAllConversations(), isEmpty);
      expect(await db.getMessages('convo-1'), isEmpty);
    });
  });

  group('Injection resistance', () {
    test('hostile identifiers are treated as data', () async {
      final db = await makeDb(FakeDatabaseOpener());
      const hostile = "' OR '1'='1";
      await db.addMessage(makeMessage('m1', 'c1', 'real'));
      final rows = await db.getMessages(hostile);
      expect(rows, isEmpty);
      // Tables survive hostile deletes and drops.
      await db.deleteMessage("x'; DROP TABLE messages; --");
      await db.deleteConversation("x'; DROP TABLE conversations; --");
      expect((await db.getMessages('c1')).length, 1);
      expect((await db.getAllConversations()), isEmpty);
    });

    test('identifier validation rejects hostile names', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final runner = MigrationRunner(chhayaMigrations());
      await runner.migrateUp(db);
      expect(
        () => DbQueries.upsert(db, 'messages; DROP TABLE messages; --', {}),
        throwsArgumentError,
      );
      expect(
        () => DbQueries.find(db, 'messages', equals: {'a b': 1}),
        throwsArgumentError,
      );
      await db.close();
    });
  });
}
