import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

/// Chaaya Identity — No-account, keypair-based identity system.
/// Generates Ed25519 keypair on first launch. No phone number, no email.
class IdentityService {
  static const String _boxName = 'chaaya_identity';
  static const _secureStorage = FlutterSecureStorage();

  Box? _box;
  MeshIdentity? _currentIdentity;

  MeshIdentity? get currentIdentity => _currentIdentity;

  /// Initialize and load existing identity, or signal that setup is needed
  Future<bool> initialize() async {
    _box = await Hive.openBox(_boxName);

    final existing = _box?.get('identity');
    if (existing != null) {
      _currentIdentity = MeshIdentity.fromJson(jsonDecode(existing));
      debugPrint('[Identity] Loaded: ${_currentIdentity!.username} (${_currentIdentity!.deviceId})');
      return true;
    }
    return false; // needs setup
  }

  /// Create a new identity (first launch)
  Future<MeshIdentity> createIdentity(String username) async {
    // Generate device ID
    final deviceId = const Uuid().v4();

    // Generate Ed25519 keypair using pointycastle
    final keyParams = Ed25519KeyGeneratorParameters();
    final random = FortunaRandom();
    random.seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (i) => DateTime.now().microsecond + i)),
    ));
    
    final keyGenerator = Ed25519KeyGenerator();
    keyGenerator.init(ParametersWithRandom(keyParams, random));
    final pair = keyGenerator.generateKeyPair();

    final publicKey = pair.publicKey as Ed25519PublicKeyParameters;
    final privateKey = pair.privateKey as Ed25519PrivateKeyParameters;

    // Encode keys as base64
    final publicKeyStr = base64Encode(publicKey.bytes);
    final privateKeyStr = base64Encode(privateKey.bytes);

    // Store private key securely
    await _secureStorage.write(key: 'chaaya_private_key', value: privateKeyStr);

    // Create identity
    final identity = MeshIdentity(
      username: username,
      deviceId: deviceId,
      publicKey: publicKeyStr,
      createdAt: DateTime.now(),
    );

    // Save to Hive
    await _box?.put('identity', jsonEncode(identity.toJson()));
    _currentIdentity = identity;

    debugPrint('[Identity] Created: $username ($deviceId)');
    return identity;
  }

  /// Get public key fingerprint (first 8 chars for display)
  String getFingerprint() {
    if (_currentIdentity == null) return '';
    final bytes = base64Decode(_currentIdentity!.publicKey);
    return bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }

  /// Generate QR code data (contains identity for pairing)
  String getQRData() {
    if (_currentIdentity == null) return '';
    return jsonEncode({
      'chaaya': true,
      'version': 1,
      'username': _currentIdentity!.username,
      'deviceId': _currentIdentity!.deviceId,
      'publicKey': _currentIdentity!.publicKey,
    });
  }

  /// Parse QR code data from another device
  static MeshIdentity? parseQRData(String data) {
    try {
      final json = jsonDecode(data);
      if (json['chaaya'] != true) return null;
      return MeshIdentity(
        username: json['username'],
        deviceId: json['deviceId'],
        publicKey: json['publicKey'],
        createdAt: DateTime.now(), // paired time
      );
    } catch (e) {
      debugPrint('[Identity] QR parse error: $e');
      return null;
    }
  }

  /// Destroy identity (panic wipe)
  Future<void> destroyIdentity() async {
    await _secureStorage.delete(key: 'chaaya_private_key');
    await _box?.clear();
    _currentIdentity = null;
    debugPrint('[Identity] DESTROYED — panic wipe complete');
  }
}

/// A Chaaya user identity
class MeshIdentity {
  final String username;
  final String deviceId;
  final String publicKey;
  final DateTime createdAt;

  MeshIdentity({
    required this.username,
    required this.deviceId,
    required this.publicKey,
    required this.createdAt,
  });

  factory MeshIdentity.fromJson(Map<String, dynamic> json) {
    return MeshIdentity(
      username: json['username'] as String,
      deviceId: json['deviceId'] as String,
      publicKey: json['publicKey'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'deviceId': deviceId,
      'publicKey': publicKey,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'MeshIdentity($username, $deviceId)';
}

