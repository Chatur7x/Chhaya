import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'vector_clock.dart';

class CRDTMessageStore {
  static const String _boxName = 'chaaya_crdt_messages';
  late Box<String> _box;
  final Map<String, VectorClock> _vectorClocks = {};
  final CausalOrdering _causalOrdering = CausalOrdering();
  final _messageUpdates = StreamController<List<CRDTMessage>>.broadcast();

  Stream<List<CRDTMessage>> get messageUpdates => _messageUpdates.stream;

  final Map<String, CRDTMessage> _messages = {};

  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_boxName);
    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    for (final entry in _box.toMap().entries) {
      try {
        final json = jsonDecode(entry.value as String);
        final message = CRDTMessage.fromJson(json);
        _messages[message.id] = message;
        _vectorClocks[message.id] = message.vectorClock;
        _causalOrdering.recordMessage(message.toTimestamped());
      } catch (e) {
        debugPrint('[CRDT] Error loading message: $e');
      }
    }
  }

  Future<void> addMessage(CRDTMessage message) async {
    final receivedClock = message.vectorClock;

    if (!_causalOrdering.shouldDeliver(
        message.toTimestamped(), receivedClock)) {
      debugPrint(
          '[CRDT] Message ${message.id} not delivered - causal ordering violation');
      return;
    }

    final existing = _messages[message.id];
    if (existing != null) {
      if (_resolveConflict(existing, message)) {
        _messages[message.id] = message;
        await _saveMessage(message);
        _notifyUpdate();
      }
    } else {
      _messages[message.id] = message;
      _vectorClocks[message.id] = message.vectorClock;
      _causalOrdering.recordMessage(message.toTimestamped());
      await _saveMessage(message);
      _notifyUpdate();
    }
  }

  bool _resolveConflict(CRDTMessage existing, CRDTMessage incoming) {
    switch (existing.mergeStrategy) {
      case MergeStrategy.lww:
        return incoming.vectorClock.lamportTime >=
            existing.vectorClock.lamportTime;

      case MergeStrategy.firstWriteWins:
        return false;

      case MergeStrategy.lastWriteWins:
        return incoming.timestamp.isAfter(existing.timestamp);

      case MergeStrategy.priority:
        return (incoming.priority ?? 0) > (existing.priority ?? 0);
    }
  }

  Future<void> _saveMessage(CRDTMessage message) async {
    await _box.put(message.id, jsonEncode(message.toJson()));
  }

  void _notifyUpdate() {
    _messageUpdates.add(getAllMessages());
  }

  List<CRDTMessage> getAllMessages() {
    return _causalOrdering
        .orderMessages(_messages.values.map((m) => m.toTimestamped()).toList())
        .map((tm) => _messages[tm.id]!)
        .toList();
  }

  List<CRDTMessage> getMessagesForConversation(String conversationId) {
    return getAllMessages()
        .where((m) => m.conversationId == conversationId)
        .toList();
  }

  List<CRDTMessage> getMessagesBySender(String senderId) {
    return getAllMessages().where((m) => m.senderId == senderId).toList();
  }

  CRDTMessage? getMessage(String id) => _messages[id];

  Future<void> deleteMessage(String id) async {
    final message = _messages[id];
    if (message == null) return;

    final deleted = CRDTMessage(
      id: message.id,
      senderId: message.senderId,
      conversationId: message.conversationId,
      content: '',
      timestamp: DateTime.now(),
      vectorClock: message.vectorClock,
      isDeleted: true,
      mergeStrategy: MergeStrategy.lww,
    );

    _messages[id] = deleted;
    await _saveMessage(deleted);
    _notifyUpdate();
  }

  int get messageCount => _messages.length;

  Map<String, dynamic> getStats() => {
        'totalMessages': _messages.length,
        'activeMessages': _messages.values.where((m) => !m.isDeleted).length,
        'deletedMessages': _messages.values.where((m) => m.isDeleted).length,
        'conversations':
            _messages.values.map((m) => m.conversationId).toSet().length,
      };

  Future<void> clear() async {
    _messages.clear();
    _vectorClocks.clear();
    _causalOrdering.clear();
    await _box.clear();
    _notifyUpdate();
  }

  Future<void> compact({int keepMessages = 1000}) async {
    if (_messages.length <= keepMessages) return;

    final sorted = getAllMessages().where((m) => !m.isDeleted).toList();
    final toKeep = sorted.take(keepMessages).map((m) => m.id).toSet();
    final toDelete =
        _messages.keys.where((id) => !toKeep.contains(id)).toList();

    for (final id in toDelete) {
      await _box.delete(id);
      _messages.remove(id);
      _vectorClocks.remove(id);
    }

    debugPrint('[CRDT] Compacted: removed ${toDelete.length} old messages');
    _notifyUpdate();
  }

  void dispose() {
    _messageUpdates.close();
  }
}

class CRDTMessage {
  final String id;
  final String senderId;
  final String conversationId;
  final String content;
  final DateTime timestamp;
  final VectorClock vectorClock;
  final bool isDeleted;
  final int? priority;
  final String? replyToId;
  final Map<String, dynamic>? metadata;
  final MergeStrategy mergeStrategy;

  CRDTMessage({
    required this.id,
    required this.senderId,
    required this.conversationId,
    required this.content,
    required this.timestamp,
    required this.vectorClock,
    this.isDeleted = false,
    this.priority,
    this.replyToId,
    this.metadata,
    this.mergeStrategy = MergeStrategy.lww,
  });

  TimestampedMessage toTimestamped() => TimestampedMessage(
        id: id,
        senderId: senderId,
        content: content,
        timestamp: timestamp,
        vectorClock: vectorClock,
        priority: priority ?? 0,
        replyToId: replyToId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'conversationId': conversationId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'vectorClock': vectorClock.toJson(),
        'isDeleted': isDeleted,
        'priority': priority,
        'replyToId': replyToId,
        'metadata': metadata,
        'mergeStrategy': mergeStrategy.name,
      };

  factory CRDTMessage.fromJson(Map<String, dynamic> json) {
    return CRDTMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      conversationId: json['conversationId'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      vectorClock:
          VectorClock.fromJson(json['vectorClock'] as Map<String, dynamic>),
      isDeleted: json['isDeleted'] as bool? ?? false,
      priority: json['priority'] as int?,
      replyToId: json['replyToId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      mergeStrategy: MergeStrategy.values.firstWhere(
        (e) => e.name == json['mergeStrategy'],
        orElse: () => MergeStrategy.lww,
      ),
    );
  }
}

enum MergeStrategy {
  lww,
  firstWriteWins,
  lastWriteWins,
  priority,
}
