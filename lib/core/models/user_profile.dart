import 'chhaya_id.dart';

class UserProfile {
  final ChhayaId ChhayaId;
  final String displayName;
  final String? avatarUrl;
  final List<String> recoveryPhrase;
  final DateTime createdAt;

  UserProfile({
    required this.ChhayaId,
    required this.displayName,
    this.avatarUrl,
    required this.recoveryPhrase,
    required this.createdAt,
  });

  UserProfile copyWith({
    ChhayaId? ChhayaId,
    String? displayName,
    String? avatarUrl,
    List<String>? recoveryPhrase,
    DateTime? createdAt,
  }) {
    return UserProfile(
      ChhayaId: ChhayaId ?? this.ChhayaId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      recoveryPhrase: recoveryPhrase ?? this.recoveryPhrase,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      ChhayaId: ChhayaId.fromJson(json['ChhayaId'] as Map<String, dynamic>),
      displayName: json['displayName'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      recoveryPhrase: (json['recoveryPhrase'] as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'ChhayaId': ChhayaId.toJson(),
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'recoveryPhrase': recoveryPhrase,
    'createdAt': createdAt.toIso8601String(),
  };
}
