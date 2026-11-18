import 'dart:convert';
import 'dart:typed_data';

/// Small attachments travel inside the authenticated encrypted message payload.
/// No public file URL, plaintext filename, or MIME type is sent to the API.
class MessageAttachment {
  static const maxBytes = 256 * 1024;
  final String name;
  final String mimeType;
  final String _base64;

  MessageAttachment._(this.name, this.mimeType, this._base64);

  factory MessageAttachment.fromBytes({required String name,
      required String mimeType, required Uint8List bytes}) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Attachments must contain 1–262144 bytes (256 KB).');
    }
    return MessageAttachment._(_safeName(name), _safeMime(mimeType), base64Encode(bytes));
  }

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    final encoded = json['data'];
    if (encoded is! String || encoded.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw const FormatException('Invalid attachment size');
    }
    final bytes = base64Decode(encoded);
    return MessageAttachment.fromBytes(name: json['name'] as String,
      mimeType: json['mimeType'] as String, bytes: bytes);
  }

  static String _safeName(String value) {
    final name = value.replaceAll('\\', '/').split('/').last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (name.isEmpty || name == '.' || name == '..' || name.length > 120) {
      throw const FormatException('Invalid attachment filename');
    }
    return name;
  }

  static String _safeMime(String value) {
    if (value.length > 100 || !RegExp(r'^[a-z0-9.+-]+/[a-z0-9.+-]+$').hasMatch(value)) {
      throw const FormatException('Invalid attachment media type');
    }
    return value;
  }

  Uint8List get bytes => base64Decode(_base64);
  int get size => bytes.length;
  bool get isPreviewableImage => const ['image/png', 'image/jpeg', 'image/webp'].contains(mimeType);

  Map<String, dynamic> toJson() => {'name': name, 'mimeType': mimeType, 'data': _base64};
}
