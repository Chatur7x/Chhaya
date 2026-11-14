// Authenticated device linking (DL-B, docs/spec-device-linking-v1.md).
//
// ignore_for_file: prefer_initializing_formals -- private fields are initialized
// from differently named parameters to keep call sites readable.
//
// Client-side half of the link protocol: ephemeral X25519 + device Ed25519
// keys per attempt, the one-time code, fingerprint derivation (spec §3.3/§3.5),
// AEAD verification of the primary's approval, consume, and the local
// per-device record in LocalDatabase kv.
//
// Honesty rules (spec §1.2/§3.7/§5.3): linking grants account metadata
// access only — contacts and profile. Messages never sync and nothing here
// claims they do. The pre-link UI states this verbatim.
//
// Secrecy rules: ephemeral private keys, the ECDH shared secret, the derived
// session key (SK), device Ed25519 private keys and the plaintext approval
// body are NEVER logged, persisted, or placed in exceptions. They are wiped
// on success, cancel, timeout, and every failure path.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/key_manager.dart';
import '../../core/crypto/primitives/aes_gcm.dart';
import '../../core/crypto/primitives/ed25519.dart';
import '../../core/crypto/primitives/hkdf.dart';
import '../../core/crypto/primitives/rng.dart';
import '../../core/crypto/primitives/sha.dart';
import '../../core/crypto/primitives/x25519.dart';
import '../../core/crypto/storage/secure_storage.dart';
import '../../core/database/local_database.dart';
import '../../core/log.dart';
import '../api/device_link_client.dart';
import '../../core/models/user_profile.dart';

/// kv key for the local per-device records (JSON array).
const String kLinkedDevicesKvKey = 'linked_devices_v1';

const String _linkPrefix = 'Chhaya-link-v1';
const String _capabilityMetadata = 'metadata';

// ---------------------------------------------------------------------------
// Length-prefix encoding helpers (spec §3.3: LP = u16be length + bytes).
// ---------------------------------------------------------------------------

Uint8List lpBytes(List<int> bytes) {
  final out = Uint8List(2 + bytes.length);
  out[0] = (bytes.length >> 8) & 0xFF;
  out[1] = bytes.length & 0xFF;
  out.setRange(2, out.length, bytes);
  return out;
}

Uint8List lpString(String value) =>
    lpBytes(Uint8List.fromList(utf8.encode(value)));

Uint8List _lpList(List<Uint8List> parts) {
  final builder = BytesBuilder();
  for (final part in parts) {
    builder.add(part);
  }
  return builder.toBytes();
}

Uint8List _u64be(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'value', 'Must be non-negative');
  }
  final out = Uint8List(8);
  var remaining = value;
  for (var i = 7; i >= 0; i--) {
    out[i] = remaining & 0xFF;
    remaining = remaining >> 8;
  }
  return out;
}

int _u64beDecode(List<int> bytes) {
  if (bytes.length != 8) {
    throw const FormatException('exp must be 8 bytes');
  }
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List bytesFromHex(String hex) {
  if (hex.length % 2 != 0 || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
    throw const FormatException('Invalid hex');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _base32Lower(List<int> bytes) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(alphabet[(buffer >> bits) & 0x1F]);
    }
  }
  if (bits > 0) {
    out.write(alphabet[(buffer << (5 - bits)) & 0x1F]);
  }
  return out.toString();
}

/// Normalizes user-typed codes/payload fragments: lowercase, strip anything
/// outside [a-z0-9] so grouped display formats round-trip.
String normalizeCode(String input) =>
    input.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Formats a 16-hex-char fingerprint as 4-4-4-4 for display.
String formatFingerprint(String hex16) {
  if (hex16.length != 16) return hex16;
  return '${hex16.substring(0, 4)}-${hex16.substring(4, 8)}-'
      '${hex16.substring(8, 12)}-${hex16.substring(12, 16)}';
}

// ---------------------------------------------------------------------------
// Protocol approval message (the spec's signed approval body). Both devices
// must compute identical bytes; keep this in sync with the verification path.
// ---------------------------------------------------------------------------

Uint8List buildLinkSalt({
  required String normalizedCode,
  required Uint8List eNPub,
  required Uint8List ePPub,
}) {
  return Uint8List.fromList(sha256.convert(_lpList([
    lpString('Chhaya-DeviceLink-v1'),
    lpString(normalizedCode),
    eNPub,
    ePPub,
  ])).bytes);
}

Uint8List deriveLinkSessionKey({
  required Uint8List sharedSecret,
  required Uint8List salt,
}) {
  return Hkdf.deriveKey(
    inputKeyMaterial: sharedSecret,
    length: 32,
    salt: salt,
    info: lpString('Chhaya-DeviceLink-v1/session'),
  );
}

