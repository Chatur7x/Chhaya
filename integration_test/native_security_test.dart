import 'dart:convert';
import 'dart:io';

import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_android.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chhaya_pqc/chhaya_pqc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;
import 'package:sqlite3/sqlite3.dart' as plain;

class _ObservedNativeOpener implements DatabaseOpener {
  late sqlcipher.Database handle;

  @override
  Future<sqlcipher.Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(sqlcipher.Database db) onOpen,
  }) async {
    handle = await SqlCipherOpener().open(
      path: path,
      version: version,
      passwordHex: passwordHex,
      onOpen: onOpen,
    );
    return handle;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Native wrapping rejects tampering and reports its actual storage level',
    (tester) async {
      const channel = MethodChannel('chhaya/security');
      final level = await channel.invokeMethod<String>('getStorageLevel');
      expect(level, isIn(['strongbox', 'tee', 'software']));
      // Public capability evidence only; no keys or envelopes are logged.
      // ignore: avoid_print
      print('Native Android wrapping level: $level');
      final storage = AndroidSecureStorage();
      const delegate = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      const probe = 'chhaya_verification_probe';
      try {
        await storage.write(key: probe, value: 'synthetic native test secret');
        expect(
          await AndroidSecureStorage().read(key: probe),
          'synthetic native test secret',
        );
        final wrapped = await delegate.read(key: probe);
        expect(wrapped, startsWith('chhaya.keystore.v1:'));
        final bytes = base64Decode(
          wrapped!.substring('chhaya.keystore.v1:'.length),
        );
        bytes[bytes.length - 1] ^= 1;
        await delegate.write(
          key: probe,
          value: 'chhaya.keystore.v1:${base64Encode(bytes)}',
        );
        await expectLater(
          storage.read(key: probe),
          throwsA(isA<PlatformException>()),
        );
      } finally {
        await storage.delete(key: probe);
      }
    },
  );

  testWidgets(
    'Production SQLCipher storage rejects plain SQLite and survives reopen',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'chhaya_native_verification_',
      );
      final path = '${directory.path}/encrypted.db';
      final keys = KeyManager(secureBackend: AndroidSecureStorage());
      expect(
        await keys.getChhayaId(),
        isNull,
        reason:
            'Use a fresh isolated verification package, never an account installation',
      );
      await keys.storeChhayaId('native-verification-only');
      final opener = _ObservedNativeOpener();
      final database = LocalDatabase(
        keyManager: keys,
        opener: opener,
        dbPath: path,
      );
      try {
        expect(await database.init(requireBiometric: false), isTrue);
        final version = await opener.handle.rawQuery('PRAGMA cipher_version');
        expect(version, isNotEmpty);
        expect(version.first.values.first.toString(), isNotEmpty);
        // ignore: avoid_print
        print('Native SQLCipher version: ${version.first.values.first}');
        await database.addContact(
          Contact(
            id: 'native-probe',
            chhayaId: ChhayaId.fromPublicKey('05${'11' * 32}'),
            displayName: 'Native storage probe',
          ),
        );
        await database.close();
        final header = await File(
          path,
        ).openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
        expect(header, isNot(utf8.encode('SQLite format 3\u0000')));
        plain.Database? plaintext;
        try {
          plaintext = plain.sqlite3.open(path);
          expect(
            () => plaintext!.select('SELECT name FROM sqlite_master'),
            throwsA(isA<plain.SqliteException>()),
          );
        } on plain.SqliteException {
          // Either opening or the first schema read must reject the encrypted file.
        } finally {
          plaintext?.close();
        }
        expect(await database.init(requireBiometric: false), isTrue);
        expect(
          (await database.getAllContacts()).single.displayName,
          'Native storage probe',
        );
      } finally {
        await database.close();
        await keys.clearAllAccountSecrets();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Native AWS-LC known-answer probe, ML-KEM and ML-DSA rejection checks',
    (tester) async {
      expect(await ChhayaPqc.initialize(), isTrue);
      // ignore: avoid_print
      print('Native PQ provider: ${ChhayaPqc.provider}');
      final kem = await ChhayaPqc.generateKemKeyPair();
      final dsa = await ChhayaPqc.generateDsaKeyPair();
      try {
        final encapsulated = await ChhayaPqc.encapsulate(kem.publicKey);
        final shared = await ChhayaPqc.decapsulate(
          kem.privateKey,
          encapsulated.ciphertext,
        );
        expect(shared, encapsulated.sharedSecret);
        final corrupted = Uint8List.fromList(encapsulated.ciphertext)..[0] ^= 1;
        expect(
          await ChhayaPqc.decapsulate(kem.privateKey, corrupted),
          isNot(orderedEquals(encapsulated.sharedSecret)),
        );
        final message = Uint8List.fromList(
          utf8.encode('Chhaya native verification'),
        );
        final signature = await ChhayaPqc.sign(dsa.privateKey, message);
        expect(
          await ChhayaPqc.verify(dsa.publicKey, message, signature),
          isTrue,
        );
        message[0] ^= 1;
        expect(
          await ChhayaPqc.verify(dsa.publicKey, message, signature),
          isFalse,
        );
        shared.fillRange(0, shared.length, 0);
        encapsulated.sharedSecret.fillRange(
          0,
          encapsulated.sharedSecret.length,
          0,
        );
      } finally {
        kem.destroy();
        dsa.destroy();
      }
    },
  );
}
