import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/message.dart';
import '../../core/models/contact.dart';
import '../../core/models/conversation.dart';
import '../../core/models/chhaya_id.dart';
import '../../core/crypto/key_manager.dart';
import '../auth/identity_challenge_proof.dart';
import '../../core/crypto/chhaya_crypto_engine.dart';
import '../../core/crypto/storage/secure_storage.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String _baseUrl = const String.fromEnvironment('CHHAYA_API_URL');
  final SecureStorage _secure = SecureStorages.platformDefault();
  String? _deviceId;
  String? get deviceId => _deviceId;
  bool get isConfigured => _baseUrl.isNotEmpty;
  String? _authToken;
  String? _userId;

  String get baseUrl => _baseUrl;
  String? get authToken => _authToken;
  String? get userId => _userId;
  bool get isAuthenticated => _authToken != null;

  void setBaseUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError('Use the HTTPS origin of your Chhaya server');
    }
    _baseUrl = uri.toString().replaceFirst(RegExp(r'/$'), '');
  }

  Future<void> connectAccount(String url, UserProfile profile, KeyManager keys) async {
    await logout();
    setBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', _baseUrl);
    _deviceId = await _secure.read(key: 'chhaya_device_id') ?? const Uuid().v4();
    await _secure.write(key: 'chhaya_device_id', value: _deviceId!);
    final proof = ChhayaCryptoEngine().hashString(profile.recoveryPhrase.join(' '));
    final pair = await keys.getKeyPair();
    if(pair == null) { throw StateError('Identity keys unavailable'); }
    // The server receives only a passphrase-encrypted private-key backup.
    final wrappingKey = ChhayaCryptoEngine.keyFromRecoveryPhrase(profile.recoveryPhrase.join(' '));
    final encrypted = await ChhayaCryptoEngine().encryptMessage(base64Encode(pair.privateKey), wrappingKey);
    wrappingKey.fillRange(0, wrappingKey.length, 0);
    final registration=await _identityClaim('register',pair,_deviceId!);
    try {
      await register(chhayaId: profile.chhayaId.publicKey, displayName: profile.displayName,
        publicKey: pair.publicKeyHex, encryptedPrivateKey: encrypted, recoveryPhraseHash: proof,
        deviceId: _deviceId!, platform: 'flutter',
        challengeId:registration['challengeId'],identityProof:registration['proof']);
    } on ApiException catch (error) {
      if (error.statusCode != 409) rethrow;
      final loginClaim=await _identityClaim('login',pair,_deviceId!);
      await login(chhayaId:profile.chhayaId.publicKey,recoveryPhraseHash:proof,deviceId:_deviceId!,
        challengeId:loginClaim['challengeId'],identityProof:loginClaim['proof']);
    }
  }

  Future<Map<String,String>> _identityClaim(String purpose,ChhayaKeyPair pair,String deviceId) async {
    final challenge=await _request<Map<String,dynamic>>('POST','/api/v1/auth/challenge',
      body:{'purpose':purpose,'publicKey':pair.publicKeyHex,'deviceId':deviceId});
    final proof=await IdentityChallengeProof.create(identity:pair,purpose:purpose,deviceId:deviceId,challenge:challenge);
    return {'challengeId':challenge['challengeId'] as String,'proof':proof};
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = await _secure.read(key: 'chhaya_auth_token');
    await prefs.remove('auth_token');
    _deviceId = await _secure.read(key: 'chhaya_device_id');
    _userId = prefs.getString('user_id');
    _baseUrl = prefs.getString('base_url') ?? _baseUrl;
  }

  Future<void> _saveAuth(String token, String userId) async {
    _authToken = token;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: 'chhaya_auth_token', value: token);
    await prefs.setString('user_id', userId);
  }

  Future<void> logout() async {
    if(isAuthenticated&&isConfigured) {
      try { await _request<dynamic>('POST','/api/v1/auth/logout'); } catch (_) { /* Local logout must remain possible offline. */ }
    }
    _authToken = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: 'chhaya_auth_token');
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
  }

  Map<String, String> _headers({bool auth = true}) => {
    'Content-Type': 'application/json',
    if (auth && _authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Future<T> _request<T>(String method, String path, 
      {Map<String, dynamic>? body, Map<String, String>? headers, T Function(dynamic)? parser}) async {
    if(!isConfigured) { throw StateError('Configure your HTTPS server in Settings first'); }
    final uri = Uri.parse('$_baseUrl$path');
    final reqHeaders = {..._headers(), ...?headers};

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: reqHeaders).timeout(const Duration(seconds: 15));
        break;
      case 'POST':
        response = await http.post(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null).timeout(const Duration(seconds: 15));
        break;
      case 'PUT':
        response = await http.put(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null).timeout(const Duration(seconds: 15));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: reqHeaders).timeout(const Duration(seconds: 15));
        break;
      default:
        throw ArgumentError('Unsupported method: $method');
    }

    if (response.statusCode >= 400) {
      Map<String, dynamic> error = {};
      try { error = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
      throw ApiException(response.statusCode, error['error'] as String? ?? 'Server request failed', null);
    }

    if(response.body.isEmpty) { return null as T; }
    final data = jsonDecode(response.body);
    return parser != null ? parser(data) : data as T;
  }

  Contact _contact(Map<String, dynamic> row) => Contact(
    id: row['id'] as String,
    chhayaId: ChhayaId.fromPublicKey(row['chhaya_id'] as String),
    displayName: row['display_name'] as String? ?? 'Contact',
    isBlocked: row['is_blocked'] as bool? ?? false,
  );

  Conversation _conversation(Map<String, dynamic> row) => Conversation(
    id: row['id'] as String,
    participants: ((row['participants'] as List?) ?? []).map((p) => _contact(Map<String, dynamic>.from(p as Map)))
        .where((p) => p.id != _userId).toList(),
    unreadCount: int.tryParse('${row['unread_count']}') ?? 0,
    isGroup: row['type'] == 'group', groupName: row['name'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  Message _message(Map<String, dynamic> row) => Message(
    id: row['id'] as String, conversationId: row['conversation_id'] as String,
    senderId: row['sender_id'] as String, content: row['content'] as String,
    timestamp: DateTime.parse(row['sent_at'] as String),
    isRead: row['read_at'] != null, isDelivered: row['delivered_at'] != null,
  );

  // Auth
  Future<AuthResult> register({
    required String chhayaId,
    required String displayName,
    required String publicKey,
    required String encryptedPrivateKey,
    required String recoveryPhraseHash,
    required String deviceId,
    String? challengeId,
    String? identityProof,
    String? deviceName,
    String? platform,
    String? fcmToken,
  }) async {
    final data = await _request('POST', '/api/v1/auth/register',
      body: {
        'chhayaId': chhayaId,
        'displayName': displayName,
        'publicKey': publicKey,
        'encryptedPrivateKey': encryptedPrivateKey,
        'recoveryPhraseHash': recoveryPhraseHash,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'fcmToken': fcmToken,
      },
      parser: (d) => AuthResult.fromJson(d),
    );
    await _saveAuth(data.token, data.userId);
    return data;
  }

  Future<AuthResult> login({
    required String chhayaId,
    required String recoveryPhraseHash,
    required String deviceId,
    String? challengeId,
    String? identityProof,
    String? deviceName,
    String? platform,
    String? fcmToken,
  }) async {
    final data = await _request('POST', '/api/v1/auth/login',
      body: {
        'chhayaId': chhayaId,
        'recoveryPhraseHash': recoveryPhraseHash,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'fcmToken': fcmToken,
      },
      parser: (d) => AuthResult.fromJson(d),
    );
    await _saveAuth(data.token, data.userId);
    return data;
  }

  // User
  Future<UserProfile> getCurrentUser() async {
    return await _request('GET', '/api/v1/users/me',
      parser: (d) => UserProfile.fromJson(d),
    );
  }

  Future<void> updateSettings({
    bool? biometricEnabled,
    String? pin,
    String? panicPin,
    bool? readReceipts,
    int? disappearingDuration,
    bool? onionRouting,
    bool? notifications,
  }) async {
    await _request('PUT', '/api/v1/users/me/settings', body: {
      if (biometricEnabled != null) 'biometricEnabled': biometricEnabled,
      if (pin != null) 'pin': pin,
      if (panicPin != null) 'panicPin': panicPin,
      if (readReceipts != null) 'readReceipts': readReceipts,
      if (disappearingDuration != null) 'disappearingDuration': disappearingDuration,
      if (onionRouting != null) 'onionRouting': onionRouting,
      if (notifications != null) 'notifications': notifications,
    });
  }

  // Contacts
  Future<Contact> addContact({
    required String chhayaId,
    required String displayName,
  }) async {
    return await _request('POST', '/api/v1/contacts',
      body: {'chhayaId': chhayaId, 'displayName': displayName},
      parser: (d) => Contact(id: d['contactId'] as String, chhayaId: ChhayaId.fromPublicKey(chhayaId), displayName: displayName),
    );
  }

  Future<List<Contact>> getContacts() async {
    return await _request('GET', '/api/v1/contacts',
      parser: (d) => (d as List).map((e) => _contact(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  // Conversations
  Future<Conversation> createConversation({
    required String type,
    required List<String> participantIds,
    String? name,
    String? avatarUrl,
  }) async {
    return await _request('POST', '/api/v1/conversations',
      body: {'type': type, 'participantIds': participantIds, 'name': name, 'avatarUrl': avatarUrl},
      parser: (d) => Conversation(id: d['conversationId'] as String, participants: const [], isGroup: type == 'group', groupName: name, createdAt: DateTime.now()),
    );
  }

  Future<List<Conversation>> getConversations() async {
    return await _request('GET', '/api/v1/conversations',
      parser: (d) => (d as List).map((e) => _conversation(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  // Messages
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String messageType = 'text',
    String? messageId,
    String? mediaUrl,
    Map<String, dynamic>? mediaMeta,
    String? replyToId,
  }) async {
    return await _request('POST', '/api/v1/messages',
      body: {
        if (messageId != null) 'messageId': messageId,
        'conversationId': conversationId,
        'content': content,
        'messageType': messageType,
        'mediaUrl': mediaUrl,
        'mediaMeta': mediaMeta,
        'replyToId': replyToId,
      },
      parser: (d) => _message(Map<String, dynamic>.from(d as Map)),
    );
  }

  Future<List<Message>> getMessages(String conversationId, {int limit = 50, String? before}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/messages/$conversationId')
        .replace(queryParameters: {'limit': limit.toString(), if (before != null) 'before': before});
    final path = uri.toString().replaceFirst(_baseUrl, '');
    return await _request('GET', path,
      parser: (d) => (d as List).map((e) => _message(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Future<void> markMessagesRead(String messageId) async {
    await _request('POST', '/api/v1/messages/$messageId/read');
  }

  // Devices
  Future<void> linkDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String publicKey,
  }) async {
    await _request('POST', '/api/v1/devices/link', body: {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'publicKey': publicKey,
    });
  }

  // Push
  Future<void> subscribePush({
    required String endpoint,
    required String p256dh,
    required String auth,
  }) async {
    await _request('POST', '/api/v1/push/subscribe', body: {
      'endpoint': endpoint,
      'keys': {'p256dh': p256dh, 'auth': auth},
    });
  }

  // Onion
  Future<List<OnionNode>> getOnionNodes() async {
    return await _request('GET', '/api/v1/onion/nodes',
      parser: (d) => (d as List).map((e) => OnionNode.fromJson(e)).toList(),
    );
  }

  Future<List<OnionNode>> getOnionPath({int hops = 3, String? excludeRegion}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/onion/path')
        .replace(queryParameters: {'hops': hops.toString(), if (excludeRegion != null) 'excludeRegion': excludeRegion});
    final path = uri.toString().replaceFirst(_baseUrl, '');
    return await _request('GET', path,
      parser: (d) => (d as List).map((e) => OnionNode.fromJson(e)).toList(),
    );
  }
}

class AuthResult {
  final String userId;
  final String token;
  AuthResult({required this.userId, required this.token});
  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(userId: json['userId'], token: json['token']);
}

class OnionNode {
  final String id;
  final String address;
  final String region;
  final int latencyMs;
  final double reliability;
  OnionNode({required this.id, required this.address, required this.region, required this.latencyMs, required this.reliability});
  factory OnionNode.fromJson(Map<String, dynamic> json) => OnionNode(
    id: json['id'], address: json['address'], region: json['region'],
    latencyMs: json['latencyMs'] ?? json['latency_ms'], reliability: (json['reliability'] as num).toDouble(),
  );
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;
  ApiException(this.statusCode, this.message, this.details);
  @override String toString() => 'ApiException($statusCode): $message';
}