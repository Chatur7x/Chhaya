// PQC hybrid layer tests (V14 Part 5).
//
// Covers everything rule-compliant: combiner binding, dual-KEM
// behavior with test KEMs, consent-gated fallback, no-silent-
// downgrade, and the audit gates on ML-KEM-1024 / ML-DSA-87.
// NIST KATs are tracked as blocked until an approved provider lands.
import 'dart:typed_data';

import 'package:chaaya/core/crypto/pqc/dual_kem.dart';
import 'package:chaaya/core/crypto/pqc/hybrid_kex.dart';
import 'package:chaaya/core/crypto/pqc/ml_dsa.dart';
import 'package:chaaya/core/crypto/pqc/ml_kem.dart';
import 'package:chaaya/core/crypto/pqc/pqc_provider.dart';
import 'package:chaaya/core/crypto/pqc/pqxdh.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only KEM (deterministic, NOT secure). Production KEMs land
/// behind the audit gate in ml_kem.dart.
class FakeKem implements PqKem {
  final Uint8List tag;
  FakeKem(this.tag);

  @override
  String get name => 'FakeKem';

  @override
  bool get isAvailable => true;

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  ) async {
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = (tag[i % tag.length] + publicKey[i % publicKey.length] + i) &
          0xFF;
    }
    return (ciphertext: Uint8List.fromList(out), sharedSecret: out);
  }

  @override
  Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  ) async {
    return Uint8List.fromList(ciphertext);
  }
}

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
  group('PQC hybrid layer', () {
    test('combiner binds both inputs and context', () {
      final c = Csprng.instance.bytes(32);
      final p = Csprng.instance.bytes(32);
      final ctx = Csprng.instance.bytes(16);
      final base = HybridKex.combine(classical: c, pq: p, context: ctx);
      expect(base.pqUsed, isTrue);
      expect(base.consentedFallback, isFalse);
      final flipped = Uint8List.fromList(p)..[0] ^= 0x01;
      final other = HybridKex.combine(classical: c, pq: flipped, context: ctx);
      expect(eq(other.secret, base.secret), isFalse);
      final otherCtx = HybridKex.combine(
        classical: c,
        pq: p,
        context: Uint8List.fromList(ctx)..[0] ^= 0x01,
      );
      expect(eq(otherCtx.secret, base.secret), isFalse);
      expect(
        HybridKex.combine(classical: c, pq: p, context: ctx).secret,
        base.secret,
      );
    });

    test('hybrid differs from classical-only (no silent downgrade)', () {
      final c = Csprng.instance.bytes(32);
      final p = Csprng.instance.bytes(32);
      final ctx = Csprng.instance.bytes(16);
      final hybrid =
          HybridKex.combine(classical: c, pq: p, context: ctx).secret;
      final fallback = HybridKex.classicalFallback(
        classical: c,
        context: ctx,
        userConsented: true,
      );
      expect(fallback.pqUsed, isFalse);
      expect(fallback.consentedFallback, isTrue);
      expect(eq(hybrid, fallback.secret), isFalse);
    });

    test('fallback requires explicit consent', () {
      expect(
        () => HybridKex.classicalFallback(
          classical: Csprng.instance.bytes(32),
          context: Uint8List(16),
          userConsented: false,
        ),
        throwsStateError,
      );
    });

    test('dual KEM combines two test KEMs, aborts if either missing', () async {
      final kemA = FakeKem(Uint8List.fromList([1]));
      final kemB = FakeKem(Uint8List.fromList([2]));
      final out = await DualKem.establish(
        primary: kemA,
        secondary: kemB,
        primaryPublicKey: Uint8List.fromList(List.filled(32, 7)),
        secondaryPublicKey: Uint8List.fromList(List.filled(32, 9)),
        context: Uint8List.fromList([0]),
      );
      expect(out.length, 32);
      expect(
        () => DualKem.establish(
          primary: MlKem1024(),
          secondary: kemB,
          primaryPublicKey: Uint8List(32),
          secondaryPublicKey: Uint8List(32),
          context: Uint8List(0),
        ),
        throwsA(isA<PqcUnavailableException>()),
      );
    });

    test('audit gates: ML-KEM-1024 and ML-DSA-87 unavailable', () {
      expect(MlKem1024().isAvailable, isFalse);
      expect(MlDsa87().isAvailable, isFalse);
      expect(() => MlKem1024().encapsulate(Uint8List(32)),
          throwsA(isA<PqcUnavailableException>()));
      expect(() => MlDsa87().sign(Uint8List(32), Uint8List(3)),
          throwsA(isA<PqcUnavailableException>()));
    });

    test('PQXDH refuses without KEM and without consent', () async {
      final remote = (await X25519Kex.generateKeyPair()).publicKey;
      expect(
        () => Pqxdh.establish(
          remotePublicKey: remote,
          context: Uint8List.fromList([1]),
        ),
        throwsStateError,
      );
    });

    test('PQXDH consented fallback establishes honestly-flagged secret',
        () async {
      final remote = (await X25519Kex.generateKeyPair()).publicKey;
      final (secret: secret, ourPublicKey: ours) = await Pqxdh.establish(
        remotePublicKey: remote,
        context: Uint8List.fromList([1]),
        allowClassicalFallback: true,
        userConsented: true,
      );
      expect(secret.secret.length, 32);
      expect(secret.pqUsed, isFalse);
      expect(secret.consentedFallback, isTrue);
      expect(ours.length, 32);
    });
  });
}