Uint8List linkFingerprintBytes({
  required Uint8List eNPub,
  required Uint8List ePPub,
}) {
  return Uint8List.fromList(sha256.convert(_lpList([
    lpString('Chhaya-DeviceLink-v1/fp'),
    eNPub,
    ePPub,
  ])).bytes.sublist(0, 8));
}

Uint8List buildApprovalAad({
  required String requestId,
  required Uint8List fingerprintBytes,
}) {
  return _lpList([
    lpString('Chhaya-DeviceLink-v1/approval-aad'),
    Uint8List.fromList(utf8.encode(requestId)),
    fingerprintBytes,
  ]);
}

Uint8List buildApprovalMessage({
  required String requestId,
  required String normalizedCode,
  required Uint8List eNPub,
  required Uint8List ePPub,
  required String accountChhayaId,
  required Uint8List accountEd25519PublicKey,
  required Uint8List deviceEd25519PublicKey,
  required int expiresAtMs,
  required String capabilities,
}) {
  return _lpList([
    lpString('Chhaya-DeviceLink-v1/approval'),
    lpString(requestId),
    lpString(normalizedCode),
    lpBytes(eNPub),
    lpBytes(ePPub),
    lpString(accountChhayaId),
    lpBytes(accountEd25519PublicKey),
    lpBytes(deviceEd25519PublicKey),
    lpBytes(_u64be(expiresAtMs)),
    lpString(capabilities),
  ]);
}

// ---------------------------------------------------------------------------
// Link payload (QR / manual entry format). The spec's five-field payload is
// extended with the device name, platform and deviceId so the approving
// screen can show the §3.5 "Link to \"<name>\"?" string and persist a local
// record; the server never sees the payload.
//   Chhaya-link-v1:{requestId}:{code}:{eNPubHex}:{dPubHex}
//     :{base64url(deviceName)}:{platform}:{deviceId}
// ---------------------------------------------------------------------------

class LinkPayload {
  final String requestId;
  final String code; // normalized
  final Uint8List ephPub;
  final Uint8List devicePublicKey;
  final String? deviceName;
  final String? platform;
  final String? deviceId;

  const LinkPayload({
    required this.requestId,
    required this.code,
    required this.ephPub,
    required this.devicePublicKey,
    this.deviceName,
    this.platform,
    this.deviceId,
  });

  static LinkPayload? parse(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 5 && parts.length != 8) return null;
    if (parts[0] != _linkPrefix) return null;
    final requestId = parts[1].toLowerCase();
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(requestId)) {
      return null;
    }
    final code = normalizeCode(parts[2]);
    if (code.length < 8 || code.length > 128) return null;
    final Uint8List ephPub;
    final Uint8List dPub;
    try {
      ephPub = bytesFromHex(parts[3].toLowerCase());
      dPub = bytesFromHex(parts[4].toLowerCase());
    } on FormatException {
      return null;
    }
    if (ephPub.length != 32 || dPub.length != 32) return null;
    String? deviceName;
    String? platform;
    String? deviceId;
    if (parts.length == 8) {
      try {
        final normalized = base64Url.normalize(parts[5]);
        deviceName = utf8.decode(base64Url.decode(normalized));
      } catch (_) {
        return null;
      }
      platform = parts[6].toLowerCase();
      if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,19}$').hasMatch(platform)) {
        return null;
      }
      deviceId = parts[7].toLowerCase();
      if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(deviceId)) {
        return null;
      }
      if (deviceName.isEmpty || deviceName.length > 100) return null;
    }
    return LinkPayload(
      requestId: requestId,
      code: code,
      ephPub: ephPub,
      devicePublicKey: dPub,
      deviceName: deviceName,
      platform: platform,
      deviceId: deviceId,
    );
  }
}

// ---------------------------------------------------------------------------
// Result/value types
// ---------------------------------------------------------------------------

class ActiveEnrollment {
  final String deviceId;
  final String requestId;
  final String code;
  final String linkPayload;
  final DateTime expiresAt;
  const ActiveEnrollment({
    required this.deviceId,
    required this.requestId,
    required this.code,
    required this.linkPayload,
    required this.expiresAt,
  });
}

enum DeviceLinkPollKind {
  pending,
  approved,
  denied,
  expired,
  notFound,
  networkError,
}

class DeviceLinkPollResult {
  final DeviceLinkPollKind kind;
  final DateTime? expiresAt;
  const DeviceLinkPollResult(this.kind, {this.expiresAt});
}

