// CSPRNG wrapper for Chhaya cryptography.
//
// Purpose: single source of cryptographically secure randomness. Seeds a
// PointyCastle Fortuna PRNG from Dart's `Random.secure()` (OS entropy).
// Also owns key zeroization via [Csprng.wipe]. Never use `Random()` for
// anything security-sensitive.
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;

/// Cryptographically secure random number generator.
///
/// Backed by Fortuna, seeded once from OS entropy. Use [Csprng.instance]
/// for app code; use [Csprng.create] in tests for isolation.
class Csprng {
  Csprng._(this._random);

  final pc.SecureRandom _random;

  static Csprng? _instance;

  /// Shared application instance, lazily created.
  static Csprng get instance {
    return _instance ??= Csprng.create();
  }

  /// Creates an independently seeded generator.
  static Csprng create() {
    final fortuna = pc.FortunaRandom();
    final seedSource = Random.secure();
    final seed = List<int>.generate(32, (_) => seedSource.nextInt(256));
    fortuna.seed(pc.KeyParameter(Uint8List.fromList(seed)));
    return Csprng._(fortuna);
  }

  /// Returns [count] cryptographically secure random bytes.
  Uint8List bytes(int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'Must be positive');
    }
    return _random.nextBytes(count);
  }

  /// Returns a lowercase hex string of [byteLength] random bytes.
  String hex(int byteLength) {
    final raw = bytes(byteLength);
    final out = StringBuffer();
    for (final b in raw) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    wipe(raw);
    return out.toString();
  }

  /// Overwrites [secret] with zeros in place.
  ///
  /// Call this on key material as soon as it is no longer needed.
  static void wipe(Uint8List secret) {
    secret.fillRange(0, secret.length, 0);
  }
}
