// Rollback detection and forced resync via the session_generation dual-store
// (spec §3.8, §6 criterion 7).
//
// `session_generation` is dual-stored in SQLCipher kv and in the platform
// keystore (`session_generation.<conversationId>`), written keystore-first.
// Any mismatch or one-sided presence means the client must refuse to use
// the stale session and force a resync — never adopt the lower value.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/messaging/pq_hybrid_v1.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';

import '../../support/fake_prekey_server.dart';

class FakeDatabaseOpener implements DatabaseOpener {
  String? passwordHex;
  Database? opened;

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
        singleInstance: false,
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
    opened = db;
    return db;
  }
}

Future<LocalDatabase> makeDb() async {
  sqfliteFfiInit();
  final keyManager = KeyManager(secureBackend: SecureStorageMock());
  await keyManager.storeChhayaId('rollback-user');
  final db = LocalDatabase(
    keyManager: keyManager,
    opener: FakeDatabaseOpener(),
    dbPath: inMemoryDatabasePath,
    secureStorage: SecureStorageMock(),
  );
  expect(await db.init(requireBiometric: false), isTrue);
  return db;
}

bool bytesEq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<LocalDatabase> setupDbWithProfile(String displayName) async {
  final db = await makeDb();
  final ident = await ChhayaCryptoEngine.generateKeyPair();
  await db.saveUserProfile(
    UserProfile(
      chhayaId: ChhayaId.fromPublicKey('05${ident.publicKeyHex}'),
      displayName: displayName,
      recoveryPhrase: const ['local', 'test', 'phrase'],
      createdAt: DateTime.now(),
    ),
  );
  final keys = KeyManager(secureBackend: SecureStorageMock());
  await keys.storeKeyPair(ident);
  return db;
}