class VerifiedApproval {
  final String accountChhayaId;
  final String accountEd25519PublicKeyHex;
  final String fingerprint; // 16 lowercase hex chars
  final DateTime approvalExpiresAt;
  const VerifiedApproval({
    required this.accountChhayaId,
    required this.accountEd25519PublicKeyHex,
    required this.fingerprint,
    required this.approvalExpiresAt,
  });
}

class EnrollOutcome {
  final String userId;
  final String deviceId;
  const EnrollOutcome({required this.userId, required this.deviceId});
}

/// Local per-device record persisted in LocalDatabase kv under
/// [kLinkedDevicesKvKey]. Never contains keys.
class DeviceLinkDeviceRecord {
  final String deviceId;
  final String name;
  final String platform;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final String? devicePublicKey;
  final bool isCurrentLocal;

  const DeviceLinkDeviceRecord({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.createdAt,
    this.revokedAt,
    this.devicePublicKey,
    this.isCurrentLocal = false,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'platform': platform,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
        'devicePublicKey': devicePublicKey,
        'isCurrentLocal': isCurrentLocal,
      };

  static DeviceLinkDeviceRecord? fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    final name = json['name'];
    final platform = json['platform'];
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    if (deviceId is! String || name is! String || platform is! String ||
        createdAt == null) {
      return null;
    }
    final revokedRaw = json['revokedAt'];
    return DeviceLinkDeviceRecord(
      deviceId: deviceId,
      name: name,
      platform: platform,
      createdAt: createdAt.toUtc(),
      revokedAt: revokedRaw == null ? null : DateTime.tryParse('$revokedRaw')?.toUtc(),
      devicePublicKey: json['devicePublicKey'] as String?,
      isCurrentLocal: json['isCurrentLocal'] == true,
    );
  }
}

/// Merged view of a device for UI: server data when reachable, local kv
/// records otherwise, with local revocation overlayed on both.
class LinkedDeviceEntry {
  final String deviceId;
  final String name;
  final String platform;
  final DateTime createdAt;
  final DateTime? lastActiveAt;
  final bool isCurrent;
  final DateTime? revokedAt;

  /// True when the server does not know this device id yet (approved but
  /// never consumed, or the server list was unreachable). Such entries can
  /// only be removed after a successful server call — never locally alone.
  final bool pending;

  const LinkedDeviceEntry({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastActiveAt,
    required this.isCurrent,
    required this.revokedAt,
    required this.pending,
  });

  bool get isRevoked => revokedAt != null;
}

class DeviceLinkDeviceList {
  final List<LinkedDeviceEntry> devices;

  /// True when the server list could not be fetched (no session, network,
  /// or server error) and the view is built from local records only.
  final bool serverUnavailable;

  const DeviceLinkDeviceList({required this.devices, required this.serverUnavailable});
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class DeviceLinkService {
  DeviceLinkService({
    required DeviceLinkClient client,
    required LocalDatabase database,
    required KeyManager keys,
    required Future<String?> Function() authTokenProvider,
    required Future<UserProfile?> Function() profileProvider,
    // Ignored. Retained so existing call sites (UI widget tests) still
    // compile. v1 persists nothing to secure storage; the consume token
    // is deliberately never written.
    SecureStorage? secureStorage,
    Csprng? rng,
  })  : _client = client,
        _database = database,
        _keys = keys,
        _authTokenProvider = authTokenProvider,
        _profileProvider = profileProvider,
        _rng = rng ?? Csprng.instance;

  final DeviceLinkClient _client;
  final LocalDatabase _database;
  final KeyManager _keys;
  final Future<String?> Function() _authTokenProvider;
  final Future<UserProfile?> Function() _profileProvider;
  final Csprng _rng;

  // --- in-flight enrollment attempt state (memory only, wiped on outcome) ---
  Uint8List? _eNPriv;
  Uint8List? _eNPub;
  Uint8List? _dPrivSeed;
  Uint8List? _dPub;
  String? _code;
  String? _requestId;
  String? _deviceId;
  String? _deviceName;
  String? _platform;
  DateTime? _expiresAt;
  DeviceLinkStatusResult? _approvedStatus;
  VerifiedApproval? _verifiedApproval;

  bool get hasActiveEnrollment => _requestId != null;

  // -------------------------------------------------------------------------
  // Enroll flow (this device is the NEW device)
  // -------------------------------------------------------------------------

  /// Generates fresh ephemeral keys and the one-time code, registers the
  /// pending link with the server and returns the display data. Any previous
  /// in-flight attempt is cancelled and wiped first.
  Future<ActiveEnrollment> beginEnrollment({
    required String deviceName,
    required String platform,
  }) async {
    final name = deviceName.trim();
    final plat = platform.trim().toLowerCase();
    if (name.isEmpty || name.length > 100) {
      throw ArgumentError.value(deviceName, 'deviceName', 'Must be 1..100 chars');
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,19}$').hasMatch(plat)) {
      throw ArgumentError.value(platform, 'platform', 'Use a short lowercase platform tag');
    }
    await cancelEnrollment();

    final deviceId = const Uuid().v4();
    final eph = await X25519Kex.generateKeyPair();
    final deviceKeyPair = await Ed25519Sign.generateKeyPair();
    final dPub = Uint8List.fromList((await deviceKeyPair.extractPublicKey()).bytes);
    final dSeed = Uint8List.fromList(await deviceKeyPair.extractPrivateKeyBytes());
    final code = _base32Lower(_rng.bytes(20)); // 160 bits, 32 chars
    final codeHash = Sha.hexOf(Uint8List.fromList(sha256.convert(utf8.encode(code)).bytes));

    final request = await _client.requestLink(
      deviceId: deviceId,
      deviceName: name,
      platform: plat,
      devicePublicKey: hexOf(dPub),
      ephemeralPublicKey: hexOf(eph.publicKey),
      codeHash: codeHash,
    );

    _eNPriv = Uint8List.fromList(eph.privateKey);
    _eNPub = Uint8List.fromList(eph.publicKey);
    _dPrivSeed = dSeed;
    _dPub = dPub;
    _code = code;
    _requestId = request.requestId;
    _deviceId = deviceId;
    _deviceName = name;
    _platform = plat;
    _expiresAt = request.expiresAt;

    final payload = '$_linkPrefix:${request.requestId}:$code:'
        '${hexOf(eph.publicKey)}:${hexOf(dPub)}:'
        '${base64Url.encode(utf8.encode(name)).replaceAll('=', '')}:$plat:$deviceId';

    return ActiveEnrollment(
      deviceId: deviceId,
      requestId: request.requestId,
      code: code,
      linkPayload: payload,
      expiresAt: request.expiresAt,
    );
  }

