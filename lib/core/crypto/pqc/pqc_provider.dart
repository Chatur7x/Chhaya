// Post-quantum provider interfaces (V14 Part 5).
//
// Abstraction boundary for all PQ algorithms. Concrete ML-KEM-1024 and
// ML-DSA-87 primitives use the user-approved, version-pinned native AWS-LC
// provider. Primitive availability does not enable authenticated PQ identity
// distribution or a messaging protocol; those remain separately gated and
// require security review.
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

  /// True only after the native implementation passes its self-check.
  bool get isAvailable;

  /// Initializes the provider and runs its native self-check when required.
  Future<bool> initialize() async => isAvailable;

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

  /// True only after the native implementation passes its self-check.
  bool get isAvailable;

  /// Initializes the provider and runs its native self-check when required.
  Future<bool> initialize() async => isAvailable;

  Future<Uint8List> sign(Uint8List privateKey, Uint8List message);
  Future<bool> verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  );
}
