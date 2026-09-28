// Chhaya key manager — secure key lifecycle (V14 Part 2).
//
// Purpose: own every secret the app holds. Long-term secrets live only
// in platform hardware storage (Keystore / Keychain / DPAPI) behind the
// [SecureStorage] interface — never shared_preferences, never plain
// files, never logs. Short-lived session keys live in a memory cache
// that is wiped when the app backgrounds.
//
// Key derivation paths (HKDF-SHA256 over the master seed):
//   identity/ed25519, identity/x25519,
//   session/<contact_id>/<device_id>,
//   database/master/<user_id>, vault/master
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../log.dart';
import 'chhaya_crypto_engine.dart';
import 'primitives/ed25519.dart';
import 'primitives/hkdf.dart' as hkdf;
import 'primitives/rng.dart';
import 'primitives/sha.dart';
import 'storage/secure_storage.dart';

/// Announcement published when the identity key rotates.
///
/// Transport-agnostic: Part 4/9 deliver it to contacts. Verifiable with
/// the OLD Ed25519 public key, so contacts can trust the rotation even
/// though the signing key is being replaced.
class RotationAnnouncement {
  /// Creates an announcement (use [KeyManager.rotateIdentity]).
  RotationAnnouncement({
    required this.oldPublicKeyHex,
    required this.newPublicKeyHex,
    required this.issuedAt,
    required this.signatureHex,
  });

  /// Previous Ed25519 identity public key (hex).
  final String oldPublicKeyHex;

  /// Replacement Ed25519 identity public key (hex).
  final String newPublicKeyHex;

  /// UTC issuance time.
  final DateTime issuedAt;

  /// Ed25519 signature over [_signedPayload] by the old key (hex).
  final String signatureHex;

  /// Canonical signed payload: old|new|issuedAt-ms.
  String get _signedPayload =>
      '$oldPublicKeyHex|$newPublicKeyHex|${issuedAt.millisecondsSinceEpoch}';

  /// Serializes for transport (contains public keys only — no secrets).
  Map<String, dynamic> toJson() => {
        'oldPublicKey': oldPublicKeyHex,
        'newPublicKey': newPublicKeyHex,
        'issuedAt': issuedAt.toIso8601String(),
        'signature': signatureHex,
      };

  /// Parses a received announcement.
  factory RotationAnnouncement.fromJson(Map<String, dynamic> json) {
    return RotationAnnouncement(
      oldPublicKeyHex: json['oldPublicKey'] as String,
      newPublicKeyHex: json['newPublicKey'] as String,
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      signatureHex: json['signature'] as String,
    );
  }

  /// Verifies the announcement against the OLD public key bytes.
  Future<bool> verifySignature(Uint8List oldPublicKey) {
    return Ed25519Sign.verify(
      Uint8List.fromList(utf8.encode(_signedPayload)),
      _hexToBytes(signatureHex),
      oldPublicKey,
    );
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }
}

/// Owns all application secrets across storage, memory, and rotation.
///
/// V13 API is preserved verbatim. New in V14: derivation paths, rotation
/// helpers, background zeroization, per-user database keys.
class KeyManager with WidgetsBindingObserver {
  /// Creates a manager. Pass [storage] (V13 style) or [secureBackend];
  /// defaults to the platform-appropriate secure adapter.
  KeyManager({
    FlutterSecureStorage? storage,
    SecureStorage? secureBackend,
    Csprng? rng,
  })  : _backend = secureBackend ??
            (storage != null
                ? FlutterSecureStorageAdapter(storage)
                : SecureStorages.platformDefault()),
        _rng = rng ?? Csprng.instance;

  static const _publicKeyKey = 'chhaya_public_key';
  static const _privateKeyKey = 'chhaya_private_key';
  static const _recoveryPhraseKey = 'chhaya_recovery_phrase';
  static const _chhayaIdKey = 'chhaya_chhaya_id';

