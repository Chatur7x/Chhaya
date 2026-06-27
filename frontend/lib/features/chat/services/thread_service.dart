import 'dart:async';
import 'package:flutter/foundation.dart';

class MessageThread {
  final String id;
  final String subject;
  final String? parentMessageId;
  final List<String> participantIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final bool isArchived;
  final Map<String, dynamic>? metadata;

  MessageThread({
    required this.id,
    required this.subject,
    this.parentMessageId,
    required this.participantIds,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.isArchived = false,
    this.metadata,
  });

  MessageThread copyWith({
    String? id,
    String? subject,
    String? parentMessageId,
    List<String>? participantIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    bool? isArchived,
    Map<String, dynamic>? metadata,
  }) {
    return MessageThread(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      participantIds: participantIds ?? this.participantIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isArchived: isArchived ?? this.isArchived,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'parentMessageId': parentMessageId,
        'participantIds': participantIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messageCount': messageCount,
        'lastMessagePreview': lastMessagePreview,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'isArchived': isArchived,
        'metadata': metadata,
      };

  factory MessageThread.fromJson(Map<String, dynamic> json) {
    return MessageThread(
      id: json['id'],
      subject: json['subject'],
      parentMessageId: json['parentMessageId'],
      participantIds: List<String>.from(json['participantIds']),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      messageCount: json['messageCount'] ?? 0,
      lastMessagePreview: json['lastMessagePreview'],
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'])
          : null,
      isArchived: json['isArchived'] ?? false,
      metadata: json['metadata'],
    );
  }
}

class ThreadedMessage {
  final String id;
  final String threadId;
  final String? parentMessageId;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final int depth;
  final List<String> childMessageIds;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isDeleted;

  ThreadedMessage({
    required this.id,
    required this.threadId,
    this.parentMessageId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.depth = 0,
    this.childMessageIds = const [],
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
  });

