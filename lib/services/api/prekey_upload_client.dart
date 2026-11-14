// HTTP client for WS1's prekey upload endpoints
// (POST /api/v1/prekeys, POST /api/v1/prekeys/rotate).
//
// Fail-closed: non-2xx is always an exception carrying the status code and,
// when the server provided one, its error code (e.g. `feature_disabled`).
// No automatic retries: upload/rotate policy belongs to the caller. Explicitly
// invoked only; not enabled by default. Never logs or otherwise exposes key
// material — bodies are public prekey material only, and error paths parse
// only the server's `error` code string.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/log.dart';

/// Thrown for any non-2xx outcome, an unreadable body, or a network failure.
/// Carries the status code and, when the server provided one, its error code
/// string. Never contains key material.
class PrekeyUploadException implements Exception {
  final int statusCode;
  final String errorCode;
  const PrekeyUploadException(this.statusCode, this.errorCode);
  @override
  String toString() => 'PrekeyUploadException($statusCode): $errorCode';
}

class PrekeyUploadClient {
  PrekeyUploadClient({
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

  /// Uploads a freshly generated bundle (public material only, spec §3.2).
  /// Throws [PrekeyUploadException] on any non-2xx outcome. Does not retry.
  Future<void> uploadBundle(Map<String, dynamic> bundleJson) =>
      _post('/api/v1/prekeys', bundleJson);

  /// Rotates signed prekeys / the reseed key (spec §4.2).
  /// Throws [PrekeyUploadException] on any non-2xx outcome. Does not retry.
  Future<void> rotatePrekeys(Map<String, dynamic> rotationJson) =>
      _post('/api/v1/prekeys/rotate', rotationJson);

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.Request('POST', uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $authToken',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });
    request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
    } on Object {
      // No body, no key material — status class only.
      ChhayaLog.w(
        'prekey upload failed (network/timeout)',
        name: 'PrekeyUploadClient',
      );
      throw const PrekeyUploadException(0, 'network_error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var code = 'http_${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          code = decoded['error'] as String;
        }
      } catch (_) {
        // Non-JSON error body: keep the status-derived code.
      }
      // Never log the body; it may carry server internals or echo material.
      ChhayaLog.w(
        'prekey upload rejected: HTTP ${response.statusCode}',
        name: 'PrekeyUploadClient',
      );
      throw PrekeyUploadException(response.statusCode, code);
    }
  }
}
