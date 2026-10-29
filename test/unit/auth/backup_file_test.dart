import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/services/auth/backup_file.dart';
import 'package:file_picker/file_picker.dart';

class DesktopSavePicker extends FilePicker {
  DesktopSavePicker(this.path);
  final String path;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'desktop save writes the encrypted bytes to the selected path',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chhaya-backup-test-',
      );
      final path = '${directory.path}${Platform.pathSeparator}backup.json';
      addTearDown(() async {
        if (await File(path).exists()) await File(path).delete();
        await directory.delete();
      });
      FilePicker.platform = DesktopSavePicker(path);
      expect(await BackupFile.save('{"ciphertext":"example"}'), path);
      expect(await File(path).readAsString(), '{"ciphertext":"example"}');
    },
  );
  test('reads encrypted backup across stream chunks', () async {
    final data = utf8.encode('{"version":2,"ciphertext":"test"}');
    expect(
      await BackupFile.readBounded(
        Stream.fromIterable([data.sublist(0, 5), data.sublist(5)]),
      ),
      utf8.decode(data),
    );
  });
  test('rejects empty, oversized and malformed UTF-8 files', () async {
    await expectLater(
      BackupFile.readBounded(Stream.empty()),
      throwsFormatException,
    );
    await expectLater(
      BackupFile.readBounded(Stream.value(Uint8List(BackupFile.maxBytes + 1))),
      throwsFormatException,
    );
    await expectLater(
      BackupFile.readBounded(Stream.value([0xff])),
      throwsFormatException,
    );
  });
}
