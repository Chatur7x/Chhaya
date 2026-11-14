// HTTP client for the DL-A authenticated device linking endpoints
// (docs/spec-device-linking-v1.md §4.4). Fail-closed: non-200, malformed
// JSON, or structural rejection — always an exception, never a partially
// filled result. No automatic retries: retry policy belongs to the caller,
// and retries must never weaken parameters. Explicitly invoked only.
//
// Never logs request/response bodies or key material. Status codes and
// server error codes only (spec §4.6 store-only-public-material rule).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/log.dart';

/// Thrown for any non-200 outcome or unreadable body. Carries the status
/// code and, when the server provided one, its error code string. Never
/// carries request or response payload bytes.
class DeviceLinkException implements Exception {
  final int statusCode;
  final String errorCode;
  const DeviceLinkException(this.statusCode, this.errorCode);
  @override
  String toString() => 'DeviceLinkException($statusCode): $errorCode';
}

class DeviceLinkRequestResult {
  final String requestId;
  final DateTime expiresAt;
  const DeviceLinkRequestResult({required this.requestId, required this.expiresAt});
}

class DeviceLinkStatusResult {
  final String state;
  final String? approval; // base64 AEAD blob, present when state == 'approved'
  final String? approvalSignature; // hex ed25519, present when state == 'approved'
  final String? primEphPub; // hex x25519, present when state == 'approved'
  final DateTime? expiresAt;
  const DeviceLinkStatusResult({
    required this.state,
    this.approval,
    this.approvalSignature,
    this.primEphPub,
    this.expiresAt,
  });
}

class DeviceLinkApproveResult {
  final String state; // 'approved' | 'denied'
  final bool idempotent;
  const DeviceLinkApproveResult({required this.state, required this.idempotent});
}

class DeviceLinkConsumeResult {
  final String userId;
  final String deviceId;
  final String token;
  const DeviceLinkConsumeResult({
    required this.userId,
    required this.deviceId,
    required this.token,
  });
}

class LinkedDevice {
  final String deviceId;
  final String? name;
  final String? platform;
  final DateTime createdAt;
  final DateTime? lastActiveAt;
  final bool isCurrent;
  final DateTime? revokedAt;
  const LinkedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastActiveAt,
    required this.isCurrent,
    required this.revokedAt,
  });
}

class DeviceLinkClient {
  /// HTTPS origin of the Chhaya server (no path, no query). Always validated.
  /// [authToken] is required for the authenticated calls (approve, list,
  /// revoke); the unauthenticated calls (request, status, consume) never
  /// send it.
  DeviceLinkClient({
    required String baseUrl,
    this.authToken,
    this.tokenProvider,
    http.Client? client,
  })  : _baseUrl = _validatedUrl(baseUrl),
        _client = client ?? http.Client();

  /// Static bearer token (prekey-bundle style). When [tokenProvider] is set
  /// it takes precedence so authenticated calls always see the freshest
  /// session token.
  final String? authToken;

  /// Optional live token source, evaluated per authenticated call.
  final Future<String?> Function()? tokenProvider;
  final String _baseUrl;
  final http.Client _client;

  String get baseUrl => _baseUrl;