  ThreadedMessage copyWith({
    String? id,
    String? threadId,
    String? parentMessageId,
    String? senderId,
    String? content,
    DateTime? timestamp,
    int? depth,
    List<String>? childMessageIds,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
  }) {
    return ThreadedMessage(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      depth: depth ?? this.depth,
      childMessageIds: childMessageIds ?? this.childMessageIds,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'threadId': threadId,
        'parentMessageId': parentMessageId,
        'senderId': senderId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'depth': depth,
        'childMessageIds': childMessageIds,
        'isEdited': isEdited,
        'editedAt': editedAt?.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory ThreadedMessage.fromJson(Map<String, dynamic> json) {
    return ThreadedMessage(
      id: json['id'],
      threadId: json['threadId'],
      parentMessageId: json['parentMessageId'],
      senderId: json['senderId'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      depth: json['depth'] ?? 0,
      childMessageIds: List<String>.from(json['childMessageIds'] ?? []),
      isEdited: json['isEdited'] ?? false,
      editedAt:
          json['editedAt'] != null ? DateTime.parse(json['editedAt']) : null,
      isDeleted: json['isDeleted'] ?? false,
    );
  }
}

class ThreadService {
  final Map<String, MessageThread> _threads = {};
  final Map<String, ThreadedMessage> _messages = {};
  final Map<String, Set<String>> _userThreads = {};

  static const int _maxThreadDepth = 10;
  static const int _maxPreviewLength = 100;

  final _threadController = StreamController<MessageThread>.broadcast();
  Stream<MessageThread> get threadUpdates => _threadController.stream;

  final _messageController = StreamController<ThreadedMessage>.broadcast();
  Stream<ThreadedMessage> get messageUpdates => _messageController.stream;

  String createThread({
    required String subject,
    required String creatorId,
    required List<String> participantIds,
    required String initialContent,
    Map<String, dynamic>? metadata,
  }) {
    final threadId = 'THREAD_${DateTime.now().millisecondsSinceEpoch}';
    final messageId = 'MSG_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    final thread = MessageThread(
      id: threadId,
      subject: subject,
      participantIds: [creatorId, ...participantIds],
      createdAt: now,
      updatedAt: now,
      messageCount: 1,
      lastMessagePreview: _truncatePreview(initialContent),
      lastMessageAt: now,
      metadata: metadata,
    );

    final initialMessage = ThreadedMessage(
      id: messageId,
      threadId: threadId,
      senderId: creatorId,
      content: initialContent,
      timestamp: now,
    );

    _threads[threadId] = thread;
    _messages[messageId] = initialMessage;

    for (final userId in thread.participantIds) {
      _userThreads[userId] ??= {};
      _userThreads[userId]!.add(threadId);
    }

    _threadController.add(thread);
    _messageController.add(initialMessage);

    return threadId;
  }

  String addReply({
    required String threadId,
    required String senderId,
    required String content,
    String? parentMessageId,
  }) {
    final thread = _threads[threadId];
    if (thread == null) throw Exception('Thread not found');

    final parentMessage =
        parentMessageId != null ? _messages[parentMessageId] : null;
    final depth = parentMessage != null ? (parentMessage.depth + 1) : 0;

    if (depth >= _maxThreadDepth) {
      throw Exception('Maximum thread depth reached');
    }

    final messageId = 'MSG_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    final reply = ThreadedMessage(
      id: messageId,
      threadId: threadId,
      parentMessageId: parentMessageId,
      senderId: senderId,
      content: content,
      timestamp: now,
      depth: depth,
    );

    _messages[messageId] = reply;

    if (parentMessageId != null) {
      final parent = _messages[parentMessageId];
      if (parent != null) {
        _messages[parentMessageId] = parent.copyWith(
          childMessageIds: [...parent.childMessageIds, messageId],
        );
      }
    }

    final updatedThread = thread.copyWith(
      messageCount: thread.messageCount + 1,
      lastMessagePreview: _truncatePreview(content),
      lastMessageAt: now,
      updatedAt: now,
    );

    _threads[threadId] = updatedThread;
    _messageController.add(reply);
    _threadController.add(updatedThread);

    return messageId;
  }

  void editMessage(String messageId, String newContent) {
    final message = _messages[messageId];
    if (message == null) return;

    final updated = message.copyWith(
      content: newContent,
      isEdited: true,
      editedAt: DateTime.now(),
    );

    _messages[messageId] = updated;
    _messageController.add(updated);
  }

  void softDeleteMessage(String messageId) {
    final message = _messages[messageId];
    if (message == null) return;

    final updated = message.copyWith(
      isDeleted: true,
      content: '[Message deleted]',
    );

    _messages[messageId] = updated;
    _messageController.add(updated);
  }

  void archiveThread(String threadId) {
    final thread = _threads[threadId];
    if (thread == null) return;

    final updated = thread.copyWith(
      isArchived: true,
      updatedAt: DateTime.now(),
    );

    _threads[threadId] = updated;
    _threadController.add(updated);
  }

  void unarchiveThread(String threadId) {
    final thread = _threads[threadId];
    if (thread == null) return;

    final updated = thread.copyWith(
      isArchived: false,
      updatedAt: DateTime.now(),
    );

    _threads[threadId] = updated;
    _threadController.add(updated);
  }

  void addParticipant(String threadId, String userId) {
    final thread = _threads[threadId];
    if (thread == null) return;

    if (!thread.participantIds.contains(userId)) {
      final updated = thread.copyWith(
        participantIds: [...thread.participantIds, userId],
        updatedAt: DateTime.now(),
      );

      _threads[threadId] = updated;
      _userThreads[userId] ??= {};
      _userThreads[userId]!.add(threadId);
      _threadController.add(updated);
    }
  }

  void removeParticipant(String threadId, String userId) {
    final thread = _threads[threadId];
    if (thread == null) return;

    final updated = thread.copyWith(
      participantIds:
          thread.participantIds.where((id) => id != userId).toList(),
      updatedAt: DateTime.now(),
    );

    _threads[threadId] = updated;
    _userThreads[userId]?.remove(threadId);
    _threadController.add(updated);
  }

  void updateSubject(String threadId, String newSubject) {
    final thread = _threads[threadId];
    if (thread == null) return;

    final updated = thread.copyWith(
      subject: newSubject,
      updatedAt: DateTime.now(),
    );

    _threads[threadId] = updated;
    _threadController.add(updated);
  }

  MessageThread? getThread(String threadId) => _threads[threadId];

  ThreadedMessage? getMessage(String messageId) => _messages[messageId];

  List<MessageThread> getUserThreads(String userId,
      {bool includeArchived = false}) {
    final threadIds = _userThreads[userId] ?? {};
    return threadIds
        .where((id) => includeArchived || !_threads[id]!.isArchived)
        .map((id) => _threads[id]!)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<ThreadedMessage> getThreadMessages(String threadId) {
    return _messages.values.where((m) => m.threadId == threadId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<ThreadedMessage> getMessageReplies(String messageId) {
    final message = _messages[messageId];
    if (message == null) return [];

    return message.childMessageIds
        .map((id) => _messages[id])
        .where((m) => m != null)
        .cast<ThreadedMessage>()
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<ThreadedMessage> getMessageChain(String messageId) {
    final chain = <ThreadedMessage>[];
    var current = _messages[messageId];

    while (current != null) {
      chain.add(current);
      if (current.parentMessageId != null) {
        current = _messages[current.parentMessageId!];
      } else {
        break;
      }
    }

    return chain.reversed.toList();
  }

  int getUnreadCount(String threadId, String userId, DateTime lastRead) {
    return _messages.values
        .where((m) =>
            m.threadId == threadId &&
            m.timestamp.isAfter(lastRead) &&
            m.senderId != userId)
        .length;
  }

  void markThreadAsRead(String threadId) {
    final thread = _threads[threadId];
    if (thread == null) return;

    final updated = thread.copyWith(updatedAt: DateTime.now());
    _threads[threadId] = updated;
    _threadController.add(updated);
  }

  List<MessageThread> searchThreads(String query) {
    final lowerQuery = query.toLowerCase();
    return _threads.values
        .where((t) =>
            t.subject.toLowerCase().contains(lowerQuery) ||
            t.lastMessagePreview?.toLowerCase().contains(lowerQuery) == true)
        .toList();
  }

  List<ThreadedMessage> searchMessages(String query) {
    final lowerQuery = query.toLowerCase();
    return _messages.values
        .where(
            (m) => !m.isDeleted && m.content.toLowerCase().contains(lowerQuery))
        .toList();
  }

  void mergeThread(
      MessageThread remoteThread, List<ThreadedMessage> remoteMessages) {
    final local = _threads[remoteThread.id];

    if (local == null) {
      _threads[remoteThread.id] = remoteThread;
      for (final msg in remoteMessages) {
        _messages[msg.id] = msg;
      }
      _threadController.add(remoteThread);
      return;
    }

    if (remoteThread.updatedAt.isAfter(local.updatedAt)) {
      _threads[remoteThread.id] = remoteThread;
      _threadController.add(remoteThread);
    }

    for (final remoteMsg in remoteMessages) {
      final localMsg = _messages[remoteMsg.id];
      if (localMsg == null || remoteMsg.timestamp.isAfter(localMsg.timestamp)) {
        _messages[remoteMsg.id] = remoteMsg;
        _messageController.add(remoteMsg);
      }
    }
  }

  Map<String, dynamic> getThreadStatistics(String threadId) {
    final thread = _threads[threadId];
    if (thread == null) return {};

    final messages = getThreadMessages(threadId);
    final participants = thread.participantIds.length;
    final messageCount = messages.length;
    final avgDepth = messages.isEmpty
        ? 0.0
        : messages.map((m) => m.depth).reduce((a, b) => a + b) / messageCount;

    return {
      'threadId': threadId,
      'participantCount': participants,
      'messageCount': messageCount,
      'averageDepth': avgDepth,
      'createdAt': thread.createdAt,
      'lastActivity': thread.lastMessageAt,
      'isArchived': thread.isArchived,
    };
  }

  String _truncatePreview(String content) {
    if (content.length <= _maxPreviewLength) return content;
    return '${content.substring(0, _maxPreviewLength)}...';
  }

  void dispose() {
    _threadController.close();
    _messageController.close();
  }
}
