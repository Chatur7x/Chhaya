import 'package:flutter/foundation.dart';

class VectorClock {
  final Map<String, int> _clock;
  final String _deviceId;
  int _lamportTime;

  VectorClock(this._deviceId)
      : _clock = {},
        _lamportTime = 0;

  String get deviceId => _deviceId;
  int get lamportTime => _lamportTime;
  Map<String, int> get clock => Map.unmodifiable(_clock);

  int increment() {
    _lamportTime++;
    _clock[_deviceId] = _lamportTime;
    return _lamportTime;
  }

  void update(String nodeId, int timestamp) {
    _lamportTime = timestamp > _lamportTime ? timestamp + 1 : _lamportTime + 1;
    _clock[nodeId] = timestamp;
    _clock[_deviceId] = _lamportTime;
  }

  void merge(VectorClock other) {
    for (final entry in other._clock.entries) {
      if (!_clock.containsKey(entry.key) || _clock[entry.key]! < entry.value) {
        _clock[entry.key] = entry.value;
      }
    }
    final maxTime =
        _clock.values.fold(_lamportTime, (max, t) => t > max ? t : max);
    _lamportTime = maxTime + 1;
    _clock[_deviceId] = _lamportTime;
  }

  bool happensBefore(VectorClock other) {
    bool atLeastOneLess = false;

    for (final entry in _clock.entries) {
      final otherTime = other._clock[entry.key] ?? 0;
      if (entry.value > otherTime) {
        return false;
      }
      if (entry.value < otherTime) {
        atLeastOneLess = true;
      }
    }

    for (final entry in other._clock.entries) {
      if (!_clock.containsKey(entry.key) && entry.value > 0) {
        atLeastOneLess = true;
      }
    }

    return atLeastOneLess;
  }

  bool isConcurrent(VectorClock other) {
    return !happensBefore(other) &&
        !other.happensBefore(this) &&
        !equals(other);
  }

  bool equals(VectorClock other) {
    if (_clock.length != other._clock.length) return false;
    for (final entry in _clock.entries) {
      if (other._clock[entry.key] != entry.value) return false;
    }
    return true;
  }

  VectorClock copy() {
    final newClock = VectorClock(_deviceId);
    newClock._clock.addAll(_clock);
    newClock._lamportTime = _lamportTime;
    return newClock;
  }

  Map<String, dynamic> toJson() => {
        'deviceId': _deviceId,
        'clock': _clock,
        'lamportTime': _lamportTime,
      };

  factory VectorClock.fromJson(Map<String, dynamic> json) {
    final clock = VectorClock(json['deviceId'] as String);
    clock._clock.addAll(Map<String, int>.from(json['clock'] as Map));
    clock._lamportTime = json['lamportTime'] as int;
    return clock;
  }

  @override
  String toString() => 'VectorClock($_clock)';
}

class TimestampedMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final VectorClock vectorClock;
  final int priority;
  final String? replyToId;

  TimestampedMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.vectorClock,
    this.priority = 0,
    this.replyToId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'vectorClock': vectorClock.toJson(),
        'priority': priority,
        'replyToId': replyToId,
      };

  factory TimestampedMessage.fromJson(Map<String, dynamic> json) {
    return TimestampedMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      vectorClock:
          VectorClock.fromJson(json['vectorClock'] as Map<String, dynamic>),
      priority: json['priority'] as int? ?? 0,
      replyToId: json['replyToId'] as String?,
    );
  }
}

class CausalOrdering {
  final Map<String, VectorClock> _messageClocks = {};

  void recordMessage(TimestampedMessage message) {
    _messageClocks[message.id] = message.vectorClock.copy();
  }

  List<TimestampedMessage> orderMessages(List<TimestampedMessage> messages) {
    final sorted = List<TimestampedMessage>.from(messages);
    sorted.sort((a, b) => _compareMessages(a, b));
    return sorted;
  }

  int _compareMessages(TimestampedMessage a, TimestampedMessage b) {
    if (a.vectorClock.happensBefore(b.vectorClock)) {
      return -1;
    }
    if (b.vectorClock.happensBefore(a.vectorClock)) {
      return 1;
    }

    if (a.vectorClock.isConcurrent(b.vectorClock)) {
      return a.timestamp.compareTo(b.timestamp);
    }

    return 0;
  }

  bool shouldDeliver(TimestampedMessage message, VectorClock receivedClock) {
    for (final entry in _messageClocks.entries) {
      final deliveredClock = entry.value;

      if (deliveredClock.happensBefore(receivedClock)) {
        continue;
      }

      if (receivedClock.happensBefore(deliveredClock)) {
        return false;
      }
    }

    return true;
  }

  VectorClock? getClock(String messageId) => _messageClocks[messageId];

  void clear() => _messageClocks.clear();
}
