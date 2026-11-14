// Triple Ratchet facade (V14 Part 4).
//
// Combines the X25519 Double Ratchet with the delayed-reseed epoch
// chain (spec §3.9):
//   messageKey = HKDF(dhMessageKey || chainKey, counter)
// The DH step runs on direction change; the epoch advances every
// 10 sent messages. Session start validates the peer (verified only).
//
// Delayed reseed (spec §3.9): the session initiator's side advertises a
// fresh ML-KEM-1024 keypair every ~25 sends or ≥7 days (whichever
// first), carried in an optional trailing soft-extension section of the
// ratchet header. The other side encapsulates to it on its next message
// and returns the ciphertext the same way. Both sides then derive
// HKDF(step(seed, generation+1) || SS_reseed, "Chhaya-SPQR-reseed-v1")
// and switch to the next chain state. The flight rides the normal
// authenticated envelope path — there is never an in-message network
// round-trip. Legacy parsers tolerate the trailing section: the fixed
// 44-byte prefix is unchanged and unknown trailing sections are skipped.
//
// Audit status: [ ] Ready for external audit. When no reseed provider is
// available the flight silently stays classical; the session works
// untouched. No user-facing claim depends on any of this.
import 'dart:convert';
import 'dart:typed_data';

import '../../models/contact.dart';
import '../primitives/hkdf.dart';
import '../primitives/rng.dart';
import 'double_ratchet.dart';
import 'header.dart';
import 'message_keys.dart';
import 'session_state.dart';
import 'spqr.dart';

/// Wire header: 40-byte DH header + u32be epoch + optional trailing
/// soft-extension sections (44 bytes when absent).
class TripleHeader {
  static const int encodedLength = RatchetHeader.encodedLength + 4;

  /// Hard bound on the trailing soft-extension blob (DoS guard).
  static const int maxTrailingBytes = 8192;

  static const int _pqTag = 0x7071; // 'pq'

  final RatchetHeader dh;
  final int spqrEpoch;

  /// Parsed delayed-reseed payload, or null when absent/ignored. Covered
  /// by AEAD additional data like every other header byte; it carries no
  /// authenticity of its own.
  final Map<String, dynamic>? pq;

  /// Raw trailing sections; echoed byte-for-byte on re-encode so a
  /// lenient parse never corrupts what AEAD covers.
  final Uint8List _trailing;

  TripleHeader({required this.dh, required this.spqrEpoch, this.pq})
      : _trailing = pq == null ? Uint8List(0) : _encodePqSection(pq) {
    if (spqrEpoch < 0 || spqrEpoch > 0xFFFFFFFF) {
      throw ArgumentError.value(
        spqrEpoch,
        'spqrEpoch',
        'Epoch must fit in u32',
      );
    }
  }

  TripleHeader._({
    required this.dh,
    required this.spqrEpoch,
    required this.pq,
    required Uint8List trailing,
  }) : _trailing = Uint8List.fromList(trailing) {
    if (spqrEpoch < 0 || spqrEpoch > 0xFFFFFFFF) {
      throw ArgumentError.value(
        spqrEpoch,
        'spqrEpoch',
        'Epoch must fit in u32',
      );
    }
  }

  /// Wire length of the trailing section (0 when the header is fixed).
  int get trailingLength => _trailing.length;

  Uint8List toBytes() {
    final out = Uint8List(encodedLength + _trailing.length);
    out.setRange(0, RatchetHeader.encodedLength, dh.toBytes());
    ByteData.sublistView(out).setUint32(RatchetHeader.encodedLength, spqrEpoch);
    if (_trailing.isNotEmpty) {
      out.setRange(encodedLength, out.length, _trailing);
    }
    return out;
  }

