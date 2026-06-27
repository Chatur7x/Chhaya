import 'package:hive/hive.dart';

part 'contact.g.dart';

enum ContactStatus { nearby, viaRelay, unreachable }

enum ContactGroup {
  family,
  team,
  emergency,
  custom,
}

@HiveType(typeId: 0)
class Contact extends HiveObject {
  @HiveField(0)
  final String deviceId;

  @HiveField(1)
  final String publicKey;

  @HiveField(2)
  String name;

  @HiveField(3)
  final DateTime addedAt;

  @HiveField(4)
  bool isTrusted;

  @HiveField(5)
  bool isStealth;

  @HiveField(6)
  List<ContactGroup> groups;

  @HiveField(7)
  String? callsign;

  @HiveField(8)
  bool isBlocked;

  @HiveField(9)
  String? avatarEmoji;

  ContactStatus status = ContactStatus.unreachable;

  Contact({
    required this.deviceId,
    required this.publicKey,
    this.name = 'Anonymous',
    DateTime? addedAt,
    this.isTrusted = false,
    this.isStealth = false,
    this.groups = const [],
    this.callsign,
    this.isBlocked = false,
    this.avatarEmoji,
  }) : addedAt = addedAt ?? DateTime.now();

  String get displayCallsign =>
      callsign ?? '${name.substring(0, 1).toUpperCase()}-1';

  String get statusText {
    switch (status) {
      case ContactStatus.nearby:
        return 'Nearby';
      case ContactStatus.viaRelay:
        return 'Reachable via relay';
      case ContactStatus.unreachable:
        return 'Offline';
    }
  }

  String get groupNames {
    if (groups.isEmpty) return 'No groups';
    return groups
        .map((g) => g.name.substring(0, 1).toUpperCase() + g.name.substring(1))
        .join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': deviceId,
        'pk': publicKey,
        'name': name,
        'trusted': isTrusted,
        'stealth': isStealth,
        'groups': groups.map((g) => g.index).toList(),
        'callsign': callsign,
        'blocked': isBlocked,
        'avatarEmoji': avatarEmoji,
      };

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      deviceId: json['id'] as String,
      publicKey: json['pk'] as String,
      name: json['name'] as String? ?? 'Anonymous',
      isTrusted: json['trusted'] as bool? ?? false,
      isStealth: json['stealth'] as bool? ?? false,
      groups: (json['groups'] as List<dynamic>?)
              ?.map((i) => ContactGroup.values[i as int])
              .toList() ??
          [],
      callsign: json['callsign'] as String?,
      isBlocked: json['blocked'] as bool? ?? false,
      avatarEmoji: json['avatarEmoji'] as String?,
    );
  }

  Contact copyWith({
    String? name,
    bool? isTrusted,
    bool? isStealth,
    List<ContactGroup>? groups,
    String? callsign,
    bool? isBlocked,
    String? avatarEmoji,
    ContactStatus? status,
  }) {
    return Contact(
      deviceId: deviceId,
      publicKey: publicKey,
      name: name ?? this.name,
      addedAt: addedAt,
      isTrusted: isTrusted ?? this.isTrusted,
      isStealth: isStealth ?? this.isStealth,
      groups: groups ?? this.groups,
      callsign: callsign ?? this.callsign,
      isBlocked: isBlocked ?? this.isBlocked,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
    )..status = status ?? this.status;
  }
}

@HiveType(typeId: 10)
class ContactGroupModel extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  int colorValue;

  @HiveField(2)
  String? iconName;

  @HiveField(3)
  List<String> memberIds;

  @HiveField(4)
  bool isSystem;

  ContactGroupModel({
    required this.name,
    required this.colorValue,
    this.iconName,
    this.memberIds = const [],
    this.isSystem = false,
  });

  ContactGroupModel copyWith({
    String? name,
    int? colorValue,
    String? iconName,
    List<String>? memberIds,
  }) {
    return ContactGroupModel(
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconName: iconName ?? this.iconName,
      memberIds: memberIds ?? this.memberIds,
      isSystem: isSystem,
    );
  }
}
