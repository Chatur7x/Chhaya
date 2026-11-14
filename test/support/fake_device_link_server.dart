// In-memory fake of the DL-A authenticated device linking API
// (backend/server/src/devices.ts, docs/spec-device-linking-v1.md §4) for
// unit tests. Mirrors the contract: request → approve → status → consume,
// list, revoke; 5-minute expiry; one-shot consume; idempotent approve.
// State lives in memory only; nothing is persisted.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeDeviceLinkServer {
  int _counter = 0;
  final Map<String, _LinkRow> _requests = {};
  final List<Map<String, Object?>> _devices = [];
  final List<Map<String, String?>> _events = [];
  final Map<String, _Session> _sessions = {};

  /// Issues a device-bound account session token (the P side). The primary
  /// device id is a valid uuid so self-revoke is refused like production.
  String issueAccountToken({
    required String userId,
    required String primaryDeviceId,
  }) {
    final token = 'account-${_counter++}';
    _sessions[token] = _Session(userId: userId, deviceId: primaryDeviceId);
    _devices.add({
      'id': primaryDeviceId,
      'device_name': 'Primary phone',
      'platform': 'android',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'last_active_at': null,
      'revoked_at': null,
    });
    return token;
  }

  /// Seeds an already-linked device (for list/revoke tests).
  void seedDevice({
    required String deviceId,
    required String userId,
    required String name,
    required String platform,
    DateTime? revokedAt,
  }) {
    _devices.add({
      'id': deviceId,
      'device_name': name,
      'platform': platform,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'last_active_at': null,
      'revoked_at': revokedAt?.toUtc().toIso8601String(),
    });
  }

  List<String> get auditEvents =>
      _events.map((e) => '${e['action']}').toList(growable: false);

  MockClient client() => MockClient(_handle);

  // ----------------------------------------------------------------------

  static String _uuid() {
    final bytes = List<int>.generate(16, (i) => (DateTime.now().microsecondsSinceEpoch + i * 37) & 0xFF);
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String h(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${h(bytes[0])}${h(bytes[1])}${h(bytes[2])}${h(bytes[3])}-'
        '${h(bytes[4])}${h(bytes[5])}-${h(bytes[6])}${h(bytes[7])}-'
        '${h(bytes[8])}${h(bytes[9])}-'
        '${List.generate(6, (i) => h(bytes[10 + i])).join()}';
  }

  static String _sha256Hex(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  String? _bearer(http.Request request) {
    final header = request.headers['Authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  _Session? _sessionFor(http.Request request) {
    final token = _bearer(request);
    if (token == null) return null;
    return _sessions[token];
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    final method = request.method;

    if (method == 'POST' && path == '/api/v1/devices/link/request') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final deviceId = body['deviceId'] as String;
      final now = DateTime.now().toUtc();
      final existing = _requests.values.where(
        (r) => r.deviceId == deviceId &&
            (r.state == 'pending' || r.state == 'approved') &&
            r.expiresAt.isAfter(now),
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        return _json(200, {
          'requestId': row.requestId,
          'expiresAt': row.expiresAt.toIso8601String(),
        });
      }
      final row = _LinkRow(
        requestId: _uuid(),
        deviceId: deviceId,
        deviceName: body['deviceName'] as String,
        platform: body['platform'] as String,
        devicePublicKey: body['devicePublicKey'] as String,
        ephemeralPublicKey: body['ephemeralPublicKey'] as String?,
        codeHash: body['codeHash'] as String,
        expiresAt: now.add(const Duration(minutes: 5)),
      );
      _requests[row.requestId] = row;
      _events.add({'action': 'request', 'device_id': deviceId});
      return _json(201, {
        'requestId': row.requestId,
        'expiresAt': row.expiresAt.toIso8601String(),
      });
    }

    if (method == 'POST' && path == '/api/v1/devices/link/approve') {
      final session = _sessionFor(request);
      if (session == null) {
        return _json(401, {'error': 'Invalid or expired token', 'code': 'not_authenticated'});
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final requestId = body['requestId'] as String;
      final row = _requests[requestId];
      if (row == null) return _json(404, {'error': 'Not found', 'code': 'not_found'});
      final now = DateTime.now().toUtc();
      if (!row.expiresAt.isAfter(now)) {
        _requests.remove(requestId);
        return _json(410, {'error': 'Link request expired', 'code': 'link_expired'});
      }
      if (_sha256Hex(body['code'] as String) != row.codeHash) {
        return _json(403, {'error': 'Code mismatch', 'code': 'code_mismatch'});
      }
      if (body['action'] == 'approve') {
        if (row.state == 'approved') {
          final identical = row.userId == session.userId &&
              row.approval == body['approval'] &&
              row.approvalSignature == body['approvalSignature'] &&
              row.primEphPub == body['primEphPub'];
          if (identical) return _json(200, {'state': 'approved', 'idempotent': true});
          return _json(409, {'error': 'request_already_claimed', 'code': row.userId != session.userId ? 'request_already_claimed' : 'invalid_state'});
        }
        if (row.state != 'pending') return _json(409, {'error': 'invalid_state', 'code': 'invalid_state'});
        row.state = 'approved';
        row.userId = session.userId;
        row.approval = body['approval'] as String?;
        row.approvalSignature = body['approvalSignature'] as String?;
        row.primEphPub = body['primEphPub'] as String?;
        _events.add({'action': 'approve', 'device_id': row.deviceId});
        return _json(200, {'state': 'approved', 'idempotent': false});
      }
      // deny
      if (row.state == 'denied') return _json(200, {'state': 'denied', 'idempotent': true});
      if (row.state != 'pending') return _json(409, {'error': 'invalid_state', 'code': 'invalid_state'});
      row.state = 'denied';
      row.userId = session.userId;
      _events.add({'action': 'deny', 'device_id': row.deviceId});
      return _json(200, {'state': 'denied', 'idempotent': false});
    }

    if (method == 'GET' && path.startsWith('/api/v1/devices/link/status/')) {
      final requestId = path.substring('/api/v1/devices/link/status/'.length);
      final row = _requests[requestId];
      if (row == null) return _json(404, {'error': 'Not found', 'code': 'not_found'});
      final now = DateTime.now().toUtc();
      if (!row.expiresAt.isAfter(now)) {
        _requests.remove(requestId);
        return _json(410, {'error': 'Link request expired', 'code': 'link_expired'});
      }
      if (row.state == 'approved') {
        return _json(200, {
          'state': 'approved',
          'approval': row.approval,
          'approvalSignature': row.approvalSignature,
          'primEphPub': row.primEphPub,
          'expiresAt': row.expiresAt.toIso8601String(),
        });
      }
      return _json(200, {'state': row.state, 'expiresAt': row.expiresAt.toIso8601String()});
    }

    if (method == 'POST' && path == '/api/v1/devices/link/consume') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final requestId = body['requestId'] as String;
      final row = _requests[requestId];
      if (row == null) return _json(404, {'error': 'Not found', 'code': 'not_found'});
      final now = DateTime.now().toUtc();
      if (!row.expiresAt.isAfter(now)) {
        _requests.remove(requestId);
        return _json(410, {'error': 'Link request expired', 'code': 'link_expired'});
      }
      if (_sha256Hex(body['code'] as String) != row.codeHash) {
        return _json(403, {'error': 'Code mismatch', 'code': 'code_mismatch'});
      }
      if (row.state != 'approved' || row.userId == null) {
        return _json(409, {'error': 'invalid_state', 'code': 'invalid_state'});
      }
      row.state = 'consumed';
      _devices.add({
        'id': row.deviceId,
        'device_name': row.deviceName,
        'platform': row.platform,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'last_active_at': null,
        'revoked_at': null,
        'user_id': row.userId,
      });
      final token = 'device-${_counter++}';
      _sessions[token] = _Session(userId: row.userId!, deviceId: row.deviceId);
      _events.add({'action': 'consume', 'device_id': row.deviceId});
      return _json(200, {'userId': row.userId, 'deviceId': row.deviceId, 'token': token});
    }

    if (method == 'GET' && path == '/api/v1/devices') {
      final session = _sessionFor(request);
      if (session == null) {
        return _json(401, {'error': 'Invalid or expired token', 'code': 'not_authenticated'});
      }
      final rows = _devices
          .where((d) => d['user_id'] == null || d['user_id'] == session.userId)
          .toList();
      return _json(200, [
        for (final d in rows)
          {
            'deviceId': d['id'],
            'name': d['device_name'],
            'platform': d['platform'],
            'createdAt': d['created_at'],
            'lastActiveAt': d['last_active_at'],
            'isCurrent': d['id'] == session.deviceId,
            'revokedAt': d['revoked_at'],
          },
      ]);
    }

    if (method == 'DELETE' && path.startsWith('/api/v1/devices/')) {
      final session = _sessionFor(request);
      if (session == null) {
        return _json(401, {'error': 'Invalid or expired token', 'code': 'not_authenticated'});
      }
      final deviceId = path.substring('/api/v1/devices/'.length);
      if (session.deviceId == deviceId) {
        return _json(400, {'error': 'Cannot revoke the device you are calling from; use logout', 'code': 'use_logout'});
      }
      final row = _devices.where((d) => d['id'] == deviceId).firstOrNull;
      if (row == null) return _json(404, {'error': 'Not found', 'code': 'not_found'});
      if (row['revoked_at'] != null) return _json(200, {'revoked': true});
      row['revoked_at'] = DateTime.now().toUtc().toIso8601String();
      _sessions.removeWhere((_, s) => s.deviceId == deviceId);
      _events.add({'action': 'revoke', 'device_id': deviceId});
      return _json(200, {'revoked': true});
    }

    return _json(404, {'error': 'Not found', 'code': 'not_found'});
  }

  /// Forces every link request to be expired (test-only lever).
  void debugExpireAll() {
    for (final row in _requests.values) {
      row.expiresAt = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    }
  }

  /// Corrupts the stored approval for [requestId] (test-only MITM lever).
  void tamperApproval(String requestId, {required String target}) {
    final row = _requests[requestId];
    if (row == null) return;
    switch (target) {
      case 'approval':
        final bytes = base64Decode(row.approval!);
        bytes[bytes.length ~/ 2] ^= 0x01;
        row.approval = base64Encode(bytes);
        return;
      case 'primEphPub':
        final bytes = [
          for (final b in _hexToBytes(row.primEphPub!)) b ^ 0x01,
        ];
        row.primEphPub = _hex(bytes);
        return;
      case 'signature':
        final bytes = _hexToBytes(row.approvalSignature!);
        bytes[0] ^= 0x01;
        row.approvalSignature = _hex(bytes);
        return;
      default:
        throw ArgumentError.value(target, 'target', 'Unknown tamper target');
    }
  }

  static List<int> _hexToBytes(String hex) =>
      [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Device revoke helper: checks a device token is now invalid.
  bool isDeviceTokenValid(String token) => _sessions.containsKey(token);

  http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

class _LinkRow {
  _LinkRow({
    required this.requestId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.devicePublicKey,
    required this.ephemeralPublicKey,
    required this.codeHash,
    required this.expiresAt,
  });

  final String requestId;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String devicePublicKey;
  final String? ephemeralPublicKey;
  final String codeHash;
  DateTime expiresAt;
  String state = 'pending';
  String? userId;
  String? approval;
  String? approvalSignature;
  String? primEphPub;
}

class _Session {
  _Session({required this.userId, required this.deviceId});
  final String userId;
  final String? deviceId;
}
