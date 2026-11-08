// Adversarial replay / out-of-order / skip-limit coverage for the
// ratchet layer. All sessions are in-memory and synthetic.
//
// Pinned behaviour (verified empirically, do not weaken):
//   * A replayed or tampered envelope never advances the persisted
//     session: RatchetMessageCodec.decrypt mutates state in memory, but
//     the failure path never reaches commit(), so the stored session
//     blob is unchanged afterwards.
//   * Skipped keys are single-use; a replayed out-of-order envelope fails
//     after its key was consumed.
//   * A gap of exactly DoubleRatchet.maxSkip (1000) is served; a gap of
//     1001 throws TooManySkippedException and leaves the session intact.
import 'dart:convert';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/ratchet/double_ratchet.dart';
import 'package:chaaya/core/crypto/ratchet/session_store.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/services/messaging/ratchet_message_codec.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pair {
  _Pair(this.codecA, this.codecB, this.storageB, this.contactA, this.contactB,
      this.ownIdA);
  final RatchetMessageCodec codecA;
  final RatchetMessageCodec codecB;
  final InMemorySessionStorage storageB;
  final Contact contactA;
  final Contact contactB;
  final String ownIdA;
}

Future<_Pair> _pair() async {
  final idA = await ChhayaCryptoEngine.generateKeyPair();
  final idB = await ChhayaCryptoEngine.generateKeyPair();
  final contactA = Contact(
    id: 'a',
    chhayaId: ChhayaId.fromPublicKey('05${idA.publicKeyHex}'),
    displayName: 'A',
    isVerified: true,
  );
  final contactB = Contact(
    id: 'b',
    chhayaId: ChhayaId.fromPublicKey('05${idB.publicKeyHex}'),
    displayName: 'B',
    isVerified: true,
  );
  final storageA = InMemorySessionStorage();
  final storageB = InMemorySessionStorage();
  return _Pair(
    RatchetMessageCodec(
      sessions: storageA,
      identity: idA,
      ownId: contactA.chhayaId.publicKey,
    ),
    RatchetMessageCodec(
      sessions: storageB,
      identity: idB,
      ownId: contactB.chhayaId.publicKey,
    ),
    storageB,
    contactA,
    contactB,
    contactA.chhayaId.publicKey,
  );
}

String sessionKeyOf(Contact peer, String conversation) =>
    '$conversation:${peer.chhayaId.publicKey}';

