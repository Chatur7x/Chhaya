// HTTP client for WS1's prekey bundle endpoint
// (GET /prekeys/:userId/bundle). Fail-closed: non-200, malformed JSON,
// structural or signature rejection — always an exception, never a
// partially filled bundle. No automatic retries: retry policy belongs to
// the establishment caller, and retries must never weaken parameters
// (spec §3.6). Explicitly invoked only; not wired into messaging yet.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/crypto/pqc/prekey_bundle.dart';
import '../../core/log.dart';

/// Thrown for any non-200 outcome or unreadable body. Carries the status
/// code and, when the server provided one, its error code string.
class PrekeyBundleFetchException implements Exception {
  final int statusCode;
  final String errorCode;
  const PrekeyBundleFetchException(this.statusCode, this.errorCode);
  @override
  String toString() => 'PrekeyBundleFetchException($statusCode): $errorCode';
}

class PrekeyBundleClient {
  PrekeyBundleClient({
    required String baseUrl,
    required this.authToken,
    http.Client? client,
  })  : _baseUrl = _validatedUrl(baseUrl),
        _client = client ?? http.Client();

  /// HTTPS origin of the Chhaya server (no path, no query). Always validated.
  String get baseUrl => _baseUrl;

  final String authToken;
  final String _baseUrl;
  final http.Client _client;

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

  static final RegExp _userIdPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Fetches, structurally parses, and signature-verifies the bundle for
  /// [userId]. Throws [PrekeyBundleException] or
  /// [PrekeyBundleFetchException] on any failure. Does not retry.
  Future<PrekeyBundle> fetchBundle(String userId, {DateTime? now}) async {
    if (!_userIdPattern.hasMatch(userId)) {
      throw ArgumentError.value(userId, 'userId', 'Must be a lowercase UUID');
    }
    final uri = Uri.parse('$_baseUrl/api/v1/prekeys/$userId/bundle');
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $authToken',
      'Accept': 'application/json',
    });
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
    } on Object {
      ChhayaLog.w(
        'prekey bundle fetch failed (network/timeout)',
        name: 'PrekeyBundleClient',
      );
      throw const PrekeyBundleFetchException(0, 'network_error');
    }
    if (response.statusCode != 200) {
      var code = 'http_${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String) {
          code = body['error'] as String;
        }
      } catch (_) {
        // Non-JSON error body: keep the status-derived code.
      }
      // Never log the body; it may carry server internals.
      ChhayaLog.w(
        'prekey bundle fetch rejected: HTTP ${response.statusCode}',
        name: 'PrekeyBundleClient',
      );
      throw PrekeyBundleFetchException(response.statusCode, code);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const PrekeyBundleFetchException(200, 'malformed_json');
    }
    final bundle = parsePrekeyBundle(decoded); // throws PrekeyBundleException
    await verifyPrekeyBundleSignatures(bundle, now: now);
    return bundle;
  }
}
