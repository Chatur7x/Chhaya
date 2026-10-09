// Double Ratchet unit tests (V14 Part 4).
import 'dart:typed_data';

import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:chaaya/core/crypto/ratchet/double_ratchet.dart';
import 'package:chaaya/core/crypto/ratchet/header.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Paired sessions with pre-exchanged DH keys (what PQXDH in Part 5
/// will establish). Chains agree by construction.
Future<(SessionState, SessionState)> makePair() async {
  final shared = Csprng.instance.bytes(32);
  final aKeys = await X25519Kex.generateKeyPair();
  final bKeys = await X25519Kex.generateKeyPair();
  final alice = await DoubleRatchet.initSession(
    peerId: 'bob',
    initiator: true,
    sharedSecret: shared,
    remotePublicKey: bKeys.publicKey,
    ourPrivateKey: aKeys.privateKey,
  );
  final bob = await DoubleRatchet.initSession(
    peerId: 'alice',
    initiator: false,
    sharedSecret: shared,
    remotePublicKey: aKeys.publicKey,
    ourPrivateKey: bKeys.privateKey,
  );
  Csprng.wipe(shared);
  return (alice, bob);
}

void main() {
  group('DoubleRatchet', () {
    test('ping-pong both directions agrees', () async {
      final (alice, bob) = await makePair();
      for (var i = 0; i < 5; i++) {
        final out = await DoubleRatchet.encrypt(alice);
        final back = await DoubleRatchet.decrypt(bob, out.header);
        expect(eq(back.messageKey, out.keys.messageKey), isTrue);
        final reply = await DoubleRatchet.encrypt(bob);
        final fwd = await DoubleRatchet.decrypt(alice, reply.header);
        expect(eq(fwd.messageKey, reply.keys.messageKey), isTrue);
      }
    });

    test('DH ratchet triggers on direction change', () async {
      final (alice, bob) = await makePair();
      final first = await DoubleRatchet.encrypt(alice);
      await DoubleRatchet.decrypt(bob, first.header);
      final remoteBefore = Uint8List.fromList(alice.remotePublicKey);
      final reply = await DoubleRatchet.encrypt(bob);
      await DoubleRatchet.decrypt(alice, reply.header);
      expect(eq(alice.remotePublicKey, remoteBefore), isFalse);
      expect(alice.recvGeneration, 1);
      // Conversation continues after healing.
      final again = await DoubleRatchet.encrypt(alice);
      final back = await DoubleRatchet.decrypt(bob, again.header);
      expect(eq(back.messageKey, again.keys.messageKey), isTrue);
    });

    test('out-of-order delivery within window', () async {
      final (alice, bob) = await makePair();
      final sent = <int, ({RatchetHeader header, List<int> key})>{};
      for (var i = 0; i < 5; i++) {
        final out = await DoubleRatchet.encrypt(alice);
        sent[i] = (
          header: out.header,
          key: List<int>.from(out.keys.messageKey),
        );
      }
      for (final i in [4, 2, 0, 3, 1]) {
        final back =
            await DoubleRatchet.decrypt(bob, sent[i]!.header);
        expect(List<int>.from(back.messageKey), sent[i]!.key);
      }
      expect(bob.skipped, isEmpty);
    });

    test('replayed header fails (skipped keys are single-use)', () async {
      final (alice, bob) = await makePair();
      final first = await DoubleRatchet.encrypt(alice);
      final second = await DoubleRatchet.encrypt(alice);
      await DoubleRatchet.decrypt(bob, second.header);
      await DoubleRatchet.decrypt(bob, first.header);
      expect(
        () => DoubleRatchet.decrypt(bob, first.header),
        throwsA(isA<RatchetException>()),
      );
    });

    test('skip beyond MAX_SKIP throws', () async {
      final (alice, bob) = await makePair();
      RatchetHeader? far;
      for (var i = 0; i <= DoubleRatchet.maxSkip + 1; i++) {
        far = (await DoubleRatchet.encrypt(alice)).header;
      }
      expect(
        () => DoubleRatchet.decrypt(bob, far!),
        throwsA(isA<TooManySkippedException>()),
      );
    });

    test('malformed inputs rejected', () async {
      final (alice, bob) = await makePair();
      expect(
        () => RatchetHeader.fromBytes(Uint8List(39)),
        throwsArgumentError,
      );
      expect(
        () => DoubleRatchet.initSession(
          peerId: 'x',
          initiator: true,
          sharedSecret: Uint8List(16),
          remotePublicKey: Uint8List(32),
        ),
        throwsArgumentError,
      );
      expect(
        () => DoubleRatchet.initSession(
          peerId: 'x',
          initiator: true,
          sharedSecret: Uint8List(32),
          remotePublicKey: Uint8List(31),
        ),
        throwsArgumentError,
      );
      expect(bob.peerId, 'alice');
    });
  });
}
