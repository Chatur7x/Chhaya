// Sparse Post-Quantum Ratchet (V14 Part 4).
//
// Second ratchet dimension alongside the X25519 Double Ratchet. The
// SPQR chain evolves deterministically per epoch from the session seed
// (epoch = sendCounter ~/ advanceEvery), so either side can compute any
// epoch's key without interaction. Real post-quantum freshness arrives
// via [inject]: Part 5 (ml_kem.dart) reseeds with ML-KEM-1024 output,
// which is the spec-locked KEM. Until then the chain is classical-HKDF
// evolution and MUST be described as such — see the audit checklist.
import 'dart:convert';
import 'dart:typed_data';

import '../primitives/hkdf.dart';
import '../primitives/rng.dart';

/// Async source of post-quantum key material.
///
/// Contract: returns 32 bytes of fresh PQ-derived output bound to
/// [context]. The production ML-KEM-1024 implementation lands in Part 5
/// and must be audited before release. Part 4 pins the interface and
/// the advance cadence, not the KEM math.
abstract class KemProvider {
  Future<Uint8List> establish(Uint8List context);
}

/// Deterministic KEM stand-in for unit tests ONLY.
///
/// Derives output from a fixed seed via HKDF — no forward secrecy, no
/// quantum resistance. Never use outside tests.
class DeterministicTestKem implements KemProvider {
  final Uint8List seed;

  DeterministicTestKem(Uint8List seed) : seed = Uint8List.fromList(seed);

  @override
  Future<Uint8List> establish(Uint8List context) async {
    return Hkdf.deriveKey(
      inputKeyMaterial: seed,
      salt: Uint8List.fromList(context),
      info: Uint8List.fromList(utf8.encode('Chhaya-testkem-v1')),
      length: 32,
    );
  }
}

/// Epoch-evolving SPQR chain over an immutable seed.
class SpqrChain {
  SpqrChain._();

  /// Messages per SPQR epoch (spec-locked).
  static const int advanceEvery = 10;

  /// Epoch key: HKDF(seed, 'Chhaya-SPQR-v1' || u32be(epoch)).
  static Uint8List chainKeyFor(Uint8List seed, int epoch) {
    if (seed.length < 32) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'SPQR seeds must be at least 32 bytes',
      );
    }
    if (epoch < 0 || epoch > 0xFFFFFFFF) {
      throw ArgumentError.value(epoch, 'epoch', 'Epoch must fit in u32');
    }
    final epochBytes = Uint8List(4)..buffer.asByteData().setUint32(0, epoch);
    return Hkdf.deriveKey(
      inputKeyMaterial: seed,
      info: Uint8List.fromList(
        [...utf8.encode('Chhaya-SPQR-v1'), ...epochBytes],
      ),
      length: 32,
    );
  }

  /// Reseeds the chain with fresh PQ output (Part 5 calls this after
  /// each ML-KEM-1024 establishment). Returns the new seed; the caller
  /// wipes the old one via [SessionState] replacement.
  static Uint8List reseed(Uint8List seed, Uint8List pqOutput) {
    if (pqOutput.length < 32) {
      throw ArgumentError.value(
        pqOutput.length,
        'pqOutput',
        'PQ outputs must be at least 32 bytes',
      );
    }
    final next = Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList([...seed, ...pqOutput]),
      info: Uint8List.fromList(utf8.encode('Chhaya-SPQR-reseed-v1')),
      length: 32,
    );
    Csprng.wipe(pqOutput);
    return next;
  }
}
