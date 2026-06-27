import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService();
});

class PresenceService {
  static const String presenceBoxName = 'presence_data';
  static const String typingBoxName = 'typing_indicators';
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration presenceTimeout = Duration(minutes: 2);

  Box? _presenceBox;
  Box? _typingBox;
  Timer? _heartbeatTimer;

  final _typingController = StreamController<TypingEvent>.broadcast();
  Stream<TypingEvent> get typingStream => _typingController.stream;

  final _presenceController = StreamController<PresenceEvent>.broadcast();
  Stream<PresenceEvent> get presenceStream => _presenceController.stream;

  bool readReceiptsEnabled = true;
  bool typingIndicatorsEnabled = true;

  Future<void> initialize() async {
    _presenceBox = await Hive.openBox(presenceBoxName);
    _typingBox = await Hive.openBox(typingBoxName);
    _startHeartbeat();
    _loadSettings();
  }

  void _loadSettings() {
    readReceiptsEnabled =
        _presenceBox?.get('readReceiptsEnabled', defaultValue: true) ?? true;
    typingIndicatorsEnabled =
        _presenceBox?.get('typingIndicatorsEnabled', defaultValue: true) ??
            true;
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _updateHeartbeat();
    });
  }

  void _updateHeartbeat() {
    _presenceBox?.put('lastHeartbeat', DateTime.now().toIso8601String());
    _checkUserPresence();
  }

  void _checkUserPresence() {
    final now = DateTime.now();
    for (final key in _presenceBox?.keys ?? []) {
      if (key == 'lastHeartbeat' ||
          key == 'readReceiptsEnabled' ||
          key == 'typingIndicatorsEnabled') continue;

      final lastSeenStr = _presenceBox?.get(key);
      if (lastSeenStr != null) {
        try {
          final lastSeen = DateTime.parse(lastSeenStr as String);
          if (now.difference(lastSeen) > presenceTimeout) {
            _presenceController.add(PresenceEvent(
              userId: key as String,
              isOnline: false,
            ));
          }
        } catch (_) {}
      }
    }
  }

  void sendTyping(String recipientId) {
    if (!typingIndicatorsEnabled) return;

    _typingBox?.put('typing_$recipientId', DateTime.now().toIso8601String());
    _typingController.add(TypingEvent(
      senderId: recipientId,
      isTyping: true,
    ));
  }

  void receiveTyping(String senderId, bool isTyping) {
    if (!typingIndicatorsEnabled) return;

    if (isTyping) {
      _typingBox?.put('typing_$senderId', DateTime.now().toIso8601String());
    } else {
      _typingBox?.delete('typing_$senderId');
    }

    _typingController.add(TypingEvent(
      senderId: senderId,
      isTyping: isTyping,
    ));
  }

  void sendReadReceipt(String messageId, String senderId) {
    if (!readReceiptsEnabled) return;

    _presenceBox?.put('read_$messageId', DateTime.now().toIso8601String());
  }

  void setOnlineStatus(String userId, bool isOnline) {
    _presenceBox?.put(
      userId,
      isOnline ? DateTime.now().toIso8601String() : null,
    );

    _presenceController.add(PresenceEvent(
      userId: userId,
      isOnline: isOnline,
    ));
  }

  bool isUserOnline(String userId) {
    final lastSeenStr = _presenceBox?.get(userId);
    if (lastSeenStr == null) return false;

    try {
      final lastSeen = DateTime.parse(lastSeenStr as String);
      return DateTime.now().difference(lastSeen) < presenceTimeout;
    } catch (_) {
      return false;
    }
  }

  DateTime? getLastSeen(String userId) {
    final lastSeenStr = _presenceBox?.get(userId);
    if (lastSeenStr == null) return null;

    try {
      return DateTime.parse(lastSeenStr as String);
    } catch (_) {
      return null;
    }
  }

  bool isTyping(String userId) {
    final typingStr = _typingBox?.get('typing_$userId');
    if (typingStr == null) return false;

    try {
      final lastTyping = DateTime.parse(typingStr as String);
      return DateTime.now().difference(lastTyping) < const Duration(seconds: 5);
    } catch (_) {
      return false;
    }
  }

  void setReadReceiptsEnabled(bool enabled) {
    readReceiptsEnabled = enabled;
    _presenceBox?.put('readReceiptsEnabled', enabled);
  }

  void setTypingIndicatorsEnabled(bool enabled) {
    typingIndicatorsEnabled = enabled;
    _presenceBox?.put('typingIndicatorsEnabled', enabled);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _typingController.close();
    _presenceController.close();
  }
}

class TypingEvent {
  final String senderId;
  final bool isTyping;

  TypingEvent({required this.senderId, required this.isTyping});
}

class PresenceEvent {
  final String userId;
  final bool isOnline;

  PresenceEvent({required this.userId, required this.isOnline});
}
