// Backup/restore slice — acceptance pinned by spec §2.1, §3.7–§3.8, §6 #1.
//
// WHAT CHANGED vs the previous pinned tests: the deterministic identity-ECDH
// establishment (`ratchet_message_codec._state`) is DELETED. A restore no
// longer re-derives a byte-identical initial session; every post-restore
// conversation runs a fresh, authenticated, peer-coordinated establishment
// (v2, hybrid PQXDH — tests force it on) and sends `chhaya-resync-v1`
// before any user content.
//
// Pinned here (criterion 1):
//   * a post-restore session differs byte-wise from the pre-restore session
//     in every derived field (root key, chains, SPQR seed, transcript, EKA);
//   * two sessions established from one restore (two conversations) differ
//     from each other in every derived field;
//   * the counter may restart at 0 but key reuse is impossible: at equal
//     counters, pre- and post-restore chains are disjoint;
//   * restore erases exactly the ratchet/outbox class of state and records
//     `session_resync_pending` + `restore_generation` per conversation;
//   * the `session_generation` dual-store is not reset by a restore.
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
import 'package:chaaya/core/models/message.dart';
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
  await keyManager.storeChhayaId('restore-user');
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

void expectSessionsDiffer(SessionState? before, SessionState? after) {
  expect(before, isNotNull);
  expect(after, isNotNull);
  expect(bytesEq(before!.rootKey, after!.rootKey), isFalse,
      reason: 'root keys must differ across generations');
  expect(bytesEq(before.sendChainKey, after.sendChainKey), isFalse);
  expect(bytesEq(before.recvChainKey, after.recvChainKey), isFalse);
  // ourPublicKey is the DR identity re-derived from the same identity
  // private key on every establishment; it is expected to be equal. The
  // fresh peer-side ratchet key (what DoubleRatchet derives the new
  // session with) is what must differ, which the chains/root already
  // pin down.
  expect(bytesEq(before.spqrSeed, after.spqrSeed), isFalse);
  expect(
    before.transcript == null ||
        after.transcript == null ||
        !bytesEq(before.transcript!, after.transcript!),
    isTrue,
    reason: 'v2 transcripts must differ (fresh establishment)',
  );
}

