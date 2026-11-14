// Delayed reseed chain (spec §3.9).
//
// Second ratchet dimension alongside the X25519 Double Ratchet. The epoch
// seed evolves one-way per epoch: the next seed is HKDF of the previous
// one, so holding the live seed never yields earlier epoch keys, and the
// intermediate seeds are wiped as the chain steps. The deterministic
// epoch derivation within the skip window stays: an epoch key is
// HKDF(seed_n, 'Chhaya-SPQR-v1' || u32be(epoch)).
//
// Epoch keys are derivable only inside the skip window: past in-window
// epoch keys are served from a bounded single-generation cache (keyed by
// generation:epoch, capped), and anything older — or any jump beyond
// [maxSkip] — is refused. Fresh ML-KEM-1024 material arrives via the
// sparse reseed ([applyReseed]); both sides wipe the injected output.
//
// The reseed flight rides the normal authenticated envelope path (a
// trailing section of the ratchet header); there is never an in-message
// network round-trip. See docs/spec-pq-hybrid-resync-v1.md §3.9.
import 'dart:convert';
import 'dart:typed_data';

import '../primitives/hkdf.dart';
import '../primitives/rng.dart';
import 'double_ratchet.dart' show RatchetException, TooManySkippedException;
import 'session_state.dart';

/// Async source of post-quantum key material.
///
/// Contract: returns 32 bytes of fresh PQ-derived output bound to
/// [context]. Primitive availability never enables a messaging path by
/// itself; callers gate all use on the feature flag and on
/// [isAvailable]/[initialize] succeeding (fail closed otherwise).
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

/// Structural seam for the delayed ML-KEM reseed (spec §3.9).
///
/// This mirrors the provider abstraction used everywhere else for PQ
/// primitives without importing the PQ modules into the ratchet layer:
/// production wires the ML-KEM-1024 provider through an adapter that is
/// only passed in when the feature flag is on and the provider is usable.
/// When no provider is available the caller simply passes null and the
/// session silently continues on the classical chain — no crash, no
/// claim, no behaviour change.
abstract class ReseedKem {
  /// True only after the native implementation passes its self-check.
  bool get isAvailable;

  /// Initializes the provider and runs its native self-check when required.
  Future<bool> initialize();

  /// Generates a fresh keypair. Throws when the provider cannot produce
  /// one (callers treat that as "reseed unavailable", never as fatal).
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair();

  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  );

  Future<Uint8List> decapsulate(Uint8List privateKey, Uint8List ciphertext);
}

/// Thrown when an epoch key is no longer derivable (its seed was retired
/// and the epoch fell outside the skipped-message window).
class EpochKeyUnavailableException extends RatchetException {
  EpochKeyUnavailableException(int epoch)
      : super('Epoch key for epoch $epoch is no longer derivable');
}

/// One-way hash-step chain over the session seed.
class SpqrChain {
  SpqrChain._();

  /// Messages per chain epoch (spec-locked).
  static const int advanceEvery = 10;

  /// Maximum epoch jump honoured before giving up (spec §3.10 discipline,
  /// mirrors the message-level [DoubleRatchet.maxSkip]).
  static const int maxSkip = 1000;

  /// Epochs within the skipped-message window (1000 messages / 10).
  static const int epochSkipWindow = maxSkip ~/ advanceEvery;

  /// Bounded cache of retired-generation epoch keys. Holds the window on
  /// either side of a reseed transition.
  static const int epochKeyCacheLimit = 2 * epochSkipWindow;

