import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:chaaya/core/models/message_attachment.dart';
import 'package:chaaya/ui/widgets/voice_recorder_sheet.dart';

class FakeRecorder extends RecordPlatform {
  final audio = StreamController<Uint8List>.broadcast();
  bool permission = true;
  bool recording = false;
  bool disposed = false;
  RecordConfig? config;
  @override
  Future<void> create(String id) async {}
  @override
  Future<bool> hasPermission(String id, {bool request = true}) async => permission;
  @override
  Stream<RecordState> onStateChanged(String id) => const Stream.empty();
  @override
  Future<Stream<Uint8List>> startStream(String id, RecordConfig value) async {
    config = value;
    recording = true;
    return audio.stream;
  }

  @override
  Future<bool> isRecording(String id) async => recording;
  @override
  Future<String?> stop(String id) async {
    recording = false;
    await audio.close();
    return null;
  }

  @override
  Future<void> cancel(String id) async {
    recording = false;
  }

  @override
  Future<void> dispose(String id) async {
    disposed = true;
  }

  @override
  Future<Amplitude> getAmplitude(String id) async =>
      Amplitude(current: -30, max: -10);
  @override
  void setOnConfigChanged(String id, void Function(RecordConfig)? handler) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('recorded AAC bytes are returned as a voice attachment', (
    tester,
  ) async {
    final previous = RecordPlatform.instance;
    final recorder = FakeRecorder();
    RecordPlatform.instance = recorder;
    addTearDown(() async {
      RecordPlatform.instance = previous;
      if (!recorder.audio.isClosed) await recorder.audio.close();
    });
    MessageAttachment? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<MessageAttachment>(
                      context: context,
                      builder: (_) => const VoiceRecorderSheet(),
                    );
                  },
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    await tester.pump();
    expect(recorder.config!.encoder, AudioEncoder.aacLc);
    recorder.audio.add(Uint8List.fromList([255, 241, 1, 2]));
    await tester.pump();
    await tester.tap(find.text('Use recording'));
    for (var i = 0; i < 12 && result == null; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text('Recording could not be attached. Try a shorter recording.'),
      findsNothing,
    );
    expect(result, isNotNull);
    expect(result!.mimeType, 'audio/aac');
    expect(result!.bytes, [255, 241, 1, 2]);
    expect(recorder.disposed, isTrue);
  });
  testWidgets('denied microphone permission does not start recording', (tester) async {
    final previous = RecordPlatform.instance;
    final recorder = FakeRecorder()..permission = false;
    RecordPlatform.instance = recorder;
    addTearDown(() async {
      RecordPlatform.instance = previous;
      if (!recorder.audio.isClosed) await recorder.audio.close();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showModalBottomSheet<void>(context: context,
        builder: (_) => const VoiceRecorderSheet()), child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    for (var i = 0; i < 10 && find.textContaining('Could not record').evaluate().isEmpty; i++) {
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 50)); });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Could not record'), findsOneWidget);
    expect(recorder.config, isNull);
    expect(recorder.recording, isFalse);
    await tester.tap(find.text('Cancel'));
    for (var i = 0; i < 10 && !recorder.disposed; i++) {
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 50)); });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(recorder.disposed, isTrue);
  });

  testWidgets('oversized audio is discarded and the recorder closes', (tester) async {
    final previous = RecordPlatform.instance;
    final recorder = FakeRecorder();
    RecordPlatform.instance = recorder;
    addTearDown(() async {
      RecordPlatform.instance = previous;
      if (!recorder.audio.isClosed) await recorder.audio.close();
    });
    MessageAttachment? result;
    var returned = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { result = await showModalBottomSheet<MessageAttachment>(
        context: context, builder: (_) => const VoiceRecorderSheet()); returned = true; },
        child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording')); await tester.pump(); await tester.pump();
    recorder.audio.add(Uint8List(MessageAttachment.maxBytes + 1));
    for (var i = 0; i < 12 && !returned; i++) {
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 50)); });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(returned, isTrue);
    expect(result, isNull);
    expect(recorder.disposed, isTrue);
    expect(find.textContaining('exceeds the attachment limit'), findsOneWidget);
  });

}
