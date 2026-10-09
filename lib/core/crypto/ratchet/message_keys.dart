// Per-message key derivation (V14 Part 4).
//
// Symmetric chain step: from a 32-byte chain key and a message counter,
// derives the 32-byte message key, the next chain key, and the 12-byte
// AES-GCM nonce. All outputs are domain-separated via distinct HKDF
// info strings, so a message key can never equal a chain key or nonce.
import 'dart:convert';
import 'dart:typed_data';

import '../primitives/hkdf.dart';
import '../primitives/rng.dart';

/// A derived message key with its nonce. Wipe when done via [wipe].
class MessageKeyBundle {
  /// 32-byte AES-256 message key.
  final Uint8List messageKey;

  /// 12-byte AES-GCM nonce, unique per (chain key, counter).
  final Uint8List nonce;

  MessageKeyBundle({required Uint8List messageKey, required Uint8List nonce})
      : messageKey = Uint8List.fromList(messageKey),
        nonce = Uint8List.fromList(nonce) {
    if (messageKey.length != MessageKeys.keyLength) {
      throw ArgumentError.value(
        messageKey.length,
        'messageKey',
        'Message keys must be ${MessageKeys.keyLength} bytes',
      );
    }
    if (nonce.length != MessageKeys.nonceLength) {
      throw ArgumentError.value(
        nonce.length,
        'nonce',
        'Nonces must be ${MessageKeys.nonceLength} bytes',
      );
    }
  }

  /// Zeroizes both buffers in place.
  void wipe() {
    Csprng.wipe(messageKey);
    Csprng.wipe(nonce);
  }
}

/// Symmetric ratchet step over a single chain.
class MessageKeys {
  MessageKeys._();

  /// Message key length in bytes (AES-256).
  static const int keyLength = 32;

  /// AES-GCM nonce length in bytes.
  static const int nonceLength = 12;

  /// Derives the bundle for [counter] and advances the chain.
  ///
  /// Returns the bundle plus the next chain key. The input [chainKey]
  /// is not wiped; the caller owns it.
  static ({MessageKeyBundle bundle, Uint8List nextChainKey}) derive(
    Uint8List chainKey,
    int counter,
  ) {
    if (chainKey.length != keyLength) {
      throw ArgumentError.value(
        chainKey.length,
        'chainKey',
        'Chain keys must be $keyLength bytes',
      );
    }
    if (counter < 0 || counter > 0xFFFFFFFF) {
      throw ArgumentError.value(
        counter,
        'counter',
        'Counter must fit in u32',
      );
    }
    final ctr = Uint8List(4)..buffer.asByteData().setUint32(0, counter);
    final messageKey = Hkdf.expand(
      chainKey,
      Uint8List.fromList([...utf8.encode('Chhaya-msg-v1'), ...ctr]),
      keyLength,
    );
    final nextChainKey = Hkdf.expand(
      chainKey,
      Uint8List.fromList([...utf8.encode('Chhaya-chain-v1'), ...ctr]),
      keyLength,
    );
    final nonce = Hkdf.expand(
      messageKey,
      Uint8List.fromList([...utf8.encode('Chhaya-nonce-v1'), ...ctr]),
      nonceLength,
    );
    return (
      bundle: MessageKeyBundle(messageKey: messageKey, nonce: nonce),
      nextChainKey: nextChainKey,
    );
  }
}