  /// One-way step: `seed_{n+1} = HKDF(seed_n, "Chhaya-SPQR-step-v1" || u32be(n+1))`.
  /// Compromising seed_{n+1} does not reveal seed_n.
  static Uint8List stepSeed(Uint8List seed, int nextIndex) {
    if (seed.length < 32) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'Chain seeds must be at least 32 bytes',
      );
    }
    if (nextIndex < 0 || nextIndex > 0xFFFFFFFF) {
      throw ArgumentError.value(nextIndex, 'nextIndex', 'Index must fit in u32');
    }
    final indexBytes = Uint8List(4)..buffer.asByteData().setUint32(0, nextIndex);
    return Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList(seed),
      info: Uint8List.fromList(
        [...utf8.encode('Chhaya-SPQR-step-v1'), ...indexBytes],
      ),
      length: 32,
    );
  }

  /// Epoch key for [epoch] derived from the seed *at* that epoch:
  /// `epochKey_n = HKDF(seed_n, "Chhaya-SPQR-v1" || u32be(epoch))`.
  ///
  /// [seed] must be the seed positioned at [epoch] (see [epochKey] for the
  /// state-aware wrapper that steps and wipes as it goes).
  static Uint8List chainKeyFor(Uint8List seed, int epoch) {
    if (seed.length < 32) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'Chain seeds must be at least 32 bytes',
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

  static String _cacheKey(int generation, int epoch) => '$generation:$epoch';

  static void _cacheEpochKey(
    SessionState state,
    int epoch,
    Uint8List key,
  ) {
    final k = _cacheKey(state.spqrGeneration, epoch);
    state.spqrEpochKeys[k] = Uint8List.fromList(key);
    while (state.spqrEpochKeys.length > epochKeyCacheLimit) {
      final oldest = state.spqrEpochKeys.keys.first;
      Csprng.wipe(state.spqrEpochKeys.remove(oldest)!);
    }
  }

  /// Returns the epoch key for [epoch] from [state], stepping the chain
  /// forward one-way when [epoch] is in the future (retiring seeds are
  /// wiped), serving past in-window keys from the cache, and refusing
  /// everything else. Advances `state.spqrEpoch`/`state.spqrSeed`.
  ///
  /// Throws [TooManySkippedException] when [epoch] is more than [maxSkip]
  /// ahead — the state is left untouched. Throws
  /// [EpochKeyUnavailableException] when a past epoch's key was retired.
  static Uint8List epochKey(SessionState state, int epoch) {
    if (epoch < 0 || epoch > 0xFFFFFFFF) {
      throw ArgumentError.value(epoch, 'epoch', 'Epoch must fit in u32');
    }
    final gap = epoch - state.spqrEpoch;
    if (gap > maxSkip) {
      throw TooManySkippedException(gap);
    }
    if (gap < 0) {
      final cached = state.spqrEpochKeys[_cacheKey(state.spqrGeneration, epoch)];
      if (cached != null) {
        return Uint8List.fromList(cached);
      }
      throw EpochKeyUnavailableException(epoch);
    }
    var seed = Uint8List.fromList(state.spqrSeed);
    for (var e = state.spqrEpoch; e < epoch; e++) {
      _cacheEpochKey(state, e, chainKeyFor(seed, e));
      final next = stepSeed(seed, e + 1);
      Csprng.wipe(seed);
      seed = next;
    }
    state.rotateSpqrSeed(seed);
    Csprng.wipe(seed);
    state.spqrEpoch = epoch;
    return chainKeyFor(state.spqrSeed, epoch);
  }

  /// True when [state] can still derive [epoch] without advancing — a
  /// read-only pre-flight used so decrypt can fail before any state
  /// mutation.
  static bool epochKeyAvailable(SessionState state, int epoch) {
    if (epoch < 0 || epoch > 0xFFFFFFFF) return false;
    final gap = epoch - state.spqrEpoch;
    if (gap > maxSkip) return false;
    if (gap >= 0) return true;
    return state.spqrEpochKeys.containsKey(
      _cacheKey(state.spqrGeneration, epoch),
    );
  }

  /// Pre-derives in-window epoch keys for the retiring generation so
  /// messages in flight during a reseed transition still decrypt.
  static void _preDeriveRetiring(SessionState state) {
    var retire = Uint8List.fromList(state.spqrSeed);
    for (var e = state.spqrEpoch; e < state.spqrEpoch + epochSkipWindow; e++) {
      _cacheEpochKey(state, e, chainKeyFor(retire, e));
      final next = stepSeed(retire, e + 1);
      Csprng.wipe(retire);
      retire = next;
    }
    Csprng.wipe(retire);
  }

  /// Applies a delayed reseed: both sides call this with the shared
  /// secret from the ML-KEM encapsulation. The new seed is
  /// `HKDF(step(seed, generation+1) || SS_reseed, "Chhaya-SPQR-reseed-v1")`
  /// (spec §3.9); the retiring seed is wiped and `state.spqrGeneration`
  /// is incremented. Epoch continuity is preserved — epoch numbers are not
  /// reused across generations.
  static void applyReseed(SessionState state, Uint8List sharedSecret) {
    if (sharedSecret.length < 32) {
      throw ArgumentError.value(
        sharedSecret.length,
        'sharedSecret',
        'Reseed outputs must be at least 32 bytes',
      );
    }
    _preDeriveRetiring(state);
    final stepped = stepSeed(
      Uint8List.fromList(state.spqrSeed),
      state.spqrGeneration + 1,
    );
    final newSeed = reseed(stepped, sharedSecret);
    Csprng.wipe(stepped);
    state.rotateSpqrSeed(newSeed);
    Csprng.wipe(newSeed);
    state.spqrGeneration += 1;
    state.reseedSendCounter = 0;
    state.reseedLastAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Reseeds with fresh PQ output (delayed reseed, spec §3.9).
  /// Returns the new seed; the caller wipes the old one via
  /// [SessionState.rotateSpqrSeed]. [sharedSecret] is wiped here.
  static Uint8List reseed(Uint8List seed, Uint8List pqOutput, {int? nextIndex}) {
    if (pqOutput.length < 32) {
      throw ArgumentError.value(
        pqOutput.length,
        'pqOutput',
        'Reseed outputs must be at least 32 bytes',
      );
    }
    Uint8List input = seed;
    var stepped = false;
    if (nextIndex != null) {
      input = stepSeed(seed, nextIndex);
      stepped = true;
    }
    final next = Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList([...input, ...pqOutput]),
      info: Uint8List.fromList(utf8.encode('Chhaya-SPQR-reseed-v1')),
      length: 32,
    );
    if (stepped) {
      Csprng.wipe(input);
    }
    Csprng.wipe(pqOutput);
    return next;
  }
}
