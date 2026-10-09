// ML-KEM-1024 wrapper — AUDIT-GATED placeholder (V14 Part 5).
//
// Spec-locked API shape for the session KEM. There is deliberately NO
// math here: implementing FIPS 203 from scratch would be unaudited
// custom crypto (rule §2.10). Wiring requires either a vetted
// dependency (human approval, rule §2.7) or a funded external audit
// of a from-scratch implementation (rule §2.16, Part 5 is in scope).
import 'dart:typed_data';

import 'pqc_provider.dart';

/// ML-KEM-1024 (FIPS 203) provider shape. Unavailable until approved.
class MlKem1024 implements PqKem {
  @override
  String get name => 'ML-KEM-1024';

  @override
  bool get isAvailable => false;

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  ) {
    throw PqcUnavailableException(name);
  }

  @override
  Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  ) {
    throw PqcUnavailableException(name);
  }
}
