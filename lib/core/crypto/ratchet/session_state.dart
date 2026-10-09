// Ratchet session state (V14 Part 4).
//
// Serializable snapshot of one Double Ratchet + SPQR session. All key
// material is base64 in JSON; [wipe] zeroizes in-memory secrets.
// Persistence itself lives in session_store.dart.
import 'dart:convert';
import 'dart:typed_data';

import '../primitives/rng.dart';
import 'message_keys.dart';

/// Mutable snapshot of a single peer session.
class SessionState {
  /// Stable peer identifier (Contact.id), never key material.
  final String peerId;

  /// True when this side created the session (drives chain roles).
  final bool initiatedByUs;

  /// 32-byte root key. Reassigned by DH ratchet steps (not just mutated).
  Uint8List rootKey;

  /// Current sending chain key / next message number / previous length.
  Uint8List sendChainKey;

  /// Whether the sending chain is live. The responder's sending chain
  /// starts uninitialized: their first send performs a DH ratchet
  /// (fresh keypair), which is what heals the session after any
  /// compromise of the initial secret.
  bool sendInitialized;
  int sendCounter;
  int prevSendChainLength;

  /// Current receiving chain key / next expected number / generation id.
  /// [recvGeneration] increments on every DH ratchet so skipped keys
  /// from older chains can never collide with newer ones.
  Uint8List recvChainKey;
  int recvCounter;
  int recvGeneration;

  /// Our current DH key pair (private kept in memory only).
  Uint8List ourPrivateKey;
  Uint8List ourPublicKey;

  /// Peer's latest advertised DH public key.
  Uint8List remotePublicKey;

  /// Out-of-order message keys, keyed by sending chain public key
  /// (hex) plus message number, joined by a colon.
  /// Single-use: entries are removed on first use (no replays). Keying
  /// by chain (not generation) keeps staged keys reachable after later
  /// DH ratchets, exactly like Signal's per-sender-chain cache.
  final Map<String, MessageKeyBundle> skipped;

  /// SPQR seed shared at session start; epoch advances per 10 sends.
  final Uint8List spqrSeed;
  int spqrEpoch;

  SessionState({
    required this.peerId,
    required this.initiatedByUs,
    required Uint8List rootKey,
    required Uint8List sendChainKey,
    required Uint8List recvChainKey,
    required Uint8List ourPrivateKey,
    required Uint8List ourPublicKey,
    required Uint8List remotePublicKey,
    required Uint8List spqrSeed,
    this.sendCounter = 0,
    this.prevSendChainLength = 0,
    this.sendInitialized = true,
    this.recvCounter = 0,
    this.recvGeneration = 0,
    this.spqrEpoch = 0,
    Map<String, MessageKeyBundle>? skipped,
  })  : rootKey = Uint8List.fromList(rootKey),
        sendChainKey = Uint8List.fromList(sendChainKey),
        recvChainKey = Uint8List.fromList(recvChainKey),
        ourPrivateKey = Uint8List.fromList(ourPrivateKey),
        ourPublicKey = Uint8List.fromList(ourPublicKey),
        remotePublicKey = Uint8List.fromList(remotePublicKey),
        spqrSeed = Uint8List.fromList(spqrSeed),
        skipped = skipped ?? {};

  /// Serializes to JSON-safe primitives (bytes as base64).
  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'initiatedByUs': initiatedByUs,
        'rootKey': base64Encode(rootKey),
        'sendChainKey': base64Encode(sendChainKey),
        'sendCounter': sendCounter,
        'prevSendChainLength': prevSendChainLength,
        'sendInitialized': sendInitialized,
        'recvChainKey': base64Encode(recvChainKey),
        'recvCounter': recvCounter,
        'recvGeneration': recvGeneration,
        'ourPrivateKey': base64Encode(ourPrivateKey),
        'ourPublicKey': base64Encode(ourPublicKey),
        'remotePublicKey': base64Encode(remotePublicKey),
        'spqrSeed': base64Encode(spqrSeed),
        'spqrEpoch': spqrEpoch,
        'skipped': skipped.map(
          (k, v) => MapEntry(k, {
            'key': base64Encode(v.messageKey),
            'nonce': base64Encode(v.nonce),
          }),
        ),
      };

  /// Restores a snapshot. Throws [FormatException] on corrupt input —
  /// callers treat a corrupt session as lost, never as usable.
  factory SessionState.fromJson(Map<String, dynamic> json) {
    Uint8List b64(String field) {
      final raw = json[field];
      if (raw is! String) {
        throw FormatException('Session field $field missing');
      }
      return base64Decode(raw);
    }

    final skippedRaw = json['skipped'];
    if (skippedRaw is! Map) {
      throw const FormatException('Session field skipped missing');
    }
    final skipped = <String, MessageKeyBundle>{};
    for (final entry in skippedRaw.entries) {
      final v = entry.value;
      if (v is! Map || v['key'] is! String || v['nonce'] is! String) {
        throw const FormatException('Corrupt skipped key entry');
      }
      skipped[entry.key as String] = MessageKeyBundle(
        messageKey: base64Decode(v['key'] as String),
        nonce: base64Decode(v['nonce'] as String),
      );
    }
    return SessionState(
      peerId: json['peerId'] as String,
      initiatedByUs: json['initiatedByUs'] as bool,
      rootKey: b64('rootKey'),
      sendChainKey: b64('sendChainKey'),
      sendCounter: json['sendCounter'] as int,
      prevSendChainLength: json['prevSendChainLength'] as int,
      sendInitialized: json['sendInitialized'] as bool? ?? true,
      recvChainKey: b64('recvChainKey'),
      recvCounter: json['recvCounter'] as int,
      recvGeneration: json['recvGeneration'] as int,
      ourPrivateKey: b64('ourPrivateKey'),
      ourPublicKey: b64('ourPublicKey'),
      remotePublicKey: b64('remotePublicKey'),
      spqrSeed: b64('spqrSeed'),
      spqrEpoch: json['spqrEpoch'] as int,
      skipped: skipped,
    );
  }

  /// Zeroizes all in-memory key material (structure stays usable).
  void wipe() {
    Csprng.wipe(rootKey);
    Csprng.wipe(sendChainKey);
    Csprng.wipe(recvChainKey);
    Csprng.wipe(ourPrivateKey);
    Csprng.wipe(spqrSeed);
    for (final v in skipped.values) {
      v.wipe();
    }
    skipped.clear();
  }
}
