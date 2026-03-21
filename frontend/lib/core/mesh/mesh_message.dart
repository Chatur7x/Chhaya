import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Represents a message in the Chaaya mesh network.
/// Can be serialized for BLE transport or JSON for WiFi.
class MeshMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String content;
  final DateTime timestamp;
  final MeshMessageType type;
  final String channel;
  final int hopCount;
  final int maxHops;
  final MessageStatus status;
  final bool isSOS;
  final Map<String, dynamic>? metadata;

  MeshMessage({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.content,
    DateTime? timestamp,
    this.type = MeshMessageType.text,
    this.channel = 'ble',
    this.hopCount = 0,
    this.maxHops = 7,
    this.status = MessageStatus.queued,
    this.isSOS = false,
    this.metadata,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Create from JSON (WiFi Direct / storage)
  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    return MeshMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String? ?? 'Unknown',
      recipientId: json['recipientId'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: MeshMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MeshMessageType.text,
      ),
      channel: json['channel'] as String? ?? 'ble',
      hopCount: json['hopCount'] as int? ?? 0,
      maxHops: json['maxHops'] as int? ?? 7,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.queued,
      ),
      isSOS: json['isSOS'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'recipientId': recipientId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'channel': channel,
      'hopCount': hopCount,
      'maxHops': maxHops,
      'status': status.name,
      'isSOS': isSOS,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Serialize to compact bytes for BLE transport
  List<int> toBytes() {
    final jsonStr = jsonEncode(toJson());
    return utf8.encode(jsonStr);
  }

  /// Deserialize from BLE bytes
  factory MeshMessage.fromBytes(List<int> bytes) {
    final jsonStr = utf8.decode(bytes);
    return MeshMessage.fromJson(jsonDecode(jsonStr));
  }

  /// Create a copy with updated fields
  MeshMessage copyWith({
    MessageStatus? status,
    int? hopCount,
    String? channel,
  }) {
    return MeshMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      recipientId: recipientId,
      content: content,
      timestamp: timestamp,
      type: type,
      channel: channel ?? this.channel,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops,
      status: status ?? this.status,
      isSOS: isSOS,
      metadata: metadata,
    );
  }

  /// Create a delivery receipt
  MeshMessage createReceipt(MessageStatus receiptStatus) {
    return MeshMessage(
      senderId: recipientId,
      senderName: '',
      recipientId: senderId,
      content: id, // original message ID
      type: MeshMessageType.receipt,
      status: receiptStatus,
    );
  }

  @override
  String toString() => 'MeshMessage($id, $senderName→$recipientId: $content)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MeshMessage && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Message types
enum MeshMessageType {
  text,
  image,
  video,
  audio,
  file,
  location,
  receipt,
  sos,
  broadcast,
  ptt, // push-to-talk audio
  contact, // contact card sharing
  system, // system messages
}

/// Message delivery status
enum MessageStatus {
  queued,    // ⏳ waiting in queue
  sent,      // ✓  sent to mesh
  delivered, // ✓✓ reached recipient
  read,      // ✓✓ blue — recipient opened
  failed,    // ✗  delivery failed
}

