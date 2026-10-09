// SPQR unit tests (V14 Part 4).
import 'dart:typed_data';

import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/ratchet/spqr.dart';
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

void main() {
  group('SpqrChain', () {
    test('epoch stable within window, advances every 10', () {
      final seed = Csprng.instance.bytes(32);
      final e0 = SpqrChain.chainKeyFor(seed, 0);
      expect(eq(e0, SpqrChain.chainKeyFor(seed, 0)), isTrue);
      // Distinct epochs must diverge (message-to-epoch mapping,
      // counter ~/ 10, is covered in triple_ratchet_test).
      expect(eq(e0, SpqrChain.chainKeyFor(seed, 1)), isFalse);
      final e1 = SpqrChain.chainKeyFor(seed, 1);
      expect(eq(e1, SpqrChain.chainKeyFor(seed, 1)), isTrue);
      expect(eq(e1, e0), isFalse);
      expect(SpqrChain.advanceEvery, 10);
    });

    test('both sides derive identical epoch keys', () {
      final seed = Csprng.instance.bytes(32);
      for (final epoch in [0, 3, 10, 99]) {
        expect(
          eq(SpqrChain.chainKeyFor(seed, epoch),
              SpqrChain.chainKeyFor(Uint8List.fromList(seed), epoch)),
          isTrue,
        );
      }
    });

    test('reseed rotates the chain', () async {
      final seed = Csprng.instance.bytes(32);
      final kem = DeterministicTestKem(Csprng.instance.bytes(32));
      final pq = await kem.establish(Uint8List.fromList([1, 2, 3]));
      final next = SpqrChain.reseed(seed, pq);
      expect(eq(SpqrChain.chainKeyFor(seed, 0),
          SpqrChain.chainKeyFor(next, 0)), isFalse);
    });

    test('test KEM is context-bound', () async {
      final kem = DeterministicTestKem(Csprng.instance.bytes(32));
      final a = await kem.establish(Uint8List.fromList([1]));
      final b = await kem.establish(Uint8List.fromList([2]));
      expect(eq(a, b), isFalse);
    });

    test('invalid inputs rejected', () {
      expect(() => SpqrChain.chainKeyFor(Uint8List(16), 0), throwsArgumentError);
      expect(() => SpqrChain.chainKeyFor(Uint8List(32), -1), throwsArgumentError);
      expect(() => SpqrChain.reseed(Uint8List(32), Uint8List(4)),
          throwsArgumentError);
    });
  });
}
