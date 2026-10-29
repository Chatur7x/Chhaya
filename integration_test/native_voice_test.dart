import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native microphone records ADTS AAC and native player completes', (tester) async {
    final recorder = AudioRecorder();
    final player = AudioPlayer();
    final output = BytesBuilder();
    StreamSubscription<Uint8List>? subscription;
    Uint8List? captured;
    try {
      expect(await recorder.hasPermission(request: false), isTrue,
          reason: 'Microphone permission must be granted for this explicit device test');
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000, numChannels: 1));
      subscription = stream.listen((bytes) => output.add(bytes));
      await Future<void>.delayed(const Duration(seconds: 2));
      await recorder.stop();
      await subscription.cancel();
      subscription = null;
      captured = output.takeBytes();
      expect(captured.length, greaterThan(16));
      expect(captured[0], 0xff);
      expect(captured[1] & 0xf0, 0xf0);
      final completed = player.onPlayerComplete.first.timeout(const Duration(seconds: 12));
      await player.play(BytesSource(captured, mimeType: 'audio/aac'));
      await completed;
    } finally {
      await subscription?.cancel();
      try { await recorder.cancel(); } catch (_) {}
      await recorder.dispose();
      await player.dispose();
      captured?.fillRange(0, captured.length, 0);
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
