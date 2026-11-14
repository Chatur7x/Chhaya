// Ratchet session state (V14 Part 4).
//
// Serializable snapshot of one Double Ratchet + delayed-reseed session
// (spec §3.9). All key material is base64 in JSON; [wipe] zeroizes
// in-memory secrets. Persistence itself lives in session_store.dart.
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

  /// Delayed-reseed chain seed (spec §3.9); epoch advances per 10 sends.
  /// Advanced one-way as epochs step; rotated on every reseed.
  Uint8List spqrSeed;
  int spqrEpoch;

  /// Retired-generation epoch keys kept for the skipped-message window,
  /// keyed by 'generation:epoch'. Bounded by
  /// SpqrChain.epochKeyCacheLimit; entries are single-generation and are
  /// wiped on eviction and on [wipe].
  final Map<String, Uint8List> spqrEpochKeys;

  /// Number of reseed transitions applied (bumped on every delayed
  /// reseed). Used to key the epoch-key cache so retiring and current
  /// generations never collide.
  int spqrGeneration;

  /// Sends since the last reseed was initiated (cadence bookkeeping,
  /// persisted with the session).
  int reseedSendCounter;

  /// Wall-clock ms when the last reseed was initiated (cadence
  /// bookkeeping, persisted with the session).
  int reseedLastAtMs;

  /// Our freshly generated ML-KEM keypair offered for a delayed reseed,
  /// awaiting the peer's encapsulation. Private key is in-memory/at-rest
  /// secret material exactly like the DH keys; wiped on transition.
  Uint8List? pendingReseedPublicKey;
  Uint8List? pendingReseedPrivateKey;

  /// Peer's advertised reseed public key; we encapsulate to it on our
  /// next send and return the ciphertext in the trailing reseed section.
  Uint8List? peerReseedPublicKey;

  /// 1 = legacy classical session, 2 = v2 hybrid PQXDH session.
  /// Absent in JSON ⇒ legacy (backwards compatible).
  final int sessionVersion;

  /// v2 only: the canonical transcript T; bound into AEAD additional data.
  final Uint8List? transcript;

  /// v2 classical-consent fallback markers (spec §3.5 rule 5): the session
  /// used the consented classical suite, never a PQ suite.
  final bool nonPQ;
  final bool consented;

  /// v2 establishment flight this session was derived from (public prekey
  /// and ephemeral material). Included on outbound v2 envelopes until the
  /// peer proves freshness with an AEAD-valid inbound. Not secret.
  final Map<String, dynamic>? establishFlight;

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
    this.spqrGeneration = 0,
    this.reseedSendCounter = 0,
    int? reseedLastAtMs,
    Uint8List? pendingReseedPublicKey,
    Uint8List? pendingReseedPrivateKey,
    Uint8List? peerReseedPublicKey,
    this.sessionVersion = 1,
    Uint8List? transcript,
    this.nonPQ = false,
    this.consented = false,
    Map<String, dynamic>? establishFlight,
    Map<String, MessageKeyBundle>? skipped,
    Map<String, Uint8List>? spqrEpochKeys,
  })  : rootKey = Uint8List.fromList(rootKey),

        sendChainKey = Uint8List.fromList(sendChainKey),
        recvChainKey = Uint8List.fromList(recvChainKey),
        ourPrivateKey = Uint8List.fromList(ourPrivateKey),
        ourPublicKey = Uint8List.fromList(ourPublicKey),
        transcript = transcript == null ? null : Uint8List.fromList(transcript),
        establishFlight = establishFlight == null
            ? null
            : Map<String, dynamic>.from(establishFlight),
        remotePublicKey = Uint8List.fromList(remotePublicKey),
        spqrSeed = Uint8List.fromList(spqrSeed),
        pendingReseedPublicKey = pendingReseedPublicKey == null
            ? null
            : Uint8List.fromList(pendingReseedPublicKey),
        pendingReseedPrivateKey = pendingReseedPrivateKey == null
            ? null
            : Uint8List.fromList(pendingReseedPrivateKey),
        peerReseedPublicKey = peerReseedPublicKey == null
            ? null
            : Uint8List.fromList(peerReseedPublicKey),
        spqrEpochKeys = spqrEpochKeys == null
            ? {}
            : Map<String, Uint8List>.fromEntries(
                spqrEpochKeys.entries
                    .map((e) => MapEntry(e.key, Uint8List.fromList(e.value))),
              ),
        reseedLastAtMs =
            reseedLastAtMs ?? DateTime.now().millisecondsSinceEpoch,
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
        'spqrGeneration': spqrGeneration,
        'reseedSendCounter': reseedSendCounter,
        'reseedLastAtMs': reseedLastAtMs,
        'spqrEpochKeys': spqrEpochKeys.map(
          (k, v) => MapEntry(k, base64Encode(v)),
        ),
        if (pendingReseedPublicKey != null)
          'pendingReseedPublicKey': base64Encode(pendingReseedPublicKey!),
        if (pendingReseedPrivateKey != null)
          'pendingReseedPrivateKey': base64Encode(pendingReseedPrivateKey!),
        if (peerReseedPublicKey != null)
          'peerReseedPublicKey': base64Encode(peerReseedPublicKey!),
        'skipped': skipped.map(
          (k, v) => MapEntry(k, {
            'key': base64Encode(v.messageKey),
            'nonce': base64Encode(v.nonce),
          }),
        ),
        'sessionVersion': sessionVersion,
        if (transcript != null) 'transcript': base64Encode(transcript!),
        'nonPQ': nonPQ,
        'consented': consented,
        if (establishFlight != null) 'establishFlight': establishFlight,
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
    final epochKeysRaw = json['spqrEpochKeys'];
    final spqrEpochKeys = <String, Uint8List>{};
    if (epochKeysRaw is Map) {
      for (final entry in epochKeysRaw.entries) {
        final v = entry.value;
        if (v is! String) {
          throw const FormatException('Corrupt epoch key cache entry');
        }
        spqrEpochKeys[entry.key as String] = base64Decode(v);
      }
    }
    Uint8List? readBytes(String field) {
      final raw = json[field];
      return raw is String ? base64Decode(raw) : null;
    }

    final transcriptRaw = json['transcript'];
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
      spqrGeneration: json['spqrGeneration'] as int? ?? 0,
      reseedSendCounter: json['reseedSendCounter'] as int? ?? 0,
      reseedLastAtMs: json['reseedLastAtMs'] as int?,
      pendingReseedPublicKey: readBytes('pendingReseedPublicKey'),
      pendingReseedPrivateKey: readBytes('pendingReseedPrivateKey'),
      peerReseedPublicKey: readBytes('peerReseedPublicKey'),
      spqrEpochKeys: spqrEpochKeys,
      skipped: skipped,
      sessionVersion: json['sessionVersion'] as int? ?? 1,
      transcript: transcriptRaw == null ? null : base64Decode(transcriptRaw as String),
      nonPQ: json['nonPQ'] as bool? ?? false,
      consented: json['consented'] as bool? ?? false,
      establishFlight: json['establishFlight'] == null
          ? null
          : Map<String, dynamic>.from(json['establishFlight'] as Map),
    );
  }

  /// Returns a copy with v2 session fields replaced. Used right after
  /// establishment to stamp the negotiated suite outcome onto the
  /// Double Ratchet session (spec §3.4/§3.11).
  SessionState copyWith({
    int? sessionVersion,
    Uint8List? transcript,
    bool? nonPQ,
    bool? consented,
    Map<String, dynamic>? establishFlight,
  }) =>
      SessionState(
        peerId: peerId,
        initiatedByUs: initiatedByUs,
        rootKey: rootKey,
        sendChainKey: sendChainKey,
        sendCounter: sendCounter,
        prevSendChainLength: prevSendChainLength,
        sendInitialized: sendInitialized,
        recvChainKey: recvChainKey,
        recvCounter: recvCounter,
        recvGeneration: recvGeneration,
        ourPrivateKey: ourPrivateKey,
        ourPublicKey: ourPublicKey,
        remotePublicKey: remotePublicKey,
        spqrSeed: spqrSeed,
        spqrEpoch: spqrEpoch,
        spqrGeneration: spqrGeneration,
        reseedSendCounter: reseedSendCounter,
        reseedLastAtMs: reseedLastAtMs,
        pendingReseedPublicKey: pendingReseedPublicKey,
        pendingReseedPrivateKey: pendingReseedPrivateKey,
        peerReseedPublicKey: peerReseedPublicKey,
        spqrEpochKeys: Map<String, Uint8List>.from(spqrEpochKeys),
        sessionVersion: sessionVersion ?? this.sessionVersion,
        transcript: transcript ?? this.transcript,
        nonPQ: nonPQ ?? this.nonPQ,
        consented: consented ?? this.consented,
        establishFlight: establishFlight ?? this.establishFlight,
        skipped: skipped,
      );

  /// Replaces the chain seed with [newSeed], wiping the retiring seed.
  /// Called by the delayed-reseed transition and by the one-way epoch
  /// stepping.
  void rotateSpqrSeed(Uint8List newSeed) {
    Csprng.wipe(spqrSeed);
    spqrSeed = Uint8List.fromList(newSeed);
  }

  /// Zeroizes all in-memory key material (structure stays usable).
  void wipe() {
    Csprng.wipe(rootKey);
    if (transcript != null) {
      Csprng.wipe(transcript!);
    }
    Csprng.wipe(sendChainKey);
    Csprng.wipe(recvChainKey);
    Csprng.wipe(ourPrivateKey);
    Csprng.wipe(spqrSeed);
    if (pendingReseedPublicKey != null) {
      Csprng.wipe(pendingReseedPublicKey!);
    }
    if (pendingReseedPrivateKey != null) {
      Csprng.wipe(pendingReseedPrivateKey!);
    }
    if (peerReseedPublicKey != null) {
      Csprng.wipe(peerReseedPublicKey!);
    }
    for (final v in spqrEpochKeys.values) {
      Csprng.wipe(v);
    }
    spqrEpochKeys.clear();
    for (final v in skipped.values) {
      v.wipe();
    }
    skipped.clear();
  }
}
