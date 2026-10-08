// Hybrid PQXDH session establishment (V14 Part 5).
//
// Orchestrates one session establishment: X25519 (Part 1, audited)
// always runs; the PQ KEM runs when an approved provider exists.
// Output is a [HybridSecret] whose flags record exactly what
// contributed — callers (Part 4 TripleRatchet) feed it forward, and
// UI (Part 8) surfaces non-PQ sessions honestly.
import 'dart:typed_data';

import '../primitives/x25519.dart';
import 'hybrid_kex.dart';
import 'pqc_provider.dart';

/// Establishes hybrid session secrets.
class Pqxdh {
  Pqxdh._();

  /// Runs X25519 against [remotePublicKey] with our fresh keypair and
  /// combines with [pqKem] output. Without an available KEM the call
  /// fails closed unless [allowClassicalFallback] AND [userConsented]
  /// are both true.
  static Future<({HybridSecret secret, Uint8List ourPublicKey})> establish({
    required Uint8List remotePublicKey,
    PqKem? pqKem,
    Uint8List? pqPublicKey,
    required Uint8List context,
    bool allowClassicalFallback = false,
    bool userConsented = false,
  }) async {
    final ours = await X25519Kex.generateKeyPair();
    final classical = await X25519Kex.sharedSecret(
      ours.privateKey,
      remotePublicKey,
    );
    try {
      if (pqKem != null && pqKem.isAvailable && pqPublicKey != null) {
        final enc = await pqKem.encapsulate(pqPublicKey);
        final secret = HybridKex.combine(
          classical: classical,
          pq: enc.sharedSecret,
          context: context,
        );
        return (secret: secret, ourPublicKey: ours.publicKey);
      }
      if (!allowClassicalFallback || !userConsented) {
        throw StateError(
          'No approved PQ KEM available and classical fallback was '
          'not consented. Refusing to establish.',
        );
      }
      final secret = HybridKex.classicalFallback(
        classical: classical,
        context: context,
        userConsented: true,
      );
      return (secret: secret, ourPublicKey: ours.publicKey);
    } finally {
      // Classical output is consumed into the combiner; wipe the copy.
      for (var i = 0; i < classical.length; i++) {
        classical[i] = 0;
      }
    }
  }
}
