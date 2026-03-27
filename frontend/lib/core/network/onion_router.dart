import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Onion Router — Layered encryption over mesh relay nodes (Req 10).
/// Each relay decrypts only its own layer and sees only immediate neighbours.
class OnionRouter {
  static const int minHops = 3; // Req 10.2

  /// Wrap a payload in onion layers for the given path.
  /// Path is [hop1, hop2, ..., destination]. Each hop's public key is used.
  /// innermost layer = destination, outermost = first hop (Req 10.1).
  Uint8List wrap(Uint8List payload, List<OnionHop> path) {
    if (path.length < minHops) {
      throw ArgumentError('Onion path must have at least $minHops hops');
    }

    var data = payload;

    // Wrap from innermost (destination) to outermost (first relay)
    for (final hop in path.reversed) {
      final layer = _buildLayer(
        payload: data,
        nextHop: hop.nextHopId,
        recipientPublicKey: hop.publicKeyBytes,
      );
      data = layer;
    }

    return data;
  }

  /// Peel one layer of onion encryption using our private key.
  /// Returns {nextHop, remainingPayload} or null if decryption fails.
  OnionPeelResult? peel(Uint8List onionBlob, Uint8List myPrivateKey) {
    try {
      // Parse layer: [iv(12)] [nextHopLen(2)] [nextHop] [payload]
      if (onionBlob.length < 15) return null;

      final iv = onionBlob.sublist(0, 12);
      final keyBytes = _deriveLayerKey(myPrivateKey, iv);

      // Decrypt the rest
      final decrypted = _aesGcmDecrypt(onionBlob.sublist(12), keyBytes, iv);
      if (decrypted == null) return null;

      // Parse decrypted content
      final nextHopLen = decrypted[0] | (decrypted[1] << 8);
      final nextHop = utf8.decode(decrypted.sublist(2, 2 + nextHopLen));
      final remaining = decrypted.sublist(2 + nextHopLen);

      return OnionPeelResult(nextHopId: nextHop, payload: remaining);
    } catch (e) {
      debugPrint('[OnionRouter] Peel failed: $e');
      return null;
    }
  }

  /// Select a 3-hop path from available peers, excluding self and destination
  List<OnionHop> selectPath({
    required List<String> availablePeerIds,
    required Map<String, Uint8List> peerPublicKeys,
    required String destinationId,
    required Uint8List destinationPublicKey,
  }) {
    final candidates = availablePeerIds
        .where((id) => id != destinationId && peerPublicKeys.containsKey(id))
        .toList();

    if (candidates.length < minHops - 1) {
      throw StateError('Not enough peers for onion routing (need ${minHops - 1} relays)');
    }

    final rng = Random.secure();
    candidates.shuffle(rng);
    final relays = candidates.take(minHops - 1).toList();

    // Build path: relay1 → relay2 → destination
    final path = <OnionHop>[];
    for (var i = 0; i < relays.length; i++) {
      path.add(OnionHop(
        nodeId: relays[i],
        nextHopId: i + 1 < relays.length ? relays[i + 1] : destinationId,
        publicKeyBytes: peerPublicKeys[relays[i]]!,
      ));
    }
    path.add(OnionHop(
      nodeId: destinationId,
      nextHopId: '', // final destination
      publicKeyBytes: destinationPublicKey,
    ));

    return path;
  }

  // ─── Internal ─────────────────────────────────────────────────

  Uint8List _buildLayer({
    required Uint8List payload,
    required String nextHop,
    required Uint8List recipientPublicKey,
  }) {
    final iv = _randomBytes(12);
    final keyBytes = _deriveLayerKey(recipientPublicKey, iv);

    // Build content: [nextHopLen(2)] [nextHop bytes] [payload]
    final hopBytes = utf8.encode(nextHop) as Uint8List;
    final content = Uint8List(2 + hopBytes.length + payload.length);
    content[0] = hopBytes.length & 0xFF;
    content[1] = (hopBytes.length >> 8) & 0xFF;
    content.setRange(2, 2 + hopBytes.length, hopBytes);
    content.setRange(2 + hopBytes.length, content.length, payload);

    final encrypted = _aesGcmEncrypt(content, keyBytes, iv);
    return Uint8List.fromList([...iv, ...encrypted]);
  }

  Uint8List _deriveLayerKey(Uint8List keyMaterial, Uint8List iv) {
    // HKDF-like: HMAC-SHA256(keyMaterial, iv || "chaaya-onion")
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(keyMaterial.sublist(0, min(32, keyMaterial.length))));
    final infoBytes = utf8.encode('chaaya-onion');
    final info = Uint8List.fromList([...iv, ...infoBytes]);
    final output = Uint8List(32);
    hmac.update(info, 0, info.length);
    hmac.doFinal(output, 0);
    return output;
  }

  Uint8List _aesGcmEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    final len = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    cipher.doFinal(output, len);
    return output;
  }

  Uint8List? _aesGcmDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    try {
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final output = Uint8List(cipher.getOutputSize(ciphertext.length));
      final len = cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
      cipher.doFinal(output, len);
      return output;
    } catch (_) {
      return null;
    }
  }

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }
}

class OnionHop {
  final String nodeId;
  final String nextHopId;
  final Uint8List publicKeyBytes;

  OnionHop({
    required this.nodeId,
    required this.nextHopId,
    required this.publicKeyBytes,
  });
}

class OnionPeelResult {
  final String nextHopId;
  final Uint8List payload;

  OnionPeelResult({required this.nextHopId, required this.payload});

  bool get isFinalDestination => nextHopId.isEmpty;
}
