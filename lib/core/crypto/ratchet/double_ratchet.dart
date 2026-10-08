// Double Ratchet engine (V14 Part 4).
//
// X25519 DH ratchet on direction change + symmetric chain ratchet per
// message, following the Signal Double Ratchet structure: root key feeds
// sending/receiving chain keys; each message derives a single-use key
// and advances its chain (forward secrecy). Out-of-order messages are
// served from a bounded single-use skipped-key cache (post-compromise
// healing is preserved: a DH ratchet on direction change reseeds both
// chains from fresh ephemeral output).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' hide Hkdf;

import '../primitives/hkdf.dart';
import '../primitives/rng.dart';
import '../primitives/x25519.dart';
import 'header.dart';
import 'message_keys.dart';
import 'session_state.dart';

/// Base class for ratchet failures. Never carries key material.
class RatchetException implements Exception {
  final String message;
  RatchetException(this.message);

  @override
  String toString() => 'RatchetException: $message';
}

/// Thrown when a session is requested with an unverified peer.
class UnverifiedPeerException extends RatchetException {
  UnverifiedPeerException(String peerId)
      : super(
          'Refusing session with unverified peer "$peerId": verify via '
          'QR scan or Arke handshake (Part 12). Demo/placeholder keys '
          'are rejected outright.',
        );
}

/// Thrown when a peer skips more messages than the cache allows.
class TooManySkippedException extends RatchetException {
  TooManySkippedException(int skipped)
      : super('Peer skipped $skipped messages (max $DoubleRatchet.maxSkip)');
}

/// X25519 Double Ratchet over [SessionState].
class DoubleRatchet {
  DoubleRatchet._();

  /// Maximum messages staged into the skipped cache in one step.
  static const int maxSkip = 1000;

  /// Hard cap on total cached skipped keys (DoS bound).
  static const int maxSkippedTotal = 2000;