  static const _masterSeedKey = 'chhaya_master_seed_v1';
  static const _identityEd25519Key = 'chhaya_identity_ed25519_seed';
  static const _identityX25519Key = 'chhaya_identity_x25519_seed';
  static const _identityEpochKey = 'chhaya_identity_epoch';

  /// HKDF path for the Ed25519 identity seed.
  static const String pathIdentityEd25519 = 'identity/ed25519';

  /// HKDF path for the X25519 identity seed.
  static const String pathIdentityX25519 = 'identity/x25519';

  /// HKDF path for the vault master key.
  static const String pathVaultMaster = 'vault/master';

  /// HKDF path for a contact/device session key.
  static String sessionPath(String contactId, String deviceId) {
    _checkSegment(contactId, 'contactId');
    _checkSegment(deviceId, 'deviceId');
    return 'session/$contactId/$deviceId';
  }

  /// HKDF path for a user's database key (consumed by Part 3 SQLCipher).
  static String databasePath(String userId) {
    _checkSegment(userId, 'userId');
    return 'database/master/$userId';
  }

  final SecureStorage _backend;
  final Csprng _rng;

  /// In-memory session key cache. Wiped on background. Never logged.
  final Map<String, Uint8List> _sessionCache = {};

  /// In-memory rotation epochs per contact.
  final Map<String, int> _rotationEpochs = {};

  bool _observing = false;

  // ---- V13 API (preserved verbatim) ----

  /// Stores an X25519 key pair in secure storage.
  Future<void> storeKeyPair(ChhayaKeyPair keyPair) async {
    await _backend.write(
        key: _publicKeyKey, value: base64Encode(keyPair.publicKey));
    await _backend.write(
        key: _privateKeyKey, value: base64Encode(keyPair.privateKey));
  }

  /// Loads the stored X25519 key pair, or null when absent.
  Future<ChhayaKeyPair?> getKeyPair() async {
    final pub = await _backend.read(key: _publicKeyKey);
    final priv = await _backend.read(key: _privateKeyKey);
    if (pub == null || priv == null) {
      return null;
    }
    return ChhayaKeyPair(
        publicKey: base64Decode(pub), privateKey: base64Decode(priv));
  }

  /// Stores the BIP-39 recovery phrase in secure storage.
  Future<void> storeRecoveryPhrase(List<String> phrase) async =>
      _backend.write(key: _recoveryPhraseKey, value: jsonEncode(phrase));

  /// Loads the stored recovery phrase, or null when absent.
  Future<List<String>?> getRecoveryPhrase() async {
    final s = await _backend.read(key: _recoveryPhraseKey);
    if (s == null) {
      return null;
    }
    return (jsonDecode(s) as List).cast<String>();
  }

  /// Stores the Chhaya ID string in secure storage.
  Future<void> storeChhayaId(String id) async =>
      _backend.write(key: _chhayaIdKey, value: id);

  /// Loads the stored Chhaya ID, or null when absent.
  Future<String?> getChhayaId() async => _backend.read(key: _chhayaIdKey);

  /// Returns true when an X25519 key pair is stored.
  Future<bool> hasKeys() async {
    final p = await _backend.read(key: _publicKeyKey);
    final pr = await _backend.read(key: _privateKeyKey);
    return p != null && pr != null;
  }

  /// Deletes all V13 keys from secure storage.
  Future<void> clearAllKeys() async {
    await _backend.delete(key: _publicKeyKey);
    await _backend.delete(key: _privateKeyKey);
    await _backend.delete(key: _recoveryPhraseKey);
    await _backend.delete(key: _chhayaIdKey);
  }

  // ---- V14: master seed + derivation paths ----

  /// Loads the 32-byte master seed, generating and storing it on first
  /// use. The seed itself never leaves secure storage or this method's
  /// return value — callers must wipe derived copies when done.
  Future<Uint8List> _masterSeed() async {
    final stored = await _backend.read(key: _masterSeedKey);
    if (stored != null) {
      return base64Decode(stored);
    }
    final seed = _rng.bytes(32);
    await _backend.write(key: _masterSeedKey, value: base64Encode(seed));
    final copy = Uint8List.fromList(seed);
    Csprng.wipe(seed);
    return copy;
  }

