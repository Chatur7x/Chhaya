// SQLCipher-encrypted local database (V14 Part 3).
//
// Purpose: all on-device persistence. Whole-file encryption via
// SQLCipher (`PRAGMA key` on open from a per-user Part 2 key), plus a
// field-level AES-GCM envelope on content columns for defense in depth.
// Every query is parameterized (see queries.dart); identifiers used in
// SQL are validated, never interpolated from user input.
//
// Migration path from V13: SKIP. V13 used a plain-SQLite file keyed by
// a weak app-level envelope (DateTime.microsecond entropy) and the app
// is pre-release with no production users, so carrying that data
// forward would preserve broken cryptography. V14 opens a fresh
// `chhaya_v14.db`; the legacy file is left untouched on disk.
// V13 public API is preserved verbatim — no call-site changes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../crypto/key_manager.dart';
import '../crypto/ratchet/session_state.dart';
import '../crypto/primitives/rng.dart';
import '../models/message.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';
import 'database_key.dart';
import 'migrations/migration_runner.dart';
import 'migrations/v001_initial.dart' show MigrationV001Initial;
import 'migrations/v002_messages.dart' show MigrationV002Messages;
import 'migrations/v003_devices.dart' show MigrationV003Devices;
import 'migrations/v004_circuits.dart' show MigrationV004Circuits;
import 'migrations/v005_payloads.dart' show MigrationV005Payloads;
import 'migrations/v006_message_index.dart' show MigrationV006MessageIndex;
import 'queries.dart';
import 'schema.dart';

/// Opens SQLCipher databases with hardening PRAGMAs.
///
/// Production implementation. Tests inject a fake that records the
/// password and PRAGMAs against an in-memory database.
abstract class DatabaseOpener {
  /// Opens [path] at [version], running [onOpen] inside the open flow.
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  });
}

/// Production opener: SQLCipher + memory security + DELETE journal.
class SqlCipherOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  }) async {
    final db = await openDatabase(
      path,
      password: passwordHex,
      version: version,
      onCreate: (db, _) => onOpen(db),
      onUpgrade: (db, _, __) => onOpen(db),
    );
    try {
      // Hardening. Constant strings only — no parameters, no user input.
      await db.execute('PRAGMA cipher_memory_security = ON');
      // journal_mode returns the resulting mode as a row. Android's
      // SQLCipher driver rejects row-returning PRAGMAs through execute().
      await db.rawQuery('PRAGMA journal_mode = DELETE');
      return db;
    } catch (_) {
      // openDatabase has already handed us a native handle. If a hardening
      // pragma fails, release that handle before allowing startup to retry.
      try {
        await db.close();
      } catch (_) {
        // Keep the original SQLCipher/SQLite exception for diagnostics.
      }
      rethrow;
    }
  }
}

/// Windows uses the SQLCipher native asset through the sqflite FFI factory.
class WindowsSqlCipherOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required int version,
    required String passwordHex,
    required Future<void> Function(Database db) onOpen,
  }) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(passwordHex)) {
      throw ArgumentError('Invalid database key');
    }
    ffi.sqfliteFfiInit();
    return ffi.databaseFactoryFfi.openDatabase(
      path,
      options: ffi.OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute("PRAGMA key = '$passwordHex'");
          final cipher = await db.rawQuery('PRAGMA cipher_version');
          if (cipher.isEmpty || cipher.first.values.firstOrNull == null) {
            throw StateError('SQLCipher is unavailable');
          }
          await db.execute('PRAGMA cipher_memory_security = ON');
          await db.rawQuery('PRAGMA journal_mode = DELETE');
        },
        onCreate: (db, _) => onOpen(db),
        onUpgrade: (db, _, __) => onOpen(db),
      ),
    );
  }
}

/// PRAGMA statements the production opener applies. Tests assert the
/// fake opener records exactly these (see test/unit/database/).
const List<String> kHardeningPragmas = [
  'PRAGMA cipher_memory_security = ON',
  'PRAGMA journal_mode = DELETE',
];

/// Production migration chain: v001 → v006 in order. Single place that
/// defines the full history; LocalDatabase and tests share it.
List<Migration> chhayaMigrations() => [
  MigrationV001Initial(),
  MigrationV002Messages(),
  MigrationV003Devices(),
  MigrationV004Circuits(),
  MigrationV005Payloads(),
  MigrationV006MessageIndex(),
];

class LocalDatabase {
  static const _dbName = 'chhaya_v14.db';

  /// Owner id used when no profile exists yet (pre-login).
  static const String localOwnerId = 'local';

  Database? _db;
  bool _initialized = false;
  bool _biometricUnlocked = false;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secure;
  final KeyManager _keyManager;
  final DatabaseOpener _opener;
  final String? _dbPathOverride;

  Uint8List? _dbKey;
  String _ownerId = localOwnerId;

