import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import '../../core/mesh/mesh_message.dart';

/// Dead Drop Service — GPS-coordinate-bound encrypted messages (Req 13).
/// Messages can only be decrypted when device is within 10m of the drop.
class DeadDropService {
  static const double _unlockRadiusMetres = 10.0;
  static const double _requiredAccuracyMetres = 10.0;
  static const int _coordinatePrecision = 5;

  final _rng = Random.secure();

  /// Create a dead drop message (Req 13.1)
  /// Returns an opaque MeshMessage — coordinates NOT in plaintext (Req 13.2)
  Future<MeshMessage> createDrop({
    required String message,
    required double lat,
    required double lng,
    required String senderId,
    required String senderName,
  }) async {
    final roundedLat = _round(lat, _coordinatePrecision);
    final roundedLng = _round(lng, _coordinatePrecision);

    final key = _deriveCoordKey(roundedLat, roundedLng);
    final iv = _randomBytes(12);
    final plainBytes = Uint8List.fromList(utf8.encode(message));
    final cipher = _aesGcmEncrypt(plainBytes, key, iv);

    final payloadBytes = Uint8List.fromList([...iv, ...cipher]);
    final payloadB64 = base64Encode(payloadBytes);

    // Only transmit opaque hash of coords, not the coords themselves
    final coordHash = _coordHash(roundedLat, roundedLng);

    return MeshMessage(
      senderId: senderId,
      senderName: senderName,
      recipientId: 'broadcast',
      content: payloadB64,
      type: MeshMessageType.location, // closest semantic type in existing enum
      metadata: {
        'coordHash': coordHash,
        'type': 'deadDrop',
      },
    );
  }

  /// Called when a dead drop packet arrives.
  /// Tries to decrypt using current GPS position (Req 13.3–13.6).
  Future<DeadDropResult> onReceiveDrop({
    required MeshMessage message,
    required double myLat,
    required double myLng,
    required double gpsAccuracy,
  }) async {
    // GPS not accurate enough (Req 13.6)
    if (gpsAccuracy > _requiredAccuracyMetres) {
      return DeadDropResult.notUnlocked();
    }

    final coordHash = message.metadata?['coordHash'] as String?;
    if (coordHash == null) return DeadDropResult.notUnlocked();

    Uint8List payloadBytes;
    try {
      payloadBytes = base64Decode(message.content);
    } catch (_) {
      return DeadDropResult.notUnlocked();
    }
    if (payloadBytes.length < 13) return DeadDropResult.notUnlocked();

    // Try offsets in small grid around our position (covers 10m radius)
    const double step = 0.00009; // ~10m per 0.0001 degree
    String? decryptedMsg;

    for (final latOffset in [-step, 0.0, step]) {
      for (final lngOffset in [-step, 0.0, step]) {
        final testLat = _round(myLat + latOffset, _coordinatePrecision);
        final testLng = _round(myLng + lngOffset, _coordinatePrecision);

        // Check distance (Req 13.3)
        final dist = haversineMetres(myLat, myLng, testLat, testLng);
        if (dist > _unlockRadiusMetres) continue;

        // Check hash match
        final testHash = _coordHash(testLat, testLng);
        if (testHash != coordHash) continue;

        // Attempt decrypt
        final key = _deriveCoordKey(testLat, testLng);
        final iv = payloadBytes.sublist(0, 12);
        final cipher = payloadBytes.sublist(12);
        final plain = _aesGcmDecrypt(cipher, key, iv);
        if (plain != null) {
          decryptedMsg = utf8.decode(plain);
          break;
        }
      }
      if (decryptedMsg != null) break;
    }

    if (decryptedMsg != null) {
      debugPrint('[DeadDrop] Unlocked! Message: $decryptedMsg');
      return DeadDropResult.unlockSuccess(decryptedMsg);
    }

    // Req 13.5 — discard without display
    debugPrint('[DeadDrop] Out of range or wrong coords — discarding');
    return DeadDropResult.notUnlocked();
  }

  // ─── Haversine Formula (Req 13.3) ───

  static double haversineMetres(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * pi / 180.0;

  // ─── Helpers ───

  Uint8List _deriveCoordKey(double lat, double lng) {
    final input = utf8.encode(
        'chaaya-drop:${lat.toStringAsFixed(_coordinatePrecision)},${lng.toStringAsFixed(_coordinatePrecision)}');
    final digest = SHA256Digest();
    final hash = Uint8List(32);
    digest.update(input as Uint8List, 0, input.length);
    digest.doFinal(hash, 0);
    return hash;
  }

  String _coordHash(double lat, double lng) {
    final key = _deriveCoordKey(lat, lng);
    return base64Encode(key.sublist(0, 8));
  }

  double _round(double v, int decimals) {
    final factor = pow(10, decimals);
    return (v * factor).round() / factor;
  }

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  Uint8List _aesGcmEncrypt(Uint8List pt, Uint8List key, Uint8List iv) {
    final c = GCMBlockCipher(AESEngine());
    c.init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final out = Uint8List(c.getOutputSize(pt.length));
    c.doFinal(out, c.processBytes(pt, 0, pt.length, out, 0));
    return out;
  }

  Uint8List? _aesGcmDecrypt(Uint8List ct, Uint8List key, Uint8List iv) {
    try {
      final c = GCMBlockCipher(AESEngine());
      c.init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final out = Uint8List(c.getOutputSize(ct.length));
      c.doFinal(out, c.processBytes(ct, 0, ct.length, out, 0));
      return out;
    } catch (_) {
      return null;
    }
  }
}

class DeadDropResult {
  final bool isUnlocked;
  final String? message;

  DeadDropResult._({required this.isUnlocked, this.message});

  factory DeadDropResult.notUnlocked() => DeadDropResult._(isUnlocked: false);
  factory DeadDropResult.unlockSuccess(String msg) =>
      DeadDropResult._(isUnlocked: true, message: msg);
}