  /// Derives a 32-byte key for an HKDF [path] from the master seed.
  ///
  /// Paths: `identity/ed25519`, `identity/x25519`,
  /// `session/<contact>/<device>`, `database/master/<user>`,
  /// `vault/master`. Rejects malformed paths.
  Future<Uint8List> derivePathKey(String path, {Uint8List? salt}) async {
    _checkPath(path);
    final seed = await _masterSeed();
    try {
      return hkdf.Hkdf.deriveKey(
        inputKeyMaterial: seed,
        length: 32,
        salt: salt,
        info: Uint8List.fromList(utf8.encode('chhaya-v14/$path')),
      );
    } finally {
      Csprng.wipe(seed);
    }
  }

  /// Derives the per-user database master key (consumed by Part 3).
  ///
  /// Deterministic per user, 32 bytes, never stored — re-derived on
  /// demand from the master seed.
  Future<Uint8List> getDatabaseKey({required String userId}) {
    return derivePathKey(databasePath(userId));
  }

  // ---- V14: session key cache + zeroization ----

  /// Caches a session key in memory (copy). Wiped on background.
  void cacheSessionKey(String contactId, String deviceId, Uint8List key) {
    final cacheKey = sessionPath(contactId, deviceId);
    final old = _sessionCache[cacheKey];
    if (old != null) {
      Csprng.wipe(old);
    }
    _sessionCache[cacheKey] = Uint8List.fromList(key);
  }

  /// Returns a copy of the cached session key, or null when absent.
  Uint8List? getCachedSessionKey(String contactId, String deviceId) {
    final cached = _sessionCache[sessionPath(contactId, deviceId)];
    return cached == null ? null : Uint8List.fromList(cached);
  }

  /// Wipes every in-memory session key. Called automatically on
  /// background; callers may also invoke it directly (e.g. lock now).
  void zeroizeCache() {
    for (final key in _sessionCache.values) {
      Csprng.wipe(key);
    }
    _sessionCache.clear();
    ChhayaLog.i('Session key cache wiped', name: 'KeyManager');
  }

  /// Starts observing app lifecycle for background zeroization.
  void startObserving() {
    if (_observing) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  /// Stops lifecycle observation.
  void stopObserving() {
    if (!_observing) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      zeroizeCache();
    }
  }

  // ---- V14: rotation ----

  /// Rotates the Ed25519 identity key.
  ///
  /// Signs a rotation announcement with the OLD key, stores the new
  /// seed, and bumps the identity epoch. Returns the announcement for
  /// delivery to contacts (transport owned by Part 4/9). The old seed
  /// bytes are wiped before returning.
  Future<RotationAnnouncement> rotateIdentity() async {
    final oldSeedBytes =
        await _backend.read(key: _identityEd25519Key);
    final oldSeed = oldSeedBytes != null
        ? base64Decode(oldSeedBytes)
        : await derivePathKey(pathIdentityEd25519);
    try {
      final algorithm = Ed25519();
      final oldKeyPair = await algorithm.newKeyPairFromSeed(oldSeed);
      final oldPub = await oldKeyPair.extractPublicKey();
      final oldPubHex = Sha.hexOf(Uint8List.fromList(oldPub.bytes));

      final newSeed = _rng.bytes(32);
      try {
        final newKeyPair = await algorithm.newKeyPairFromSeed(newSeed);
        final newPub = await newKeyPair.extractPublicKey();
        final newPubHex = Sha.hexOf(Uint8List.fromList(newPub.bytes));

        final announcement = RotationAnnouncement(
          oldPublicKeyHex: oldPubHex,
          newPublicKeyHex: newPubHex,
          issuedAt: DateTime.now().toUtc(),
          signatureHex: '',
        );
        final payload =
            '${announcement.oldPublicKeyHex}|${announcement.newPublicKeyHex}|'
            '${announcement.issuedAt.millisecondsSinceEpoch}';
        final signature = await Ed25519Sign.sign(
          Uint8List.fromList(utf8.encode(payload)),
          oldSeed,
        );
        final signed = RotationAnnouncement(
          oldPublicKeyHex: oldPubHex,
          newPublicKeyHex: newPubHex,
          issuedAt: announcement.issuedAt,
          signatureHex: Sha.hexOf(signature),
        );

        await _backend.write(
          key: _identityEd25519Key,
          value: base64Encode(newSeed),
        );
        await _bumpIdentityEpoch();
        ChhayaLog.i('Identity key rotated', name: 'KeyManager');
        Csprng.wipe(signature);
        return signed;
      } finally {
        Csprng.wipe(newSeed);
      }
    } finally {
      Csprng.wipe(oldSeed);
    }
  }