Future<String?> sessionBlob(SessionStorage storage, String key) async {
  final state = await storage.loadSession(key);
  return state == null ? null : jsonEncode(state.toJson());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const conversation = 'conv-1';

  test('replayed envelope is rejected and persisted session is unchanged',
      () async {
    final pair = await _pair();
    final envelope = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-1',
      pair.ownIdA,
      {'text': 'first'},
    );
    final first = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-1',
      pair.ownIdA,
      envelope,
    );
    expect(first['text'], 'first');
    final key = sessionKeyOf(pair.contactA, conversation);
    final blobAfterFirst = await sessionBlob(pair.storageB, key);
    expect(blobAfterFirst, isNotNull);

    // Exact same envelope bytes, second delivery.
    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-1',
        pair.ownIdA,
        envelope,
      ),
      throwsA(isA<RatchetException>()),
    );
    expect(await sessionBlob(pair.storageB, key), blobAfterFirst);

    // The very next legitimate message still decrypts.
    final next = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-2',
      pair.ownIdA,
      {'text': 'second'},
    );
    final decoded = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-2',
      pair.ownIdA,
      next,
    );
    expect(decoded['text'], 'second');
  });

  test('tampered body fails authentication and session is not advanced',
      () async {
    final pair = await _pair();
    final envelope = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-1',
      pair.ownIdA,
      {'text': 'integrity'},
    );
    final wire = jsonDecode(envelope) as Map<String, dynamic>;
    final body = base64Decode(wire['body'] as String);
    body[0] = body[0] ^ 0x01;
    wire['body'] = base64Encode(body);
    final tampered = jsonEncode(wire);

    final key = sessionKeyOf(pair.contactA, conversation);
    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-1',
        pair.ownIdA,
        tampered,
      ),
      throwsA(anything),
    );
    // Tampering must not persist a session.
    expect(await sessionBlob(pair.storageB, key), isNull);

    // Untampered envelope still decrypts afterwards.
    final decoded = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-1',
      pair.ownIdA,
      envelope,
    );
    expect(decoded['text'], 'integrity');
  });

  test('tampered header fails and session is not advanced', () async {
    final pair = await _pair();
    final envelope = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-1',
      pair.ownIdA,
      {'text': 'header'},
    );
    final wire = jsonDecode(envelope) as Map<String, dynamic>;
    final header = base64Decode(wire['header'] as String);
    header[10] = header[10] ^ 0x01; // inside the DH public key
    wire['header'] = base64Encode(header);
    final tampered = jsonEncode(wire);

    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-1',
        pair.ownIdA,
        tampered,
      ),
      throwsA(anything),
    );
    final key = sessionKeyOf(pair.contactA, conversation);
    expect(await sessionBlob(pair.storageB, key), isNull);
  });

  test('out-of-order envelopes within the skip window are served, replays are not',
      () async {
    final pair = await _pair();
    final envelopes = <String>[];
    for (var i = 0; i < 3; i++) {
      envelopes.add(
        await pair.codecA.encrypt(
          pair.contactB,
          conversation,
          'msg-$i',
          pair.ownIdA,
          {'n': i},
        ),
      );
    }
    // Deliver newest first: message 2 stages skipped keys for 0 and 1.
    final m2 = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-2',
      pair.ownIdA,
      envelopes[2],
    );
    expect(m2['n'], 2);
    // Older envelopes arrive later and are served from the skipped cache.
    final m0 = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-0',
      pair.ownIdA,
      envelopes[0],
    );
    expect(m0['n'], 0);
    final m1 = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-1',
      pair.ownIdA,
      envelopes[1],
    );
    expect(m1['n'], 1);
    // Single-use: replaying either consumed envelope now fails.
    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-0',
        pair.ownIdA,
        envelopes[0],
      ),
      throwsA(isA<RatchetException>()),
    );
    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-2',
        pair.ownIdA,
        envelopes[2],
      ),
      throwsA(isA<RatchetException>()),
    );
  });

  test('a gap of exactly maxSkip (1000) is served', () async {
    final pair = await _pair();
    final first = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-0',
      pair.ownIdA,
      {'n': 0},
    );
    await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-0',
      pair.ownIdA,
      first,
    );
    String? last;
    for (var i = 1; i <= DoubleRatchet.maxSkip + 1; i++) {
      last = await pair.codecA.encrypt(
        pair.contactB,
        conversation,
        'msg-$i',
        pair.ownIdA,
        {'n': i},
      );
    }
    // recvCounter == 1; message 1001 is a gap of exactly 1000.
    final decoded = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-${DoubleRatchet.maxSkip + 1}',
      pair.ownIdA,
      last!,
    );
    expect(decoded['n'], DoubleRatchet.maxSkip + 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a gap of maxSkip + 1 throws TooManySkippedException and the session survives',
      () async {
    final pair = await _pair();
    final first = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-0',
      pair.ownIdA,
      {'n': 0},
    );
    await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-0',
      pair.ownIdA,
      first,
    );
    final key = sessionKeyOf(pair.contactA, conversation);
    final before = await sessionBlob(pair.storageB, key);

    final envelopes = <int, String>{};
    for (var i = 1; i <= DoubleRatchet.maxSkip + 2; i++) {
      envelopes[i] = await pair.codecA.encrypt(
        pair.contactB,
        conversation,
        'msg-$i',
        pair.ownIdA,
        {'n': i},
      );
    }
    // recvCounter == 1; message 1002 is a gap of 1001 > maxSkip.
    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-${DoubleRatchet.maxSkip + 2}',
        pair.ownIdA,
        envelopes[DoubleRatchet.maxSkip + 2]!,
      ),
      throwsA(isA<TooManySkippedException>()),
    );
    // The failed decrypt must not persist any advance.
    expect(await sessionBlob(pair.storageB, key), before);
    // The very next in-limit message is still decryptable.
    final decoded = await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-${DoubleRatchet.maxSkip + 1}',
      pair.ownIdA,
      envelopes[DoubleRatchet.maxSkip + 1]!,
    );
    expect(decoded['n'], DoubleRatchet.maxSkip + 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('an envelope older than the receive counter is rejected as too old',
      () async {
    final pair = await _pair();
    final first = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-0',
      pair.ownIdA,
      {'n': 0},
    );
    final second = await pair.codecA.encrypt(
      pair.contactB,
      conversation,
      'msg-1',
      pair.ownIdA,
      {'n': 1},
    );
    await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-0',
      pair.ownIdA,
      first,
    );
    await pair.codecB.decrypt(
      pair.contactA,
      conversation,
      'msg-1',
      pair.ownIdA,
      second,
    );
    // msg-0 again: messageNumber 0 < recvCounter 2.
    await expectLater(
      pair.codecB.decrypt(
        pair.contactA,
        conversation,
        'msg-0',
        pair.ownIdA,
        first,
      ),
      throwsA(isA<RatchetException>()),
    );
  });
}