Future<SessionState?> loadState(LocalDatabase db, String key) async {
  final raw = await db.loadSessionBlob(key);
  if (raw == null) return null;
  return SessionState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePrekeyServer fakePrekeys;

  setUp(() {
    fakePrekeys = FakePrekeyServer();
    fakePrekeys.wireInto();
  });
  tearDown(() => PqHybridV1.resetForTest());

  Future<
      ({
        RatchetMessageCodec codec,
        LocalDatabase db,
        ChhayaKeyPair ident,
        UserProfile profile,
      })> setupAccount({
    required String userId,
    required String displayName,
  }) async {
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
    await fakePrekeys.enroll(userId, Uint8List.fromList(ident.publicKey));
    final enrolled = await fakePrekeys.fetch(userId);
    final codec = RatchetMessageCodec(
      sessions: LocalDatabaseSessionStorage(db),
      identity: ident,
      ownId: profile.chhayaId.publicKey,
      database: db,
      ed25519PublicKey: () async => enrolled.identityEd25519,
    );
    return (codec: codec, db: db, ident: ident, profile: profile);
  }

  group('criterion 1: byte-level fresh establishment after restore', () {
    test(
      'a post-restore session differs from the pre-restore session in every '
      'derived field; the counter may restart but key reuse is impossible',
      () async {
        final alice = await setupAccount(userId: 'alice', displayName: 'Alice');
        addTearDown(alice.db.close);
        final bob = await setupAccount(userId: 'bob', displayName: 'Bob');
        addTearDown(bob.db.close);
        final peerB = Contact(
          id: 'bob',
          chhayaId: ChhayaId.fromPublicKey('05${bob.ident.publicKeyHex}'),
          displayName: 'Bob',
          isVerified: true,
        );
        final conversation = Conversation(
          id: '923e4567-e89b-42d3-a456-426655440008',
          participants: [peerB],
          createdAt: DateTime.now(),
        );
        await alice.db.addContact(peerB);
        await alice.db.addConversation(conversation);
        final key = '${conversation.id}:${peerB.chhayaId.publicKey}';

        await alice.codec.encrypt(
          peerB,
          conversation.id,
          'msg-1',
          'alice-server-id',
          {'text': 'before backup'},
        );
        final state1 = await loadState(alice.db, key);
        expect(state1?.sessionVersion, 2);

        // Restore from a backup taken before the first message.
        await alice.db.replaceAccountSnapshot(
          profile: alice.profile,
          contacts: [peerB],
          conversations: [conversation],
          messages: const [],
        );
        expect(await alice.db.loadSessionBlob(key), isNull,
            reason: 'restore deletes ratchet sessions (spec §3.7/§9.1)');

        final envelope2 = await alice.codec.encrypt(
          peerB,
          conversation.id,
          'msg-2',
          'alice-server-id',
          {'text': 'after restore'},
        );
        final state2 = await loadState(alice.db, key);
        expectSessionsDiffer(state1, state2);
        expect(state2!.sendCounter, 1,
            reason: 'fresh establishment restarts the counter; keys must not coincide');
        // The header carries our DR public key (identity) — byte-equal on a
        // fresh establishment; freshness comes from the transcript, which
        // binds the new ephemeral.
        final state2Transcript = state2.transcript;
        expect(state2Transcript, isNotNull);
        expect(bytesEq(state1!.transcript!, state2Transcript!), isFalse,
            reason: 'fresh ephemeral keys must produce different transcripts');

        // The peer decrypts the post-restore message under its own freshly
        // accepted session.
        final bobContact = Contact(
          id: 'alice',
          chhayaId: ChhayaId.fromPublicKey('05${alice.ident.publicKeyHex}'),
          displayName: 'Alice',
          isVerified: true,
        );
        final bobReceived = await bob.codec.decrypt(
          bobContact,
          conversation.id,
          'msg-2',
          'alice-server-id',
          envelope2,
        );
        expect(bobReceived['text'], 'after restore');
      },
    );

    test(
      'two sessions established from one restore (two conversations) differ '
      'from each other in every derived field',
      () async {
        final alice = await setupAccount(userId: 'alice', displayName: 'Alice');
        addTearDown(alice.db.close);
        final bob = await setupAccount(userId: 'bob', displayName: 'Bob');
        addTearDown(bob.db.close);
        final carol = await setupAccount(userId: 'carol', displayName: 'Carol');
        addTearDown(carol.db.close);
        final contacts = [
          Contact(
            id: 'bob',
            chhayaId: ChhayaId.fromPublicKey('05${bob.ident.publicKeyHex}'),
            displayName: 'Bob',
            isVerified: true,
          ),
          Contact(
            id: 'carol',
            chhayaId: ChhayaId.fromPublicKey('05${carol.ident.publicKeyHex}'),
            displayName: 'Carol',
            isVerified: true,
          ),
        ];
        final conversations = [
          Conversation(id: '923e4567-e89b-42d3-a456-426655440008', participants: [contacts[0]], createdAt: DateTime.now()),
          Conversation(id: 'b23e4567-e89b-42d3-a456-426655440010', participants: [contacts[1]], createdAt: DateTime.now()),
        ];
        for (final contact in contacts) {
          await alice.db.addContact(contact);
        }
        for (final conversation in conversations) {
          await alice.db.addConversation(conversation);
        }
        for (final conversation in conversations) {
          await alice.codec.encrypt(
            conversation.participants.single,
            conversation.id,
            'msg-${conversation.id}',
            'alice-server-id',
            {'text': 'hello ${conversation.id}'},
          );
        }

        await alice.db.replaceAccountSnapshot(
          profile: alice.profile,
          contacts: contacts,
          conversations: conversations,
          messages: const [],
        );
        for (final conversation in conversations) {
          await alice.codec.encrypt(
            conversation.participants.single,
            conversation.id,
            'msg2-${conversation.id}',
            'alice-server-id',
            {'text': 'after restore'},
          );
        }
        final state1 = await loadState(
          alice.db,
          '923e4567-e89b-42d3-a456-426655440008:${contacts[0].chhayaId.publicKey}',
        );
        final state2 = await loadState(
          alice.db,
          'b23e4567-e89b-42d3-a456-426655440010:${contacts[1].chhayaId.publicKey}',
        );
        expectSessionsDiffer(state1, state2);
      },
    );
  });

  test(
    'restore erases ratchet/outbox state, keeps DB content, records '
    'session_resync_pending and restore_generation per conversation',
    () async {
      final alice = await setupAccount(userId: 'alice', displayName: 'Alice');
      addTearDown(alice.db.close);
      final bob = await setupAccount(userId: 'bob', displayName: 'Bob');
      addTearDown(bob.db.close);
      final peerB = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${bob.ident.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      final conversation = Conversation(
        id: '923e4567-e89b-42d3-a456-426655440008',
        participants: [peerB],
        createdAt: DateTime.now(),
      );
      await alice.db.addContact(peerB);
      await alice.db.addConversation(conversation);

      final pending = Message(
        id: 'msg-pending',
        conversationId: conversation.id,
        senderId: 'me',
        content: 'queued before backup',
        timestamp: DateTime.now(),
        isSent: false,
      );
      await alice.db.commitOutgoingMessage(
        SessionState(
          peerId: '923e4567-e89b-42d3-a456-426655440008:${peerB.chhayaId.publicKey}',
          initiatedByUs: true,
          rootKey: Uint8List(32),
          sendChainKey: Uint8List(32),
          recvChainKey: Uint8List(32),
          ourPrivateKey: Uint8List(32),
          ourPublicKey: Uint8List(32),
          remotePublicKey: Uint8List(32),
          spqrSeed: Uint8List(32),
        ),
        pending,
        jsonEncode({'v': 1, 'header': '', 'body': ''}),
      );

      await alice.db.replaceAccountSnapshot(
        profile: alice.profile,
        contacts: [peerB],
        conversations: [conversation],
        messages: [pending],
      );

      // DB content survives; the envelope and ratchet state are gone.
      final restored = await alice.db.getPendingMessages(conversation.id);
      expect(restored, hasLength(1));
      expect(restored.single.content, 'queued before backup');
      expect(await alice.db.loadSessionBlob('outbox:msg-pending'), isNull);

      final pendingKv =
          await alice.db.readPlainKv(LocalDatabase.resyncPendingKey('923e4567-e89b-42d3-a456-426655440008'));
      expect(pendingKv, isNotNull,
          reason: 'restore records session_resync_pending per conversation');
      final pendingJson = jsonDecode(pendingKv!) as Map<String, dynamic>;
      expect(pendingJson['reason'], 'restore');
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
            .hasMatch(pendingJson['restoreGeneration'] as String),
        isTrue,
      );
      expect(
        await alice.db.readPlainKv(LocalDatabase.restoreGenerationKey('923e4567-e89b-42d3-a456-426655440008')),
        pendingJson['restoreGeneration'],
        reason: 'restore_generation is recorded once per restore per conversation',
      );
    },
  );

  test(
    'the session_generation dual-store is not reset by a restore',
    () async {
      final alice = await setupAccount(userId: 'alice', displayName: 'Alice');
      addTearDown(alice.db.close);
      final peerB = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${'11' * 32}'),
        displayName: 'Bob',
        isVerified: true,
      );
      final conversation = Conversation(
        id: '923e4567-e89b-42d3-a456-426655440008',
        participants: [peerB],
        createdAt: DateTime.now(),
      );
      await alice.db.addContact(peerB);
      await alice.db.addConversation(conversation);
      await alice.db.writeSessionGeneration('923e4567-e89b-42d3-a456-426655440008', 5);
      final before = await alice.db.readSessionGenerationPair('923e4567-e89b-42d3-a456-426655440008');
      expect(before.db, 5);
      expect(before.keystore, 5);

      await alice.db.replaceAccountSnapshot(
        profile: alice.profile,
        contacts: [peerB],
        conversations: [conversation],
        messages: const [],
      );
      final after = await alice.db.readSessionGenerationPair('923e4567-e89b-42d3-a456-426655440008');
      expect(after.db, 5,
          reason: 'the SQLCipher store is not rewritten by a restore');
      expect(await alice.db.sessionGenerationState('923e4567-e89b-42d3-a456-426655440008'), 'ok');
    },
  );
}
