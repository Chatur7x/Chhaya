import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/identity/identity_service.dart';

/// Chaaya Contact Service — manages paired contacts.
/// Contacts are stored locally in Hive after QR code pairing.
class ContactService {
  static const String _boxName = 'chaaya_contacts';
  Box<String>? _box;

  /// Initialize contact storage
  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Add a new contact (from QR pairing)
  Future<MeshContact> addContact(MeshIdentity identity) async {
    final contact = MeshContact(
      username: identity.username,
      deviceId: identity.deviceId,
      publicKey: identity.publicKey,
      pairedAt: DateTime.now(),
      status: ContactStatus.unreachable,
      lastSeen: DateTime.now(),
    );

    await _box?.put(contact.deviceId, jsonEncode(contact.toJson()));
    debugPrint('[Contacts] Added: ${contact.username} (${contact.deviceId})');
    return contact;
  }

  /// Get all contacts
  List<MeshContact> getAll() {
    final box = _box;
    if (box == null) return [];
    return box.values.map((json) => MeshContact.fromJson(jsonDecode(json))).toList()
      ..sort((a, b) => a.username.compareTo(b.username));
  }

  /// Get contact by device ID
  MeshContact? getById(String deviceId) {
    final json = _box?.get(deviceId);
    if (json == null) return null;
    return MeshContact.fromJson(jsonDecode(json));
  }

  /// Update contact status
  Future<void> updateStatus(String deviceId, ContactStatus status) async {
    final contact = getById(deviceId);
    if (contact == null) return;
    final updated = contact.copyWith(status: status, lastSeen: DateTime.now());
    await _box?.put(deviceId, jsonEncode(updated.toJson()));
  }

  /// Update last seen
  Future<void> updateLastSeen(String deviceId) async {
    final contact = getById(deviceId);
    if (contact == null) return;
    final updated = contact.copyWith(lastSeen: DateTime.now());
    await _box?.put(deviceId, jsonEncode(updated.toJson()));
  }

  /// Delete a contact
  Future<void> delete(String deviceId) async {
    await _box?.delete(deviceId);
  }

  /// Check if a device is already a contact
  bool isContact(String deviceId) {
    return _box?.containsKey(deviceId) ?? false;
  }

  /// Get contact count
  int get count => _box?.length ?? 0;

  /// Clear all contacts (panic wipe)
  Future<void> clearAll() async {
    await _box?.clear();
  }

  Future<void> dispose() async {
    await _box?.close();
  }
}

/// A paired Chaaya contact
class MeshContact {
  final String username;
  final String deviceId;
  final String publicKey;
  final DateTime pairedAt;
  final ContactStatus status;
  final DateTime lastSeen;
  final String? group;
  final bool isTrustedRing;
  final bool isStealth;

  MeshContact({
    required this.username,
    required this.deviceId,
    required this.publicKey,
    required this.pairedAt,
    this.status = ContactStatus.unreachable,
    required this.lastSeen,
    this.group,
    this.isTrustedRing = false,
    this.isStealth = false,
  });

  factory MeshContact.fromJson(Map<String, dynamic> json) {
    return MeshContact(
      username: json['username'] as String,
      deviceId: json['deviceId'] as String,
      publicKey: json['publicKey'] as String,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
      status: ContactStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ContactStatus.unreachable,
      ),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      group: json['group'] as String?,
      isTrustedRing: json['isTrustedRing'] as bool? ?? false,
      isStealth: json['isStealth'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'deviceId': deviceId,
      'publicKey': publicKey,
      'pairedAt': pairedAt.toIso8601String(),
      'status': status.name,
      'lastSeen': lastSeen.toIso8601String(),
      if (group != null) 'group': group,
      'isTrustedRing': isTrustedRing,
      'isStealth': isStealth,
    };
  }

  MeshContact copyWith({
    ContactStatus? status,
    DateTime? lastSeen,
    String? group,
    bool? isTrustedRing,
    bool? isStealth,
  }) {
    return MeshContact(
      username: username,
      deviceId: deviceId,
      publicKey: publicKey,
      pairedAt: pairedAt,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      group: group ?? this.group,
      isTrustedRing: isTrustedRing ?? this.isTrustedRing,
      isStealth: isStealth ?? this.isStealth,
    );
  }

  /// Time since last seen (human readable)
  String get lastSeenText {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  String toString() => 'MeshContact($username, $status)';
}

/// Contact reachability status
enum ContactStatus {
  nearby,      // green dot — direct BLE connection
  relay,       // yellow dot — reachable via relay hops
  unreachable, // gray dot — not currently reachable
}

