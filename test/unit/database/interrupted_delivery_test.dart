// Interrupted delivery against a real encrypted database file.
//
// commitOutgoingMessage writes message + ratchet session + outbox envelope
// in ONE SQLCipher transaction, so a crash cannot leave a half-written
// outbox. This suite pins the restart-recovery half of that claim:
//   * an encrypted file closed with an unsent message reopens with the
//     message still pending and the exact retry envelope available;
//   * if the content-free message index loses a row (partial index write,
//     manual damage), the init backfill rebuilds it so retry can find the
//     message again — it is not silently lost.
//
// Gated to Windows: the SQLCipher native asset is what production uses on
// Windows; other hosts skip this file rather than count it as covered.
import 'dart:io';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/ratchet/session_state.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/database/database_key.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/database/migrations/migration_runner.dart';
import 'package:chaaya/core/database/schema.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

SessionState realSession(String peerId) => SessionState(
      peerId: peerId,
      initiatedByUs: true,
      rootKey: Uint8List(32),
      sendChainKey: Uint8List(32),
      recvChainKey: Uint8List(32),
      ourPrivateKey: Uint8List(32),
      ourPublicKey: Uint8List(32),
      remotePublicKey: Uint8List(32),
      spqrSeed: Uint8List(32),
    );

Future<(LocalDatabase, UserProfile)> makeSeededDb(
  KeyManager keys,
  String chhayaId,
  String path,
) async {
  await keys.storeChhayaId(chhayaId);
  final identity = await ChhayaCryptoEngine.generateKeyPair();
  await keys.storeKeyPair(identity);
  final peerIdentity = await ChhayaCryptoEngine.generateKeyPair();
  final profile = UserProfile(
    chhayaId: ChhayaId.fromPublicKey('05${identity.publicKeyHex}'),
    displayName: 'Alice',
    recoveryPhrase: const [],
    createdAt: DateTime.now(),
  );
  final db = LocalDatabase(keyManager: keys, dbPath: path);
  expect(await db.init(requireBiometric: false), isTrue);
  await db.saveUserProfile(profile);
  final peer = Contact(
    id: 'bob',
    chhayaId: ChhayaId.fromPublicKey('05${peerIdentity.publicKeyHex}'),
    displayName: 'Bob',
    isVerified: true,
  );
  await db.addContact(peer);
  await db.addConversation(
    Conversation(
      id: 'conv-1',
      participants: [peer],
      createdAt: DateTime.now(),
    ),
  );
  return (db, profile);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final isWindows = Platform.isWindows;

  test(
    'unsent outbox survives an encrypted-file restart; retry finds it',
    () async {
      final directory =
          await Directory.systemTemp.createTemp('chhaya-restart-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final path = '${directory.path}${Platform.pathSeparator}m.db';
      final keys = KeyManager(secureBackend: SecureStorageMock());
      final (db, _) = await makeSeededDb(keys, 'interrupted-user', path);
      final outgoing = Message(
        id: 'm-1',
        conversationId: 'conv-1',
        senderId: 'me',
        content: 'unsent across restart',
        timestamp: DateTime.now(),
        isSent: false,
      );
      await db.commitOutgoingMessage(
        realSession('conv-1:05${'22' * 32}'),
        outgoing,
        '{"v":1,"header":"aGVsbG8=","body":"d29ybGQ="}',
      );
      await db.close();

      // Simulate a process restart.
      final reopened = LocalDatabase(keyManager: keys, dbPath: path);
      expect(await reopened.init(requireBiometric: false), isTrue);
      final pending = await reopened.getPendingMessages('conv-1');
      expect(pending, hasLength(1));
      expect(pending.single.id, 'm-1');
      expect(
        await reopened.loadSessionBlob('outbox:m-1'),
        '{"v":1,"header":"aGVsbG8=","body":"d29ybGQ="}',
      );
      await reopened.close();
      await reopened.destroy();
      expect(await File(path).exists(), isFalse);
    },
    skip: isWindows ? false : 'Windows SQLCipher native asset required',
  );

  test(
    'a row missing from the message index is rebuilt at next init; the '
    'pending message is recovered, not lost',
    () async {
      final directory =
          await Directory.systemTemp.createTemp('chhaya-index-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final path = '${directory.path}${Platform.pathSeparator}i.db';
      final keys = KeyManager(secureBackend: SecureStorageMock());
      final (db, _) = await makeSeededDb(keys, 'index-user', path);
      final outgoing = Message(
        id: 'm-2',
        conversationId: 'conv-1',
        senderId: 'me',
        content: 'unsent with a damaged index',
        timestamp: DateTime.now(),
        isSent: false,
      );
      await db.commitOutgoingMessage(
        realSession('conv-1:05${'33' * 32}'),
        outgoing,
        '{"v":1,"header":"aGVsbG8=","body":"c2Vjb25k"}',
      );
      expect(
        (await db.getPendingMessages('conv-1')).map((m) => m.id),
        contains('m-2'),
      );
      await db.close();

      // Simulate a partial index write: the index row for m-2 is lost while
      // the encrypted message and outbox rows remain intact. Open the file
      // at the same schema version with the same derived key.
      final derived = await DatabaseKey.derive(keys, userId: 'index-user');
      final raw = await WindowsSqlCipherOpener().open(
        path: path,
        version: MigrationRunner(chhayaMigrations()).latestVersion,
        passwordHex: DatabaseKey.toPragmaHex(derived),
        onOpen: (_) async {},
      );
      final deleted =
          await raw.delete(DbTables.messageIndex, where: 'id = ?', whereArgs: ['m-2']);
      expect(deleted, 1);
      await raw.close();

      // init() must rebuild the missing index row (migration backfill).
      final reopened = LocalDatabase(keyManager: keys, dbPath: path);
      expect(await reopened.init(requireBiometric: false), isTrue);
      final pending = await reopened.getPendingMessages('conv-1');
      expect(pending, hasLength(1));
      expect(pending.single.id, 'm-2');
      expect(
        await reopened.loadSessionBlob('outbox:m-2'),
        '{"v":1,"header":"aGVsbG8=","body":"c2Vjb25k"}',
      );
      await reopened.close();
      await reopened.destroy();
    },
    skip: isWindows ? false : 'Windows SQLCipher native asset required',
  );
}
