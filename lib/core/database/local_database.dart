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
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../crypto/key_manager.dart';
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
    // Hardening. Constant strings only — no parameters, no user input.
    await db.execute('PRAGMA cipher_memory_security = ON');
    await db.execute('PRAGMA journal_mode = DELETE');
    return db;
  }
}

/// PRAGMA statements the production opener applies. Tests assert the
/// fake opener records exactly these (see test/unit/database/).
const List<String> kHardeningPragmas = [
  'PRAGMA cipher_memory_security = ON',
  'PRAGMA journal_mode = DELETE',
];

/// Production migration chain: v001 → v005 in order. Single place that
/// defines the full history; LocalDatabase and tests share it.
List<Migration> chhayaMigrations() => [
      MigrationV001Initial(),
      MigrationV002Messages(),
      MigrationV003Devices(),
      MigrationV004Circuits(),
      MigrationV005Payloads(),
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
  })  : _keyManager = keyManager ?? KeyManager(),
        _opener = opener ?? SqlCipherOpener(),
        _dbPathOverride = dbPath,
        _secure = secureStorage ?? const FlutterSecureStorage();

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

  Future<bool> authenticateWithBiometrics(
      {String reason = 'Unlock Chhaya'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
            stickyAuth: true, biometricOnly: false, useErrorDialogs: true),
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
    final dbKey = await DatabaseKey.derive(
      _keyManager,
      userId: _ownerId,
    );
    final passwordHex = DatabaseKey.toPragmaHex(dbKey);
    final dbPath =
        _dbPathOverride ?? p.join(await getDatabasesPath(), _dbName);
    final runner = MigrationRunner(chhayaMigrations());
    _db = await _opener.open(
      path: dbPath,
      version: runner.latestVersion,
      passwordHex: passwordHex,
      onOpen: (db) => runner.migrateTo(db, runner.latestVersion),
    );
    Csprng.wipe(dbKey);
    _dbKey = await DatabaseKey.derive(_keyManager, userId: _ownerId);
    _initialized = true;
    await preloadSettings();
    return true;
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

  void _ensureInitialized() {
    if (!_initialized || _db == null || _dbKey == null) {
      throw StateError('LocalDatabase not initialized. Call init() first.');
    }
  }

  String _enc(String plain) =>
      DatabaseKey.encryptField(plain, _dbKey!);

  String? _dec(String? envelope) =>
      DatabaseKey.decryptField(envelope, _dbKey!);

  // ---- Messages
  Future<void> addMessage(Message message) async {
    _ensureInitialized();
    await DbQueries.upsert(_db!, DbTables.messages, {
      DbCols.id: message.id,
      DbCols.conversationId: message.conversationId,
      DbCols.senderId: message.senderId,
      DbCols.encryptedContent: _enc(jsonEncode(message.toJson())),
      DbCols.contentType: message.type.name,
      DbCols.mediaBlob: null,
      DbCols.mediaMetaEnc: null,
      DbCols.replyToId: message.replyToId,
      DbCols.sentAt: message.timestamp.millisecondsSinceEpoch,
      DbCols.deliveredAt:
          message.isDelivered ? message.timestamp.millisecondsSinceEpoch : null,
      DbCols.readAt:
          message.isRead ? message.timestamp.millisecondsSinceEpoch : null,
    });
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
    for (final row in rows) {
      try {
        final json = _dec(row[DbCols.encryptedContent] as String?);
        if (json == null) {
          continue; // skip corrupt/undecryptable row
        }
        list.add(Message.fromJson(jsonDecode(json) as Map<String, dynamic>));
      } catch (_) {
        continue; // skip malformed row, never crash the chat
      }
    }
    return list;
  }

  Future<void> deleteMessage(String messageId) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(
      _db!,
      DbTables.messages,
      {DbCols.id: messageId},
    );
  }

  Future<List<Message>> searchMessages(String query) async {
    _ensureInitialized();
    // Deliberately no SQL LIKE on content: message text is encrypted
    // at rest, so search decrypts in Dart. Slower, but leaks nothing
    // into indices or query logs.
    final lower = query.toLowerCase();
    final rows = await DbQueries.find(_db!, DbTables.messages);
    final out = <Message>[];
    for (final row in rows) {
      try {
        final json = _dec(row[DbCols.encryptedContent] as String?);
        if (json == null) {
          continue;
        }
        final m =
            Message.fromJson(jsonDecode(json) as Map<String, dynamic>);
        if (m.content.toLowerCase().contains(lower)) {
          out.add(m);
        }
      } catch (_) {
        continue;
      }
    }
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
      DbCols.avatarEnc:
          contact.avatarUrl == null ? null : _enc(contact.avatarUrl!),
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
    await DbQueries.deleteWhere(
      _db!,
      DbTables.contacts,
      {DbCols.userId: _ownerId, DbCols.contactId: contactId},
    );
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
      orderBy: const [DbOrder('pinned', descending: true), DbOrder('last_ts', descending: true)],
    );
    final out = <Conversation>[];
    for (final row in rows) {
      try {
        final json = _dec(row['payload_enc'] as String?);
        if (json == null) {
          continue;
        }
        out.add(
            Conversation.fromJson(jsonDecode(json) as Map<String, dynamic>));
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
    final lastTs = (c.lastMessage?.timestamp ?? c.createdAt)
        .millisecondsSinceEpoch;
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
    await DbQueries.deleteWhere(
      _db!,
      DbTables.participants,
      {DbCols.conversationId: c.id},
    );
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

  Future<void> updateConversation(Conversation c) async =>
      addConversation(c);

  Future<void> deleteConversation(String id) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(
      _db!,
      DbTables.conversations,
      {DbCols.id: id},
    );
    await DbQueries.deleteWhere(
      _db!,
      DbTables.messages,
      {DbCols.conversationId: id},
    );
    await DbQueries.deleteWhere(
      _db!,
      DbTables.participants,
      {DbCols.conversationId: id},
    );
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
        await DbQueries.deleteWhere(
          _db!,
          DbTables.circuits,
          {DbCols.id: row[DbCols.id] as String},
        );
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
  bool getReadReceiptsEnabled() =>
      _getSettingsSync()['read_receipts'] as bool? ?? true;
  Future<void> setReadReceiptsEnabled(bool v) async {
    final s = await _getSettings();
    s['read_receipts'] = v;
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
    final list =
        _getSettingsSync()['blocked_contacts'] as List<dynamic>?;
    return list?.map((e) => e as String).toList() ?? <String>[];
  }
  Future<void> blockContact(String id) async {
    final s = await _getSettings();
    final list =
        (s['blocked_contacts'] as List<dynamic>? ?? []).cast<String>();
    if (!list.contains(id)) {
      list.add(id);
    }
    s['blocked_contacts'] = list;
    await _saveSettings(s);
    _settingsCache = s;
  }
  Future<void> unblockContact(String id) async {
    final s = await _getSettings();
    final list =
        (s['blocked_contacts'] as List<dynamic>? ?? []).cast<String>();
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
    final id = d['id'] as String? ??
        'dev_${DateTime.now().millisecondsSinceEpoch}';
    await DbQueries.upsert(_db!, DbTables.devices, {
      DbCols.id: id,
      DbCols.userId: _ownerId,
      DbCols.deviceName: d['name'] as String? ?? 'Device',
      DbCols.platform: d['platform'] as String? ?? 'unknown',
      DbCols.fcmTokenEncrypted:
          d['fcmToken'] == null ? null : _enc(d['fcmToken'] as String),
      DbCols.publicKey: d['publicKey'] as String? ?? '',
      DbCols.isLinked: 1,
      DbCols.lastActiveAt: DateTime.now().millisecondsSinceEpoch,
    });
    await _refreshDeviceCache();
  }
  Future<void> removeLinkedDevice(String id) async {
    _ensureInitialized();
    await DbQueries.deleteWhere(
      _db!,
      DbTables.devices,
      {DbCols.userId: _ownerId, DbCols.id: id},
    );
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
            ?.map((row) => <String, dynamic>{
                  'id': row[DbCols.id],
                  'name': row[DbCols.deviceName],
                  'platform': row[DbCols.platform],
                })
            .toList() ??
        [];
  }
  List<Map<String, Object?>>? _deviceCache;
  String? getPanicPin() =>
      _getSettingsSync()['panic_pin'] as String?;
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
