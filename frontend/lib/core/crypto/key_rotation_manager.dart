import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'dart:convert';

class KeyRotationManager {
  static const String _keysBoxName = 'chaaya_key_rotation';

  late Box<String> _keysBox;
  final Random _random = Random.secure();

  DateTime? _lastIdentityRotation;
  DateTime? _lastSessionRotation;
  int _messageCountSinceRotation = 0;

  static const int _identityRotationDays = 180;
  static const int _sessionRotationMessages = 1000;
  static const int _preKeyRotationMessages = 500;

  final _keyChangeEvents = StreamController<KeyRotationEvent>.broadcast();
  Stream<KeyRotationEvent> get keyChangeEvents => _keyChangeEvents.stream;

  Future<void> initialize() async {
    _keysBox = await Hive.openBox<String>(_keysBoxName);
    await _loadLastRotations();
    _startRotationScheduler();
  }

  Future<void> _loadLastRotations() async {
    final lastIdentity = _keysBox.get('lastIdentityRotation');
    final lastSession = _keysBox.get('lastSessionRotation');

    if (lastIdentity != null) {
      _lastIdentityRotation = DateTime.parse(lastIdentity);
    }
    if (lastSession != null) {
      _lastSessionRotation = DateTime.parse(lastSession);
    }

    _messageCountSinceRotation =
        int.tryParse(_keysBox.get('messageCount') ?? '0') ?? 0;
  }

  Future<void> _saveLastRotations() async {
    if (_lastIdentityRotation != null) {
      await _keysBox.put(
          'lastIdentityRotation', _lastIdentityRotation!.toIso8601String());
    }
    if (_lastSessionRotation != null) {
      await _keysBox.put(
          'lastSessionRotation', _lastSessionRotation!.toIso8601String());
    }
    await _keysBox.put('messageCount', _messageCountSinceRotation.toString());
  }

  void _startRotationScheduler() {
    Timer.periodic(const Duration(hours: 1), (_) {
      _checkScheduledRotations();
    });
  }

  void _checkScheduledRotations() {
    if (_shouldRotateIdentityKeys()) {
      rotateIdentityKeys();
    }
  }

  bool _shouldRotateIdentityKeys() {
    if (_lastIdentityRotation == null) return false;
    final daysSinceRotation =
        DateTime.now().difference(_lastIdentityRotation!).inDays;
    return daysSinceRotation >= _identityRotationDays;
  }

  bool shouldRotateSessionKeys() {
    return _messageCountSinceRotation >= _sessionRotationMessages;
  }

  bool shouldRotatePreKeys() {
    return _messageCountSinceRotation >= _preKeyRotationMessages;
  }

  Future<void> rotateIdentityKeys() async {
    debugPrint('[KeyRotation] Rotating identity keys...');

    final keyId = _generateKeyId();
    final publicKey = _generateKeyPair();
    final privateKey = _generateKeyPair();

    final newIdentityKey = IdentityKeyPair(
      publicKey: publicKey,
      privateKey: privateKey,
      createdAt: DateTime.now(),
      rotatedFrom: _keysBox.get('currentIdentityKeyId'),
    );

    await _keysBox.put('currentIdentityKeyId', keyId);
    await _keysBox.put('identity_$keyId', jsonEncode(newIdentityKey.toJson()));

    _lastIdentityRotation = DateTime.now();
    _messageCountSinceRotation = 0;
    await _saveLastRotations();

    _keyChangeEvents.add(KeyRotationEvent(
      type: KeyRotationType.identity,
      keyId: keyId,
      timestamp: DateTime.now(),
    ));

    debugPrint('[KeyRotation] Identity keys rotated successfully');
  }

