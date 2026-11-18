// Dual-KEM combiner, CRYPTO SHIELD algorithm diversity (V14 Part 5).
//
// Combines two independent KEM outputs (primary: ML-KEM slot,
// secondary: NTRU slot) so a break in either algorithm alone does not
// expose the session. Combination is HKDF over the concatenation —
// order-fixed, context-bound, length-checked.
import 'dart:convert';
import 'dart:typed_data';

import '../primitives/hkdf.dart';
import 'pqc_provider.dart';

/// Combines two KEM shared secrets with domain separation.
class DualKem {
  DualKem._();

  /// combined = HKDF(primary || secondary, info='Chhaya-dualkem-v1'||ctx).
  /// Both inputs must be at least 32 bytes; outputs 32 bytes.
  static Uint8List combine({
    required Uint8List primary,
    required Uint8List secondary,
    required Uint8List context,
  }) {
    if (primary.length < 32) {
      throw ArgumentError.value(
        primary.length,
        'primary',
        'KEM outputs must be at least 32 bytes',
      );
    }
    if (secondary.length < 32) {
      throw ArgumentError.value(
        secondary.length,
        'secondary',
        'KEM outputs must be at least 32 bytes',
      );
    }
    final inputKeyMaterial = Uint8List.fromList([...primary, ...secondary]);
    try {
      return Hkdf.deriveKey(
        inputKeyMaterial: inputKeyMaterial,
        salt: Uint8List.fromList(context),
        info: Uint8List.fromList(utf8.encode('Chhaya-dualkem-v1')),
        length: 32,
      );
    } finally {
      inputKeyMaterial.fillRange(0, inputKeyMaterial.length, 0);
    }
  }

  /// Runs [primary] and [secondary] KEMs and combines. Either being
  /// unavailable aborts — no silent single-KEM fallback.
  static Future<Uint8List> establish({
    required PqKem primary,
    required PqKem secondary,
    required Uint8List primaryPublicKey,
    required Uint8List secondaryPublicKey,
    required Uint8List context,
  }) async {
    if (!await primary.initialize()) {
      throw PqcUnavailableException(primary.name);
    }
    if (!await secondary.initialize()) {
      throw PqcUnavailableException(secondary.name);
    }
    final a = await primary.encapsulate(primaryPublicKey);
    try {
      final b = await secondary.encapsulate(secondaryPublicKey);
      try {
        return combine(
          primary: a.sharedSecret,
          secondary: b.sharedSecret,
          context: context,
        );
      } finally {
        b.sharedSecret.fillRange(0, b.sharedSecret.length, 0);
      }
    } finally {
      a.sharedSecret.fillRange(0, a.sharedSecret.length, 0);
    }
  }
}
