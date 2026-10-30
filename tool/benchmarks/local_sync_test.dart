import 'dart:io';
import 'dart:typed_data';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/message_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

// Run explicitly: flutter test tool/benchmarks/local_sync_test.dart
// Uses a disposable Windows SQLCipher file and synthetic attachments only.
void main() {
  test(
    'measure full-history reads versus indexed sync reads',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chhaya-sync-benchmark-',
      );
      final database = LocalDatabase(
        keyManager: KeyManager(secureBackend: SecureStorageMock()),
        dbPath: '${directory.path}${Platform.pathSeparator}benchmark.db',
      );
      try {
        await database.init(requireBiometric: false);
        final attachment = MessageAttachment.fromBytes(
          name: 'synthetic.bin',
          mimeType: 'application/octet-stream',
          bytes: Uint8List(16 * 1024),
        );
        for (var i = 0; i < 40; i++) {
          await database.addMessage(
            Message(
              id: 'message-$i',
              conversationId: 'chat',
              senderId: 'me',
              content: '',
              type: MessageType.file,
              attachment: attachment,
              timestamp: DateTime(2026).add(Duration(seconds: i)),
            ),
          );
        }
        final full = <int>[];
        final indexed = <int>[];
        for (var i = 0; i < 3; i++) {
          final watch = Stopwatch()..start();
          expect((await database.getMessages('chat')).length, 40);
          full.add(watch.elapsedMicroseconds);
          watch.reset();
          expect(
            (await database.getKnownMessageIds(
              'chat',
              messageIds: List.generate(40, (i) => 'message-$i'),
            )).length,
            40,
          );
          expect(await database.getPendingMessages('chat'), isEmpty);
          expect((await database.getLatestMessage('chat'))?.id, 'message-39');
          indexed.add(watch.elapsedMicroseconds);
          watch.stop();
        }
        full.sort();
        indexed.sort();
        // ignore: avoid_print
        print(
          'Windows SQLCipher / 40 x 16 KiB synthetic attachments: '
          'full-history median ${full[1] / 1000} ms; '
          'index + pending + latest median ${indexed[1] / 1000} ms',
        );
      } finally {
        await database.close();
        // Remove only this benchmark's explicitly created files.
        for (final name in ['benchmark.db', 'benchmark.db-journal']) {
          final file = File('${directory.path}${Platform.pathSeparator}$name');
          if (await file.exists()) await file.delete();
        }
        await directory.delete();
      }
    },
    skip: !Platform.isWindows ? 'Requires native Windows SQLCipher' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