  /// Single status poll. Maps server and network failures onto the result
  /// enum; expected states never throw. Honours the local expiry bound so a
  /// stalled client stops asking the server.
  Future<DeviceLinkPollResult> checkStatus() async {
    final requestId = _requestId;
    final expiresAt = _expiresAt;
    if (requestId == null || expiresAt == null) {
      return const DeviceLinkPollResult(DeviceLinkPollKind.expired);
    }
    if (DateTime.now().toUtc().isAfter(expiresAt.add(const Duration(seconds: 30)))) {
      await cancelEnrollment();
      return DeviceLinkPollResult(DeviceLinkPollKind.expired, expiresAt: expiresAt);
    }
    final DeviceLinkStatusResult status;
    try {
      status = await _client.linkStatus(requestId: requestId);
    } on DeviceLinkException catch (error) {
      switch (error.errorCode) {
        case 'link_expired':
          await cancelEnrollment();
          return DeviceLinkPollResult(DeviceLinkPollKind.expired, expiresAt: expiresAt);
        case 'not_found':
          await cancelEnrollment();
          return DeviceLinkPollResult(DeviceLinkPollKind.notFound, expiresAt: expiresAt);
        default:
          return DeviceLinkPollResult(DeviceLinkPollKind.networkError, expiresAt: expiresAt);
      }
    }
    if (status.state == 'pending') {
      return DeviceLinkPollResult(DeviceLinkPollKind.pending, expiresAt: status.expiresAt ?? expiresAt);
    }
    if (status.state == 'denied') {
      await cancelEnrollment();
      return DeviceLinkPollResult(DeviceLinkPollKind.denied, expiresAt: status.expiresAt);
    }
    if (status.state == 'approved') {
      _approvedStatus = status;
      return DeviceLinkPollResult(DeviceLinkPollKind.approved, expiresAt: status.expiresAt ?? expiresAt);
    }
    return DeviceLinkPollResult(DeviceLinkPollKind.networkError, expiresAt: expiresAt);
  }

