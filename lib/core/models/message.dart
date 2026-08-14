enum MessageType { text, image, file, voice, system, poll }

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isRead;
  final bool isDelivered;
  final bool isSent;
  final String? replyToId;
  final Duration? ttl;
  final List<String> agreeUsers;
  final List<String> disagreeUsers;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    required this.timestamp,
    this.isRead = false,
    this.isDelivered = false,
    this.isSent = true,
    this.replyToId,
    this.ttl,
    List<String>? agreeUsers,
    List<String>? disagreeUsers,
  })  : agreeUsers = agreeUsers ?? const [],
        disagreeUsers = disagreeUsers ?? const [];

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    bool? isRead,
    bool? isDelivered,
    bool? isSent,
    String? replyToId,
    Duration? ttl,
    List<String>? agreeUsers,
    List<String>? disagreeUsers,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      isSent: isSent ?? this.isSent,
      replyToId: replyToId ?? this.replyToId,
      ttl: ttl ?? this.ttl,
      agreeUsers: agreeUsers ?? this.agreeUsers,
      disagreeUsers: disagreeUsers ?? this.disagreeUsers,
    );
  }

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(timestamp) > ttl!;
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
      isDelivered: json['isDelivered'] as bool? ?? false,
      isSent: json['isSent'] as bool? ?? true,
      replyToId: json['replyToId'] as String?,
      ttl: json['ttlMs'] != null
          ? Duration(milliseconds: json['ttlMs'] as int)
          : null,
      agreeUsers: (json['agreeUsers'] as List<dynamic>?)?.map((e) => e as String).toList(),
      disagreeUsers: (json['disagreeUsers'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'senderId': senderId,
    'content': content,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
    'isDelivered': isDelivered,
    'isSent': isSent,
    'replyToId': replyToId,
    'ttlMs': ttl?.inMilliseconds,
    'agreeUsers': agreeUsers,
    'disagreeUsers': disagreeUsers,
  };
}

