import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'mesh_message.dart';

/// Store-and-Forward Service (Req 6)
/// Holds encrypted message blobs for offline recipients with 7-day TTL.
/// Never decrypts — only relays opaque blobs.
class StoreForwardService {
  static const String _boxName = 'chaaya_sfq';
  static const int _maxPerRecipient = 500;
  static const int _ttlDays = 7;

  Box<String>? _box;
  Timer? _purgeTimer;

  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_boxName);
    // Start background purge every 60 seconds
    _purgeTimer = Timer.periodic(const Duration(seconds: 60), (_) => purgeExpired());
    purgeExpired(); // run immediately on startup
    debugPrint('[SFQ] Initialized with ${_box?.length ?? 0} queued messages');
  }

  /// Enqueue an encrypted blob for an offline recipient
  Future<bool> enqueue(MeshMessage message) async {
    final box = _box;
    if (box == null) return false;

    // Enforce per-recipient capacity limit
    final existing = _getKeysForRecipient(message.recipientId);
    if (existing.length >= _maxPerRecipient) {
      debugPrint('[SFQ] Queue full for ${message.recipientId}, dropping oldest');
      // Remove oldest to make room
      await box.delete(existing.first);
    }

    final entry = _SFQEntry(
      messageId: message.id,
      recipientId: message.recipientId,
      encryptedBlob: base64Encode(message.toBytes()),
      enqueuedAt: DateTime.now(),
      ttlDays: _ttlDays,
    );

    await box.put(_entryKey(message.recipientId, message.id), jsonEncode(entry.toJson()));
    debugPrint('[SFQ] Queued message ${message.id} for ${message.recipientId}');
    return true;
  }

  /// Retrieve all queued messages for a recipient (called when they come online)
  List<MeshMessage> getQueuedFor(String recipientId) {
    final box = _box;
    if (box == null) return [];

    final keys = _getKeysForRecipient(recipientId);
    final messages = <MeshMessage>[];

    for (final key in keys) {
      final json = box.get(key);
      if (json == null) continue;
      try {
        final entry = _SFQEntry.fromJson(jsonDecode(json));
        final bytes = base64Decode(entry.encryptedBlob);
        messages.add(MeshMessage.fromBytes(bytes));
      } catch (e) {
        debugPrint('[SFQ] Failed to deserialise entry $key: $e');
      }
    }

    return messages;
  }

  /// Remove a successfully delivered message from the queue (Req 6.3)
  Future<void> removeDelivered(String recipientId, String messageId) async {
    await _box?.delete(_entryKey(recipientId, messageId));
    debugPrint('[SFQ] Removed delivered message $messageId');
  }

  /// Purge all entries whose TTL has expired (Req 6.4)
  Future<void> purgeExpired() async {
    final box = _box;
    if (box == null) return;

    final now = DateTime.now();
    final toDelete = <String>[];

    for (final key in box.keys) {
      final json = box.get(key as String);
      if (json == null) continue;
      try {
        final entry = _SFQEntry.fromJson(jsonDecode(json));
        final expiresAt = entry.enqueuedAt.add(Duration(days: entry.ttlDays));
        if (now.isAfter(expiresAt)) {
          toDelete.add(key);
        }
      } catch (_) {
        toDelete.add(key); // delete corrupt entries
      }
    }

    for (final key in toDelete) {
      await box.delete(key);
    }

    if (toDelete.isNotEmpty) {
      debugPrint('[SFQ] Purged ${toDelete.length} expired entries');
    }
  }

  /// Clear entire queue (panic wipe)
  Future<void> clearAll() async {
    await _box?.clear();
    debugPrint('[SFQ] All queued messages cleared');
  }

  int get queueSize => _box?.length ?? 0;

  List<String> _getKeysForRecipient(String recipientId) {
    final box = _box;
    if (box == null) return [];
    return box.keys
        .where((k) => (k as String).startsWith('sfq_${recipientId}_'))
        .cast<String>()
        .toList()
      ..sort();
  }

  String _entryKey(String recipientId, String messageId) =>
      'sfq_${recipientId}_$messageId';

  void dispose() {
    _purgeTimer?.cancel();
  }
}

class _SFQEntry {
  final String messageId;
  final String recipientId;
  final String encryptedBlob; // base64 of MeshMessage.toBytes()
  final DateTime enqueuedAt;
  final int ttlDays;

  _SFQEntry({
    required this.messageId,
    required this.recipientId,
    required this.encryptedBlob,
    required this.enqueuedAt,
    required this.ttlDays,
  });

  factory _SFQEntry.fromJson(Map<String, dynamic> j) => _SFQEntry(
        messageId: j['messageId'],
        recipientId: j['recipientId'],
        encryptedBlob: j['encryptedBlob'],
        enqueuedAt: DateTime.parse(j['enqueuedAt']),
        ttlDays: j['ttlDays'] ?? 7,
      );

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'recipientId': recipientId,
        'encryptedBlob': encryptedBlob,
        'enqueuedAt': enqueuedAt.toIso8601String(),
        'ttlDays': ttlDays,
      };
}
