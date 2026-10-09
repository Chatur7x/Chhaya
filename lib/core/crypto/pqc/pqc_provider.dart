// Post-quantum provider interfaces (V14 Part 5).
//
// Abstraction boundary for all PQ algorithms. Concrete ML-KEM-1024
// and ML-DSA-87 providers are AUDIT-GATED: the frozen stack
// (cryptography + pointycastle) ships no PQC, and rule §2.10 forbids
// unaudited custom crypto. Until an approved provider lands (vetted
// dependency or audited from-scratch FIPS 203/204 implementation),
// providers report unavailable and the hybrid layer refuses silent
// downgrade — classical-only operation requires explicit user consent.
import 'dart:typed_data';

/// Thrown when PQ material is requested but no approved provider exists.
class PqcUnavailableException implements Exception {
  final String algorithm;
  PqcUnavailableException(this.algorithm);

  @override
  String toString() =>
      'PqcUnavailableException: $algorithm has no approved provider. '
      'Ship requires a vetted dependency or an audited implementation.';
}

/// Key-encapsulation mechanism interface (KEM API shape).
abstract class PqKem {
  /// Spec name, e.g. 'ML-KEM-1024'.
  String get name;

  /// False until an approved implementation is wired.
  bool get isAvailable;

  /// Encapsulates to [publicKey], returning (ciphertext, sharedSecret).
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  );

  /// Decapsulates [ciphertext] with [privateKey].
  Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  );
}

/// Post-quantum signature interface.
abstract class PqSigner {
  /// Spec name, e.g. 'ML-DSA-87'.
  String get name;

  /// False until an approved implementation is wired.
  bool get isAvailable;

  Future<Uint8List> sign(Uint8List privateKey, Uint8List message);
  Future<bool> verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  );
}
