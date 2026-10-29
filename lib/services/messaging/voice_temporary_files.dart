import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Remove only app-owned voice scratch files left behind by an earlier process.
class VoiceTemporaryFiles {
  static final _scratchName = RegExp(
    r'^chhaya-voice-(?:play-)?[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.aac$',
  );

  static Future<void> cleanup({Directory? directory}) async {
    final root = directory ?? await getTemporaryDirectory();
    await for (final entry in root.list(followLinks: false)) {
      if (entry is File && _scratchName.hasMatch(p.basename(entry.path))) {
        try {
          await entry.delete();
        } on FileSystemException {
          // OS-managed temporary storage can change during cleanup.
        }
      }
    }
  }
}