  /// Decrypts and verifies the stashed approval (cached from the last
  /// approved status poll). Returns the fingerprint + account chhayaId for
  /// the confirm screen. Wipes the ECDH shared secret and session key.
  /// Throws on any mismatch; the caller must treat that as a hard abort.
  Future<VerifiedApproval> verifyApproval() async {
    final status = _approvedStatus;
    final cached = _verifiedApproval;
    if (cached != null) return cached;
    final eNPriv = _eNPriv, eNPub = _eNPub, code = _code, requestId = _requestId;
    final dPub = _dPub;
    if (status == null || eNPriv == null || eNPub == null ||
        code == null || requestId == null || dPub == null) {
      throw StateError('No approved link to verify yet');
    }

    Uint8List? sharedSecret;
    Uint8List? sessionKey;
    Uint8List? plaintext;
    Uint8List? approvalMessage;
    Uint8List? body;
    Uint8List? sig;
    List<Uint8List>? fieldsToWipe;
    try {
      final primEphPub = bytesFromHex(status.primEphPub!);
      sharedSecret = await X25519Kex.sharedSecret(eNPriv, primEphPub);
      final salt = buildLinkSalt(normalizedCode: code, eNPub: eNPub, ePPub: primEphPub);
      sessionKey = deriveLinkSessionKey(sharedSecret: sharedSecret, salt: salt);
      final fingerprintBytes = linkFingerprintBytes(eNPub: eNPub, ePPub: primEphPub);
      final aad = buildApprovalAad(requestId: requestId, fingerprintBytes: fingerprintBytes);
      plaintext = AesGcm.decryptBytes(sessionKey, base64Decode(status.approval!), aad: aad);

      // body = LP fields... || signature (last 64 bytes)
      if (plaintext.length <= 64 + 2) {
        throw const FormatException('Approval payload too short');
      }
      final bodyRaw = Uint8List.fromList(plaintext);
      body = bodyRaw;
      sig = Uint8List.fromList(body.sublist(body.length - 64));
      approvalMessage = Uint8List.fromList(body.sublist(0, body.length - 64));
      body.fillRange(0, body.length, 0);

      final fields = _splitLpFields(approvalMessage);
      fieldsToWipe = fields;
      if (fields.length != 10) {
        throw const FormatException('Approval message field count mismatch');
      }
      String fieldString(int index) => utf8.decode(fields[index]);
      if (fieldString(0) != 'Chhaya-DeviceLink-v1/approval') {
        throw const FormatException('Approval domain mismatch');
      }
      if (fieldString(1) != requestId) {
        throw const FormatException('Approval request binding mismatch');
      }
      if (fieldString(2) != code) {
        throw const FormatException('Approval code binding mismatch');
      }
      if (!_bytesEqual(fields[3], eNPub)) {
        throw const FormatException('Approval ephemeral key mismatch');
      }
      if (!_bytesEqual(fields[4], primEphPub)) {
        throw const FormatException('Approval primary ephemeral key mismatch');
      }
      final accountChhayaId = fieldString(5);
      if (accountChhayaId.isEmpty) {
        throw const FormatException('Approval account id missing');
      }
      final accountEdPub = fields[6];
      if (accountEdPub.length != 32) {
        throw const FormatException('Approval account key malformed');
      }
      if (!_bytesEqual(fields[7], dPub)) {
        throw const FormatException('Approval device key mismatch');
      }
      final expMs = _u64beDecode(fields[8]);
      if (expMs <= DateTime.now().millisecondsSinceEpoch) {
        throw const FormatException('Approval expired');
      }
      if (fieldString(9) != _capabilityMetadata) {
        throw const FormatException('Approval capability mismatch');
      }

      final ok = await Ed25519Sign.verify(approvalMessage, sig, accountEdPub);
      if (!ok) {
        throw const FormatException('Approval signature invalid');
      }

      final verified = VerifiedApproval(
        accountChhayaId: accountChhayaId,
        accountEd25519PublicKeyHex: hexOf(accountEdPub),
        fingerprint: hexOf(fingerprintBytes),
        approvalExpiresAt: DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true),
      );
      _verifiedApproval = verified;
      return verified;
    } finally {
      if (sharedSecret != null) Csprng.wipe(sharedSecret);
      if (sessionKey != null) Csprng.wipe(sessionKey);
      if (plaintext != null) Csprng.wipe(plaintext);
      if (body != null) Csprng.wipe(body);
      if (sig != null) Csprng.wipe(sig);
      if (approvalMessage != null) Csprng.wipe(approvalMessage);
      if (fieldsToWipe != null) {
        for (final field in fieldsToWipe) {
          Csprng.wipe(field);
        }
      }
    }
  }

  /// Redeems the approved request (one-shot). Persists the local device
  /// record, then wipes all attempt secrets. The per-device session token
  /// returned by consume is NOT persisted in v1 (no ApiService consumer
  /// exists yet); it does not outlive this call.
  /// Requires a prior successful [verifyApproval].
  Future<EnrollOutcome> consumeAfterConfirm() async {
    final verified = _verifiedApproval;
    final code = _code, requestId = _requestId, deviceId = _deviceId;
    if (verified == null || code == null || requestId == null || deviceId == null) {
      throw StateError('Verify the approval before consuming it');
    }
    try {
      final result = await _client.consumeLink(requestId: requestId, code: code);
      if (result.deviceId != deviceId) {
        throw const FormatException('Consumed device id mismatch');
      }
      final record = DeviceLinkDeviceRecord(
        deviceId: deviceId,
        name: _deviceName ?? 'This device',
        platform: _platform ?? 'unknown',
        createdAt: DateTime.now().toUtc(),
        devicePublicKey: hexOf(_dPub!),
        isCurrentLocal: true,
      );
      await _upsertLocalRecord(record);
      // The consume token is deliberately not persisted: nothing in this
      // release consumes it, so storing it would be a write-only credential.
      return EnrollOutcome(userId: result.userId, deviceId: result.deviceId);
    } finally {
      await _wipeAttempt();
    }
  }

  /// Cancels a pending enrollment and wipes all attempt secrets.
  /// Safe to call at any time, including after outcome.
  Future<void> cancelEnrollment() async {
    await _wipeAttempt();
  }

  Future<void> _wipeAttempt() async {
    if (_eNPriv != null) Csprng.wipe(_eNPriv!);
    if (_dPrivSeed != null) Csprng.wipe(_dPrivSeed!);
    _eNPriv = null;
    _eNPub = null;
    _dPrivSeed = null;
    _dPub = null;
    _code = null;
    _requestId = null;
    _deviceId = null;
    _deviceName = null;
    _platform = null;
    _expiresAt = null;
    _approvedStatus = null;
    _verifiedApproval = null;
  }

  // -------------------------------------------------------------------------
  // Approve flow (this device is the EXISTING primary)
  //
  // The approve screen parses the payload, starts an [ApproveSession] which
  // generates the primary's ephemeral pair and derives the fingerprint both
  // screens must show (spec §3.5). The user compares the fingerprint against
  // the new device, then taps Approve or Deny. All secrets are wiped on
  // dispose either way.
  // -------------------------------------------------------------------------

  /// Denies a pending enrollment. Still authenticated; the new device
  /// surfaces "Link declined".
  Future<void> denyPendingLink({required LinkPayload payload}) async {
    final token = await _authTokenProvider();
    if (token == null) {
      throw const DeviceLinkException(401, 'not_authenticated');
    }
    await _client.approveLink(
      requestId: payload.requestId,
      code: payload.code,
      action: 'deny',
    );
  }

  /// Generates the primary's ephemeral pair and returns a session whose
  /// fingerprint both screens must show (spec §3.5). The private half never
  /// leaves the [ApproveSession] object and is wiped by [ApproveSession.wipe]
  /// or [ApproveSession.finishApproval].
  ApproveSession beginApproval({required LinkPayload payload}) {
    return ApproveSession._(this, payload, X25519Kex.generateKeyPair());
  }

  // -------------------------------------------------------------------------
  // Devices: list + revoke
  // -------------------------------------------------------------------------

  /// Merges the server list (when a session exists) with the local kv
  /// records. Local revocations overlay server state; server entries win
  /// for name/platform. Local-only records are marked [LinkedDeviceEntry.pending].
  Future<DeviceLinkDeviceList> listDevices() async {
    final token = await _authTokenProvider();
    List<LinkedDevice>? serverDevices;
    if (token != null) {
      try {
        serverDevices = await _client.listDevices();
      } catch (_) {
        serverDevices = null;
      }
    }
    final local = await _readLocalRecords();
    final localById = {for (final r in local) r.deviceId: r};

    if (serverDevices == null) {
      // Built purely from local records — honest offline view.
      final entries = local
          .map((r) => LinkedDeviceEntry(
                deviceId: r.deviceId,
                name: r.name,
                platform: r.platform,
                createdAt: r.createdAt,
                lastActiveAt: null,
                isCurrent: r.isCurrentLocal,
                revokedAt: r.revokedAt,
                pending: true,
              ))
          .toList();
      return DeviceLinkDeviceList(devices: entries, serverUnavailable: true);
    }

    final seen = <String>{};
    final entries = <LinkedDeviceEntry>[];
    for (final device in serverDevices) {
      seen.add(device.deviceId);
      final overlay = localById[device.deviceId];
      final revokedAt = device.revokedAt ?? overlay?.revokedAt;
      entries.add(LinkedDeviceEntry(
        deviceId: device.deviceId,
        name: device.name ?? overlay?.name ?? 'Unnamed device',
        platform: device.platform ?? overlay?.platform ?? 'unknown',
        createdAt: device.createdAt,
        lastActiveAt: device.lastActiveAt,
        isCurrent: device.isCurrent || (overlay?.isCurrentLocal ?? false),
        revokedAt: revokedAt,
        pending: false,
      ));
    }
    for (final record in local) {
      if (seen.contains(record.deviceId)) continue;
      entries.add(LinkedDeviceEntry(
        deviceId: record.deviceId,
        name: record.name,
        platform: record.platform,
        createdAt: record.createdAt,
        lastActiveAt: null,
        isCurrent: record.isCurrentLocal,
        revokedAt: record.revokedAt,
        pending: true,
      ));
    }
    return DeviceLinkDeviceList(devices: entries, serverUnavailable: false);
  }

  /// Revokes a device: the server call is authoritative and must succeed
  /// before the local record is flagged. Local-only removal is never
  /// performed; a failed server call leaves local state untouched.
  Future<void> revokeDevice({required String deviceId}) async {
    final token = await _authTokenProvider();
    if (token == null) {
      throw const DeviceLinkException(401, 'not_authenticated');
    }
    await _client.revokeDevice(deviceId: deviceId);
    await _markLocalRevoked(deviceId, DateTime.now().toUtc());
  }

  Future<List<DeviceLinkDeviceRecord>> _readLocalRecords() async {
    try {
      final raw = await _database.readPlainKv(kLinkedDevicesKvKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <DeviceLinkDeviceRecord>[];
      for (final entry in decoded) {
        if (entry is Map) {
          final record = DeviceLinkDeviceRecord.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (record != null) out.add(record);
        }
      }
      return out;
    } catch (_) {
      ChhayaLog.w('linked devices kv unreadable; ignoring local list',
          name: 'DeviceLinkService');
      return [];
    }
  }

  Future<void> _writeLocalRecords(List<DeviceLinkDeviceRecord> records) async {
    final raw = jsonEncode(records.map((r) => r.toJson()).toList());
    await _database.writePlainKv(kLinkedDevicesKvKey, raw);
  }

  Future<void> _upsertLocalRecord(DeviceLinkDeviceRecord record) async {
    final records = await _readLocalRecords();
    final out = <DeviceLinkDeviceRecord>[
      for (final r in records)
        if (r.deviceId != record.deviceId) r,
      record,
    ];
    await _writeLocalRecords(out);
  }

  Future<void> _markLocalRevoked(String deviceId, DateTime revokedAt) async {
    final records = await _readLocalRecords();
    var touched = false;
    final out = <DeviceLinkDeviceRecord>[];
    for (final r in records) {
      if (r.deviceId == deviceId) {
        touched = true;
        out.add(DeviceLinkDeviceRecord(
          deviceId: r.deviceId,
          name: r.name,
          platform: r.platform,
          createdAt: r.createdAt,
          revokedAt: revokedAt,
          devicePublicKey: r.devicePublicKey,
          isCurrentLocal: r.isCurrentLocal,
        ));
      } else {
        out.add(r);
      }
    }
    if (touched) {
      await _writeLocalRecords(out);
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static List<Uint8List> _splitLpFields(Uint8List bytes) {
    final fields = <Uint8List>[];
    var offset = 0;
    while (offset < bytes.length) {
      if (offset + 2 > bytes.length) {
        throw const FormatException('Truncated length prefix');
      }
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      offset += 2;
      if (offset + length > bytes.length) {
        throw const FormatException('Truncated field');
      }
      fields.add(Uint8List.fromList(bytes.sublist(offset, offset + length)));
      offset += length;
    }
    return fields;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Holds the primary's ephemeral keypair for one approval attempt. The
/// caller must invoke [wipe] when done (or [finishApproval]).
class ApproveSession {
  ApproveSession._(this._service, this.payload, this.primaryKeyPair);

  final DeviceLinkService _service;
  final LinkPayload payload;
  final Future<({Uint8List publicKey, Uint8List privateKey})> primaryKeyPair;

  Uint8List? _publicKey;
  Uint8List? _fingerprintBytes;

  Future<String> fingerprint() async {
    if (_fingerprintBytes != null) return hexOf(_fingerprintBytes!);
    final pair = await primaryKeyPair;
    _publicKey = pair.publicKey;
    _fingerprintBytes =
        linkFingerprintBytes(eNPub: payload.ephPub, ePPub: _publicKey!);
    return hexOf(_fingerprintBytes!);
  }

  /// Approves the link using the held ephemeral key. Wipes the private half
  /// and all intermediate secrets before returning.
  Future<void> finishApproval() async {
    final pair = await primaryKeyPair;
    try {
      await _service._approveWithPrimaryKeys(
        payload: payload,
        primaryEphemeral: pair,
      );
    } finally {
      Csprng.wipe(pair.privateKey);
    }
  }

  /// Drops the held ephemeral key without approving.
  Future<void> wipe() async {
    final pair = await primaryKeyPair;
    Csprng.wipe(pair.privateKey);
  }
}

/// User-facing copy for link failures. Never includes key material.
String deviceLinkErrorCopy(Object error) {
  if (error is DeviceLinkException) {
    switch (error.errorCode) {
      case 'network_error':
        return 'No connection to the server. Check your network and try again.';
      case 'link_expired':
        return 'That link code has expired. Generate a new one and try again.';
      case 'not_found':
        return 'That link request no longer exists. Generate a new code and try again.';
      case 'code_mismatch':
        return 'That code does not match this link request. Check the code and try again.';
      case 'rate_limited':
        return 'Too many attempts. Wait a while and try again.';
      case 'invalid_state':
        return 'This link request has already been used or declined.';
      case 'request_already_claimed':
        return 'This link request was already approved from another account.';
      case 'use_logout':
        return 'You cannot revoke the device you are calling from. Use logout instead.';
      case 'not_authenticated':
        return 'Sign in to your account on this device first.';
      case 'device_conflict':
        return 'This device is already linked to a different account.';
    }
    if (error.statusCode == 0) {
      return 'No connection to the server. Check your network and try again.';
    }
  }
  return 'Something went wrong. Nothing was linked; try again.';
}

/// Internal: shared approval path that takes an already-generated primary
/// ephemeral pair (used by [ApproveSession]).
extension on DeviceLinkService {
  Future<void> _approveWithPrimaryKeys({
    required LinkPayload payload,
    required ({Uint8List publicKey, Uint8List privateKey}) primaryEphemeral,
  }) async {
    final token = await _authTokenProvider();
    if (token == null) {
      throw const DeviceLinkException(401, 'not_authenticated');
    }
    final profile = await _profileProvider();
    if (profile == null) {
      throw StateError('No account profile available on this device');
    }
    final ePPub = primaryEphemeral.publicKey;
    final seed = await _keys.getIdentityEd25519SeedBytes();
    Uint8List? sharedSecret;
    Uint8List? sessionKey;
    Uint8List? body;
    Uint8List? approvalMessage;
    Uint8List? approvalBytes;
    try {
      sharedSecret =
          await X25519Kex.sharedSecret(primaryEphemeral.privateKey, payload.ephPub);
      final salt = buildLinkSalt(
        normalizedCode: payload.code,
        eNPub: payload.ephPub,
        ePPub: ePPub,
      );
      sessionKey = deriveLinkSessionKey(sharedSecret: sharedSecret, salt: salt);
      final fingerprintBytes =
          linkFingerprintBytes(eNPub: payload.ephPub, ePPub: ePPub);
      final aad = buildApprovalAad(
        requestId: payload.requestId,
        fingerprintBytes: fingerprintBytes,
      );
      final accountEdPub = await _keys.getIdentityEd25519PublicKeyBytes();
      final expMs = DateTime.now().millisecondsSinceEpoch +
          const Duration(minutes: 5).inMilliseconds;
      approvalMessage = buildApprovalMessage(
        requestId: payload.requestId,
        normalizedCode: payload.code,
        eNPub: payload.ephPub,
        ePPub: ePPub,
        accountChhayaId: profile.chhayaId.publicKey,
        accountEd25519PublicKey: accountEdPub,
        deviceEd25519PublicKey: payload.devicePublicKey,
        expiresAtMs: expMs,
        capabilities: _capabilityMetadata,
      );
      final signature = await Ed25519Sign.sign(approvalMessage, seed);
      body = Uint8List.fromList([...approvalMessage, ...signature]);
      approvalBytes = AesGcm.encryptBytes(sessionKey, body, aad: aad);

      await _client.approveLink(
        requestId: payload.requestId,
        code: payload.code,
        action: 'approve',
        approval: base64Encode(approvalBytes),
        approvalSignature: hexOf(signature),
        primEphPub: hexOf(ePPub),
      );
      Csprng.wipe(signature);

      if (payload.deviceId != null) {
        await _upsertLocalRecord(DeviceLinkDeviceRecord(
          deviceId: payload.deviceId!,
          name: payload.deviceName ?? 'New device',
          platform: payload.platform ?? 'unknown',
          createdAt: DateTime.now().toUtc(),
          devicePublicKey: hexOf(payload.devicePublicKey),
        ));
      }
    } finally {
      Csprng.wipe(seed);
      if (sharedSecret != null) Csprng.wipe(sharedSecret);
      if (sessionKey != null) Csprng.wipe(sessionKey);
      if (body != null) Csprng.wipe(body);
      if (approvalMessage != null) Csprng.wipe(approvalMessage);
      if (approvalBytes != null) Csprng.wipe(approvalBytes);
    }
  }
}