  Future<void> rotateSessionKeys(String sessionId) async {
    debugPrint('[KeyRotation] Rotating session keys for: $sessionId');

    final newSessionKey = _generateSessionKey();

    await _keysBox.put(
        'session_$sessionId',
        jsonEncode({
          'key': newSessionKey,
          'createdAt': DateTime.now().toIso8601String(),
          'messageCount': 0,
        }));

    _messageCountSinceRotation = 0;
    await _saveLastRotations();

    _keyChangeEvents.add(KeyRotationEvent(
      type: KeyRotationType.session,
      keyId: sessionId,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> rotatePreKeys(String contactId) async {
    debugPrint('[KeyRotation] Rotating pre-keys for: $contactId');

    final preKeyId = _generateKeyId();
    final preKey = _generateSessionKey();

    await _keysBox.put(
        'prekey_${contactId}_$preKeyId',
        jsonEncode({
          'key': preKey,
          'createdAt': DateTime.now().toIso8601String(),
          'contactId': contactId,
        }));

    _messageCountSinceRotation = 0;
    await _saveLastRotations();

    _keyChangeEvents.add(KeyRotationEvent(
      type: KeyRotationType.preKey,
      keyId: preKeyId,
      timestamp: DateTime.now(),
    ));
  }

  void recordMessage() {
    _messageCountSinceRotation++;

    if (_messageCountSinceRotation >= _sessionRotationMessages) {
      debugPrint('[KeyRotation] Session key rotation threshold reached');
    }
  }

  String _generateKeyId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes).replaceAll('=', '');
  }

  String _generateKeyPair() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  String _generateSessionKey() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  Map<String, dynamic> getRotationStatus() {
    final daysSinceIdentity = _lastIdentityRotation != null
        ? DateTime.now().difference(_lastIdentityRotation!).inDays
        : null;

    return {
      'lastIdentityRotation': _lastIdentityRotation?.toIso8601String(),
      'lastSessionRotation': _lastSessionRotation?.toIso8601String(),
      'daysSinceIdentityRotation': daysSinceIdentity,
      'messageCountSinceRotation': _messageCountSinceRotation,
      'shouldRotateIdentity': _shouldRotateIdentityKeys(),
      'shouldRotateSession': shouldRotateSessionKeys(),
      'shouldRotatePreKeys': shouldRotatePreKeys(),
      'identityRotationDays': _identityRotationDays,
      'sessionRotationMessages': _sessionRotationMessages,
      'preKeyRotationMessages': _preKeyRotationMessages,
    };
  }

  Future<void> forceRotateAll(String sessionId) async {
    await rotateIdentityKeys();
    await rotateSessionKeys(sessionId);
    await rotatePreKeys(sessionId);
  }

  Future<void> clearOldKeys({int keepDays = 365}) async {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    final keysToDelete = <String>[];

    final map = _keysBox.toMap();
    for (final entry in map.entries) {
      final key = entry.key as String;
      final value = entry.value as String;
      if (key.startsWith('identity_') ||
          key.startsWith('session_') ||
          key.startsWith('prekey_')) {
        try {
          final json = jsonDecode(value);
          final createdAt = DateTime.parse(json['createdAt']);
          if (createdAt.isBefore(cutoff)) {
            keysToDelete.add(key);
          }
        } catch (_) {}
      }
    }

    for (final key in keysToDelete) {
      await _keysBox.delete(key);
    }

    debugPrint('[KeyRotation] Cleared ${keysToDelete.length} old keys');
  }

  void dispose() {
    _keyChangeEvents.close();
  }
}

class KeyRotationEvent {
  final KeyRotationType type;
  final String keyId;
  final DateTime timestamp;

  KeyRotationEvent({
    required this.type,
    required this.keyId,
    required this.timestamp,
  });
}

enum KeyRotationType { identity, session, preKey }

class IdentityKeyPair {
  final String publicKey;
  final String privateKey;
  final DateTime createdAt;
  final String? rotatedFrom;

  IdentityKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
    this.rotatedFrom,
  });

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        'privateKey': privateKey,
        'createdAt': createdAt.toIso8601String(),
        'rotatedFrom': rotatedFrom,
      };
}
