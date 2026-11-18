import '../../core/models/message.dart';
import '../../core/models/message_attachment.dart';

/// Versioned content fields are authenticated inside the ratchet envelope.
/// Older text envelopes without these optional fields remain readable.
class MessagePayload {
  static const maxTextLength = 8000;

  static Map<String, dynamic> encode(Message message) {
    final payload = <String, dynamic>{
      'content': message.content,
      'type': message.type.name,
      if (message.ttl != null) 'ttlMs': message.ttl!.inMilliseconds,
      if (message.replyToId != null) 'replyToId': message.replyToId,
      if (message.attachment != null) 'attachment': message.attachment!.toJson(),
    };
    decode(message, payload); // Validate before advancing encryption state.
    return payload;
  }

  static Message decode(Message envelope, Map<String, dynamic> payload) {
    final content = payload['content'];
    final rawType = payload['type'] ?? 'text';
    final reply = payload['replyToId'];
    final ttl = payload['ttlMs'];
    if (content is! String || content.length > maxTextLength ||
        (reply != null && (reply is! String || reply.isEmpty || reply.length > 128)) ||
        (ttl != null && (ttl is! int || ttl <= 0 || ttl > 604800000))) {
      throw const FormatException('Invalid message content');
    }
    final type = switch (rawType) {
      'text' => MessageType.text,
      'image' => MessageType.image,
      'file' => MessageType.file,
      'voice' => MessageType.voice,
      _ => throw const FormatException('Unsupported encrypted message type'),
    };
    final rawAttachment = payload['attachment'];
    final attachment = rawAttachment == null ? null : MessageAttachment.fromJson(
      Map<String, dynamic>.from(rawAttachment as Map));
    if ((type == MessageType.text && (attachment != null || content.trim().isEmpty)) ||
        (type != MessageType.text && attachment == null) ||
        (type == MessageType.image && !attachment!.isPreviewableImage) ||
        (type == MessageType.voice && attachment!.mimeType != 'audio/aac')) {
      throw const FormatException('Message type does not match its content');
    }
    return Message(id: envelope.id, conversationId: envelope.conversationId,
      senderId: envelope.senderId, content: content, type: type,
      timestamp: envelope.timestamp, isRead: envelope.isRead,
      isDelivered: envelope.isDelivered, isSent: envelope.isSent,
      replyToId: reply as String?, attachment: attachment,
      ttl: ttl == null ? null : Duration(milliseconds: ttl as int));
  }
}
