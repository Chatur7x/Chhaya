import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/crypto/ratchet/triple_ratchet.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/services/messaging/pq_hybrid_v1.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';

import '../../support/fake_prekey_server.dart';

/// In-memory opener for the LocalDatabase round-trip (mirrors the
/// Part 3 unit-test fake).
class _DbOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  }) async {
    if (passwordHex.isEmpty) {
      throw StateError('password required');
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

Future<LocalDatabase> _makeDb() async {
  sqfliteFfiInit();
  final keyManager = KeyManager(secureBackend: SecureStorageMock());
  await keyManager.storeChhayaId('codec-test-user');
  final db = LocalDatabase(
    keyManager: keyManager,
    opener: _DbOpener(),
    dbPath: inMemoryDatabasePath,
    secureStorage: SecureStorageMock(),
  );
  expect(await db.init(requireBiometric: false), isTrue);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePrekeyServer fakePrekeys;

  setUp(() {
    fakePrekeys = FakePrekeyServer();
    fakePrekeys.wireInto();
  });
  tearDown(() => PqHybridV1.resetForTest());

  Future<RatchetMessageCodec> codecFor(
    ChhayaKeyPair keyPair,
    String accountId,
  ) async {
    final account =
        await fakePrekeys.enroll(accountId, Uint8List.fromList(keyPair.publicKey));
    return RatchetMessageCodec(
      sessions: InMemorySessionStorage(),
      identity: keyPair,
      ownId: '05${keyPair.publicKeyHex}',
      ed25519PublicKey: () async => account.identityEd25519Public,
    );
  }

  Contact contactFor(ChhayaKeyPair keyPair, String id) => Contact(
        id: id,
        chhayaId: ChhayaId.fromPublicKey('05${keyPair.publicKeyHex}'),
        displayName: id,
        isVerified: true,
      );

  test(
      'two clients exchange authenticated messages, reject tampering and replay',
      () async {
    final a = await ChhayaCryptoEngine.generateKeyPair();
    final b = await ChhayaCryptoEngine.generateKeyPair();
    final alice = await codecFor(a, 'alice');
    final bob = await codecFor(b, 'bob');
    final ap = contactFor(a, 'alice');
    final bp = contactFor(b, 'bob');

    await expectLater(
      alice.encrypt(bp, '123e4567-e89b-42d3-a456-426655440000', 'failed', 'alice', {'content': 'not committed'},
          commit: (state, envelope) async {
            throw StateError('disk full');
          }),
      throwsStateError,
    );
    final encrypted =
        await alice.encrypt(bp, '123e4567-e89b-42d3-a456-426655440000', 'one', 'alice', {'content': 'hello'});
    expect(encrypted, isNot(contains('hello')));
    final damaged = jsonDecode(encrypted) as Map<String, dynamic>;
    final bytes = base64Decode(damaged['body'] as String);
    bytes[bytes.length - 1] ^= 1;
    damaged['body'] = base64Encode(bytes);
    await expectLater(bob.decrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'one', 'alice', jsonEncode(damaged)),
        throwsA(anything));
    await expectLater(
      bob.decrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'one', 'alice', encrypted,
          commit: (state, payload) async {
            throw StateError('database unavailable');
          }),
      throwsStateError,
    );
    expect((await bob.decrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'one', 'alice', encrypted))['content'],
        'hello');
    await expectLater(
        bob.decrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'one', 'alice', encrypted), throwsA(anything));
    final reply = await bob.encrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'two', 'bob', {'content': 'reply'});
    expect((await alice.decrypt(bp, '123e4567-e89b-42d3-a456-426655440000', 'two', 'bob', reply))['content'],
        'reply');
    final next =
        await alice.encrypt(bp, '123e4567-e89b-42d3-a456-426655440000', 'three', 'alice', {'content': 'bound metadata'});
    await expectLater(bob.decrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'wrong-id', 'alice', next),
        throwsA(anything));
    expect((await bob.decrypt(ap, '123e4567-e89b-42d3-a456-426655440000', 'three', 'alice', next))['content'],
        'bound metadata');
  });

  test('unverified contacts cannot start an encrypted session', () async {
    final a = await ChhayaCryptoEngine.generateKeyPair();
    final b = await ChhayaCryptoEngine.generateKeyPair();
    final codec = RatchetMessageCodec(
      sessions: InMemorySessionStorage(),
      identity: a,
      ownId: '05${a.publicKeyHex}',
    );
    final peer = Contact(
      id: 'bob',
      chhayaId: ChhayaId.fromPublicKey('05${b.publicKeyHex}'),
      displayName: 'Bob',
    );
    await expectLater(
      codec.encrypt(peer, '123e4567-e89b-42d3-a456-426655440000', 'id', 'alice', {'content': 'hello'}),
      throwsStateError,
    );
  });

  test('v1 decrypt under a legacy-retained session commits the advanced legacy state to the legacy slot, never the primary v2 slot', () async {
    final a = await ChhayaCryptoEngine.generateKeyPair();
    final b = await ChhayaCryptoEngine.generateKeyPair();
    final aid = '05${a.publicKeyHex}', bid = '05${b.publicKeyHex}';
    final accountA =
        await fakePrekeys.enroll('alice', Uint8List.fromList(a.publicKey));
    final accountB =
        await fakePrekeys.enroll('bob', Uint8List.fromList(b.publicKey));
    final db = await _makeDb();
    final ap = contactFor(a, 'alice');
    final bp = contactFor(b, 'bob');
    const conversation = '123e4567-e89b-42d3-a456-426655440099';
    // Each side stores the ratchet under the peer's chhayaId.
    final keyA = '$conversation:$bid'; // alice side
    final keyB = '$conversation:$aid'; // bob side
    final aliceStore = InMemorySessionStorage();
    final alice = RatchetMessageCodec(
      sessions: aliceStore,
      identity: a,
      ownId: aid,
      ed25519PublicKey: () async => accountA.identityEd25519Public,
    );
    final bob = RatchetMessageCodec(
      sessions: LocalDatabaseSessionStorage(db),
      identity: b,
      ownId: bid,
      database: db,
      ed25519PublicKey: () async => accountB.identityEd25519Public,
    );
    // Establish a v2 session; bob's primary slot then holds the v2 state.
    final v2Envelope = await alice.encrypt(
        bp, conversation, 'v2-1', 'alice', {'content': 'ping'});
    await bob.decrypt(ap, conversation, 'v2-1', 'alice', v2Envelope);
    final primaryBefore = await db.loadSessionBlob(keyB);
    expect(primaryBefore, isNotNull);
    // Seed a shared v1 session: alice keeps hers in memory, bob's is
    // retained under the legacy key (spec §3.11).
    final shared = Csprng.instance.bytes(32);
    final aKeys = await X25519Kex.generateKeyPair();
    final bKeys = await X25519Kex.generateKeyPair();
    final aliceV1 = await TripleRatchet.startSession(
      peer: bp.copyWith(id: keyA),
      remoteDhPublicKey: bKeys.publicKey,
      sharedSecret: shared,
      initiator: true,
      ourPrivateKey: aKeys.privateKey,
    );
    final bobV1 = await TripleRatchet.startSession(
      peer: ap.copyWith(id: keyB),
      remoteDhPublicKey: aKeys.publicKey,
      sharedSecret: shared,
      initiator: false,
      ourPrivateKey: bKeys.privateKey,
    );
    Csprng.wipe(shared);
    await aliceStore.saveSession(aliceV1);
    await db.saveSessionBlob(
        RatchetMessageCodec.legacyKey(keyB), jsonEncode(bobV1.toJson()));
    final v1Envelope = await alice.encrypt(
        bp, conversation, 'legacy-1', 'alice', {'content': 'hello legacy'});
    // Production-shaped commit: persists the ratchet under state.peerId.
    final decrypted = await bob.decrypt(
      ap,
      conversation,
      'legacy-1',
      'alice',
      v1Envelope,
      commit: (state, payload) => db.commitRatchetOnly(state),
    );
    expect(decrypted['content'], 'hello legacy');
    // The primary v2 slot is byte-identical; only the legacy slot advanced.
    expect(await db.loadSessionBlob(keyB), primaryBefore);
    final legacyRaw = await db.loadSessionBlob(RatchetMessageCodec.legacyKey(keyB));
    expect(legacyRaw, isNotNull);
    final legacy = SessionState.fromJson(
        jsonDecode(legacyRaw!) as Map<String, dynamic>);
    expect(legacy.recvCounter, greaterThan(0));
    await db.close();
  });

  test(
      'v2 decrypt hard-rejects a replayed establishment flight and writes no kv entries',
      () async {
    final a = await ChhayaCryptoEngine.generateKeyPair();
    final b = await ChhayaCryptoEngine.generateKeyPair();
    final aid = '05${a.publicKeyHex}', bid = '05${b.publicKeyHex}';
    final accountA =
        await fakePrekeys.enroll('alice', Uint8List.fromList(a.publicKey));
    final accountB =
        await fakePrekeys.enroll('bob', Uint8List.fromList(b.publicKey));
    final aliceDb = await _makeDb();
    final bobDb = await _makeDb();
    final ap = contactFor(a, 'alice');
    final bp = contactFor(b, 'bob');
    const conversation = '123e4567-e89b-42d3-a456-4266554400aa';
    final keyB = '$conversation:$aid'; // bob's kv slot for the session
    const genLow = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const genHigh = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    // Alice's pending restore carries the LOW generation, so her next v2
    // flight advertises it.
    await aliceDb.writePlainKv(
      LocalDatabase.resyncPendingKey(conversation),
      jsonEncode({
        'restoreGeneration': genLow,
        'reason': 'restore',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    // Bob's per-conversation marker already records a HIGHER generation and
    // his kv slot holds no session blob (state == null).
    await bobDb.writePlainKv(
      LocalDatabase.restoreGenerationKey(conversation),
      genHigh,
    );
    final alice = RatchetMessageCodec(
      sessions: InMemorySessionStorage(),
      identity: a,
      ownId: aid,
      database: aliceDb,
      ed25519PublicKey: () async => accountA.identityEd25519Public,
    );
    final bob = RatchetMessageCodec(
      sessions: LocalDatabaseSessionStorage(bobDb),
      identity: b,
      ownId: bid,
      database: bobDb,
      ed25519PublicKey: () async => accountB.identityEd25519Public,
    );
    final envelope = await alice.encrypt(
        bp, conversation, 'stale-1', 'alice', {'content': 'replay'});
    await expectLater(
      bob.decrypt(ap, conversation, 'stale-1', 'alice', envelope),
      throwsA(isA<FormatException>()),
    );
    // Zero kv writes: marker untouched, no restore bookkeeping, no session.
    expect(
      await bobDb.readPlainKv(LocalDatabase.restoreGenerationKey(conversation)),
      genHigh,
    );
    expect(await bobDb.readPlainKv(LocalDatabase.peerRestoredKey(conversation)),
        isNull);
    expect(await bobDb.readPlainKv(LocalDatabase.resyncPendingKey(conversation)),
        isNull);
    expect(await bobDb.readPlainKv(LocalDatabase.resyncResumeKey(conversation)),
        isNull);
    expect(
        await bobDb.readPlainKv(LocalDatabase.sessionGenerationKey(conversation)),
        isNull);
    expect(await bobDb.loadSessionBlob(keyB), isNull);
    await aliceDb.close();
    await bobDb.close();
  });

  test('prepared group wrappers advance only when the caller commits them', () async {
    final a = await ChhayaCryptoEngine.generateKeyPair();
    final b = await ChhayaCryptoEngine.generateKeyPair();
    final aid = '05${a.publicKeyHex}', bid = '05${b.publicKeyHex}';
    final accountA =
        await fakePrekeys.enroll('alice', Uint8List.fromList(a.publicKey));
    final accountB =
        await fakePrekeys.enroll('bob', Uint8List.fromList(b.publicKey));
    final aStore = InMemorySessionStorage();
    final bStore = InMemorySessionStorage();
    final alice = RatchetMessageCodec(
      sessions: aStore,
      identity: a,
      ownId: aid,
      ed25519PublicKey: () async => accountA.identityEd25519Public,
    );
    final bob = RatchetMessageCodec(
      sessions: bStore,
      identity: b,
      ownId: bid,
      ed25519PublicKey: () async => accountB.identityEd25519Public,
    );
    final ap = contactFor(a, 'alice');
    final bp = contactFor(b, 'bob');
    final prepared = await alice.prepareEncrypt(
        bp, '223e4567-e89b-42d3-a456-426655440001', 'message-1', 'alice', {'kind': 'key', 'key': 'secret'});
    expect(await aStore.loadSession(prepared.state.peerId), isNull);
    await aStore.saveSession(prepared.state);
    prepared.state.wipe();
    expect((await bob.decrypt(ap, '223e4567-e89b-42d3-a456-426655440001', 'message-1', 'alice', prepared.envelope))['key'],
        'secret');
  });
}
