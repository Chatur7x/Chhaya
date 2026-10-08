// Hybrid classical+PQ key combiner (V14 Part 5).
//
// The hybrid secret always binds BOTH the X25519 output and the PQ
// output. Classical-only operation is possible but NEVER silent: it
// requires explicit user consent and logs a warning. Downgrade attacks
// that strip the PQ component therefore fail closed — the resulting
// secret differs and the peer comparison mismatches.
import 'dart:convert';
import 'dart:typed_data';

import '../../log.dart';
import '../primitives/hkdf.dart';
import '../primitives/rng.dart';

/// Result of hybrid establishment, with its own provenance flags.
class HybridSecret {
  /// 32-byte combined session secret. Wipe with [Csprng.wipe] when done.
  final Uint8List secret;

  /// True when a PQ KEM contributed.
  final bool pqUsed;

  /// True when X25519 contributed (always true).
  final bool classicalUsed;

  /// True when classical-only mode was explicitly consented.
  final bool consentedFallback;

  HybridSecret({
    required Uint8List secret,
    required this.pqUsed,
    required this.classicalUsed,
    required this.consentedFallback,
  }) : secret = Uint8List.fromList(secret);
}

/// HKDF combiner for hybrid key exchange.
class HybridKex {
  HybridKex._();

  /// combined = HKDF(classical || pq, info || context). Every input bit
  /// affects the output; omitting PQ yields a different secret.
  static HybridSecret combine({
    required Uint8List classical,
    required Uint8List pq,
    required Uint8List context,
  }) {
    if (classical.length < 32) {
      throw ArgumentError.value(
        classical.length,
        'classical',
        'Classical output must be at least 32 bytes',
      );
    }
    if (pq.length < 32) {
      throw ArgumentError.value(
        pq.length,
        'pq',
        'PQ output must be at least 32 bytes',
      );
    }
    final secret = Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList([...classical, ...pq]),
      salt: Uint8List.fromList(context),
      info: Uint8List.fromList(utf8.encode('Chhaya-hybrid-v1')),
      length: 32,
    );
    return HybridSecret(
      secret: secret,
      pqUsed: true,
      classicalUsed: true,
      consentedFallback: false,
    );
  }

  /// Classical-only fallback. Throws unless [userConsented] is true,
  /// and always logs. The output is domain-separated from hybrid mode
  /// so fallback secrets can never collide with hybrid secrets.
  static HybridSecret classicalFallback({
    required Uint8List classical,
    required Uint8List context,
    required bool userConsented,
  }) {
    if (!userConsented) {
      throw StateError(
        'Classical-only fallback requires explicit user consent. '
        'No silent downgrade is permitted.',
      );
    }
    ChhayaLog.w(
      'PQ KEM unavailable — classical-only session with user consent',
      name: 'HybridKex',
    );
    final secret = Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList(classical),
      salt: Uint8List.fromList(context),
      info: Uint8List.fromList(utf8.encode('Chhaya-classical-fallback-v1')),
      length: 32,
    );
    return HybridSecret(
      secret: secret,
      pqUsed: false,
      classicalUsed: true,
      consentedFallback: true,
    );
  }
}
