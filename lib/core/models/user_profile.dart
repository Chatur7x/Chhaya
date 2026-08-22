import 'chhaya_id.dart';

class UserProfile {
  final ChhayaId chhayaId;
  final String displayName;
  final String? avatarUrl;
  final List<String> recoveryPhrase;
  final DateTime createdAt;

  UserProfile({
    required this.chhayaId,
    required this.displayName,
    this.avatarUrl,
    required this.recoveryPhrase,
    required this.createdAt,
  });

  UserProfile copyWith({
    ChhayaId? chhayaId,
    String? displayName,
    String? avatarUrl,
    List<String>? recoveryPhrase,
    DateTime? createdAt,
  }) {
    return UserProfile(
      chhayaId: chhayaId ?? this.chhayaId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      recoveryPhrase: recoveryPhrase ?? this.recoveryPhrase,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      chhayaId: ChhayaId.fromJson(json['ChhayaId'] as Map<String, dynamic>),
      displayName: json['displayName'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      recoveryPhrase: (json['recoveryPhrase'] as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'ChhayaId': chhayaId.toJson(),
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'recoveryPhrase': recoveryPhrase,
    'createdAt': createdAt.toIso8601String(),
  };
}
