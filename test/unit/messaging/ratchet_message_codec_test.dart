import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/services/messaging/pq_hybrid_v1.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';

import '../../support/fake_prekey_server.dart';

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
