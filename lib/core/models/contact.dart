import 'chhaya_id.dart';

class Contact {
  final String id;
  final ChhayaId ChhayaId;
  final String displayName;
  final String? avatarUrl;
  final int verificationLevel;
  final bool isBlocked;
  final bool isPinned;
  final DateTime? lastSeen;
  final bool isOnline;

  Contact({
    required this.id,
    required this.ChhayaId,
    required this.displayName,
    this.avatarUrl,
    this.verificationLevel = 1,
    this.isBlocked = false,
    this.isPinned = false,
    this.lastSeen,
    this.isOnline = false,
  });

  Contact copyWith({
    String? id,
    ChhayaId? ChhayaId,
    String? displayName,
    String? avatarUrl,
    int? verificationLevel,
    bool? isBlocked,
    bool? isPinned,
    DateTime? lastSeen,
    bool? isOnline,
  }) {
    return Contact(
      id: id ?? this.id,
      ChhayaId: ChhayaId ?? this.ChhayaId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      isBlocked: isBlocked ?? this.isBlocked,
      isPinned: isPinned ?? this.isPinned,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      ChhayaId: ChhayaId.fromJson(json['ChhayaId'] as Map<String, dynamic>),
      displayName: json['displayName'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      verificationLevel: json['verificationLevel'] as int? ?? 1,
      isBlocked: json['isBlocked'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ChhayaId': ChhayaId.toJson(),
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'verificationLevel': verificationLevel,
    'isBlocked': isBlocked,
    'isPinned': isPinned,
    'lastSeen': lastSeen?.toIso8601String(),
    'isOnline': isOnline,
  };
}