  factory TripleHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < encodedLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Headers must be at least $encodedLength bytes',
      );
    }
    final trailing = bytes.length == encodedLength
        ? Uint8List(0)
        : Uint8List.fromList(bytes.sublist(encodedLength));
    if (trailing.length > maxTrailingBytes) {
      throw ArgumentError.value(
        trailing.length,
        'bytes',
        'Trailing sections exceed $maxTrailingBytes bytes',
      );
    }
    return TripleHeader._(
      dh: RatchetHeader.fromBytes(
        Uint8List.fromList(bytes.sublist(0, RatchetHeader.encodedLength)),
      ),
      spqrEpoch:
          ByteData.sublistView(bytes).getUint32(RatchetHeader.encodedLength),
      pq: _parseTrailing(trailing),
      trailing: trailing,
    );
  }

  /// Encodes a validated reseed payload into its trailing section.
  static Uint8List _encodePqSection(Map<String, dynamic> pq) {
    final t = pq['t'];
    final ok = (t == 'offer' && pq['pk'] is String) ||
        (t == 'ct' && pq['ct'] is String);
    if (!ok) {
      throw ArgumentError.value(pq, 'pq', 'Malformed reseed payload');
    }
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(pq)));
    if (payload.length > maxTrailingBytes - 6) {
      throw ArgumentError.value(
        payload.length,
        'pq',
        'Reseed payload too large',
      );
    }
    final out = Uint8List(6 + payload.length);
    out[0] = 0x70; // 'p'
    out[1] = 0x71; // 'q'
    ByteData.sublistView(out).setUint32(2, payload.length);
    out.setRange(6, out.length, payload);
    return out;
  }

  /// Lenient parse: unknown trailing sections are skipped, malformed
  /// ones are ignored, and the raw bytes are always preserved for
  /// re-encode. Never throws for trailing garbage; only a too-large
  /// trailing blob is rejected outright.
  static Map<String, dynamic>? _parseTrailing(Uint8List trailing) {
    Map<String, dynamic>? pq;
    var i = 0;
    while (i + 6 <= trailing.length) {
      final tag = (trailing[i] << 8) | trailing[i + 1];
      final len = ByteData.sublistView(trailing).getUint32(i + 2);
      if (len > maxTrailingBytes || i + 6 + len > trailing.length) {
        break; // corrupt length — ignore the rest
      }
      if (tag == _pqTag) {
        try {
          final payload = jsonDecode(
            utf8.decode(trailing.sublist(i + 6, i + 6 + len)),
          );
          if (payload is Map<String, dynamic>) {
            final t = payload['t'];
            final valid = (t == 'offer' && payload['pk'] is String) ||
                (t == 'ct' && payload['ct'] is String);
            if (valid) {
              pq = payload;
            }
          }
        } catch (_) {
          // Ignored: the section stays part of the AEAD-covered bytes.
        }
      }
      // Unknown sections are skipped by design (soft extension).
      i += 6 + len;
    }
    return pq;
  }
}

/// Triple Ratchet session operations.
class TripleRatchet {
  TripleRatchet._();

  /// Sends between delayed-reseed flights (spec §3.9: ~25 sends).
  static const int reseedEverySends = 25;

  /// Wall-clock interval between delayed-reseed flights (spec §3.9: 7 days).
  static const int reseedIntervalMs = 7 * 24 * 3600 * 1000;

  /// Opens a session. Rejects unverified peers outright — demo and
  /// placeholder keys can never pass because nothing except QR scan /
  /// Arke handshake (Part 12) sets [Contact.isVerified].
  static Future<SessionState> startSession({
    required Contact peer,
    required Uint8List remoteDhPublicKey,
    required Uint8List sharedSecret,
    required bool initiator,

    /// Overrides the fresh DH keypair (tests inject pre-exchanged keys).
    Uint8List? ourPrivateKey,
  }) async {
    if (!peer.isVerified) {
      throw UnverifiedPeerException(peer.id);
    }
    return DoubleRatchet.initSession(
      peerId: peer.id,
      initiator: initiator,
      sharedSecret: sharedSecret,
      remotePublicKey: remoteDhPublicKey,
      ourPrivateKey: ourPrivateKey,
    );
  }

  /// True when the reseed provider is usable; any failure fails closed.
  static Future<bool> _kemUsable(ReseedKem kem) async {
    try {
      return kem.isAvailable && await kem.initialize();
    } catch (_) {
      return false;
    }
  }

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

