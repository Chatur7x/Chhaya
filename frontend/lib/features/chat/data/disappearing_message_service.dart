import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Disappearing Message Service (Req 9).
/// Deletes messages after a configured timer using secure overwrite.
class DisappearingMessageService {
  static const String _timerBox = 'chaaya_disappear_timers';
  static const Duration _checkInterval = Duration(seconds: 60); // Req 9.4

  // Standard timers (Req 9.1)
  static const Duration timer24h = Duration(hours: 24);
  static const Duration timer7d = Duration(days: 7);
  static const Duration timer1m = Duration(minutes: 1);
  static const Duration timer30d = Duration(days: 30);

  Box<String>? _box;
  Timer? _bgTimer;
  Duration? _defaultTimer;

  // Notify UI when messages are deleted (Req 9.5)
  final _deletedController = StreamController<String>.broadcast();
  Stream<String> get onMessageDeleted => _deletedController.stream;

  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_timerBox);
    _bgTimer = Timer.periodic(_checkInterval, (_) => _checkExpired());
    _checkExpired(); // immediate check on startup
    debugPrint('[Disappear] Service initialized');
  }

  void setDefaultTimer(Duration? timer) {
    _defaultTimer = timer;
  }

  Duration? get defaultTimer => _defaultTimer;

  /// Schedule a message to disappear (Req 9.2)
  Future<void> schedule(String messageId, {Duration? timer}) async {
    final t = timer ?? _defaultTimer;
    if (t == null) return;

    final disappearAt = DateTime.now().add(t);
    await _box?.put(
      messageId,
      jsonEncode({
        'messageId': messageId,
        'disappearAt': disappearAt.toIso8601String(),
      }),
    );
    debugPrint('[Disappear] Scheduled $messageId to disappear at $disappearAt');
  }

  /// Cancel a disappear timer (e.g. if message was manually deleted)
  Future<void> cancel(String messageId) async {
    await _box?.delete(messageId);
  }

  /// Get disappear_at for a message (null = no timer)
  DateTime? getDisappearAt(String messageId) {
    final json = _box?.get(messageId);
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return DateTime.parse(m['disappearAt'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> Function(String)? _expireCallback;

  void setExpireCallback(Future<void> Function(String) callback) {
    _expireCallback = callback;
  }

  Future<void> _checkExpired() async {
    final box = _box;
    if (box == null) return;

    final now = DateTime.now();
    final toDelete = <String>[];

    for (final key in box.keys) {
      final json = box.get(key as String);
      if (json == null) continue;
      try {
        final m = jsonDecode(json) as Map<String, dynamic>;
        final disappearAt = DateTime.parse(m['disappearAt'] as String);
        if (now.isAfter(disappearAt)) {
          toDelete.add(key);
        }
      } catch (_) {
        toDelete.add(key);
      }
    }

    for (final msgId in toDelete) {
      await box.delete(msgId);

      // Req 9.3 — overwrite, then call storage to delete
      await _expireCallback?.call(msgId);

      // Notify UI (Req 9.5)
      _deletedController.add(msgId);
      debugPrint('[Disappear] Message $msgId expired and deleted');
    }
  }

  void dispose() {
    _bgTimer?.cancel();
    _deletedController.close();
  }
}
