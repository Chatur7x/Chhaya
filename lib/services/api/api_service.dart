import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/message.dart';
import '../../core/models/contact.dart';
import '../../core/models/conversation.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String _baseUrl = 'https://api.chhaya.network';
  String? _authToken;
  String? _userId;

  String get baseUrl => _baseUrl;
  String? get authToken => _authToken;
  String? get userId => _userId;
  bool get isAuthenticated => _authToken != null;

  void setBaseUrl(String url) => _baseUrl = url;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
    _userId = prefs.getString('user_id');
    _baseUrl = prefs.getString('base_url') ?? _baseUrl;
  }

  Future<void> _saveAuth(String token, String userId) async {
    _authToken = token;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', userId);
  }

  Future<void> logout() async {
    _authToken = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
  }

  Map<String, String> _headers({bool auth = true}) => {
    'Content-Type': 'application/json',
    if (auth && _authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Future<T> _request<T>(String method, String path, 
      {Map<String, dynamic>? body, Map<String, String>? headers, T Function(dynamic)? parser}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final reqHeaders = {..._headers(), ...?headers};

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: reqHeaders);
        break;
      case 'POST':
        response = await http.post(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        response = await http.put(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: reqHeaders);
        break;
      default:
        throw ArgumentError('Unsupported method: $method');
    }

    if (response.statusCode >= 400) {
      final error = jsonDecode(response.body);
      throw ApiException(response.statusCode, error['error'] ?? 'Request failed', error['details']);
    }

    if (response.body.isEmpty) return null as T;
    final data = jsonDecode(response.body);
    return parser != null ? parser(data) : data as T;
  }

  // Auth
  Future<AuthResult> register({
    required String chhayaId,
    required String displayName,
    required String publicKey,
    required String encryptedPrivateKey,
    required String recoveryPhraseHash,
    required String deviceId,
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
      parser: (d) => Contact.fromJson(d),
    );
  }

  Future<List<Contact>> getContacts() async {
    return await _request('GET', '/api/v1/contacts',
      parser: (d) => (d as List).map((e) => Contact.fromJson(e)).toList(),
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
      parser: (d) => Conversation.fromJson(d),
    );
  }

  Future<List<Conversation>> getConversations() async {
    return await _request('GET', '/api/v1/conversations',
      parser: (d) => (d as List).map((e) => Conversation.fromJson(e)).toList(),
    );
  }

  // Messages
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    Map<String, dynamic>? mediaMeta,
    String? replyToId,
  }) async {
    return await _request('POST', '/api/v1/messages',
      body: {
        'conversationId': conversationId,
        'content': content,
        'messageType': messageType,
        'mediaUrl': mediaUrl,
        'mediaMeta': mediaMeta,
        'replyToId': replyToId,
      },
      parser: (d) => Message.fromJson(d),
    );
  }

  Future<List<Message>> getMessages(String conversationId, {int limit = 50, String? before}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/messages/$conversationId')
        .replace(queryParameters: {'limit': limit.toString(), if (before != null) 'before': before});
    final path = uri.toString().replaceFirst(_baseUrl, '');
    return await _request('GET', path,
      parser: (d) => (d as List).map((e) => Message.fromJson(e)).toList(),
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