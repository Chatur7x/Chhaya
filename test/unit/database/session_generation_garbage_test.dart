// Fail-closed parsing of the session_generation dual-store (spec §3.8, F4).
//
// A non-null raw kv or keystore value that does not parse to an integer in
// int64 range [0, 2^63-1] is corrupt and MUST classify as `rollback` —
// never `fresh`, never silently absent. Valid values keep their behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';

class FakeDatabaseOpener implements DatabaseOpener {
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
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
  }
}

const conversationId = 'a23e4567-e89b-42d3-a456-426655440010';

Future<({LocalDatabase db, SecureStorageMock secure})> makeDb({
  SecureStorageMock? secureStorage,
}) async {
  sqfliteFfiInit();
  final keyManager = KeyManager(secureBackend: SecureStorageMock());
  await keyManager.storeChhayaId('garbage-user');
  final secure = secureStorage ?? SecureStorageMock();
  final db = LocalDatabase(
    keyManager: keyManager,
    opener: FakeDatabaseOpener(),
    dbPath: inMemoryDatabasePath,
    secureStorage: secure,
  );
  expect(await db.init(requireBiometric: false), isTrue);
  return (db: db, secure: secure);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('(a) garbage kv + missing keystore => rollback', () async {
    final (:db, secure: _) = await makeDb();
    addTearDown(db.close);
    await db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), 'not-a-number');
    expect(await db.sessionGenerationState(conversationId), 'rollback');
    final pair = await db.readSessionGenerationPair(conversationId);
    expect(pair.db, isNull);
    expect(pair.keystore, isNull);
    expect(pair.dbCorrupt, isTrue);
  });

  test('(b) garbage kv + valid keystore => rollback', () async {
    final (:db, secure: _) = await makeDb();
    addTearDown(db.close);
    await db.writeSessionGeneration(conversationId, 4);
    await db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), 'not-a-number');
    final pair = await db.readSessionGenerationPair(conversationId);
    expect(pair.db, isNull);
    expect(pair.dbCorrupt, isTrue);
    expect(pair.keystore, 4);
    expect(await db.sessionGenerationState(conversationId), 'rollback');
  });

  test('(c) garbage keystore + valid kv => rollback', () async {
    final (:db, secure: secure) = await makeDb();
    addTearDown(db.close);
    await db.writeSessionGeneration(conversationId, 4);
    await secure.write(key: 'session_generation.$conversationId', value: 'garbage!!');
    final pair = await db.readSessionGenerationPair(conversationId);
    expect(pair.keystore, isNull);
    expect(pair.keystoreCorrupt, isTrue);
    expect(pair.db, 4);
    expect(await db.sessionGenerationState(conversationId), 'rollback');
  });

  test('(d) both garbage => rollback', () async {
    final (:db, secure: secure) = await makeDb();
    addTearDown(db.close);
    await db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), 'xyz');
    await secure.write(key: 'session_generation.$conversationId', value: '12.5');
    final pair = await db.readSessionGenerationPair(conversationId);
    expect(pair.dbCorrupt, isTrue);
    expect(pair.keystoreCorrupt, isTrue);
    expect(await db.sessionGenerationState(conversationId), 'rollback');
  });

  for (final overflow in ['18446744073709551615', '9223372036854775808']) {
    test('(e) int64-overflow-looking value "$overflow" => corrupt/rollback', () async {
      // kv overflow, keystore absent.
      final a = await makeDb();
      addTearDown(a.db.close);
      await a.db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), overflow);
      expect(await a.db.sessionGenerationState(conversationId), 'rollback');
      expect((await a.db.readSessionGenerationPair(conversationId)).dbCorrupt, isTrue);

      // both stores overflow.
      final b = await makeDb();
      addTearDown(b.db.close);
      await b.db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), overflow);
      await b.secure.write(key: 'session_generation.$conversationId', value: overflow);
      expect(await b.db.sessionGenerationState(conversationId), 'rollback');
      final pairB = await b.db.readSessionGenerationPair(conversationId);
      expect(pairB.dbCorrupt, isTrue);
      expect(pairB.keystoreCorrupt, isTrue);
      expect(pairB.db, isNull);
      expect(pairB.keystore, isNull);

      // keystore overflow, kv valid.
      final c = await makeDb();
      addTearDown(c.db.close);
      await c.db.writeSessionGeneration(conversationId, 7);
      await c.secure.write(key: 'session_generation.$conversationId', value: overflow);
      expect(await c.db.sessionGenerationState(conversationId), 'rollback');
    });
  }

  test('negative / decimal / signed garbage is corrupt, never fresh', () async {
    for (final raw in ['-1', '1.5', '+3', '0x10', '  ', '١٢٣']) {
      final (:db, secure: _) = await makeDb();
      addTearDown(db.close);
      await db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), raw);
      expect(
        await db.sessionGenerationState(conversationId),
        'rollback',
        reason: 'raw "$raw" must fail closed',
      );
    }
  });

  test('boundary: int64 max (9223372036854775807) is valid; ok when mirrored', () async {
    final (:db, secure: secure) = await makeDb();
    addTearDown(db.close);
    await db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), '9223372036854775807');
    await secure.write(key: 'session_generation.$conversationId', value: '9223372036854775807');
    final pair = await db.readSessionGenerationPair(conversationId);
    expect(pair.db, 9223372036854775807);
    expect(pair.keystore, 9223372036854775807);
    expect(pair.dbCorrupt, isFalse);
    expect(pair.keystoreCorrupt, isFalse);
    expect(await db.sessionGenerationState(conversationId), 'ok');
  });

  test('valid values keep existing behavior (fresh / ok / mismatch rollback)', () async {
    final (:db, secure: _) = await makeDb();
    addTearDown(db.close);
    expect(await db.sessionGenerationState(conversationId), 'fresh');
    await db.writeSessionGeneration(conversationId, 5);
    expect(await db.sessionGenerationState(conversationId), 'ok');
    await db.writePlainKv(LocalDatabase.sessionGenerationKey(conversationId), '6');
    expect(await db.sessionGenerationState(conversationId), 'rollback');
  });
}
