// Triple Ratchet facade (V14 Part 4).
//
// Combines the X25519 Double Ratchet with the SPQR epoch chain:
//   messageKey = HKDF(dhMessageKey || spqrChainKey, counter)
// The DH step runs on direction change; the SPQR epoch advances every
// 10 sent messages. Session start validates the peer (verified only).
//
// Audit status: [ ] Ready for external audit. SPQR currently evolves
// deterministically; production ML-KEM-1024 reseeding lands in Part 5.
import 'dart:convert';
import 'dart:typed_data';

import '../../models/contact.dart';
import '../primitives/hkdf.dart';
import 'double_ratchet.dart';
import 'header.dart';
import 'message_keys.dart';
import 'session_state.dart';
import 'spqr.dart';

/// Wire header: 40-byte DH header + u32be SPQR epoch (44 bytes total).
class TripleHeader {
  static const int encodedLength = RatchetHeader.encodedLength + 4;

  final RatchetHeader dh;
  final int spqrEpoch;

  TripleHeader({required this.dh, required this.spqrEpoch}) {
    if (spqrEpoch < 0 || spqrEpoch > 0xFFFFFFFF) {
      throw ArgumentError.value(
        spqrEpoch,
        'spqrEpoch',
        'Epoch must fit in u32',
      );
    }
  }

  Uint8List toBytes() {
    final out = Uint8List(encodedLength);
    out.setRange(0, RatchetHeader.encodedLength, dh.toBytes());
    ByteData.sublistView(out).setUint32(RatchetHeader.encodedLength, spqrEpoch);
    return out;
  }

  factory TripleHeader.fromBytes(Uint8List bytes) {
    if (bytes.length != encodedLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Triple headers must be $encodedLength bytes',
      );
    }
    return TripleHeader(
      dh: RatchetHeader.fromBytes(
        Uint8List.fromList(bytes.sublist(0, RatchetHeader.encodedLength)),
      ),
      spqrEpoch: ByteData.sublistView(bytes)
          .getUint32(RatchetHeader.encodedLength),
    );
  }
}

/// Triple Ratchet session operations.
class TripleRatchet {
  TripleRatchet._();

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

  /// Advances the sending side and returns the wire header + key bundle.
  static Future<({TripleHeader header, MessageKeyBundle keys})> encrypt(
    SessionState state,
  ) async {
    final stepped = await DoubleRatchet.encrypt(state);
    // sendCounter was already incremented; epoch of the message sent.
    final messageNumber = state.sendCounter - 1;
    final epoch = messageNumber ~/ SpqrChain.advanceEvery;
    state.spqrEpoch = epoch;
    final spqrKey = SpqrChain.chainKeyFor(state.spqrSeed, epoch);
    final bundle = _combine(
      stepped.keys.messageKey,
      spqrKey,
      messageNumber,
      epoch,
    );
    stepped.keys.wipe();
    return (
      header: TripleHeader(dh: stepped.header, spqrEpoch: epoch),
      keys: bundle,
    );
  }

  /// Resolves the receiving key for [header]. Epoch keys are
  /// deterministic, so late/jumped epochs need no extra round trips.
  static Future<MessageKeyBundle> decrypt(
    SessionState state,
    TripleHeader header,
  ) async {
    final dhKeys = await DoubleRatchet.decrypt(state, header.dh);
    final spqrKey = SpqrChain.chainKeyFor(state.spqrSeed, header.spqrEpoch);
    final bundle = _combine(
      dhKeys.messageKey,
      spqrKey,
      header.dh.messageNumber,
      header.spqrEpoch,
    );
    dhKeys.wipe();
    return bundle;
  }

  /// messageKey = HKDF(dhKey || spqrKey, 'Chhaya-triple-v1' ||
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
