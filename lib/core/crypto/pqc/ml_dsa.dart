// ML-DSA-87 signatures — AUDIT-GATED placeholder (V14 Part 5).
//
// Paired with Ed25519 (Part 1, audited) until an approved FIPS 204
// implementation lands. Same gating rationale as ml_kem.dart.
import 'dart:typed_data';

import 'pqc_provider.dart';

/// ML-DSA-87 (FIPS 204) provider shape. Unavailable until approved.
class MlDsa87 implements PqSigner {
  @override
  String get name => 'ML-DSA-87';

  @override
  bool get isAvailable => false;

  @override
  Future<Uint8List> sign(Uint8List privateKey, Uint8List message) {
    throw PqcUnavailableException(name);
  }

  @override
  Future<bool> verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) {
    throw PqcUnavailableException(name);
  }
}
