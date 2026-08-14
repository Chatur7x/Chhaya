import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';
import '../models/message.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';

class LocalDatabase {
  static const String _messagesBox = 'Chhaya_messages';
  static const String _contactsBox = 'Chhaya_contacts';
  static const String _conversationsBox = 'Chhaya_conversations';
  static const String _profileBox = 'Chhaya_profile';

  Box<String>? _messages;
  Box<String>? _contacts;
  Box<String>? _conversations;
  Box<String>? _profile;

  bool _initialized = false;
  bool _biometricUnlocked = false;

  final LocalAuthentication _localAuth = LocalAuthentication();


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
    String reason = 'Authenticate to unlock your Chhaya messages',
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
    if (_initialized) return true;


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

    await Hive.initFlutter();

    _messages = await Hive.openBox<String>(_messagesBox);
    _contacts = await Hive.openBox<String>(_contactsBox);
    _conversations = await Hive.openBox<String>(_conversationsBox);
    _profile = await Hive.openBox<String>(_profileBox);

    _initialized = true;
    return true;
  }

  bool get isUnlockedWithBiometrics => _biometricUnlocked;

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('LocalDatabase not initialized. Call init() first.');
    }
  }



  Future<void> addMessage(Message message) async {
    _ensureInitialized();
    await _messages!.put(message.id, jsonEncode(message.toJson()));
  }

  Future<List<Message>> getMessages(String conversationId) async {
    _ensureInitialized();
    final allMessages = _messages!.values
        .map((json) => Message.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .where((msg) => msg.conversationId == conversationId)
        .toList();
    allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return allMessages;
  }

  Future<void> deleteMessage(String messageId) async {
    _ensureInitialized();
    await _messages!.delete(messageId);
  }

  Future<List<Message>> searchMessages(String query) async {
    _ensureInitialized();
    final lowerQuery = query.toLowerCase();
    return _messages!.values
        .map((json) => Message.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .where((msg) => msg.content.toLowerCase().contains(lowerQuery))
        .toList();
  }



  Future<List<Contact>> getAllContacts() async {
    _ensureInitialized();
    return _contacts!.values
        .map((json) => Contact.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addContact(Contact contact) async {
    _ensureInitialized();
    await _contacts!.put(contact.id, jsonEncode(contact.toJson()));
  }

  Future<void> updateContact(Contact contact) async {
    _ensureInitialized();
    await _contacts!.put(contact.id, jsonEncode(contact.toJson()));
  }

  Future<void> deleteContact(String contactId) async {
    _ensureInitialized();
    await _contacts!.delete(contactId);
  }

  Future<Contact?> getContact(String contactId) async {
    _ensureInitialized();
    final json = _contacts!.get(contactId);
    if (json == null) return null;
    return Contact.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }



  Future<List<Conversation>> getAllConversations() async {
    _ensureInitialized();
    final convos = _conversations!.values
        .map((json) => Conversation.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();

    convos.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      final aTime = a.lastMessage?.timestamp ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return convos;
  }

  Future<void> addConversation(Conversation conversation) async {
    _ensureInitialized();
    await _conversations!.put(
      conversation.id,
      jsonEncode(conversation.toJson()),
    );
  }

  Future<void> updateConversation(Conversation conversation) async {
    _ensureInitialized();
    await _conversations!.put(
      conversation.id,
      jsonEncode(conversation.toJson()),
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    _ensureInitialized();
    await _conversations!.delete(conversationId);
  }



  Future<UserProfile?> getUserProfile() async {
    _ensureInitialized();
    final json = _profile!.get('current_user');
    if (json == null) return null;
    return UserProfile.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    _ensureInitialized();
    await _profile!.put('current_user', jsonEncode(profile.toJson()));
  }



  Map<String, dynamic> _getSettings() {
    _ensureInitialized();
    final jsonStr = _profile!.get('app_settings');
    if (jsonStr == null) {
      return {
        'biometric_lock': true,
        'read_receipts': true,
        'global_disappearing_duration': 0,
        'onion_routing': true,
        'blocked_contacts': <String>[],
        'linked_devices': <Map<String, dynamic>>[],
      };
    }
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  Future<void> _saveSettings(Map<String, dynamic> settings) async {
    _ensureInitialized();
    await _profile!.put('app_settings', jsonEncode(settings));
  }

  bool getBiometricLockEnabled() {
    return _getSettings()['biometric_lock'] as bool? ?? true;
  }

  Future<void> setBiometricLockEnabled(bool enabled) async {
    final s = _getSettings();
    s['biometric_lock'] = enabled;
    await _saveSettings(s);
  }

  bool getReadReceiptsEnabled() {
    return _getSettings()['read_receipts'] as bool? ?? true;
  }

  Future<void> setReadReceiptsEnabled(bool enabled) async {
    final s = _getSettings();
    s['read_receipts'] = enabled;
    await _saveSettings(s);
  }

  int getGlobalDisappearingDuration() {
    return _getSettings()['global_disappearing_duration'] as int? ?? 0;
  }

  Future<void> setGlobalDisappearingDuration(int seconds) async {
    final s = _getSettings();
    s['global_disappearing_duration'] = seconds;
    await _saveSettings(s);
  }

  bool getOnionRoutingEnabled() {
    return _getSettings()['onion_routing'] as bool? ?? true;
  }

  Future<void> setOnionRoutingEnabled(bool enabled) async {
    final s = _getSettings();
    s['onion_routing'] = enabled;
    await _saveSettings(s);
  }

  List<String> getBlockedContacts() {
    final list = _getSettings()['blocked_contacts'] as List<dynamic>?;
    return list?.map((e) => e as String).toList() ?? <String>[];
  }

  Future<void> blockContact(String contactId) async {
    final s = _getSettings();
    final list = getBlockedContacts();
    if (!list.contains(contactId)) {
      list.add(contactId);
    }
    s['blocked_contacts'] = list;
    await _saveSettings(s);
  }

  Future<void> unblockContact(String contactId) async {
    final s = _getSettings();
    final list = getBlockedContacts();
    list.remove(contactId);
    s['blocked_contacts'] = list;
    await _saveSettings(s);
  }

  List<Map<String, dynamic>> getLinkedDevices() {
    final list = _getSettings()['linked_devices'] as List<dynamic>?;
    return list?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[];
  }

  Future<void> addLinkedDevice(Map<String, dynamic> device) async {
    final s = _getSettings();
    final list = getLinkedDevices();
    list.add(device);
    s['linked_devices'] = list;
    await _saveSettings(s);
  }

  Future<void> removeLinkedDevice(String deviceId) async {
    final s = _getSettings();
    final list = getLinkedDevices();
    list.removeWhere((d) => d['id'] == deviceId);
    s['linked_devices'] = list;
    await _saveSettings(s);
  }



  String? getPanicPin() {
    return _getSettings()['panic_pin'] as String?;
  }

  Future<void> setPanicPin(String? pin) async {
    final s = _getSettings();
    s['panic_pin'] = pin;
    await _saveSettings(s);
  }

  String? getAppPin() {
    return _getSettings()['app_pin'] as String?;
  }

  Future<void> setAppPin(String pin) async {
    final s = _getSettings();
    s['app_pin'] = pin;
    await _saveSettings(s);
  }



  bool getMeshRoutingEnabled() {
    return _getSettings()['mesh_routing'] as bool? ?? false;
  }

  Future<void> setMeshRoutingEnabled(bool enabled) async {
    final s = _getSettings();
    s['mesh_routing'] = enabled;
    await _saveSettings(s);
  }



  int getConversationTtl(String conversationId) {
    return _getSettings()['ttl_$conversationId'] as int? ?? 0;
  }

  Future<void> setConversationTtl(String conversationId, int seconds) async {
    final s = _getSettings();
    s['ttl_$conversationId'] = seconds;
    await _saveSettings(s);
  }



  Future<void> clearAll() async {
    _ensureInitialized();
    await _messages!.clear();
    await _contacts!.clear();
    await _conversations!.clear();
    await _profile!.clear();
  }
}
