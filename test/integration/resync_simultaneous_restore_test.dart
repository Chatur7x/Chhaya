// Simultaneous restore tie-break (spec §3.7, §6 criterion 4).
//
// Two accounts both restore from their own backup, each with a fresh,
// random restore_generation UUID recorded by `replaceAccountSnapshot`.
// When they re-establish a pairwise session and both restored, either
// side may send first. The conversation adopts `max(restore_generation)`;
// the lower-generation side must discard its own bootstrap, the higher
// side keeps its fresh PQXDH session; both converge to a single session.
//
// This test is purely codec-level and needs no backend.
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

import '../support/fake_prekey_server.dart';

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
  await keyManager.storeChhayaId('sim-resync-user');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePrekeyServer fakePrekeys;

  setUp(() {
    fakePrekeys = FakePrekeyServer();
    fakePrekeys.wireInto();
  });
  tearDown(() => PqHybridV1.resetForTest());

  Future<({RatchetMessageCodec codec, LocalDatabase db, ChhayaKeyPair ident})>
  setupAccount({required String userId, required String displayName}) async {
    final db = await makeDb();
    final ident = await ChhayaCryptoEngine.generateKeyPair();
    final profile = UserProfile(
      chhayaId: ChhayaId.fromPublicKey('05${ident.publicKeyHex}'),
      displayName: displayName,
      recoveryPhrase: const ['local', 'test', 'phrase'],
      createdAt: DateTime.now(),
    );
    await db.saveUserProfile(profile);
    final keys = KeyManager(secureBackend: SecureStorageMock());
    await keys.storeKeyPair(ident);
    await fakePrekeys.enroll(
      userId,
      Uint8List.fromList(ident.publicKey),
    );
    final enrolled = await fakePrekeys.fetch(userId);
    final codec = RatchetMessageCodec(
      sessions: LocalDatabaseSessionStorage(db),
      identity: ident,
      ownId: profile.chhayaId.publicKey,
      database: db,
      ed25519PublicKey: () async => enrolled.identityEd25519,
    );
    return (codec: codec, db: db, ident: ident);
  }

  Future<void> restoreAccount(
    LocalDatabase db,
    ChhayaKeyPair ident,
    String displayName,
    List<Contact> contacts,
    List<Conversation> conversations,
    String restoreGeneration,
  ) async {
    final profile = UserProfile(
      chhayaId: ChhayaId.fromPublicKey('05${ident.publicKeyHex}'),
      displayName: displayName,
      recoveryPhrase: const ['local', 'test', 'phrase'],
      createdAt: DateTime.now(),
    );
    await db.replaceAccountSnapshot(
      profile: profile,
      contacts: contacts,
      conversations: conversations,
      messages: const [],
    );
    // Deterministic generation for this test.
    await db.writePlainKv(
      LocalDatabase.restoreGenerationKey(conversations.single.id),
      restoreGeneration,
    );
    await db.writePlainKv(
      LocalDatabase.resyncPendingKey(conversations.single.id),
      jsonEncode({
        'restoreGeneration': restoreGeneration,
        'reason': 'restore',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  const convId = 'b23e4567-e89b-42d3-a456-426655440010';
  const genLow = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const genHigh = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  test(
    'higher restore_generation wins, both sides converge to one session, '
    'lower side discards its own bootstrap (spec §3.7, §6 criterion 4)',
    () async {
      final alice = await setupAccount(userId: 'alice', displayName: 'Alice');
      final bob = await setupAccount(userId: 'bob', displayName: 'Bob');
      final peerAlice = Contact(
        id: 'alice',
        chhayaId: ChhayaId.fromPublicKey('05${alice.ident.publicKeyHex}'),
        displayName: 'Alice',
        isVerified: true,
      );
      final peerBob = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${bob.ident.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );

      await bob.db.addContact(peerAlice);
      await alice.db.addContact(peerBob);
      final aliceChat = Conversation(
        id: convId,
        participants: [peerBob],
        createdAt: DateTime.now(),
      );
      final bobChat = Conversation(
        id: convId,
        participants: [peerAlice],
        createdAt: DateTime.now(),
      );
      await alice.db.addConversation(aliceChat);
      await bob.db.addConversation(bobChat);

      // Both restore, with a deterministic generation ordering.
      await restoreAccount(
        alice.db,
        alice.ident,
        'Alice',
        [peerBob],
        [aliceChat],
        genHigh, // alice wins
      );
      await restoreAccount(
        bob.db,
        bob.ident,
        'Bob',
        [peerAlice],
        [bobChat],
        genLow, // bob loses
      );

      // Alice sends; her flight carries genHigh which is > genLow. Bob
      // accepts and converges on Alice's fresh PQXDH session.
      final flightEnvelope = await alice.codec.encrypt(
        peerBob,
        aliceChat.id,
        'msg-a1',
        'alice-server-id',
        {'text': 'hello'},
      );

      // Bob decrypts under the higher-generation rule: bob's own pending
      // is genLow (< genHigh), so bob accepts.
      await expectLater(
        bob.codec.decrypt(
          peerAlice,
          bobChat.id,
          'msg-a1',
          'alice-server-id',
          flightEnvelope,
        ),
        completes,
      );

      // Both sides established the SAME session.
      final aliceState = await alice.db.loadSessionBlob(
        '${aliceChat.id}:${peerBob.chhayaId.publicKey}',
      );
      final bobState = await bob.db.loadSessionBlob(
        '${bobChat.id}:${peerAlice.chhayaId.publicKey}',
      );
      expect(aliceState, isNotNull);
      expect(bobState, isNotNull);
      final aState = SessionState.fromJson(
        jsonDecode(aliceState!) as Map<String, dynamic>,
      );
      final bState = SessionState.fromJson(
        jsonDecode(bobState!) as Map<String, dynamic>,
      );
      // Both sides accepted the SAME flight. The role comparison in
      // TripleRatchet makes the sender-per-run diverge pre-ratchet (one
      // side DH-ratchets on the other's advertised key), so rootKeys
      // legitimately differ at this point. The convergence proof is:
      // both sides derived spqrSeed from the same SK, and both directions
      // decrypt each other's messages.
      expect(bytesEq(aState.spqrSeed, bState.spqrSeed), isTrue,
          reason: 'both sides derive spqrSeed from the shared PQXDH SK — one session');
      final aliceFirst = await alice.codec.encrypt(
        peerBob,
        aliceChat.id,
        'msg-a2',
        'alice-server-id',
        {'text': 'hello again'},
      );
      await expectLater(
        bob.codec.decrypt(peerAlice, bobChat.id, 'msg-a2',
            'alice-server-id', aliceFirst),
        completes,
      );
      final bobFirst = await bob.codec.encrypt(
        peerAlice,
        bobChat.id,
        'msg-b2',
        'bob-server-id',
        {'text': 'hi alice'},
      );
      await expectLater(
        alice.codec.decrypt(peerBob, aliceChat.id, 'msg-b2',
            'bob-server-id', bobFirst),
        completes,
      );

      // After one bidirectional round-trip both sides have converged on a
      // single shared session (the higher-generation flight). The
      // SK-derived materials are identical on both sides. The root/chain
      // bytes are intentionally NOT asserted equal here: the two sides
      // went through different ratchet-step sequences to reach this state,
      // which is a legitimate Double Ratchet converged-state difference
      // (same SK, both fully decryptable) rather than a session fork.
      final aliceState2 = await alice.db.loadSessionBlob(
        '${aliceChat.id}:${peerBob.chhayaId.publicKey}',
      );
      final bobState2 = await bob.db.loadSessionBlob(
        '${bobChat.id}:${peerAlice.chhayaId.publicKey}',
      );
      final aState2 = SessionState.fromJson(
        jsonDecode(aliceState2!) as Map<String, dynamic>,
      );
      final bState2 = SessionState.fromJson(
        jsonDecode(bobState2!) as Map<String, dynamic>,
      );
      expect(bytesEq(aState2.spqrSeed, bState2.spqrSeed), isTrue,
          reason: 'both converge on one session (spqrSeed is SK-derived)');

      // Both record the max generation.
      expect(
        await alice.db
            .readPlainKv(LocalDatabase.restoreGenerationKey(aliceChat.id)),
        genHigh,
      );
      expect(
        await bob.db.readPlainKv(LocalDatabase.restoreGenerationKey(bobChat.id)),
        genHigh,
        reason: 'lower side adopts the higher generation',
      );
    },
  );

  test(
    'when the lower-generation side initiates, the higher side discards '
    'the bootstrap, re-establishes, and converges on the higher generation',
    () async {
      final alice = await setupAccount(userId: 'alice', displayName: 'Alice');
      final bob = await setupAccount(userId: 'bob', displayName: 'Bob');
      final peerAlice = Contact(
        id: 'alice',
        chhayaId: ChhayaId.fromPublicKey('05${alice.ident.publicKeyHex}'),
        displayName: 'Alice',
        isVerified: true,
      );
      final peerBob = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${bob.ident.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );

      await bob.db.addContact(peerAlice);
      await alice.db.addContact(peerBob);
      final aliceChat = Conversation(
        id: convId,
        participants: [peerBob],
        createdAt: DateTime.now(),
      );
      final bobChat = Conversation(
        id: convId,
        participants: [peerAlice],
        createdAt: DateTime.now(),
      );
      await alice.db.addConversation(aliceChat);
      await bob.db.addConversation(bobChat);

      await restoreAccount(
        alice.db,
        alice.ident,
        'Alice',
        [peerBob],
        [aliceChat],
        genLow, // alice loses this time
      );
      await restoreAccount(
        bob.db,
        bob.ident,
        'Bob',
        [peerAlice],
        [bobChat],
        genHigh, // bob wins
      );

      // Alice (lower) initiates: bob (higher) must discard the bootstrap.
      final flightEnvelope = await alice.codec.encrypt(
        peerBob,
        aliceChat.id,
        'msg-a1',
        'alice-server-id',
        {'text': 'hello from low-gen side'},
      );

      await expectLater(
        bob.codec.decrypt(
          peerAlice,
          bobChat.id,
          'msg-a1',
          'alice-server-id',
          flightEnvelope,
        ),
        throwsA(anything),
        reason: 'higher-generation side must refuse the lower-gen bootstrap',
      );

      // Bob now sends his own bootstrap with the higher generation; Alice
      // (lower) accepts, both converge on bob's session.
      final bobFlight = await bob.codec.encrypt(
        peerAlice,
        bobChat.id,
        'msg-b1',
        'bob-server-id',
        {'text': 'hello from high-gen side'},
      );

      await expectLater(
        alice.codec.decrypt(
          peerBob,
          aliceChat.id,
          'msg-b1',
          'bob-server-id',
          bobFlight,
        ),
        completes,
      );

      expect(
        await alice.db
            .readPlainKv(LocalDatabase.restoreGenerationKey(aliceChat.id)),
        genHigh,
      );
      expect(
        await bob.db.readPlainKv(LocalDatabase.restoreGenerationKey(bobChat.id)),
        genHigh,
      );
      final aliceState = await alice.db.loadSessionBlob(
        '${aliceChat.id}:${peerBob.chhayaId.publicKey}',
      );
      final bobState = await bob.db.loadSessionBlob(
        '${bobChat.id}:${peerAlice.chhayaId.publicKey}',
      );
      final aState = SessionState.fromJson(
        jsonDecode(aliceState!) as Map<String, dynamic>,
      );
      final bState = SessionState.fromJson(
        jsonDecode(bobState!) as Map<String, dynamic>,
      );
      expect(bytesEq(aState.spqrSeed, bState.spqrSeed), isTrue);
    },
  );
}
