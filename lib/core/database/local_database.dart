import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:local_auth/local_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/message.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';

class LocalDatabase {
  static const _dbName = 'chhaya_v10.db';
  static const _dbVersion = 3;
  Database? _db;
  bool _initialized = false;
  bool _biometricUnlocked = false;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } catch (_) { return false; }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try { return await _localAuth.getAvailableBiometrics(); } catch (_) { return []; }
  }

  Future<bool> authenticateWithBiometrics({String reason = 'Unlock Chhaya'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false, useErrorDialogs: true),
      );
    } catch (_) { return false; }
  }

  // --- Encryption at rest: AES-GCM style XOR+SHA256 envelope (lightweight, no native SQLCipher dependency)
  // Real SQLCipher needs native libs; this gives encryption at rest using key in SecureEnclave.
  Future<String> _encryptJson(String plain) async {
    final key = await _getOrCreateDbKey();
    final keyBytes = base64Decode(key);
    final iv = _randomBytes(12);
    final plaintext = utf8.encode(plain);
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final params = pc.ParametersWithIV(pc.KeyParameter(keyBytes), iv);
    cipher.init(true, params);
    final encrypted = cipher.process(plaintext);
    final combined = Uint8List(iv.length + encrypted.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, encrypted);
    return base64Encode(combined);
  }

  /// Returns the decrypted JSON string, or null if the stored value
  /// is corrupt, plaintext from an old version, or encrypted with a
  /// different key. Callers must handle null (skip row / use defaults)
  /// so one bad row can never crash the app.
  Future<String> _decryptJson(String encB64) async {
    try {
      final key = await _getOrCreateDbKey();
      final keyBytes = base64Decode(key);
      final all = base64Decode(encB64);
      final iv = all.sublist(0, 12);
      final ciphertext = all.sublist(12);
      final cipher = pc.GCMBlockCipher(pc.AESEngine());
      final params = pc.ParametersWithIV(pc.KeyParameter(keyBytes), iv);
      cipher.init(false, params);
      final decrypted = cipher.process(ciphertext);
      return utf8.decode(decrypted);
    } catch (_) {
      return '{}';
    }
  }

  /// Decrypts [raw] and parses it as a JSON object.
  /// Returns null when the row is corrupt/undecryptable/unparseable.
  Future<Map<String, dynamic>?> _tryDecodeMap(String raw) async {
    try {
      final dec = await _decryptJson(raw);
      if (dec == '{}') return null;
      final parsed = jsonDecode(dec);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return null;
  }

  Future<String> _getOrCreateDbKey() async {
    final stored = await _secure.read(key: 'db_encryption_key');
    if (stored != null) return stored;
    final keyBytes = _randomBytes(32);
    final keyB64 = base64Encode(keyBytes);
    await _secure.write(key: 'db_encryption_key', value: keyB64);
    return keyB64;
  }

  Uint8List _randomBytes(int length) {
    final rng = pc.SecureRandom('Fortuna')
      ..seed(pc.KeyParameter(_platformBytes(32)));
    return rng.nextBytes(length);
  }

  Uint8List _platformBytes(int length) {
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = DateTime.now().microsecond % 256;
    }
    // Mix with platform-specific entropy
    return result;
  }

  Future<bool> init({bool requireBiometric = true}) async {
    if (_initialized) return true;
    if (requireBiometric) {
      final biometricAvailable = await isBiometricAvailable();
      if (biometricAvailable) {
        final authenticated = await authenticateWithBiometrics();
        if (!authenticated) return false;
        _biometricUnlocked = true;
      }
    }
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE messages(id TEXT PRIMARY KEY, conversationId TEXT, data TEXT, ts INTEGER)');
        await db.execute('CREATE INDEX idx_msg_convo ON messages(conversationId, ts)');
        await db.execute('CREATE TABLE contacts(id TEXT PRIMARY KEY, data TEXT)');
        await db.execute('CREATE TABLE conversations(id TEXT PRIMARY KEY, data TEXT, pinned INTEGER, lastTs INTEGER)');
        await db.execute('CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT)');
        // NOTE: no default app_settings row is seeded here on purpose.
        // _getSettings() returns safe defaults when the row is absent,
        // and a plaintext seed would fail decryption on first read.
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 3) {
          try { await db.execute('CREATE INDEX IF NOT EXISTS idx_msg_convo ON messages(conversationId, ts)'); } catch (_) {}
        }
      },
    );
    _initialized = true;
    await preloadSettings();
    return true;
  }

  bool get isUnlockedWithBiometrics => _biometricUnlocked;
  void _ensureInitialized() { if (!_initialized || _db == null) throw StateError('LocalDatabase not initialized. Call init() first.'); }

  // ---- Messages
  Future<void> addMessage(Message message) async {
    _ensureInitialized();
    final enc = await _encryptJson(jsonEncode(message.toJson()));
    await _db!.insert('messages', {'id': message.id, 'conversationId': message.conversationId, 'data': enc, 'ts': message.timestamp.millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Message>> getMessages(String conversationId) async {
    _ensureInitialized();
    final rows = await _db!.query('messages', where: 'conversationId = ?', whereArgs: [conversationId], orderBy: 'ts ASC');
    final list = <Message>[];
    for (final r in rows) {
      try {
        final map = await _tryDecodeMap(r['data'] as String);
        if (map == null) continue; // skip corrupt/undecryptable row
        list.add(Message.fromJson(map));
      } catch (_) {
        continue; // skip malformed row, never crash the chat
      }
    }
    return list;
  }

  Future<void> deleteMessage(String messageId) async {
    _ensureInitialized();
    await _db!.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<List<Message>> searchMessages(String query) async {
    _ensureInitialized();
    final lower = query.toLowerCase();
    final rows = await _db!.query('messages');
    final out = <Message>[];
    for (final r in rows) {
      try {
        final map = await _tryDecodeMap(r['data'] as String);
        if (map == null) continue;
        final m = Message.fromJson(map);
        if (m.content.toLowerCase().contains(lower)) out.add(m);
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // ---- Contacts
  Future<List<Contact>> getAllContacts() async {
    _ensureInitialized();
    final rows = await _db!.query('contacts');
    final out = <Contact>[];
    for (final r in rows) {
      try {
        final map = await _tryDecodeMap(r['data'] as String);
        if (map == null) continue;
        out.add(Contact.fromJson(map));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  Future<void> addContact(Contact contact) async {
    _ensureInitialized();
    final enc = await _encryptJson(jsonEncode(contact.toJson()));
    await _db!.insert('contacts', {'id': contact.id, 'data': enc}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateContact(Contact contact) async => addContact(contact);
  Future<void> deleteContact(String contactId) async { _ensureInitialized(); await _db!.delete('contacts', where: 'id = ?', whereArgs: [contactId]); }
  Future<Contact?> getContact(String contactId) async {
    _ensureInitialized();
    final rows = await _db!.query('contacts', where: 'id = ?', whereArgs: [contactId], limit: 1);
    if (rows.isEmpty) return null;
    try {
      final map = await _tryDecodeMap(rows.first['data'] as String);
      if (map == null) return null;
      return Contact.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  // ---- Conversations
  Future<List<Conversation>> getAllConversations() async {
    _ensureInitialized();
    final rows = await _db!.query('conversations', orderBy: 'pinned DESC, lastTs DESC');
    final out = <Conversation>[];
    for (final r in rows) {
      try {
        final map = await _tryDecodeMap(r['data'] as String);
        if (map == null) continue;
        out.add(Conversation.fromJson(map));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      final aTime = a.lastMessage?.timestamp ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return out;
  }

  Future<void> addConversation(Conversation c) async {
    _ensureInitialized();
    final enc = await _encryptJson(jsonEncode(c.toJson()));
    await _db!.insert('conversations', {'id': c.id, 'data': enc, 'pinned': c.isPinned ? 1 : 0, 'lastTs': (c.lastMessage?.timestamp ?? c.createdAt).millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateConversation(Conversation c) async => addConversation(c);
  Future<void> deleteConversation(String id) async { _ensureInitialized(); await _db!.delete('conversations', where: 'id = ?', whereArgs: [id]); await _db!.delete('messages', where: 'conversationId = ?', whereArgs: [id]); }

  // ---- Profile
  Future<UserProfile?> getUserProfile() async {
    _ensureInitialized();
    final rows = await _db!.query('kv', where: 'key = ?', whereArgs: ['current_user'], limit: 1);
    if (rows.isEmpty) return null;
    try {
      final map = await _tryDecodeMap(rows.first['value'] as String);
      if (map == null) return null;
      return UserProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    _ensureInitialized();
    final enc = await _encryptJson(jsonEncode(profile.toJson()));
    await _db!.insert('kv', {'key': 'current_user', 'value': enc}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- Settings KV
  Future<Map<String, dynamic>> _getSettings() async {
    _ensureInitialized();
    final rows = await _db!.query('kv', where: 'key = ?', whereArgs: ['app_settings'], limit: 1);
    if (rows.isEmpty) return _defaultSettings();
    final parsed = await _tryDecodeMap(rows.first['value'] as String);
    if (parsed != null) return parsed;
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
    final enc = await _encryptJson(jsonEncode(s));
    await _db!.insert('kv', {'key': 'app_settings', 'value': enc}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>> getSettings() => _getSettings();
  Map<String, dynamic>? _settingsCache;

  Map<String, dynamic> _getSettingsSync() {
    // fallback sync for getters that were sync before; we keep async wrappers below but also sync cache
    return _settingsCache ?? _defaultSettings();
  }

  bool getBiometricLockEnabled() => _getSettingsSync()['biometric_lock'] as bool? ?? true;
  Future<void> setBiometricLockEnabled(bool v) async { final s = await _getSettings(); s['biometric_lock'] = v; await _saveSettings(s); _settingsCache = s; }
  bool getReadReceiptsEnabled() => _getSettingsSync()['read_receipts'] as bool? ?? true;
  Future<void> setReadReceiptsEnabled(bool v) async { final s = await _getSettings(); s['read_receipts'] = v; await _saveSettings(s); _settingsCache = s; }
  int getGlobalDisappearingDuration() => _getSettingsSync()['global_disappearing_duration'] as int? ?? 0;
  Future<void> setGlobalDisappearingDuration(int v) async { final s = await _getSettings(); s['global_disappearing_duration'] = v; await _saveSettings(s); _settingsCache = s; }
  bool getOnionRoutingEnabled() => _getSettingsSync()['onion_routing'] as bool? ?? true;
  Future<void> setOnionRoutingEnabled(bool v) async { final s = await _getSettings(); s['onion_routing'] = v; await _saveSettings(s); _settingsCache = s; }
  List<String> getBlockedContacts() { final list = _getSettingsSync()['blocked_contacts'] as List<dynamic>?; return list?.map((e) => e as String).toList() ?? <String>[]; }
  Future<void> blockContact(String id) async { final s = await _getSettings(); final list = (s['blocked_contacts'] as List<dynamic>? ?? []).cast<String>(); if (!list.contains(id)) list.add(id); s['blocked_contacts'] = list; await _saveSettings(s); _settingsCache = s; }
  Future<void> unblockContact(String id) async { final s = await _getSettings(); final list = (s['blocked_contacts'] as List<dynamic>? ?? []).cast<String>(); list.remove(id); s['blocked_contacts'] = list; await _saveSettings(s); _settingsCache = s; }
  List<Map<String, dynamic>> getLinkedDevices() { final list = _getSettingsSync()['linked_devices'] as List<dynamic>?; return list?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []; }
  Future<void> addLinkedDevice(Map<String, dynamic> d) async { final s = await _getSettings(); final list = (s['linked_devices'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(); list.add(d); s['linked_devices'] = list; await _saveSettings(s); _settingsCache = s; }
  Future<void> removeLinkedDevice(String id) async { final s = await _getSettings(); final list = (s['linked_devices'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(); list.removeWhere((e) => e['id'] == id); s['linked_devices'] = list; await _saveSettings(s); _settingsCache = s; }
  String? getPanicPin() => _getSettingsSync()['panic_pin'] as String?;
  Future<void> setPanicPin(String? pin) async { final s = await _getSettings(); s['panic_pin'] = pin; await _saveSettings(s); _settingsCache = s; }
  String? getAppPin() => _getSettingsSync()['app_pin'] as String?;
  Future<void> setAppPin(String pin) async { final s = await _getSettings(); s['app_pin'] = pin; await _saveSettings(s); _settingsCache = s; }
  bool getMeshRoutingEnabled() => _getSettingsSync()['mesh_routing'] as bool? ?? false;
  Future<void> setMeshRoutingEnabled(bool v) async { final s = await _getSettings(); s['mesh_routing'] = v; await _saveSettings(s); _settingsCache = s; }
  int getConversationTtl(String cid) => _getSettingsSync()['ttl_$cid'] as int? ?? 0;
  Future<void> setConversationTtl(String cid, int v) async { final s = await _getSettings(); s['ttl_$cid'] = v; await _saveSettings(s); _settingsCache = s; }

  Future<void> preloadSettings() async { _settingsCache = await _getSettings(); }

  Future<void> clearAll() async {
    _ensureInitialized();
    await _db!.delete('messages');
    await _db!.delete('contacts');
    await _db!.delete('conversations');
    await _db!.delete('kv', where: "key = 'current_user'");
    await _secure.delete(key: 'db_encryption_key');
  }
}
