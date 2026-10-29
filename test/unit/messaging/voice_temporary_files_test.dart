import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/services/messaging/voice_temporary_files.dart';
void main() {
 test('removes only explicitly named voice scratch files', () async {
  final root = await Directory.systemTemp.createTemp('chhaya-voice-cleanup-test-');
  final voice = File('${root.path}${Platform.pathSeparator}chhaya-voice-play-12345678-1234-4234-8234-123456789abc.aac');
  final other = File('${root.path}${Platform.pathSeparator}chhaya-voice-user-recording.aac');
  final backup = File('${root.path}${Platform.pathSeparator}backup.json');
  await voice.writeAsString('scratch'); await other.writeAsString('user file'); await backup.writeAsString('backup');
  addTearDown(() async { for (final file in [voice,other,backup]) { if (await file.exists()) await file.delete(); } await root.delete(); });
  await VoiceTemporaryFiles.cleanup(directory: root);
  expect(await voice.exists(), isFalse);
  expect(await other.readAsString(), 'user file');
  expect(await backup.readAsString(), 'backup');
 });
}