  /// Creates the database. All parameters optional for injection in
  /// tests; defaults match production behavior.
  LocalDatabase({
    KeyManager? keyManager,
    DatabaseOpener? opener,
    FlutterSecureStorage? secureStorage,
    String? dbPath,
  }) : _keyManager = keyManager ?? KeyManager(),
       _opener =
           opener ??
           (Platform.isWindows ? WindowsSqlCipherOpener() : SqlCipherOpener()),
       _dbPathOverride = dbPath,
       _secure = secureStorage ?? const FlutterSecureStorage();

  Future<String> _resolveDatabasePath({bool createParent = false}) async {
    if (_dbPathOverride != null) return _dbPathOverride;
    if (Platform.isWindows) {
      final directory = await getApplicationSupportDirectory();
      if (createParent) await directory.create(recursive: true);
      return p.join(directory.path, _dbName);
    }
    return p.join(await getDatabasesPath(), _dbName);
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticateWithBiometrics({
    String reason = 'Unlock Chhaya',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> init({bool requireBiometric = true}) async {
    if (_initialized) {
      return true;
    }
    if (requireBiometric) {
      final biometricAvailable = await isBiometricAvailable();
      if (biometricAvailable) {
        final authenticated = await authenticateWithBiometrics();
        if (!authenticated) {
          return false;
        }
        _biometricUnlocked = true;
      }
    }
    _ownerId = await _keyManager.getChhayaId() ?? localOwnerId;
    final dbKey = await DatabaseKey.derive(_keyManager, userId: _ownerId);
    try {
      final passwordHex = DatabaseKey.toPragmaHex(dbKey);
      final dbPath = await _resolveDatabasePath(createParent: true);
      final runner = MigrationRunner(chhayaMigrations());
      _db = await _opener.open(
        path: dbPath,
        version: runner.latestVersion,
        passwordHex: passwordHex,
        onOpen: (db) => runner.migrateTo(db, runner.latestVersion),
      );
      _dbKey = await DatabaseKey.derive(_keyManager, userId: _ownerId);
      await _backfillMessageIndex();
      _initialized = true;
      await preloadSettings();
      return true;
    } catch (_) {
      // A failed open/migration must not retain a partially opened native
      // handle or leave init() marked complete, so the user can retry.
      _initialized = false;
      final failedDb = _db;
      _db = null;
      if (failedDb != null) {
        try {
          await failedDb.close();
        } catch (_) {
          // Preserve the original initialization error.
        }
      }
      if (_dbKey != null) {
        Csprng.wipe(_dbKey!);
        _dbKey = null;
      }
      rethrow;
    } finally {
      Csprng.wipe(dbKey);
    }
  }

  bool get isUnlockedWithBiometrics => _biometricUnlocked;

  /// Closes the database and wipes the in-memory key. Needed by the
  /// at-rest encryption proof (TASK A2) and any clean shutdown path.
  Future<void> close() async {
    await _db?.close();
    _db = null;
    if (_dbKey != null) {
      Csprng.wipe(_dbKey!);
      _dbKey = null;
    }
    _initialized = false;
    _settingsCache = null;
    _deviceCache = null;
  }

  Future<void> destroy() async {
    final path = await _resolveDatabasePath();
    await close();
    if (Platform.isWindows) {
      await ffi.databaseFactoryFfi.deleteDatabase(path);
    } else {
      await deleteDatabase(path);
    }
  }

  void _ensureInitialized() {
    if (!_initialized || _db == null || _dbKey == null) {
      throw StateError('LocalDatabase not initialized. Call init() first.');
    }
  }

  String _enc(String plain) => DatabaseKey.encryptField(plain, _dbKey!);

  String? _dec(String? envelope) => DatabaseKey.decryptField(envelope, _dbKey!);

  // ---- Messages
  Map<String, Object?> _messageIndexRow(Message message) => {
    DbCols.id: message.id,
    DbCols.conversationId: message.conversationId,
    DbCols.sentAt: message.timestamp.millisecondsSinceEpoch,
    'expires_at': message.ttl == null
        ? null
        : message.timestamp.add(message.ttl!).millisecondsSinceEpoch,
    'is_sent': message.isSent ? 1 : 0,
    'valid': 1,
  };

  Future<void> _backfillMessageIndex() async {
    while (true) {
      final rows = await DbQueries.messagesMissingIndex(_db!);
      if (rows.isEmpty) return;
      await _db!.transaction((transaction) async {
        for (final row in rows) {
          Map<String, Object?> index;
          try {
            final json = _dec(row[DbCols.encryptedContent] as String?);
            if (json == null) throw const FormatException('Unreadable message');
            final message = Message.fromJson(
              jsonDecode(json) as Map<String, dynamic>,
            );
            if (message.id != row[DbCols.id] ||
                message.conversationId != row[DbCols.conversationId]) {
              throw const FormatException('Message index mismatch');
            }
            index = _messageIndexRow(message);
          } catch (_) {
            // Preserve unreadable legacy ciphertext for recovery; do not treat
            // it as a successfully received message or retry it.
            index = {
              DbCols.id: row[DbCols.id],
              DbCols.conversationId: row[DbCols.conversationId],
              DbCols.sentAt: row[DbCols.sentAt],
              'expires_at': null,
              'is_sent': 1,
              'valid': 0,
            };
          }
          await DbQueries.upsert(transaction, DbTables.messageIndex, index);
        }
      });
    }
  }

  Future<void> _writeMessage(DatabaseExecutor db, Message message) async {
    await DbQueries.upsert(db, DbTables.messages, _messageRow(message));
    await DbQueries.upsert(
      db,
      DbTables.messageIndex,
      _messageIndexRow(message),
    );
  }

  Map<String, Object?> _messageRow(Message message) => {
    DbCols.id: message.id,
    DbCols.conversationId: message.conversationId,
    DbCols.senderId: message.senderId,
    DbCols.encryptedContent: _enc(jsonEncode(message.toJson())),
    DbCols.contentType: message.type.name,
    DbCols.mediaBlob: null,
    DbCols.mediaMetaEnc: null,
    DbCols.replyToId: message.replyToId,
    DbCols.sentAt: message.timestamp.millisecondsSinceEpoch,
    DbCols.deliveredAt: message.isDelivered
        ? message.timestamp.millisecondsSinceEpoch
        : null,
    DbCols.readAt: message.isRead
        ? message.timestamp.millisecondsSinceEpoch
        : null,
  };

  Future<void> addMessage(Message message) async {
    _ensureInitialized();
    await _db!.transaction(
      (transaction) => _writeMessage(transaction, message),
    );
  }

  /// Ratchet advancement and the plaintext's encrypted database row commit
  /// together, so a crash cannot consume a key without preserving its message.
  Future<void> commitReceivedMessage(
    SessionState state,
    Message message,
  ) async {
    _ensureInitialized();
    await _db!.transaction((transaction) async {
      await _writeMessage(transaction, message);
      await DbQueries.upsert(transaction, DbTables.kv, {
        DbCols.key: '$_sessionKeyPrefix${state.peerId}',
        DbCols.value: _enc(jsonEncode(state.toJson())),
      });
    });
  }

  /// Commit the ratchet advance, pending message, and exact retry ciphertext
  /// together. No ciphertext reaches the network before this transaction.
  Future<void> commitOutgoingMessage(
    SessionState state,
    Message message,
    String envelope,
  ) async {
    _ensureInitialized();
    await _db!.transaction((transaction) async {
      await _writeMessage(transaction, message);
      await DbQueries.upsert(transaction, DbTables.kv, {
        DbCols.key: '$_sessionKeyPrefix${state.peerId}',
        DbCols.value: _enc(jsonEncode(state.toJson())),
      });
      await DbQueries.upsert(transaction, DbTables.kv, {
        DbCols.key: '${_sessionKeyPrefix}outbox:${message.id}',
        DbCols.value: _enc(envelope),
      });
    });
  }

  /// Atomically advances all peer ratchets and stores the one group message
  /// plus its exact retry envelope. No partial group key distribution occurs.
  Future<void> commitOutgoingGroupMessage(
    List<SessionState> states,
    Message message,
    String envelope,
  ) async {
    _ensureInitialized();
    if (states.isEmpty) throw ArgumentError('A group message needs recipients');
    await _db!.transaction((transaction) async {
      await _writeMessage(transaction, message);
      for (final state in states) {
        await DbQueries.upsert(transaction, DbTables.kv, {
          DbCols.key: '$_sessionKeyPrefix${state.peerId}',
          DbCols.value: _enc(jsonEncode(state.toJson())),
        });
      }
      await DbQueries.upsert(transaction, DbTables.kv, {
        DbCols.key: '${_sessionKeyPrefix}outbox:${message.id}',
        DbCols.value: _enc(envelope),
      });
    });
  }

  Future<void> commitMessageSent(Message message) async {
    _ensureInitialized();
    await _db!.transaction((transaction) async {
      await _writeMessage(transaction, message);
      await DbQueries.deleteWhere(transaction, DbTables.kv, {
        DbCols.key: '${_sessionKeyPrefix}outbox:${message.id}',
      });
    });
  }

  Future<void> _purgeExpiredIndexedMessages(String conversationId) async {
    final rows = await DbQueries.expiredMessageIds(
      _db!,
      conversationId,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _purgeMessages(rows.map((row) => row[DbCols.id] as String).toList());
  }

  Future<Set<String>> getKnownMessageIds(
    String conversationId, {
    List<String>? messageIds,
  }) async {
    _ensureInitialized();
    await _purgeExpiredIndexedMessages(conversationId);
    final rows = messageIds != null
        ? await DbQueries.knownMessageIds(_db!, conversationId, messageIds)
        : await DbQueries.find(
            _db!,
            DbTables.messageIndex,
            equals: {DbCols.conversationId: conversationId, 'valid': 1},
            columns: [DbCols.id],
          );
    return rows.map((row) => row[DbCols.id] as String).toSet();
  }

  Future<Message?> getMessage(String conversationId, String messageId) async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.messages,
      equals: {DbCols.conversationId: conversationId, DbCols.id: messageId},
      limit: 1,
    );
    if (rows.isEmpty) return null;
    Message? message;
    try {
      final json = _dec(rows.single[DbCols.encryptedContent] as String?);
      if (json != null) {
        message = Message.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
      if (message?.id != messageId ||
          message?.conversationId != conversationId) {
        message = null;
      }
    } catch (_) {
      message = null;
    }
    if (message == null) {
      await DbQueries.invalidateMessageIndex(_db!, messageId);
      return null;
    }
    if (message.isExpired) {
      await _purgeMessages([messageId]);
      return null;
    }
    return message;
  }

  Future<Message?> getLatestMessage(String conversationId) async {
    _ensureInitialized();
    await _purgeExpiredIndexedMessages(conversationId);
    while (true) {
      final rows = await DbQueries.find(
        _db!,
        DbTables.messageIndex,
        equals: {DbCols.conversationId: conversationId, 'valid': 1},
        columns: [DbCols.id],
        orderBy: const [
          DbOrder(DbCols.sentAt, descending: true),
          DbOrder(DbCols.id, descending: true),
        ],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final id = rows.single[DbCols.id] as String;
      final message = await getMessage(conversationId, id);
      if (message != null) return message;
      // An orphaned index must not trap sync in this loop.
      await DbQueries.invalidateMessageIndex(_db!, id);
    }
  }

  Future<List<Message>> getPendingMessages(String conversationId) async {
    _ensureInitialized();
    await _purgeExpiredIndexedMessages(conversationId);
    final rows = await DbQueries.find(
      _db!,
      DbTables.messageIndex,
      equals: {DbCols.conversationId: conversationId, 'valid': 1, 'is_sent': 0},
      columns: [DbCols.id],
      orderBy: const [DbOrder(DbCols.sentAt), DbOrder(DbCols.id)],
    );
    final pending = <Message>[];
    for (final row in rows) {
      final message = await getMessage(
        conversationId,
        row[DbCols.id] as String,
      );
      if (message != null && !message.isSent) pending.add(message);
    }
    return pending;
  }

  Future<List<Message>> getMessages(String conversationId) async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.messages,
      equals: {DbCols.conversationId: conversationId},
      orderBy: const [DbOrder('sent_at')],
    );
    final list = <Message>[];
    final expiredIds = <String>[];
    for (final row in rows) {
      try {
        final json = _dec(row[DbCols.encryptedContent] as String?);
        if (json == null) {
          continue; // skip corrupt/undecryptable row
        }
        final message = Message.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
        if (message.isExpired) {
          expiredIds.add(message.id);
        } else {
          list.add(message);
        }
      } catch (_) {
        continue; // skip malformed row, never crash the chat
      }
    }
    await _purgeMessages(expiredIds);
    return list;
  }

  Future<void> _purgeMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _db!.transaction((transaction) async {
      for (final id in messageIds) {
        await DbQueries.deleteWhere(transaction, DbTables.messages, {
          DbCols.id: id,
        });
        await DbQueries.deleteWhere(transaction, DbTables.messageIndex, {
          DbCols.id: id,
        });
        await DbQueries.deleteWhere(transaction, DbTables.kv, {
          DbCols.key: '${_sessionKeyPrefix}outbox:$id',
        });
      }
    });
  }

  Future<void> deleteMessage(String messageId) async {
    _ensureInitialized();
    await _purgeMessages([messageId]);
  }

  Future<List<Message>> searchMessages(String query) async {
    _ensureInitialized();
    // Deliberately no SQL LIKE on content: message text is encrypted
    // at rest, so search decrypts in Dart. Slower, but leaks nothing
    // into indices or query logs.
    final lower = query.toLowerCase();
    final rows = await DbQueries.find(_db!, DbTables.messages);
    final out = <Message>[];
    final expiredIds = <String>[];
    for (final row in rows) {
      try {
        final json = _dec(row[DbCols.encryptedContent] as String?);
        if (json == null) {
          continue;
        }
        final m = Message.fromJson(jsonDecode(json) as Map<String, dynamic>);
        if (m.isExpired) {
          expiredIds.add(m.id);
          continue;
        }
        if (m.content.toLowerCase().contains(lower)) {
          out.add(m);
        }
      } catch (_) {
        continue;
      }
    }
    await _purgeMessages(expiredIds);
    return out;
  }

  // ---- Contacts
  Future<List<Contact>> getAllContacts() async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.contacts,
      equals: {DbCols.userId: _ownerId},
    );
    final out = <Contact>[];
    for (final row in rows) {
      try {
        final json = _dec(row['payload_enc'] as String?);
        if (json == null) {
          continue;
        }
        out.add(Contact.fromJson(jsonDecode(json) as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  Future<void> addContact(Contact contact) async {
    _ensureInitialized();
    await DbQueries.upsert(_db!, DbTables.contacts, {
      DbCols.userId: _ownerId,
      DbCols.contactId: contact.id,
      DbCols.displayNameEnc: _enc(contact.displayName),
      DbCols.avatarEnc: contact.avatarUrl == null
          ? null
          : _enc(contact.avatarUrl!),
      DbCols.verificationLevel: contact.verificationLevel,
      DbCols.isBlocked: contact.isBlocked ? 1 : 0,
      DbCols.addedAt:
          contact.lastSeen?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'payload_enc': _enc(jsonEncode(contact.toJson())),
    });
  }

  Future<void> updateContact(Contact contact) async => addContact(contact);

  Future<void> deleteContact(String contactId) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(_db!, DbTables.contacts, {
      DbCols.userId: _ownerId,
      DbCols.contactId: contactId,
    });
  }

  // ---- Ratchet sessions (persisted by Part 4 session_store.dart).
  //
  // Blobs are AES-GCM field envelopes under `ratchet_session/<peerId>`
  // in the kv table — encrypted at rest like every other secret.
  static const String _sessionKeyPrefix = 'ratchet_session/';

  /// Stores an enveloped session blob for [peerId].
  Future<void> saveSessionBlob(String peerId, String json) async {
    _ensureInitialized();
    await DbQueries.upsert(_db!, DbTables.kv, {
      DbCols.key: '$_sessionKeyPrefix$peerId',
      DbCols.value: _enc(json),
    });
  }

  /// Null means absent. A present but unauthenticatable session fails closed.
  Future<String?> loadSessionBlob(String peerId) async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.kv,
      equals: {DbCols.key: '$_sessionKeyPrefix$peerId'},
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final plain = _dec(rows.first[DbCols.value] as String?);
    if (plain == null) throw StateError('Stored session authentication failed');
    return plain;
  }

  /// Deletes the session blob for [peerId].
  Future<void> deleteSessionBlob(String peerId) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(_db!, DbTables.kv, {
      DbCols.key: '$_sessionKeyPrefix$peerId',
    });
  }

  Future<Contact?> getContact(String contactId) async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.contacts,
      equals: {DbCols.userId: _ownerId, DbCols.contactId: contactId},
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    try {
      final json = _dec(rows.first['payload_enc'] as String?);
      if (json == null) {
        return null;
      }
      return Contact.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ---- Conversations
  Future<List<Conversation>> getAllConversations() async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.conversations,
      orderBy: const [
        DbOrder('pinned', descending: true),
        DbOrder('last_ts', descending: true),
      ],
    );
    final out = <Conversation>[];
    for (final row in rows) {
      try {
        final json = _dec(row['payload_enc'] as String?);
        if (json == null) {
          continue;
        }
        final conversation = Conversation.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
        if (conversation.lastMessage?.isExpired == true) {
          final sanitized = conversation.copyWith(clearLastMessage: true);
          out.add(sanitized);
          await addConversation(sanitized);
        } else {
          out.add(conversation);
        }
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) {
      if (a.isPinned && !b.isPinned) {
        return -1;
      }
      if (!a.isPinned && b.isPinned) {
        return 1;
      }
      final aTime = a.lastMessage?.timestamp ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return out;
  }

  Future<void> addConversation(Conversation c) async {
    _ensureInitialized();
    final lastTs =
        (c.lastMessage?.timestamp ?? c.createdAt).millisecondsSinceEpoch;
    await DbQueries.upsert(_db!, DbTables.conversations, {
      DbCols.id: c.id,
      DbCols.type: c.isGroup ? 'group' : 'direct',
      DbCols.nameEnc: c.groupName == null ? null : _enc(c.groupName!),
      DbCols.avatarBlob: null,
      DbCols.createdBy: _ownerId,
      DbCols.createdAt: c.createdAt.millisecondsSinceEpoch,
      DbCols.pinned: c.isPinned ? 1 : 0,
      DbCols.lastTs: lastTs,
      'payload_enc': _enc(jsonEncode(c.toJson())),
    });
    await DbQueries.deleteWhere(_db!, DbTables.participants, {
      DbCols.conversationId: c.id,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < c.participants.length; i++) {
      await DbQueries.upsert(_db!, DbTables.participants, {
        DbCols.conversationId: c.id,
        DbCols.userId: c.participants[i].id,
        DbCols.joinedAt: now,
        DbCols.leftAt: null,
        DbCols.isAdmin: i == 0 ? 1 : 0,
      });
    }
  }

  Future<void> updateConversation(Conversation c) async => addConversation(c);

  Future<void> deleteConversation(String id) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(_db!, DbTables.conversations, {DbCols.id: id});
    await DbQueries.deleteWhere(_db!, DbTables.messages, {
      DbCols.conversationId: id,
    });
    await DbQueries.deleteWhere(_db!, DbTables.messageIndex, {
      DbCols.conversationId: id,
    });
    await DbQueries.deleteWhere(_db!, DbTables.participants, {
      DbCols.conversationId: id,
    });
  }

  // ---- Profile
  Future<UserProfile?> getUserProfile() async {
    _ensureInitialized();
    final idRows = await DbQueries.find(
      _db!,
      DbTables.kv,
      equals: {DbCols.key: 'current_user_id'},
      limit: 1,
    );
    if (idRows.isEmpty) {
      return null;
    }
    final userId = idRows.first[DbCols.value] as String?;
    if (userId == null) {
      return null;
    }
    final rows = await DbQueries.find(
      _db!,
      DbTables.users,
      equals: {DbCols.id: userId},
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    try {
      final json = _dec(rows.first['payload_enc'] as String?);
      if (json == null) {
        return null;
      }
      return UserProfile.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    _ensureInitialized();
    final id = profile.chhayaId.publicKey;
    await DbQueries.upsert(_db!, DbTables.users, {
      DbCols.id: id,
      DbCols.chhayaId: id,
      DbCols.displayNameEnc: _enc(profile.displayName),
      DbCols.publicKey: id,
      DbCols.encryptedPrivateKey: '',
      DbCols.createdAt: profile.createdAt.millisecondsSinceEpoch,
      'payload_enc': _enc(jsonEncode(profile.toJson())),
    });
    await DbQueries.upsert(_db!, DbTables.kv, {
      DbCols.key: 'current_user_id',
      DbCols.value: id,
    });
  }

  /// Replaces the locally backed-up account snapshot in one SQLCipher
  /// transaction. Ratchet state and queued envelopes are intentionally not
  /// imported; a restored account must establish fresh messaging sessions.
  Future<void> replaceAccountSnapshot({
    required UserProfile profile,
    required List<Contact> contacts,
    required List<Conversation> conversations,
    required List<Message> messages,
  }) async {
    _ensureInitialized();
    await _db!.transaction((transaction) async {
      for (final table in [
        DbTables.messageIndex,
        DbTables.messages,
        DbTables.participants,
        DbTables.conversations,
        DbTables.contacts,
        DbTables.users,
        DbTables.devices,
        DbTables.circuits,
      ]) {
        await transaction.delete(table);
      }

      final keyRows = await DbQueries.find(transaction, DbTables.kv);
      for (final row in keyRows) {
        final key = row[DbCols.key] as String?;
        if (key != null && key.startsWith(_sessionKeyPrefix)) {
          await DbQueries.deleteWhere(transaction, DbTables.kv, {
            DbCols.key: key,
          });
        }
      }

      final profileId = profile.chhayaId.publicKey;
      await DbQueries.upsert(transaction, DbTables.users, {
        DbCols.id: profileId,
        DbCols.chhayaId: profileId,
        DbCols.displayNameEnc: _enc(profile.displayName),
        DbCols.publicKey: profileId,
        DbCols.encryptedPrivateKey: '',
        DbCols.createdAt: profile.createdAt.millisecondsSinceEpoch,
        'payload_enc': _enc(jsonEncode(profile.toJson())),
      });
      await DbQueries.upsert(transaction, DbTables.kv, {
        DbCols.key: 'current_user_id',
        DbCols.value: profileId,
      });

      for (final contact in contacts) {
        await DbQueries.upsert(transaction, DbTables.contacts, {
          DbCols.userId: _ownerId,
          DbCols.contactId: contact.id,
          DbCols.displayNameEnc: _enc(contact.displayName),
          DbCols.avatarEnc: contact.avatarUrl == null
              ? null
              : _enc(contact.avatarUrl!),
          DbCols.verificationLevel: contact.verificationLevel,
          DbCols.isBlocked: contact.isBlocked ? 1 : 0,
          DbCols.addedAt:
              contact.lastSeen?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
          'payload_enc': _enc(jsonEncode(contact.toJson())),
        });
      }

      final joinedAt = DateTime.now().millisecondsSinceEpoch;
      for (final conversation in conversations) {
        final lastTs =
            (conversation.lastMessage?.timestamp ?? conversation.createdAt)
                .millisecondsSinceEpoch;
        await DbQueries.upsert(transaction, DbTables.conversations, {
          DbCols.id: conversation.id,
          DbCols.type: conversation.isGroup ? 'group' : 'direct',
          DbCols.nameEnc: conversation.groupName == null
              ? null
              : _enc(conversation.groupName!),
          DbCols.avatarBlob: null,
          DbCols.createdBy: _ownerId,
          DbCols.createdAt: conversation.createdAt.millisecondsSinceEpoch,
          DbCols.pinned: conversation.isPinned ? 1 : 0,
          DbCols.lastTs: lastTs,
          'payload_enc': _enc(jsonEncode(conversation.toJson())),
        });
        for (var i = 0; i < conversation.participants.length; i++) {
          await DbQueries.upsert(transaction, DbTables.participants, {
            DbCols.conversationId: conversation.id,
            DbCols.userId: conversation.participants[i].id,
            DbCols.joinedAt: joinedAt,
            DbCols.leftAt: null,
            DbCols.isAdmin: i == 0 ? 1 : 0,
          });
        }
      }

      for (final message in messages) {
        await _writeMessage(transaction, message);
      }
    });
    _deviceCache = null;
  }

  // ---- Circuits (onion cache; wired by Part 10)
  /// Caches an encrypted circuit path until [expiresAt].
  Future<void> cacheCircuit({
    required String id,
    required String pathJson,
    required DateTime expiresAt,
  }) async {
    _ensureInitialized();
    await DbQueries.upsert(_db!, DbTables.circuits, {
      DbCols.id: id,
      DbCols.pathEnc: _enc(pathJson),
      DbCols.createdAt: DateTime.now().millisecondsSinceEpoch,
      DbCols.expiresAt: expiresAt.millisecondsSinceEpoch,
    });
  }

  /// Returns decrypted paths of unexpired circuits.
  Future<List<String>> getValidCircuits() async {
    _ensureInitialized();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await DbQueries.find(_db!, DbTables.circuits);
    final out = <String>[];
    for (final row in rows) {
      try {
        final expiresAt = row[DbCols.expiresAt] as int? ?? 0;
        if (expiresAt <= now) {
          continue;
        }
        final path = _dec(row[DbCols.pathEnc] as String?);
        if (path != null) {
          out.add(path);
        }
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// Deletes expired circuits. Returns the evicted count.
  Future<int> pruneExpiredCircuits() async {
    _ensureInitialized();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await DbQueries.find(_db!, DbTables.circuits);
    var evicted = 0;
    for (final row in rows) {
      final expiresAt = row[DbCols.expiresAt] as int? ?? 0;
      if (expiresAt <= now) {
        await DbQueries.deleteWhere(_db!, DbTables.circuits, {
          DbCols.id: row[DbCols.id] as String,
        });
        evicted++;
      }
    }
    return evicted;
  }

  // ---- Settings KV
  Future<Map<String, dynamic>> _getSettings() async {
    _ensureInitialized();
    final rows = await DbQueries.find(
      _db!,
      DbTables.kv,
      equals: {DbCols.key: 'app_settings'},
      limit: 1,
    );
    if (rows.isEmpty) {
      return _defaultSettings();
    }
    try {
      final json = _dec(rows.first[DbCols.value] as String?);
      if (json == null) {
        return _defaultSettings();
      }
      final parsed = jsonDecode(json);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
    } catch (_) {}
    return _defaultSettings();
  }

  Map<String, dynamic> _defaultSettings() => {
    'biometric_lock': true,
    'read_receipts': true,
    'typing_indicators': true,
    'global_disappearing_duration': 0,
    'onion_routing': true,
    'blocked_contacts': <String>[],
    'linked_devices': <Map<String, dynamic>>[],
  };

  Future<void> _saveSettings(Map<String, dynamic> s) async {
    _ensureInitialized();
    await DbQueries.upsert(_db!, DbTables.kv, {
      DbCols.key: 'app_settings',
      DbCols.value: _enc(jsonEncode(s)),
    });
  }

  Future<Map<String, dynamic>> getSettings() => _getSettings();
  Map<String, dynamic>? _settingsCache;

  Map<String, dynamic> _getSettingsSync() {
    // fallback sync for getters that were sync before; we keep async wrappers below but also sync cache
    return _settingsCache ?? _defaultSettings();
  }

  bool getBiometricLockEnabled() =>
      _getSettingsSync()['biometric_lock'] as bool? ?? true;
  Future<void> setBiometricLockEnabled(bool v) async {
    final s = await _getSettings();
    s['biometric_lock'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  bool getConversationReadReceiptsEnabled(String conversationId) {
    final overrides = _getSettingsSync()['conversation_read_receipts'];
    return getReadReceiptsEnabled() &&
        (overrides is Map ? overrides[conversationId] as bool? ?? true : true);
  }

  Future<void> setConversationReadReceiptsEnabled(
    String conversationId,
    bool enabled,
  ) async {
    final settings = await _getSettings();
    final overrides = Map<String, dynamic>.from(
      settings['conversation_read_receipts'] as Map? ?? {},
    );
    overrides[conversationId] = enabled;
    settings['conversation_read_receipts'] = overrides;
    await _saveSettings(settings);
    _settingsCache = settings;
  }

  bool getConversationTypingIndicatorsEnabled(String conversationId) {
    final overrides = _getSettingsSync()['conversation_typing_indicators'];
    return getTypingIndicatorsEnabled() &&
        (overrides is Map ? overrides[conversationId] as bool? ?? true : true);
  }

  Future<void> setConversationTypingIndicatorsEnabled(
    String conversationId,
    bool enabled,
  ) async {
    final settings = await _getSettings();
    final overrides = Map<String, dynamic>.from(
      settings['conversation_typing_indicators'] as Map? ?? {},
    );
    overrides[conversationId] = enabled;
    settings['conversation_typing_indicators'] = overrides;
    await _saveSettings(settings);
    _settingsCache = settings;
  }

  bool getReadReceiptsEnabled() =>
      _getSettingsSync()['read_receipts'] as bool? ?? true;
  Future<void> setReadReceiptsEnabled(bool v) async {
    final s = await _getSettings();
    s['read_receipts'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  bool getTypingIndicatorsEnabled() =>
      _getSettingsSync()['typing_indicators'] as bool? ?? true;
  Future<void> setTypingIndicatorsEnabled(bool v) async {
    final s = await _getSettings();
    s['typing_indicators'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  int getGlobalDisappearingDuration() =>
      _getSettingsSync()['global_disappearing_duration'] as int? ?? 0;
  Future<void> setGlobalDisappearingDuration(int v) async {
    final s = await _getSettings();
    s['global_disappearing_duration'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  bool getOnionRoutingEnabled() =>
      _getSettingsSync()['onion_routing'] as bool? ?? true;
  Future<void> setOnionRoutingEnabled(bool v) async {
    final s = await _getSettings();
    s['onion_routing'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  List<String> getBlockedContacts() {
    final list = _getSettingsSync()['blocked_contacts'] as List<dynamic>?;
    return list?.map((e) => e as String).toList() ?? <String>[];
  }

  Future<void> blockContact(String id) async {
    final s = await _getSettings();
    final list = (s['blocked_contacts'] as List<dynamic>? ?? []).cast<String>();
    if (!list.contains(id)) {
      list.add(id);
    }
    s['blocked_contacts'] = list;
    await _saveSettings(s);
    _settingsCache = s;
  }

  Future<void> unblockContact(String id) async {
    final s = await _getSettings();
    final list = (s['blocked_contacts'] as List<dynamic>? ?? []).cast<String>();
    list.remove(id);
    s['blocked_contacts'] = list;
    await _saveSettings(s);
    _settingsCache = s;
  }

  List<Map<String, dynamic>> getLinkedDevices() {
    final rows = _deviceRowsSync();
    return rows;
  }

  Future<void> addLinkedDevice(Map<String, dynamic> d) async {
    _ensureInitialized();
    final id =
        d['id'] as String? ?? 'dev_${DateTime.now().millisecondsSinceEpoch}';
    await DbQueries.upsert(_db!, DbTables.devices, {
      DbCols.id: id,
      DbCols.userId: _ownerId,
      DbCols.deviceName: d['name'] as String? ?? 'Device',
      DbCols.platform: d['platform'] as String? ?? 'unknown',
      DbCols.fcmTokenEncrypted: d['fcmToken'] == null
          ? null
          : _enc(d['fcmToken'] as String),
      DbCols.publicKey: d['publicKey'] as String? ?? '',
      DbCols.isLinked: 1,
      DbCols.lastActiveAt: DateTime.now().millisecondsSinceEpoch,
    });
    await _refreshDeviceCache();
  }

  Future<void> removeLinkedDevice(String id) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(_db!, DbTables.devices, {
      DbCols.userId: _ownerId,
      DbCols.id: id,
    });
    await _refreshDeviceCache();
  }

  Future<void> _refreshDeviceCache() async {
    _deviceCache = await DbQueries.find(
      _db!,
      DbTables.devices,
      equals: {DbCols.userId: _ownerId},
    );
  }

  List<Map<String, dynamic>> _deviceRowsSync() {
    // Devices are read async everywhere except the legacy sync getter.
    // The sync getter cannot await, so it reports the last async load.
    return _deviceCache
            ?.map(
              (row) => <String, dynamic>{
                'id': row[DbCols.id],
                'name': row[DbCols.deviceName],
                'platform': row[DbCols.platform],
              },
            )
            .toList() ??
        [];
  }

  List<Map<String, Object?>>? _deviceCache;
  String? getPanicPin() => _getSettingsSync()['panic_pin'] as String?;
  Future<void> setPanicPin(String? pin) async {
    final s = await _getSettings();
    s['panic_pin'] = pin;
    await _saveSettings(s);
    _settingsCache = s;
  }

  String? getAppPin() => _getSettingsSync()['app_pin'] as String?;
  Future<void> setAppPin(String pin) async {
    final s = await _getSettings();
    s['app_pin'] = pin;
    await _saveSettings(s);
    _settingsCache = s;
  }

  bool getMeshRoutingEnabled() =>
      _getSettingsSync()['mesh_routing'] as bool? ?? false;
  Future<void> setMeshRoutingEnabled(bool v) async {
    final s = await _getSettings();
    s['mesh_routing'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  int getConversationTtl(String cid) =>
      _getSettingsSync()['ttl_$cid'] as int? ?? 0;
  Future<void> setConversationTtl(String cid, int v) async {
    final s = await _getSettings();
    s['ttl_$cid'] = v;
    await _saveSettings(s);
    _settingsCache = s;
  }

  Future<void> preloadSettings() async {
    _settingsCache = await _getSettings();
    await _refreshDeviceCache();
  }

  Future<void> clearAll() async {
    _ensureInitialized();
    for (final table in [
      DbTables.messageIndex,
      DbTables.messages,
      DbTables.contacts,
      DbTables.conversations,
      DbTables.participants,
      DbTables.users,
      DbTables.devices,
      DbTables.circuits,
      DbTables.kv,
    ]) {
      await _db!.delete(table);
    }
    if (_dbKey != null) {
      Csprng.wipe(_dbKey!);
      // Re-derive immediately: the database stays usable after a wipe
      // (V13 clearAll never de-initialized). Derivation is deterministic.
      _dbKey = await DatabaseKey.derive(_keyManager, userId: _ownerId);
    }
    _settingsCache = null;
    _deviceCache = null;
    // Hygiene: drop the V13-era legacy key if present. The V14 key
    // lives in the Part 2 key manager, not here. Best-effort: secure
    // storage may be unreachable (e.g. unit tests without channels).
    try {
      await _secure.delete(key: 'db_encryption_key');
    } catch (_) {}
  }
}
