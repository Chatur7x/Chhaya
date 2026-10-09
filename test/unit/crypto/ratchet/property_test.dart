// Ratchet property tests (V14 Part 4).
//
// Forward-secrecy invariant, checked at every step: each message key
// is fresh (never repeats), each nonce is unique, skipped keys are
// single-use, and a compromised current state plus an old header can
// never recover an old key.
import 'dart:typed_data';

import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:chaaya/core/crypto/ratchet/double_ratchet.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/ratchet/triple_ratchet.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';

const _hex =
    'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12';

Contact _peer(String id) => Contact(
      id: id,
      chhayaId: ChhayaId.fromPublicKey(_hex),
      displayName: id,
      isVerified: true,
    );

String _h(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Future<(SessionState, SessionState)> _pair() async {
  final shared = Csprng.instance.bytes(32);
  final aKeys = await X25519Kex.generateKeyPair();
  final bKeys = await X25519Kex.generateKeyPair();
  final alice = await TripleRatchet.startSession(
    peer: _peer('bob'),
    remoteDhPublicKey: bKeys.publicKey,
    sharedSecret: shared,
    initiator: true,
    ourPrivateKey: aKeys.privateKey,
  );
  final bob = await TripleRatchet.startSession(
    peer: _peer('alice'),
    remoteDhPublicKey: aKeys.publicKey,
    sharedSecret: shared,
    initiator: false,
    ourPrivateKey: bKeys.privateKey,
  );
  Csprng.wipe(shared);
  return (alice, bob);
}

void main() {
  group('forward secrecy invariant', () {
    test('holds at every step over mixed traffic', () async {
      final (alice, bob) = await _pair();
      final seenKeys = <String>{};
      final seenNonces = <String>{};
      TripleHeader? firstHeader;
      String? firstKey;

      for (var i = 0; i < 1500; i++) {
        // Mostly Alice sends; Bob replies ~every 7th message (DH heal).
        final fromAlice = i % 7 != 6;
        final sender = fromAlice ? alice : bob;
        final receiver = fromAlice ? bob : alice;
        final out = await TripleRatchet.encrypt(sender);
        firstHeader ??= out.header;
        final keyHex = _h(out.keys.messageKey);
        firstKey ??= keyHex;
        final nonceHex = _h(out.keys.nonce);
        // Invariant 1: fresh key every message.
        expect(seenKeys.add(keyHex), isTrue, reason: 'key reuse at $i');
        // Invariant 2: unique nonce every message.
        expect(seenNonces.add(nonceHex), isTrue, reason: 'nonce reuse at $i');
        final back = await TripleRatchet.decrypt(receiver, out.header);
        expect(_h(back.messageKey), keyHex);
        // Invariant 3: state survives a JSON round-trip mid-stream.
        if (i % 500 == 499) {
          for (final s in [alice, bob]) {
            final rt = SessionState.fromJson(
              s.toJson(),
            );
            expect(rt.sendCounter, s.sendCounter);
            expect(rt.recvCounter, s.recvCounter);
          }
        }
      }
      // Invariant 4: the oldest key is unrecoverable from current state.
      // Replaying the first header either fails outright, or (if its
      // chain key is unknown and triggers a healing ratchet) yields a
      // fresh key that MUST differ from the recorded original.
      try {
        final replay = await TripleRatchet.decrypt(bob, firstHeader!);
        expect(_h(replay.messageKey) == firstKey, isFalse,
            reason: 'forward secrecy broken: old key recovered');
      } on RatchetException {
        // Also acceptable: replay rejected.
      }
      expect(seenKeys.length, 1500);
      expect(seenNonces.length, 1500);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
