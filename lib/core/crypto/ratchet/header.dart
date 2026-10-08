// Double Ratchet message header (V14 Part 4).
//
// Wire format, 40 bytes total:
//   dh_pub (32 bytes) | prev_chain_length (u32 big-endian) |
//   message_number (u32 big-endian)
import 'dart:typed_data';

/// Header attached to every ratchet message.
class RatchetHeader {
  /// Length of the X25519 DH public key prefix.
  static const int dhPubLength = 32;

  /// Total encoded length in bytes.
  static const int encodedLength = 40;

  /// Sender's current DH public key (32 bytes, copied on construction).
  final Uint8List dhPublicKey;

  /// Length of the sender's previous sending chain (for skipped-key staging).
  final int prevChainLength;

  /// Index of this message in the sender's current sending chain.
  final int messageNumber;

  RatchetHeader({
    required Uint8List dhPublicKey,
    required this.prevChainLength,
    required this.messageNumber,
  }) : dhPublicKey = Uint8List.fromList(dhPublicKey) {
    if (dhPublicKey.length != dhPubLength) {
      throw ArgumentError.value(
        dhPublicKey.length,
        'dhPublicKey',
        'DH public keys must be 32 bytes',
      );
    }
    if (prevChainLength < 0) {
      throw ArgumentError.value(
        prevChainLength,
        'prevChainLength',
        'Must be non-negative',
      );
    }
    if (messageNumber < 0) {
      throw ArgumentError.value(
        messageNumber,
        'messageNumber',
        'Must be non-negative',
      );
    }
  }

  /// Encodes the header to its 40-byte wire form.
  Uint8List toBytes() {
    final out = Uint8List(encodedLength);
    out.setRange(0, dhPubLength, dhPublicKey);
    final view = ByteData.sublistView(out);
    view.setUint32(dhPubLength, prevChainLength);
    view.setUint32(dhPubLength + 4, messageNumber);
    return out;
  }

  /// Decodes a header from its 40-byte wire form.
  factory RatchetHeader.fromBytes(Uint8List bytes) {
    if (bytes.length != encodedLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Ratchet headers must be $encodedLength bytes',
      );
    }
    final view = ByteData.sublistView(bytes);
    return RatchetHeader(
      dhPublicKey: Uint8List.fromList(bytes.sublist(0, dhPubLength)),
      prevChainLength: view.getUint32(dhPubLength),
      messageNumber: view.getUint32(dhPubLength + 4),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatchetHeader &&
          prevChainLength == other.prevChainLength &&
          messageNumber == other.messageNumber &&
          _bytesEqual(dhPublicKey, other.dhPublicKey);

  @override
  int get hashCode =>
      Object.hash(prevChainLength, messageNumber, dhPublicKey.length);

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
}