  /// Returns the current identity epoch (0 when never rotated).
  Future<int> identityEpoch() async {
    final stored = await _backend.read(key: _identityEpochKey);
    return int.tryParse(stored ?? '') ?? 0;
  }

  /// Rotates the session key for [contactId].
  ///
  /// Drops cached session keys and bumps the rotation epoch. The actual
  /// DH ratchet step that establishes the replacement key runs in
  /// Part 4 — this method only guarantees no stale key survives.
  /// Returns the new epoch.
  Future<int> rotateSessionKey(String contactId) async {
    _checkSegment(contactId, 'contactId');
    _sessionCache.removeWhere((key, value) {
      if (key.startsWith('session/$contactId/')) {
        Csprng.wipe(value);
        return true;
      }
      return false;
    });
    final epochKey = 'chhaya_session_epoch_$contactId';
    final stored = await _backend.read(key: epochKey);
    final next = (int.tryParse(stored ?? '') ?? 0) + 1;
    await _backend.write(key: epochKey, value: next.toString());
    ChhayaLog.i('Session rotated for contact', name: 'KeyManager');
    _rotationEpochs[contactId] = next;
    return next;
  }

  /// Returns the in-memory rotation epoch for [contactId], if any.
  int? rotationEpoch(String contactId) => _rotationEpochs[contactId];

  Future<void> _bumpIdentityEpoch() async {
    final current = await identityEpoch();
    await _backend.write(
      key: _identityEpochKey,
      value: (current + 1).toString(),
    );
  }

  // ---- V14: diagnostics (no secrets) ----

  /// Redacted summary for diagnostics. Contains key NAMES and counts
  /// only — never key material. Debug builds only: throws in release
  /// so even redacted metadata cannot be probed in production.
  Future<String> debugDescribe() async {
    if (!kDebugMode) {
      throw StateError('debugDescribe is debug-only');
    }
    const names = [
      _publicKeyKey,
      _privateKeyKey,
      _recoveryPhraseKey,
      _chhayaIdKey,
      _masterSeedKey,
      _identityEd25519Key,
      _identityX25519Key,
    ];
    final present = <String>[];
    for (final name in names) {
      if (await _backend.containsKey(key: name)) {
        present.add(name);
      }
    }
    return 'KeyManager(stored=[${present.join(',')}],'
        'cachedSessionKeys=${_sessionCache.length})';
  }

  /// Number of session keys currently in memory. Test-only probe used
  /// to verify background zeroization actually empties the cache.
  /// Debug builds only: throws in release.
  @visibleForTesting
  int get debugCachedSessionKeyCount {
    if (!kDebugMode) {
      throw StateError('debug-only probe');
    }
    return _sessionCache.length;
  }

  static final RegExp _pathPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9/_-]*$');

  static void _checkPath(String path) {
    if (!_pathPattern.hasMatch(path) || path.contains('..')) {
      throw ArgumentError.value(path, 'path', 'Invalid derivation path');
    }
  }

  static final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  static void _checkSegment(String value, String name) {
    if (value.isEmpty || !_segmentPattern.hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Invalid path segment');
    }
  }
}
