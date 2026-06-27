import 'package:hive_flutter/hive_flutter.dart';

class StarredMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime starredAt;
  final String messageType;

  StarredMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.starredAt,
    this.messageType = 'text',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'starredAt': starredAt.toIso8601String(),
        'messageType': messageType,
      };

  factory StarredMessage.fromJson(Map<String, dynamic> json) => StarredMessage(
        id: json['id'],
        chatId: json['chatId'],
        senderId: json['senderId'],
        senderName: json['senderName'],
        content: json['content'],
        starredAt: DateTime.parse(json['starredAt']),
        messageType: json['messageType'] ?? 'text',
      );
}

class StarService {
  static const String _boxName = 'starred_messages';
  Box<String>? _box;

  Future<void> initialize() async {
    _box = await Hive.openBox(_boxName);
  }

  Future<void> starMessage({
    required String messageId,
    required String chatId,
    required String senderId,
    required String senderName,
    required String content,
    String messageType = 'text',
  }) async {
    final starred = StarredMessage(
      id: 'star_$messageId',
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      content: content,
      starredAt: DateTime.now(),
      messageType: messageType,
    );

    await _box?.put(messageId, starred.toJson().toString());
  }

  Future<void> unstarMessage(String messageId) async {
    await _box?.delete(messageId);
  }

  bool isStarred(String messageId) {
    return _box?.containsKey(messageId) ?? false;
  }

  List<StarredMessage> getAllStarred() {
    final messages = <StarredMessage>[];
    for (final key in _box?.keys ?? []) {
      final json = _box?.get(key);
      if (json != null) {
        try {
          messages.add(StarredMessage.fromJson(Uri.splitQueryString(json)));
        } catch (_) {}
      }
    }
    messages.sort((a, b) => b.starredAt.compareTo(a.starredAt));
    return messages;
  }

  List<StarredMessage> getStarredInChat(String chatId) {
    return getAllStarred().where((m) => m.chatId == chatId).toList();
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }
}

class ForwardedMessage {
  final String originalId;
  final String originalChatId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime forwardedAt;
  final List<String> forwardedToChatIds;

  ForwardedMessage({
    required this.originalId,
    required this.originalChatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.forwardedAt,
    required this.forwardedToChatIds,
  });

  Map<String, dynamic> toJson() => {
        'originalId': originalId,
        'originalChatId': originalChatId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'forwardedAt': forwardedAt.toIso8601String(),
        'forwardedToChatIds': forwardedToChatIds,
      };

  factory ForwardedMessage.fromJson(Map<String, dynamic> json) =>
      ForwardedMessage(
        originalId: json['originalId'],
        originalChatId: json['originalChatId'],
        senderId: json['senderId'],
        senderName: json['senderName'],
        content: json['content'],
        forwardedAt: DateTime.parse(json['forwardedAt']),
        forwardedToChatIds: List<String>.from(json['forwardedToChatIds'] ?? []),
      );
}

class ForwardService {
  static const String _boxName = 'forward_history';
  Box<String>? _box;

  Future<void> initialize() async {
    _box = await Hive.openBox(_boxName);
  }

  Future<void> forwardMessage({
    required String messageId,
    required String chatId,
    required String senderId,
    required String senderName,
    required String content,
    required List<String> targetChatIds,
  }) async {
    final forwarded = ForwardedMessage(
      originalId: messageId,
      originalChatId: chatId,
      senderId: senderId,
      senderName: senderName,
      content: content,
      forwardedAt: DateTime.now(),
      forwardedToChatIds: targetChatIds,
    );

    await _box?.put(messageId, forwarded.toJson().toString());
  }

  List<ForwardedMessage> getForwardHistory() {
    final messages = <ForwardedMessage>[];
    for (final key in _box?.keys ?? []) {
      final json = _box?.get(key);
      if (json != null) {
        try {
          messages.add(ForwardedMessage.fromJson(Uri.splitQueryString(json)));
        } catch (_) {}
      }
    }
    return messages;
  }
}

class BroadcastList {
  final String id;
  final String name;
  final List<String> recipientIds;
  final DateTime createdAt;

  BroadcastList({
    required this.id,
    required this.name,
    required this.recipientIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'recipientIds': recipientIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BroadcastList.fromJson(Map<String, dynamic> json) => BroadcastList(
        id: json['id'],
        name: json['name'],
        recipientIds: List<String>.from(json['recipientIds'] ?? []),
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class BroadcastService {
  static const String _boxName = 'broadcast_lists';
  Box<String>? _box;

  Future<void> initialize() async {
    _box = await Hive.openBox(_boxName);
  }

  Future<BroadcastList> createBroadcast({
    required String name,
    required List<String> recipientIds,
  }) async {
    final id = 'broadcast_${DateTime.now().millisecondsSinceEpoch}';
    final broadcast = BroadcastList(
      id: id,
      name: name,
      recipientIds: recipientIds,
      createdAt: DateTime.now(),
    );

    await _box?.put(id, broadcast.toJson().toString());
    return broadcast;
  }

  Future<void> updateBroadcast(BroadcastList broadcast) async {
    await _box?.put(broadcast.id, broadcast.toJson().toString());
  }

  Future<void> deleteBroadcast(String id) async {
    await _box?.delete(id);
  }

  List<BroadcastList> getAllBroadcasts() {
    final broadcasts = <BroadcastList>[];
    for (final key in _box?.keys ?? []) {
      final json = _box?.get(key);
      if (json != null) {
        try {
          broadcasts.add(BroadcastList.fromJson(Uri.splitQueryString(json)));
        } catch (_) {}
      }
    }
    return broadcasts;
  }

  Future<void> addRecipient(String broadcastId, String recipientId) async {
    final json = _box?.get(broadcastId);
    if (json != null) {
      try {
        final broadcast = BroadcastList.fromJson(Uri.splitQueryString(json));
        if (!broadcast.recipientIds.contains(recipientId)) {
          final updated = BroadcastList(
            id: broadcast.id,
            name: broadcast.name,
            recipientIds: [...broadcast.recipientIds, recipientId],
            createdAt: broadcast.createdAt,
          );
          await updateBroadcast(updated);
        }
      } catch (_) {}
    }
  }

  Future<void> removeRecipient(String broadcastId, String recipientId) async {
    final json = _box?.get(broadcastId);
    if (json != null) {
      try {
        final broadcast = BroadcastList.fromJson(Uri.splitQueryString(json));
        final updated = BroadcastList(
          id: broadcast.id,
          name: broadcast.name,
          recipientIds:
              broadcast.recipientIds.where((id) => id != recipientId).toList(),
          createdAt: broadcast.createdAt,
        );
        await updateBroadcast(updated);
      } catch (_) {}
    }
  }
}