Future<
    ({
      LocalDatabase db,
      RatchetMessageCodec codec,
      ChhayaKeyPair ident,
      Contact peerB,
    })> setupWithPeer(FakePrekeyServer fakePrekeys, String displayName) async {
  final db = await makeDb();
  final ident = await ChhayaCryptoEngine.generateKeyPair();
  await db.saveUserProfile(
    UserProfile(
      chhayaId: ChhayaId.fromPublicKey('05${ident.publicKeyHex}'),
      displayName: displayName,
      recoveryPhrase: const ['local', 'test', 'phrase'],
      createdAt: DateTime.now(),
    ),
  );
  final keys = KeyManager(secureBackend: SecureStorageMock());
  await keys.storeKeyPair(ident);
  final bob = await ChhayaCryptoEngine.generateKeyPair();
  final peerB = Contact(
    id: 'bob',
    chhayaId: ChhayaId.fromPublicKey('05${bob.publicKeyHex}'),
    displayName: 'Bob',
    isVerified: true,
  );
  final conversation = Conversation(
    id: 'a23e4567-e89b-42d3-a456-426655440009',
    participants: [peerB],
    createdAt: DateTime.now(),
  );
  await db.addContact(peerB);
  await db.addConversation(conversation);
  await fakePrekeys.enroll('bob', Uint8List.fromList(bob.publicKey));
  final enrolled = await fakePrekeys.fetch('bob');
  final codec = RatchetMessageCodec(
    sessions: LocalDatabaseSessionStorage(db),
    identity: ident,
    ownId: ChhayaId.fromPublicKey('05${ident.publicKeyHex}').publicKey,
    database: db,
    ed25519PublicKey: () async => enrolled.identityEd25519,
  );
  return (db: db, codec: codec, ident: ident, peerB: peerB);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePrekeyServer fakePrekeys;

  setUp(() {
    fakePrekeys = FakePrekeyServer();
    fakePrekeys.wireInto();
  });
  tearDown(() => PqHybridV1.resetForTest());

  test('consistent stores read ok; never-written reads fresh', () async {
    final db = await setupDbWithProfile('Alice');
    addTearDown(db.close);
    expect(await db.sessionGenerationState('a23e4567-e89b-42d3-a456-426655440009'), 'fresh');
    await db.writeSessionGeneration('a23e4567-e89b-42d3-a456-426655440009', 1);
    expect((await db.readSessionGenerationPair('a23e4567-e89b-42d3-a456-426655440009')).db, 1);
    expect((await db.readSessionGenerationPair('a23e4567-e89b-42d3-a456-426655440009')).keystore, 1);
    expect(await db.sessionGenerationState('a23e4567-e89b-42d3-a456-426655440009'), 'ok');
  });

  test(
    'a stale SQLCipher copy with an advanced keystore forces resync '
    '(DB rolled back behind the keystore)',
    () async {
      final db = await setupDbWithProfile('Alice');
      addTearDown(db.close);
      await db.writeSessionGeneration('a23e4567-e89b-42d3-a456-426655440009', 4);
      // Simulate a DB-only restore: SQLCipher present but older than
      // the keystore copy.
      await db.writePlainKv(LocalDatabase.sessionGenerationKey('a23e4567-e89b-42d3-a456-426655440009'), '2');
      expect(await db.sessionGenerationState('a23e4567-e89b-42d3-a456-426655440009'), 'rollback');
    },
  );

  test(
    'a missing SQLCipher value with an advanced keystore forces resync',
    () async {
      final db = await setupDbWithProfile('Alice');
      addTearDown(db.close);
      await db.writeSessionGeneration('a23e4567-e89b-42d3-a456-426655440009', 4);
      await db.deletePlainKv(LocalDatabase.sessionGenerationKey('a23e4567-e89b-42d3-a456-426655440009'));
      expect(await db.sessionGenerationState('a23e4567-e89b-42d3-a456-426655440009'), 'rollback');
    },
  );

  test(
    'rollback on the decrypt path refuses to decrypt, deletes the stale '
    'session and marks the conversation for resync',
    () async {
      final setup = await setupWithPeer(fakePrekeys, 'Alice');
      final db = setup.db;
      addTearDown(db.close);
      final key = 'a23e4567-e89b-42d3-a456-426655440009:${setup.peerB.chhayaId.publicKey}';
      final envelope = await setup.codec.encrypt(
        setup.peerB,
        'a23e4567-e89b-42d3-a456-426655440009',
        'msg-1',
        'alice-server-id',
        {'text': 'hello'},
      );
      expect(await db.loadSessionBlob(key), isNotNull);
      await db.writeSessionGeneration('a23e4567-e89b-42d3-a456-426655440009', 4);

      // A DB-only flash restore: SQLCipher present but far behind.
      await db.writePlainKv(LocalDatabase.sessionGenerationKey('a23e4567-e89b-42d3-a456-426655440009'), '0');
      expect(await db.sessionGenerationState('a23e4567-e89b-42d3-a456-426655440009'), 'rollback');

      await expectLater(
        setup.codec.decrypt(
          setup.peerB,
          'a23e4567-e89b-42d3-a456-426655440009',
          'msg-1',
          'alice-server-id',
          envelope,
        ),
        throwsA(anything),
      );
      expect(await db.loadSessionBlob(key), isNull,
          reason: 'rollback forces resync; the stale session is deleted');
      expect(
        await db.readPlainKv(LocalDatabase.resyncPendingKey('a23e4567-e89b-42d3-a456-426655440009')),
        isNotNull,
        reason: 'rollback marks the conversation resync-pending',
      );
    },
  );

  test(
    'forced resync after rollback re-establishes a fresh session rather '
    'than adopting stale state',
    () async {
      final setup = await setupWithPeer(fakePrekeys, 'Alice');
      final db = setup.db;
      addTearDown(db.close);
      final key = 'a23e4567-e89b-42d3-a456-426655440009:${setup.peerB.chhayaId.publicKey}';
      await setup.codec.encrypt(
        setup.peerB,
        'a23e4567-e89b-42d3-a456-426655440009',
        'msg-1',
        'alice-server-id',
        {'text': 'hi'},
      );
      final before = SessionState.fromJson(
        jsonDecode((await db.loadSessionBlob(key))!) as Map<String, dynamic>,
      );

      // Simulate a DB-only flash restore.
      await db.writeSessionGeneration('a23e4567-e89b-42d3-a456-426655440009', 4);
      await db.writePlainKv(LocalDatabase.sessionGenerationKey('a23e4567-e89b-42d3-a456-426655440009'), '0');

      await setup.codec.encrypt(
        setup.peerB,
        'a23e4567-e89b-42d3-a456-426655440009',
        'msg-2',
        'alice-server-id',
        {'text': 'again'},
      );
      final after = SessionState.fromJson(
        jsonDecode((await db.loadSessionBlob(key))!) as Map<String, dynamic>,
      );
      expect(bytesEq(before.rootKey, after.rootKey), isFalse);
      expect(
        bytesEq(
          before.transcript ?? Uint8List(0),
          after.transcript ?? Uint8List(0),
        ),
        isFalse,
      );
    },
  );
}