  /// Builds the trailing reseed payload for this send, if any (spec
  /// §3.9). May transition the chain (ct side of the flight). At most
  /// one payload per message.
  ///
  /// The session initiator alone offers (keeps the two flights from
  /// crossing); the responder alone encapsulates. A message never waits
  /// on the network — encapsulation is local.
  static Future<Map<String, dynamic>?> _reseedForSend(
    SessionState state,
    ReseedKem kem,
  ) async {
    // Responder side: answer the initiator's offer, if any.
    if (!state.initiatedByUs) {
      final offer = state.peerReseedPublicKey;
      if (offer == null) {
        return null;
      }
      final answered = state.answeredReseedOffer;
      if (answered != null && _bytesEqual(answered, offer)) {
        // Retransmitted offer — already answered. Do not encapsulate
        // twice; that would fork the chain.
        Csprng.wipe(offer);
        state.peerReseedPublicKey = null;
        return null;
      }
      if (!await _kemUsable(kem)) {
        // Fail closed: keep the offer for a later send, session stays classical.
        return null;
      }
      try {
        final out = await kem.encapsulate(offer);
        SpqrChain.applyReseed(state, out.sharedSecret); // wipes SS
        if (state.answeredReseedOffer != null) {
          Csprng.wipe(state.answeredReseedOffer!);
        }
        state.answeredReseedOffer = Uint8List.fromList(offer);
        Csprng.wipe(offer);
        state.peerReseedPublicKey = null;
        return {'t': 'ct', 'ct': base64Encode(out.ciphertext)};
      } catch (_) {
        // Fail closed: drop the offer, this send proceeds classical.
        Csprng.wipe(offer);
        state.peerReseedPublicKey = null;
        return null;
      }
    }
    // Initiator side: initiate when due and not already awaiting a ct.
    if (state.pendingReseedPrivateKey != null) {
      return null; // flight in progress
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dueByCount = state.reseedSendCounter >= reseedEverySends;
    final dueByTime = now - state.reseedLastAtMs >= reseedIntervalMs;
    if (!dueByCount && !dueByTime) {
      return null;
    }
    if (!await _kemUsable(kem)) {
      return null; // fail closed: silently stay classical
    }
    try {
      final pair = await kem.generateKeyPair();
      state.pendingReseedPublicKey = Uint8List.fromList(pair.publicKey);
      state.pendingReseedPrivateKey = Uint8List.fromList(pair.privateKey);
      Csprng.wipe(pair.publicKey);
      Csprng.wipe(pair.privateKey);
      state.reseedSendCounter = 0;
      state.reseedLastAtMs = now;
      return {'t': 'offer', 'pk': base64Encode(state.pendingReseedPublicKey!)};
    } catch (_) {
      return null; // fail closed
    }
  }

  /// Applies a delayed-reseed ciphertext from the peer, if present
  /// (spec §3.9). Mirrors the ct side: both parties derive
  /// HKDF(step(seed, generation+1) || SS_reseed, "Chhaya-SPQR-reseed-v1")
  /// and switch to the next chain state before this message is keyed.
  static Future<void> _applyReseedFromPeer(
    SessionState state,
    Map<String, dynamic>? pq,
    ReseedKem? reseedKem,
  ) async {
    if (pq == null) {
      return;
    }
    if (pq['t'] == 'ct') {
      if (reseedKem == null || state.pendingReseedPrivateKey == null) {
        return; // not ours to consume (or no provider) — stay classical
      }
      if (!await _kemUsable(reseedKem)) {
        return; // fail closed: no transition
      }
      try {
        final ct = base64Decode(pq['ct'] as String);
        final ss = await reseedKem.decapsulate(
          state.pendingReseedPrivateKey!,
          ct,
        );
        SpqrChain.applyReseed(state, ss); // wipes SS
        Csprng.wipe(state.pendingReseedPrivateKey!);
        state.pendingReseedPrivateKey = null;
        if (state.pendingReseedPublicKey != null) {
          Csprng.wipe(state.pendingReseedPublicKey!);
          state.pendingReseedPublicKey = null;
        }
      } catch (_) {
        // Fail closed: no transition; AEAD will reject this message and
        // the caller aborts per spec §3.6.
      }
      return;
    }
    if (pq['t'] == 'offer' && !state.initiatedByUs) {
      try {
        final pk = base64Decode(pq['pk'] as String);
        if (pk.isEmpty || pk.length > 8192) {
          return;
        }
        final answered = state.answeredReseedOffer;
        if (answered != null && _bytesEqual(answered, pk)) {
          return; // duplicate flight — already answered
        }
        if (state.peerReseedPublicKey != null) {
          Csprng.wipe(state.peerReseedPublicKey!);
        }
        state.peerReseedPublicKey = Uint8List.fromList(pk);
      } catch (_) {
        // Ignore malformed offers entirely.
      }
    }
    // Initiator receiving an offer: not supported by design (single
    // flight direction); ignored.
  }

  /// Advances the sending side and returns the wire header + key bundle.
  ///
  /// [reseedKem] is the ML-KEM provider seam for the delayed reseed;
  /// pass null to disable reseeding entirely (sessions then stay
  /// classical, unchanged).
  static Future<({TripleHeader header, MessageKeyBundle keys})> encrypt(
    SessionState state, {
    ReseedKem? reseedKem,
  }) async {
    // Count this send for the reseed cadence.
    state.reseedSendCounter += 1;
    Map<String, dynamic>? pq;
    if (reseedKem != null) {
      pq = await _reseedForSend(state, reseedKem);
    }
    final stepped = await DoubleRatchet.encrypt(state);
    // sendCounter was already incremented; epoch of the message sent.
    final messageNumber = state.sendCounter - 1;
    final epoch = messageNumber ~/ SpqrChain.advanceEvery;
    // Epochs are monotone with the message number, so this steps the
    // seed forward (retiring seeds are wiped) rather than reading a
    // retired key.
    final chainKey = SpqrChain.epochKey(state, epoch);
    final bundle = _combine(
      stepped.keys.messageKey,
      chainKey,
      messageNumber,
      epoch,
    );
    stepped.keys.wipe();
    return (
      header: TripleHeader(dh: stepped.header, spqrEpoch: epoch, pq: pq),
      keys: bundle,
    );
  }

  /// Resolves the receiving key for [header]. Epoch keys step the seed
  /// forward one-way; past in-window epoch keys come from the bounded
  /// cache (spec §3.9/§3.10). [reseedKem] must be the same provider
  /// family the peer advertised (or null to treat reseed cts as absent).
  static Future<MessageKeyBundle> decrypt(
    SessionState state,
    TripleHeader header, {
    ReseedKem? reseedKem,
  }) async {
    // Guard the epoch gap before any state mutation: a peer jumping
    // more than the skip window is refused with state intact.
    final epochGap = header.spqrEpoch - state.spqrEpoch;
    if (epochGap > SpqrChain.maxSkip) {
      throw TooManySkippedException(epochGap);
    }
    // Delayed reseed: ct transitions the chain BEFORE this message is
    // keyed; an offer is remembered for our next send.
    await _applyReseedFromPeer(state, header.pq, reseedKem);
    if (!SpqrChain.epochKeyAvailable(state, header.spqrEpoch)) {
      throw EpochKeyUnavailableException(header.spqrEpoch);
    }
    final dhKeys = await DoubleRatchet.decrypt(state, header.dh);
    final chainKey = SpqrChain.epochKey(state, header.spqrEpoch);
    final bundle = _combine(
      dhKeys.messageKey,
      chainKey,
      header.dh.messageNumber,
      header.spqrEpoch,
    );
    dhKeys.wipe();
    return bundle;
  }

  /// messageKey = HKDF(dhKey || chainKey, 'Chhaya-triple-v1' ||
  /// u32be(messageNumber) || u32be(epoch)). Both inputs are fixed by the
  /// wire header, so sender and receiver always agree.
  /// The nonce reuses the message-key derivation (unique per message).
  static MessageKeyBundle _combine(
    Uint8List dhKey,
    Uint8List spqrKey,
    int messageNumber,
    int spqrEpoch,
  ) {
    final numBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, messageNumber);
    final epochBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, spqrEpoch);
    final messageKey = Hkdf.deriveKey(
      inputKeyMaterial: Uint8List.fromList([...dhKey, ...spqrKey]),
      info: Uint8List.fromList(
        [...utf8.encode('Chhaya-triple-v1'), ...numBytes, ...epochBytes],
      ),
      length: MessageKeys.keyLength,
    );
    final nonce = Hkdf.expand(
      messageKey,
      Uint8List.fromList(
        [...utf8.encode('Chhaya-nonce-v1'), ...numBytes, ...epochBytes],
      ),
      MessageKeys.nonceLength,
    );
    return MessageKeyBundle(messageKey: messageKey, nonce: nonce);
  }
}
