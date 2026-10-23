import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../core/models/message_attachment.dart';

class AttachmentService {
  static Future<Uint8List> readBounded(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > MessageAttachment.maxBytes) {
        throw StateError('Choose a file smaller than 256 KB.');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw StateError('The selected file is empty.');
    return bytes;
  }

  static Future<MessageAttachment?> pick({bool imagesOnly = false}) async {
    final selection = await FilePicker.platform.pickFiles(
      type: imagesOnly ? FileType.custom : FileType.any,
      allowedExtensions: imagesOnly ? ['png', 'jpg', 'jpeg', 'webp'] : null,
      allowCompression: false, withReadStream: true, withData: false,
    );
    if (selection == null) return null;
    final file = selection.files.single;
    if (file.size <= 0 || file.size > MessageAttachment.maxBytes) {
      throw StateError('Choose a non-empty file up to 256 KB.');
    }
    final stream = file.readStream ?? (file.path == null ? null : File(file.path!).openRead());
    if (stream == null) throw StateError('The selected file could not be read.');
    final bytes = await readBounded(stream);
    final mime = switch (file.extension?.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
    return MessageAttachment.fromBytes(name: file.name, mimeType: mime, bytes: bytes);
  }
}
