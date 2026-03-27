import 'package:hive/hive.dart';

part 'contact.g.dart'; // We will also manually generate this adapter

enum ContactStatus { nearby, viaRelay, unreachable }

class ContactAdapter extends TypeAdapter<Contact> {
  @override
  final int typeId = 0; // The first Hive adapter

  @override
  Contact read(BinaryReader reader) {
    try {
      final numOfFields = reader.readByte();
      final fields = <int, dynamic>{
        for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
      };
      return Contact(
        deviceId: fields[0] as String,
        publicKey: fields[1] as String,
        name: fields[2] as String? ?? 'Anonymous',
        addedAt: fields[3] as DateTime? ?? DateTime.now(),
        isTrusted: fields[4] as bool? ?? false,
        isStealth: fields[5] as bool? ?? false,
      );
    } catch (e) {
      return Contact(deviceId: 'unknown', publicKey: 'unknown');
    }
  }

  @override
  void write(BinaryWriter writer, Contact obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.deviceId)
      ..writeByte(1)
      ..write(obj.publicKey)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.addedAt)
      ..writeByte(4)
      ..write(obj.isTrusted)
      ..writeByte(5)
      ..write(obj.isStealth);
  }
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
}