  /// Creates a session from a pre-established shared secret (PQXDH in
  /// Part 5 supplies it). Both sides call this with their own role;
  /// chain assignment is role-split so sender/receiver keys agree.
  static Future<SessionState> initSession({
    required String peerId,
    required bool initiator,
    required Uint8List sharedSecret,
    required Uint8List remotePublicKey,

    /// Overrides the fresh DH keypair (tests inject pre-exchanged keys
    /// so both sides agree; production omits it for a fresh keypair).
    Uint8List? ourPrivateKey,
  }) async {
    if (sharedSecret.length < 32) {
      throw ArgumentError.value(
        sharedSecret.length,
        'sharedSecret',
        'Shared secrets must be at least 32 bytes',
      );
    }
    if (remotePublicKey.length != X25519Kex.keyLength) {
      throw ArgumentError.value(
        remotePublicKey.length,
        'remotePublicKey',
        'Remote DH keys must be 32 bytes',
      );
    }
    final ours = await _ourKeyPair(ourPrivateKey);
    final dhOut = await X25519Kex.sharedSecret(
      ours.privateKey,
      remotePublicKey,
    );
    final seed = Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList(sharedSecret),
      salt: dhOut,
      info: Uint8List.fromList(utf8.encode('Chhaya-DR-init-v1')),
      length: 96,
    );
    Csprng.wipe(dhOut);
    final rootKey = Uint8List.fromList(seed.sublist(0, 32));
    final chainA = Uint8List.fromList(seed.sublist(32, 64));
    final chainB = Uint8List.fromList(seed.sublist(64, 96));
    Csprng.wipe(seed);
    return SessionState(
      peerId: peerId,
      initiatedByUs: initiator,
      rootKey: rootKey,
      // The responder's sending chain starts dead: their first send
      // performs a DH ratchet (fresh keypair). Zeros are never used —
      // encrypt() ratchets before deriving.
      sendChainKey: initiator ? chainA : Uint8List(32),
      sendInitialized: initiator,
      recvChainKey: initiator ? chainB : chainA,
      ourPrivateKey: ours.privateKey,
      ourPublicKey: ours.publicKey,
      remotePublicKey: remotePublicKey,
      spqrSeed: Hkdf.deriveKey(
        inputKeyMaterial: Uint8List.fromList(sharedSecret),
        info: Uint8List.fromList(utf8.encode('Chhaya-SPQR-seed-v1')),
        length: 32,
      ),
    );
  }

  /// Resolves our DH keypair: fresh, or derived from an injected key.
  static Future<({Uint8List publicKey, Uint8List privateKey})> _ourKeyPair(
    Uint8List? ourPrivateKey,
  ) async {
    if (ourPrivateKey == null) {
      return X25519Kex.generateKeyPair();
    }
    if (ourPrivateKey.length != X25519Kex.keyLength) {
      throw ArgumentError.value(
        ourPrivateKey.length,
        'ourPrivateKey',
        'X25519 private keys must be 32 bytes',
      );
    }
    final algorithm = X25519();
    final pair =
        await algorithm.newKeyPairFromSeed(List<int>.from(ourPrivateKey));
    final publicKey = await pair.extractPublicKey();
    return (
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: Uint8List.fromList(ourPrivateKey),
    );
  }

  /// Advances the sending chain and returns the header + message key.
  /// The responder's first send performs a DH ratchet first (their
  /// sending chain starts uninitialized by design).
  static Future<({RatchetHeader header, MessageKeyBundle keys})> encrypt(
    SessionState state,
  ) async {
    if (!state.sendInitialized) {
      await _firstSendRatchet(state);
    }
    final stepped = MessageKeys.derive(
      state.sendChainKey,
      state.sendCounter,
    );
    final header = RatchetHeader(
      dhPublicKey: state.ourPublicKey,
      prevChainLength: state.prevSendChainLength,
      messageNumber: state.sendCounter,
    );
    Csprng.wipe(state.sendChainKey);
    state.sendChainKey = stepped.nextChainKey;
    state.sendCounter++;
    return (header: header, keys: stepped.bundle);
  }

  /// First-send ratchet: fresh keypair, evolve root + sending chain
  /// against the peer's advertised key. The receiving chain is
  /// untouched. This is the post-compromise healing step.
  static Future<void> _firstSendRatchet(SessionState state) async {
    Csprng.wipe(state.ourPrivateKey);
    final ours = await X25519Kex.generateKeyPair();
    state.ourPrivateKey = ours.privateKey;
    state.ourPublicKey = ours.publicKey;
    final dhOut = await X25519Kex.sharedSecret(
      state.ourPrivateKey,
      state.remotePublicKey,
    );
    final out = Hkdf.derive64(state.rootKey, dhOut);
    Csprng.wipe(dhOut);
    Csprng.wipe(state.rootKey);
    Csprng.wipe(state.sendChainKey);
    state.rootKey = Uint8List.fromList(out.sublist(0, 32));
    state.sendChainKey = Uint8List.fromList(out.sublist(32, 64));
    Csprng.wipe(out);
    state.prevSendChainLength = state.sendCounter;
    state.sendInitialized = true;
  }

  /// Returns the message key for [header], performing a DH ratchet
  /// when the peer rotated keys. Order matters: the skipped cache is
  /// consulted first (same or older chain), then a new key triggers a
  /// ratchet (which resets the counters), and only then are the
  /// duplicate/gap guards evaluated against the current chain.
  /// Consumed skipped keys are deleted, so a replayed header fails.
  static Future<MessageKeyBundle> decrypt(
    SessionState state,
    RatchetHeader header,
  ) async {
    final skipKey =
        '${_hexOf(header.dhPublicKey)}:${header.messageNumber}';
    final cached = state.skipped.remove(skipKey);
    if (cached != null) {
      return cached;
    }
    if (!_bytesEqual(header.dhPublicKey, state.remotePublicKey)) {
      await _dhRatchet(state, header);
    }
    if (header.messageNumber < state.recvCounter) {
      throw RatchetException(
        'Duplicate or over-delayed message ${header.messageNumber} '
        '(next expected ${state.recvCounter})',
      );
    }
    if (header.messageNumber - state.recvCounter > maxSkip) {
      throw TooManySkippedException(header.messageNumber - state.recvCounter);
    }
    while (state.recvCounter < header.messageNumber) {
      _stageSkipped(state, state.recvCounter);
      state.recvCounter++;
    }
    final stepped = MessageKeys.derive(state.recvChainKey, state.recvCounter);
    Csprng.wipe(state.recvChainKey);
    state.recvChainKey = stepped.nextChainKey;
    state.recvCounter++;
    return stepped.bundle;
  }

  /// DH ratchet: reseed root + receiving chain from the peer's new key,
  /// rotate our key pair, reseed the sending chain. Healing step.
  static Future<void> _dhRatchet(
    SessionState state,
    RatchetHeader header,
  ) async {
    var staged = 0;
    while (state.recvCounter < header.prevChainLength) {
      _stageSkipped(state, state.recvCounter);
      state.recvCounter++;
      staged++;
      if (staged > maxSkip) {
        throw TooManySkippedException(staged);
      }
    }
    final dhOut = await X25519Kex.sharedSecret(
      state.ourPrivateKey,
      header.dhPublicKey,
    );
    final out = Hkdf.derive64(state.rootKey, dhOut);
    Csprng.wipe(dhOut);
    Csprng.wipe(state.rootKey);
    Csprng.wipe(state.recvChainKey);
    state.rootKey = Uint8List.fromList(out.sublist(0, 32));
    state.recvChainKey = Uint8List.fromList(out.sublist(32, 64));
    Csprng.wipe(out);
    state.remotePublicKey = Uint8List.fromList(header.dhPublicKey);
    state.recvGeneration++;
    state.recvCounter = 0;

    Csprng.wipe(state.ourPrivateKey);
    final ours = await X25519Kex.generateKeyPair();
    state.ourPrivateKey = ours.privateKey;
    state.ourPublicKey = ours.publicKey;
    final dhOut2 = await X25519Kex.sharedSecret(
      state.ourPrivateKey,
      state.remotePublicKey,
    );
    final out2 = Hkdf.derive64(state.rootKey, dhOut2);
    Csprng.wipe(dhOut2);
    Csprng.wipe(state.rootKey);
    Csprng.wipe(state.sendChainKey);
    state.rootKey = Uint8List.fromList(out2.sublist(0, 32));
    state.sendChainKey = Uint8List.fromList(out2.sublist(32, 64));
    Csprng.wipe(out2);
    state.prevSendChainLength = state.sendCounter;
    state.sendCounter = 0;
  }

  /// Constant-time byte comparison for public keys.
  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Derives-and-discards one receiving key into the skipped cache,
  /// filed under the current (old) sending chain's public key.
  static void _stageSkipped(SessionState state, int counter) {
    if (state.skipped.length >= maxSkippedTotal) {
      throw RatchetException(
        'Skipped-key cache full ($maxSkippedTotal) — peer must ratchet',
      );
    }
    final stepped = MessageKeys.derive(state.recvChainKey, counter);
    Csprng.wipe(state.recvChainKey);
    state.recvChainKey = stepped.nextChainKey;
    state.skipped['${_hexOf(state.remotePublicKey)}:$counter'] =
        stepped.bundle;
  }

  static String _hexOf(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