  static String _validatedUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError('Use the HTTPS origin of your Chhaya server');
    }
    return uri.toString().replaceFirst(RegExp(r'/$'), '');
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final RegExp _hex64Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _hex128Pattern = RegExp(r'^[0-9a-f]{128}$');

  Future<String> _requireToken() async {
    final provider = tokenProvider;
    final token = provider != null ? await provider() : authToken;
    if (token == null || token.isEmpty) {
      throw StateError('This call requires an authenticated account session');
    }
    return token;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      request.headers['Authorization'] = 'Bearer ${await _requireToken()}';
    }
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
    } on Object {
      ChhayaLog.w(
        'device link request failed (network/timeout): $method $path',
        name: 'DeviceLinkClient',
      );
      throw const DeviceLinkException(0, 'network_error');
    }
  }

  /// Maps a non-200 response to a [DeviceLinkException] using only the
  /// server's `code`/`error` strings. The body itself is never logged or
  /// carried in the exception.
  DeviceLinkException _errorFor(http.Response response, String operation) {
    var code = 'http_${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final serverCode = body['code'];
        final serverError = body['error'];
        if (serverCode is String && serverCode.isNotEmpty) {
          code = serverCode;
        } else if (serverError is String && serverError.isNotEmpty) {
          code = serverError;
        }
      }
    } catch (_) {
      // Non-JSON error body: keep the status-derived code.
    }
    ChhayaLog.w(
      'device link call rejected: $operation HTTP ${response.statusCode}',
      name: 'DeviceLinkClient',
    );
    return DeviceLinkException(response.statusCode, code);
  }

  Map<String, dynamic> _decodeObject(http.Response response, String operation) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    if (decoded is! Map) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    return Map<String, dynamic>.from(decoded);
  }

  DateTime? _parseTime(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  /// POST /api/v1/devices/link/request — new (unenrolled) device registers a
  /// pending link. Unauthenticated. Idempotent server-side for a live
  /// pending request with the same deviceId (201 created / 200 reused).
  Future<DeviceLinkRequestResult> requestLink({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String devicePublicKey,
    required String ephemeralPublicKey,
    required String codeHash,
  }) async {
    if (!_uuidPattern.hasMatch(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must be a lowercase UUID');
    }
    for (final entry in {
      'devicePublicKey': devicePublicKey,
      'ephemeralPublicKey': ephemeralPublicKey,
      'codeHash': codeHash,
    }.entries) {
      if (!_hex64Pattern.hasMatch(entry.value)) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be 64 lowercase hex chars');
      }
    }
    final response = await _send(
      'POST',
      '/api/v1/devices/link/request',
      body: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'devicePublicKey': devicePublicKey,
        'ephemeralPublicKey': ephemeralPublicKey,
        'codeHash': codeHash,
      },
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _errorFor(response, 'link/request');
    }
    final body = _decodeObject(response, 'link/request');
    final requestId = body['requestId'];
    final expiresAt = _parseTime(body['expiresAt']);
    if (requestId is! String || !_uuidPattern.hasMatch(requestId) || expiresAt == null) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    return DeviceLinkRequestResult(requestId: requestId, expiresAt: expiresAt);
  }

  /// POST /api/v1/devices/link/approve — authenticated account session
  /// approves or denies a pending link. For approval the caller must also
  /// pass the AEAD [approval] blob (base64), its Ed25519 [approvalSignature]
  /// (hex, 128 chars) and the primary's ephemeral X25519 public key
  /// [primEphPub] (hex, 64 chars). For denial, payload fields must be null.
  Future<DeviceLinkApproveResult> approveLink({
    required String requestId,
    required String code,
    required String action, // 'approve' | 'deny'
    String? approval,
    String? approvalSignature,
    String? primEphPub,
  }) async {
    if (!_uuidPattern.hasMatch(requestId)) {
      throw ArgumentError.value(requestId, 'requestId', 'Must be a lowercase UUID');
    }
    if (code.isEmpty || code.length > 128) {
      throw ArgumentError.value(code, 'code', 'Must be 1..128 chars');
    }
    if (action != 'approve' && action != 'deny') {
      throw ArgumentError.value(action, 'action', 'Must be "approve" or "deny"');
    }
    if (action == 'approve') {
      if (approval == null || approval.isEmpty || approval.length > 16384) {
        throw ArgumentError.value(approval, 'approval', 'Approval payload required');
      }
      if (approvalSignature == null || !_hex128Pattern.hasMatch(approvalSignature)) {
        throw ArgumentError.value(approvalSignature, 'approvalSignature', 'Must be 128 lowercase hex chars');
      }
      if (primEphPub == null || !_hex64Pattern.hasMatch(primEphPub)) {
        throw ArgumentError.value(primEphPub, 'primEphPub', 'Must be 64 lowercase hex chars');
      }
    }
    final response = await _send(
      'POST',
      '/api/v1/devices/link/approve',
      authenticated: true,
      body: {
        'requestId': requestId,
        'code': code,
        'action': action,
        if (approval != null) 'approval': approval,
        if (approvalSignature != null) 'approvalSignature': approvalSignature,
        if (primEphPub != null) 'primEphPub': primEphPub,
      },
    );
    if (response.statusCode != 200) {
      throw _errorFor(response, 'link/approve');
    }
    final body = _decodeObject(response, 'link/approve');
    final state = body['state'];
    if (state is! String || (state != 'approved' && state != 'denied')) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    return DeviceLinkApproveResult(
      state: state,
      idempotent: body['idempotent'] == true,
    );
  }

  /// GET /api/v1/devices/link/status/{requestId} — unauthenticated poll for
  /// the new device. 410 (link_expired) and 404 (not_found) surface as
  /// [DeviceLinkException]; callers must fail closed.
  Future<DeviceLinkStatusResult> linkStatus({required String requestId}) async {
    if (!_uuidPattern.hasMatch(requestId)) {
      throw ArgumentError.value(requestId, 'requestId', 'Must be a lowercase UUID');
    }
    final response = await _send('GET', '/api/v1/devices/link/status/$requestId');
    if (response.statusCode != 200) {
      throw _errorFor(response, 'link/status');
    }
    final body = _decodeObject(response, 'link/status');
    final state = body['state'];
    if (state is! String) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    final approval = body['approval'] as String?;
    final approvalSignature = body['approvalSignature'] as String?;
    final primEphPub = body['primEphPub'] as String?;
    if (state == 'approved') {
      if (approval == null || approval.isEmpty ||
          approvalSignature == null || !_hex128Pattern.hasMatch(approvalSignature) ||
          primEphPub == null || !_hex64Pattern.hasMatch(primEphPub)) {
        throw DeviceLinkException(response.statusCode, 'malformed_json');
      }
    }
    return DeviceLinkStatusResult(
      state: state,
      approval: approval,
      approvalSignature: approvalSignature,
      primEphPub: primEphPub,
      expiresAt: _parseTime(body['expiresAt']),
    );
  }

  /// POST /api/v1/devices/link/consume — one-shot claim by the new device.
  /// Returns the freshly minted per-device session token.
  Future<DeviceLinkConsumeResult> consumeLink({
    required String requestId,
    required String code,
  }) async {
    if (!_uuidPattern.hasMatch(requestId)) {
      throw ArgumentError.value(requestId, 'requestId', 'Must be a lowercase UUID');
    }
    if (code.isEmpty || code.length > 128) {
      throw ArgumentError.value(code, 'code', 'Must be 1..128 chars');
    }
    final response = await _send(
      'POST',
      '/api/v1/devices/link/consume',
      body: {'requestId': requestId, 'code': code},
    );
    if (response.statusCode != 200) {
      throw _errorFor(response, 'link/consume');
    }
    final body = _decodeObject(response, 'link/consume');
    final userId = body['userId'];
    final deviceId = body['deviceId'];
    final token = body['token'];
    if (userId is! String || deviceId is! String || !_uuidPattern.hasMatch(deviceId) ||
        token is! String || token.isEmpty) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    return DeviceLinkConsumeResult(userId: userId, deviceId: deviceId, token: token);
  }

  /// GET /api/v1/devices — list the account's devices, revoked rows included
  /// (flagged via [LinkedDevice.revokedAt]). Authenticated.
  Future<List<LinkedDevice>> listDevices() async {
    final response = await _send('GET', '/api/v1/devices', authenticated: true);
    if (response.statusCode != 200) {
      throw _errorFor(response, 'devices/list');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    if (decoded is! List) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
    final out = <LinkedDevice>[];
    for (final entry in decoded) {
      if (entry is! Map) {
        throw DeviceLinkException(response.statusCode, 'malformed_json');
      }
      final row = Map<String, dynamic>.from(entry);
      final deviceId = row['deviceId'];
      final createdAt = _parseTime(row['createdAt']);
      if (deviceId is! String || !_uuidPattern.hasMatch(deviceId) || createdAt == null) {
        throw DeviceLinkException(response.statusCode, 'malformed_json');
      }
      out.add(LinkedDevice(
        deviceId: deviceId,
        name: row['name'] as String?,
        platform: row['platform'] as String?,
        createdAt: createdAt,
        lastActiveAt: _parseTime(row['lastActiveAt']),
        isCurrent: row['isCurrent'] == true,
        revokedAt: _parseTime(row['revokedAt']),
      ));
    }
    return out;
  }

  /// DELETE /api/v1/devices/{deviceId} — soft revoke; the server invalidates
  /// the device's sessions in one transaction. Authenticated. Idempotent
  /// server-side (already revoked → 200). Self-revocation is refused
  /// server-side with 400 `use_logout`.
  Future<void> revokeDevice({required String deviceId}) async {
    if (!_uuidPattern.hasMatch(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must be a lowercase UUID');
    }
    final response = await _send(
      'DELETE',
      '/api/v1/devices/$deviceId',
      authenticated: true,
    );
    if (response.statusCode != 200) {
      throw _errorFor(response, 'devices/revoke');
    }
    final body = _decodeObject(response, 'devices/revoke');
    if (body['revoked'] != true) {
      throw DeviceLinkException(response.statusCode, 'malformed_json');
    }
  }
}
