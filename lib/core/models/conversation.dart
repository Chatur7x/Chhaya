import 'contact.dart';
import 'message.dart';

class Conversation {
  final String id;
  final List<Contact> participants;
  final Message? lastMessage;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isGroup;
  final String? groupName;
  final String? groupAvatarUrl;
  final DateTime createdAt;

  Conversation({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isGroup = false,
    this.groupName,
    this.groupAvatarUrl,
    required this.createdAt,
  });


  String get displayName {
    if (isGroup && groupName != null) return groupName!;
    if (participants.isNotEmpty) return participants.first.displayName;
    return 'Unknown';
  }

  Conversation copyWith({
    String? id,
    List<Contact>? participants,
    Message? lastMessage,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    bool? isGroup,
    String? groupName,
    String? groupAvatarUrl,
    DateTime? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isGroup: isGroup ?? this.isGroup,
      groupName: groupName ?? this.groupName,
      groupAvatarUrl: groupAvatarUrl ?? this.groupAvatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      participants: (json['participants'] as List<dynamic>)
          .map((e) => Contact.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      isPinned: json['isPinned'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      isGroup: json['isGroup'] as bool? ?? false,
      groupName: json['groupName'] as String?,
      groupAvatarUrl: json['groupAvatarUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'participants': participants.map((p) => p.toJson()).toList(),
    'lastMessage': lastMessage?.toJson(),
    'unreadCount': unreadCount,
    'isPinned': isPinned,
    'isMuted': isMuted,
    'isGroup': isGroup,
    'groupName': groupName,
    'groupAvatarUrl': groupAvatarUrl,
    'createdAt': createdAt.toIso8601String(),
  };
}
