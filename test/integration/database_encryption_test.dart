// A2 — at-rest encryption proof (TASK A2).
//
// Procedure: open a LocalDatabase through the PRODUCTION SqlCipherOpener
// at a temp file path, write one contact row, close it, then attempt to
// open the same file with the plain `sqlite3` package. A SQLCipher-
// encrypted file must fail with "file is not a database".
//
// Host requirement: SQLCipher native libraries (the sqflite_sqlcipher
// platform implementation). Plain `flutter test` hosts (Windows dev,
// Linux CI) have none, so the test SKIPS with an explicit reason there
// instead of faking a pass. It executes fully on SQLCipher-capable
// hosts (on-device runs).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';

void main() {
  // Platform channels (sqflite_sqlcipher) need a binding even to fail
  // cleanly with MissingPluginException on hosts without native libs.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQLCipher file is unreadable with plain sqlite3', () async {
    final dir = await Directory.systemTemp.createTemp('chhaya_a2_');
    final dbPath = '${dir.path}${Platform.pathSeparator}at_rest.db';
    try {
      final keyManager = KeyManager(secureBackend: SecureStorageMock());
      await keyManager.storeChhayaId('user-1');
      // Default opener = production SqlCipherOpener. Known key derived
      // deterministically for user-1 via the Part 2 key manager.
      final db = LocalDatabase(keyManager: keyManager, dbPath: dbPath);
      try {
        final ok = await db.init(requireBiometric: false);
        expect(ok, isTrue);
      } on MissingPluginException catch (_) {
        markTestSkipped(
          'SQLCipher native libs unavailable on this host: '
          'sqflite_sqlcipher has no platform implementation under '
          'flutter test. At-rest proof requires a SQLCipher-capable host.',
        );
        return;
      }
      await db.addContact(
        Contact(
          id: 'c-a2',
          chhayaId: ChhayaId.fromPublicKey(
            'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef12',
          ),
          displayName: 'A2 Probe',
        ),
      );
      await db.close();

      expect(File(dbPath).existsSync(), isTrue);

      // The whole point: plain sqlite must reject the encrypted file.
      expect(
        () => sqlite3.open(dbPath),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('file is not a database'),
          ),
        ),
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
