// Ratchet fuzz test (V14 Part 4).
//
// 1,000,000 messages with direction flips, drops, and delayed
// delivery in shuffled batches. Every delivered message must decrypt
// to the sender's recorded key; every key and nonce must be unique.
// Memory note: two hex sets (~1M entries each) peak around a few
// hundred MB — fine on dev machines and CI runners, and required for
// an exhaustive uniqueness claim.
import 'dart:math';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
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

void main() {
  group('fuzz', () {
    test('1M messages, flips, drops, delays — 0 failures', () async {
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

      const total = 1000000;
      final order = Random(42); // delivery shuffling only, never key material
      final sentKeys = <int, String>{};
      final seenKeys = <String>{};
      final seenNonces = <String>{};
      final pending = <int, ({List<int> header, bool toBob})>{};
      var failures = 0;

      Future<void> flush() async {
        final keys = pending.keys.toList()..shuffle(order);
        for (final seq in keys) {
          final p = pending.remove(seq)!;
          final back = await TripleRatchet.decrypt(
            p.toBob ? bob : alice,
            TripleHeader.fromBytes(Uint8List.fromList(p.header)),
          );
          final got = _h(back.messageKey);
          if (got != sentKeys.remove(seq)) {
            failures++;
          }
        }
      }

      for (var i = 0; i < total; i++) {
        // Sender flips every 97 messages (bounds DH ops); 10% dropped
        // into the delay buffer, flushed shuffled every 50 messages.
        final toBob = (i ~/ 97) % 2 == 0;
        final out =
            await TripleRatchet.encrypt(toBob ? alice : bob);
        final keyHex = _h(out.keys.messageKey);
        final nonceHex = _h(out.keys.nonce);
        if (!seenKeys.add(keyHex) || !seenNonces.add(nonceHex)) {
          failures++;
        }
        sentKeys[i] = keyHex;
        if (i % 10 == 0) {
          pending[i] = (
            header: List<int>.from(out.header.toBytes()),
            toBob: toBob,
          );
        } else {
          final back = await TripleRatchet.decrypt(
            toBob ? bob : alice,
            out.header,
          );
          if (_h(back.messageKey) != sentKeys.remove(i)) {
            failures++;
          }
        }
        if (i % 50 == 49) {
          await flush();
        }
        if (i % 250000 == 249999) {
          // Heartbeat so long runs never look hung.
          // ignore: avoid_print
          print('fuzz progress: ${i + 1}/$total');
        }
      }
      await flush();
      expect(pending, isEmpty);
      expect(sentKeys, isEmpty);
      expect(failures, 0);
      expect(seenKeys.length, total);
      expect(seenNonces.length, total);
    }, timeout: const Timeout(Duration(minutes: 15)));
  });
}
