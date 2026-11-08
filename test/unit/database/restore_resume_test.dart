// Backup/restore -> resumed-conversation behaviour pinning (restore slice).
//
// What replaceAccountSnapshot does today (lib/core/database/local_database.dart:915):
// clears ratchet sessions and queued outbox envelopes, keeps identity,
// contacts, conversations and messages.
//
// What a resumed send does today (lib/services/messaging/ratchet_message_codec.dart:
// _state + TripleRatchet.startSession + DoubleRatchet.initSession):
//   * Every initial session is derived deterministically from the static
//     identity keys; fresh entropy enters only via the responder's
//     first-send DH ratchet and later direction changes.
//   * An INITIATOR that restores re-derives the byte-identical initial
//     session: same root key, same send chain, same message counter reset
//     to 0 — hence the same message-key/nonce material for early messages.
//   * The SPQR seed is re-derived identically in both roles.
//
// Recorded here as pinned behaviour, NOT as an acceptable design: this is
// the known dangerous failure mode (key/nonce reuse for early messages).
// Safe re-establishment requires a fresh, authenticated, peer-coordinated
// session generation; it does not exist yet. Backup-to-resumed-conversation
// acceptance is NOT established by this behaviour.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';

import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/crypto/ratchet/triple_ratchet.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Future<(ChhayaKeyPair, ChhayaKeyPair)> initiatorPair() async {
  // Role is assigned by comparing '05'-prefixed hex strings; keep
  // regenerating until A is the initiator so the deterministic-restart
  // pins below are exercised deterministically.
  while (true) {
    final a = await ChhayaCryptoEngine.generateKeyPair();
    final b = await ChhayaCryptoEngine.generateKeyPair();
    if ('05${a.publicKeyHex}'.compareTo('05${b.publicKeyHex}') < 0) {
      return (a, b);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'protocol pin: two initial sessions derived from identical inputs are '
    'byte-identical (root key, chains, SPQR seed, public keys)',
    () async {
      final peer = Contact(
        id: 'peer',
        chhayaId: ChhayaId.fromPublicKey('05${'11' * 32}'),
        displayName: 'Peer',
        isVerified: true,
      );
      final secret = Uint8List.fromList(List<int>.filled(32, 7));
      final ephemeral = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final remote = Uint8List.fromList(List<int>.filled(32, 9));
      final one = await TripleRatchet.startSession(
        peer: peer,
        remoteDhPublicKey: remote,
        sharedSecret: secret,
        initiator: true,
        ourPrivateKey: ephemeral,
      );
      final two = await TripleRatchet.startSession(
        peer: peer,
        remoteDhPublicKey: remote,
        sharedSecret: secret,
        initiator: true,
        ourPrivateKey: ephemeral,
      );
      expect(bytesEq(one.rootKey, two.rootKey), isTrue);
      expect(bytesEq(one.sendChainKey, two.sendChainKey), isTrue);
      expect(bytesEq(one.recvChainKey, two.recvChainKey), isTrue);
      expect(bytesEq(one.ourPublicKey, two.ourPublicKey), isTrue);
      expect(bytesEq(one.remotePublicKey, two.remotePublicKey), isTrue);
      expect(bytesEq(one.spqrSeed, two.spqrSeed), isTrue);
      // Same chain key at the same counter derives the same message key
      // and nonce — the precondition for AEAD nonce reuse on restart.
      expect(one.sendCounter, two.sendCounter);
      expect(one.recvCounter, two.recvCounter);
    },
  );

  test(
    'a restored initiator re-derives the IDENTICAL initial session: root key, '
    'send chain, public key, SPQR seed all reuse pre-restore material; '
    'message counter restarts at 0 (pinned dangerous defect)',
    () async {
      final (identityA, identityB) = await initiatorPair();
      final peerB = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${identityB.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      final profileA = UserProfile(
        chhayaId: ChhayaId.fromPublicKey('05${identityA.publicKeyHex}'),
        displayName: 'Alice',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      final dbA = await makeDb();
      addTearDown(dbA.close);
      await dbA.saveUserProfile(profileA);
      await dbA.addContact(peerB);
      final conversation = Conversation(
        id: 'conv-1',
        participants: [peerB],
        createdAt: DateTime.now(),
      );
      await dbA.addConversation(conversation);

      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(identityA);
      final codec = RatchetMessageCodec(
        sessions: LocalDatabaseSessionStorage(dbA),
        identity: identityA,
        ownId: profileA.chhayaId.publicKey,
      );
      final outgoing = Message(
        id: 'msg-1',
        conversationId: conversation.id,
        senderId: 'me',
        content: 'hello before backup',
        timestamp: DateTime.now(),
        isSent: false,
      );
      await codec.encrypt(
        peerB,
        conversation.id,
        outgoing.id,
        'alice-server-id',
        {'text': outgoing.content},
        commit: (state, envelope) =>
            dbA.commitOutgoingMessage(state, outgoing, envelope),
      );
      final sessionKey = '${conversation.id}:${peerB.chhayaId.publicKey}';
      final blobBefore = await dbA.loadSessionBlob(sessionKey);
      expect(blobBefore, isNotNull);
      expect(await dbA.loadSessionBlob('outbox:msg-1'), isNotNull);
      final stateBefore = SessionState.fromJson(
        jsonDecode(blobBefore!) as Map<String, dynamic>,
      );

      // Restore from a backup taken before the first message.
      await dbA.replaceAccountSnapshot(
        profile: profileA,
        contacts: [peerB],
        conversations: [conversation],
        messages: const [],
      );

      // Ratcheted state and the queued envelope are gone.
      expect(await dbA.loadSessionBlob(sessionKey), isNull);
      expect(await dbA.loadSessionBlob('outbox:msg-1'), isNull);

      // Resume the conversation.
      final resumed = Message(
        id: 'msg-2',
        conversationId: conversation.id,
        senderId: 'me',
        content: 'after restore',
        timestamp: DateTime.now(),
        isSent: false,
      );
      await codec.encrypt(
        peerB,
        conversation.id,
        resumed.id,
        'alice-server-id',
        {'text': resumed.content},
        commit: (state, envelope) =>
            dbA.commitOutgoingMessage(state, resumed, envelope),
      );
      final blobAfter = await dbA.loadSessionBlob(sessionKey);
      expect(blobAfter, isNotNull);
      final stateAfter = SessionState.fromJson(
        jsonDecode(blobAfter!) as Map<String, dynamic>,
      );

      // PIN (dangerous behaviour, current implementation): the initiator's
      // re-derived session is byte-identical to the pre-restore initial
      // session. The first post-restore message reuses the exact message
      // key/nonce derivation of the pre-restore first message.
      expect(bytesEq(stateBefore.rootKey, stateAfter.rootKey), isTrue);
      expect(bytesEq(stateBefore.sendChainKey, stateAfter.sendChainKey),
          isTrue);
      expect(bytesEq(stateBefore.ourPublicKey, stateAfter.ourPublicKey),
          isTrue);
      expect(bytesEq(stateBefore.spqrSeed, stateAfter.spqrSeed), isTrue);
      expect(stateAfter.sendCounter, 1);
    },
  );

  test(
    'the non-restored peer rejects a restored initiator’s first message '
    '(message number 0 replays an already-consumed counter)',
    () async {
      final (identityA, identityB) = await initiatorPair();
      final peerA = Contact(
        id: 'alice',
        chhayaId: ChhayaId.fromPublicKey('05${identityA.publicKeyHex}'),
        displayName: 'Alice',
        isVerified: true,
      );
      final peerB = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${identityB.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      final profileA = UserProfile(
        chhayaId: peerA.chhayaId,
        displayName: 'Alice',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      final profileB = UserProfile(
        chhayaId: peerB.chhayaId,
        displayName: 'Bob',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      final dbA = await makeDb();
      final dbB = await makeDb();
      addTearDown(dbA.close);
      addTearDown(dbB.close);
      await dbA.saveUserProfile(profileA);
      await dbB.saveUserProfile(profileB);
      await dbA.addContact(peerB);
      await dbB.addContact(peerA);
      final conversation = Conversation(
        id: 'conv-1',
        participants: [peerB],
        createdAt: DateTime.now(),
      );
      final keysA = KeyManager(secureBackend: SecureStorageMock());
      await keysA.storeKeyPair(identityA);
      final keysB = KeyManager(secureBackend: SecureStorageMock());
      await keysB.storeKeyPair(identityB);
      final codecA = RatchetMessageCodec(
        sessions: LocalDatabaseSessionStorage(dbA),
        identity: identityA,
        ownId: profileA.chhayaId.publicKey,
      );
      final codecB = RatchetMessageCodec(
        sessions: LocalDatabaseSessionStorage(dbB),
        identity: identityB,
        ownId: profileB.chhayaId.publicKey,
      );

      final first = await codecA.encrypt(
        peerB,
        conversation.id,
        'msg-1',
        'alice-server-id',
        {'text': 'before backup'},
      );
      final decoded = await codecB.decrypt(
        peerA,
        conversation.id,
        'msg-1',
        'alice-server-id',
        first,
      );
      expect(decoded['text'], 'before backup');
      final sessionKeyB = '${conversation.id}:${peerA.chhayaId.publicKey}';
      final blobB = await dbB.loadSessionBlob(sessionKeyB);
      expect(blobB, isNotNull);

      // A restores from a backup taken before the first message.
      await dbA.replaceAccountSnapshot(
        profile: profileA,
        contacts: [peerB],
        conversations: [conversation],
        messages: const [],
      );

      // A sends after restore. The replayed counter-0 message is rejected
      // by B; B's session is left untouched.
      final after = await codecA.encrypt(
        peerB,
        conversation.id,
        'msg-2',
        'alice-server-id',
        {'text': 'after restore'},
      );
      await expectLater(
        codecB.decrypt(
          peerA,
          conversation.id,
          'msg-2',
          'alice-server-id',
          after,
        ),
        throwsA(anything),
      );
      expect(await dbB.loadSessionBlob(sessionKeyB), blobB);
    },
  );

  test(
    'an unsent message restored from backup is stuck pending: its outbox '
    'envelope is gone and retry cannot send it (pinned gap)',
    () async {
      final (identityA, identityB) = await initiatorPair();
      final peerA = Contact(
        id: 'alice',
        chhayaId: ChhayaId.fromPublicKey('05${identityA.publicKeyHex}'),
        displayName: 'Alice',
        isVerified: true,
      );
      final peerB = Contact(
        id: 'bob',
        chhayaId: ChhayaId.fromPublicKey('05${identityB.publicKeyHex}'),
        displayName: 'Bob',
        isVerified: true,
      );
      final profileA = UserProfile(
        chhayaId: peerA.chhayaId,
        displayName: 'Alice',
        recoveryPhrase: const [],
        createdAt: DateTime.now(),
      );
      final dbA = await makeDb();
      addTearDown(dbA.close);
      await dbA.saveUserProfile(profileA);
      await dbA.addContact(peerB);
      final conversation = Conversation(
        id: 'conv-1',
        participants: [peerB],
        createdAt: DateTime.now(),
      );
      await dbA.addConversation(conversation);
      final pending = Message(
        id: 'msg-pending',
        conversationId: conversation.id,
        senderId: 'me',
        content: 'queued before backup',
        timestamp: DateTime.now(),
        isSent: false,
      );
      await dbA.replaceAccountSnapshot(
        profile: profileA,
        contacts: [peerB],
        conversations: [conversation],
        messages: [pending],
      );
      final restored = await dbA.getPendingMessages(conversation.id);
      expect(restored, hasLength(1));
      expect(await dbA.loadSessionBlob('outbox:msg-pending'), isNull);
    },
  );
}
