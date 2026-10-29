import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class BackupFile {
  static const maxBytes = 16 * 1024 * 1024;

  static Future<String> readBounded(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('Backup is larger than 16 MB');
      }
      bytes.add(chunk);
    }
    if (bytes.length == 0) throw const FormatException('Backup file is empty');
    return utf8.decode(bytes.takeBytes());
  }

  static Future<String?> pick() async {
    final selected = await FilePicker.platform.pickFiles(withReadStream: true);
    if (selected == null) return null;
    final file = selected.files.single;
    if (file.size > maxBytes) {
      throw const FormatException('Backup is larger than 16 MB');
    }
    final stream =
        file.readStream ??
        (file.path == null ? null : File(file.path!).openRead());
    if (stream == null) {
      throw const FormatException('Cannot read selected backup');
    }
    return readBounded(stream);
  }

  static Future<String?> save(String encryptedBackup) async {
    final bytes = Uint8List.fromList(utf8.encode(encryptedBackup));
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup is larger than 16 MB');
    }
    final mobile = Platform.isAndroid || Platform.isIOS;
    final path = await FilePicker.platform.saveFile(
      fileName: 'chhaya-backup.json',
      bytes: mobile ? bytes : null,
    );
    if (path != null && !mobile) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }
}
