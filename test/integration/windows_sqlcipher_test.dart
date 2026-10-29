import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';

void main() {
  test(
    'Windows SQLCipher encrypts, rejects wrong keys and reopens',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chhaya-windows-cipher-',
      );
      final path = '${directory.path}${Platform.pathSeparator}test.db';
      addTearDown(() async {
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is File) await entry.delete();
        }
        await directory.delete();
      });
      const key =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const wrong =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final opener = WindowsSqlCipherOpener();
      final db = await opener.open(
        path: path,
        version: 1,
        passwordHex: key,
        onOpen: (db) =>
            db.execute('CREATE TABLE secrets (value TEXT NOT NULL)'),
      );
      final version = await db.rawQuery('PRAGMA cipher_version');
      expect(version, isNotEmpty);
      await db.insert('secrets', {'value': 'synthetic secret'});
      await db.close();
      final bytes = await File(path).readAsBytes();
      expect(
        bytes.take(16).toList(),
        isNot(utf8.encode('SQLite format 3\u0000')),
      );
      final unkeyed = sqlite.sqlite3.open(path);
      try {
        expect(
          () => unkeyed.select('SELECT * FROM sqlite_master'),
          throwsA(isA<sqlite.SqliteException>()),
        );
      } finally {
        unkeyed.close();
      }
      await expectLater(
        opener.open(
          path: path,
          version: 1,
          passwordHex: wrong,
          onOpen: (db) async {},
        ),
        throwsA(anything),
      );
      final reopened = await opener.open(
        path: path,
        version: 1,
        passwordHex: key,
        onOpen: (db) async {},
      );
      try {
        expect(
          (await reopened.query('secrets')).single['value'],
          'synthetic secret',
        );
      } finally {
        await reopened.close();
      }

      final localPath = '${directory.path}${Platform.pathSeparator}local.db';
      final keys = KeyManager(secureBackend: SecureStorageMock());
      final local = LocalDatabase(keyManager: keys, dbPath: localPath);
      expect(await local.init(requireBiometric: false), isTrue);
      await local.addContact(
        Contact(
          id: 'synthetic',
          displayName: 'Test',
          chhayaId: ChhayaId.fromPublicKey('05${'a' * 64}'),
        ),
      );
      await local.close();
      final again = LocalDatabase(keyManager: keys, dbPath: localPath);
      expect(await again.init(requireBiometric: false), isTrue);
      expect((await again.getContact('synthetic'))?.displayName, 'Test');
      await again.destroy();
      expect(await File(localPath).exists(), isFalse);
      expect(await File(path).exists(), isTrue);
    },
    skip: !Platform.isWindows
        ? 'Windows SQLCipher native asset required'
        : false,
  );
}
