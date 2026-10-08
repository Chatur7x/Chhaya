// Triple Ratchet unit tests (V14 Part 4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:chaaya/core/crypto/ratchet/double_ratchet.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/crypto/ratchet/spqr.dart';
import 'package:chaaya/core/crypto/ratchet/triple_ratchet.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _demoHex =
    'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12';

Contact peer(String id, {bool verified = true}) => Contact(
      id: id,
      chhayaId: ChhayaId.fromPublicKey(_demoHex),
      displayName: id,
      isVerified: verified,
    );

bool eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Agreeing triple-ratchet pair (pre-exchanged DH keys, shared secret).
Future<(SessionState, SessionState)> makeTriplePair() async {
  final shared = Csprng.instance.bytes(32);
  final aKeys = await X25519Kex.generateKeyPair();
  final bKeys = await X25519Kex.generateKeyPair();
  final alice = await TripleRatchet.startSession(
    peer: peer('bob'),
    remoteDhPublicKey: bKeys.publicKey,
    sharedSecret: shared,
    initiator: true,
    ourPrivateKey: aKeys.privateKey,
  );
  final bob = await TripleRatchet.startSession(
    peer: peer('alice'),
    remoteDhPublicKey: aKeys.publicKey,
    sharedSecret: shared,
    initiator: false,
    ourPrivateKey: bKeys.privateKey,
  );
  Csprng.wipe(shared);
  return (alice, bob);
}

/// In-memory opener for the LocalDatabase round-trip (mirrors the
/// Part 3 unit-test fake: always keyed, hardening PRAGMAs recorded).
class FakeOpener implements DatabaseOpener {
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
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('TripleRatchet sessions', () {
    test('unverified and demo peers rejected outright', () async {
      final shared = Csprng.instance.bytes(32);
      final keys = await X25519Kex.generateKeyPair();
      expect(
        () => TripleRatchet.startSession(
          peer: peer('mallory', verified: false),
          remoteDhPublicKey: keys.publicKey,
          sharedSecret: shared,
          initiator: true,
        ),
        throwsA(isA<UnverifiedPeerException>()),
      );
      // Default contacts (like the contacts_tab placeholder) are
      // unverified and rejected too.
      final demo = Contact(
        id: 'demo',
        chhayaId: ChhayaId.fromPublicKey(_demoHex),
        displayName: 'Demo',
      );
      expect(demo.isVerified, isFalse);
      expect(
        () => TripleRatchet.startSession(
          peer: demo,
          remoteDhPublicKey: keys.publicKey,
          sharedSecret: shared,
          initiator: true,
        ),
        throwsA(isA<UnverifiedPeerException>()),
      );
    });

    test('exchange with epoch transitions agrees', () async {
      final (alice, bob) = await makeTriplePair();
      for (var i = 0; i < 25; i++) {
        final out = await TripleRatchet.encrypt(alice);
        expect(out.header.spqrEpoch, i ~/ SpqrChain.advanceEvery);
        expect(out.header.toBytes().length, TripleHeader.encodedLength);
        final back = await TripleRatchet.decrypt(
          bob,
          TripleHeader.fromBytes(out.header.toBytes()),
        );
        expect(eq(back.messageKey, out.keys.messageKey), isTrue);
        expect(eq(back.nonce, out.keys.nonce), isTrue);
      }
    });

    test('100 shuffled messages all decrypt', () async {
      final (alice, bob) = await makeTriplePair();
      final sent = <int, ({List<int> header, List<int> key})>{};
      for (var i = 0; i < 100; i++) {
        final out = await TripleRatchet.encrypt(alice);
        sent[i] = (
          header: List<int>.from(out.header.toBytes()),
          key: List<int>.from(out.keys.messageKey),
        );
      }
      final order = List<int>.generate(100, (i) => i)..shuffle();
      for (final i in order) {
        final back = await TripleRatchet.decrypt(
          bob,
          TripleHeader.fromBytes(Uint8List.fromList(sent[i]!.header)),
        );
        expect(List<int>.from(back.messageKey), sent[i]!.key);
      }
    });

    test('session state round-trips through LocalDatabase', () async {
      final (alice, bob) = await makeTriplePair();
      final keyManager = KeyManager(secureBackend: SecureStorageMock());
      await keyManager.storeChhayaId('user-1');
      final db = LocalDatabase(
        keyManager: keyManager,
        opener: FakeOpener(),
        dbPath: inMemoryDatabasePath,
      );
      expect(await db.init(requireBiometric: false), isTrue);
      final store = LocalDatabaseSessionStorage(db);
      await store.saveSession(alice);
      // Conversation continues, then state is reloaded mid-stream.
      final first = await TripleRatchet.encrypt(alice);
      await store.saveSession(alice);
      final restored = await store.loadSession('bob');
      expect(restored, isNotNull);
      final second = await TripleRatchet.encrypt(restored!);
      final forFirst = await TripleRatchet.decrypt(bob, first.header);
      final forSecond = await TripleRatchet.decrypt(bob, second.header);
      expect(eq(forFirst.messageKey, first.keys.messageKey), isTrue);
      expect(eq(forSecond.messageKey, second.keys.messageKey), isTrue);
      // JSON form also round-trips standalone.
      final viaJson = SessionState.fromJson(
        jsonDecode(jsonEncode(alice.toJson())) as Map<String, dynamic>,
      );
      expect(viaJson.peerId, alice.peerId);
      expect(viaJson.sendCounter, alice.sendCounter);
      await store.deleteSession('bob');
      expect(await store.loadSession('bob'), isNull);
    });
  });
}
