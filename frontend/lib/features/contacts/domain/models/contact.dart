import 'package:hive/hive.dart';

part 'contact.g.dart'; // We will also manually generate this adapter

enum ContactStatus { nearby, viaRelay, unreachable }


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

  // Runtime only
  ContactStatus status = ContactStatus.unreachable;

  Contact({
    required this.deviceId,
    required this.publicKey,
    this.name = 'Anonymous',
    DateTime? addedAt,
    this.isTrusted = false,
    this.isStealth = false,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': deviceId,
        'pk': publicKey,
        'name': name,
        'trusted': isTrusted,
        'stealth': isStealth,
      };

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      deviceId: json['id'] as String,
      publicKey: json['pk'] as String,
      name: json['name'] as String? ?? 'Anonymous',
      isTrusted: json['trusted'] as bool? ?? false,
      isStealth: json['stealth'] as bool? ?? false,
    );
  }
}

