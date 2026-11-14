// Client-side private-material store for the v2 PQ prekey path (WS5 slice 1).
//
// Purpose: own the PRIVATE halves of the rotating prekey material this client
// advertises to the backend so a peer can build an X3DH/PQXDH flight toward
// us (spec §3.2): one X25519 signed prekey (30-day window), one ML-KEM-1024
// PQ signed prekey (7-day window), 100 X25519 one-time prekeys, 100 ML-KEM-1024
// PQ one-time prekeys, and one ML-KEM-1024 reseed KEM key (7-day rotation
// cadence, rotated together with the PQSPK). Private halves are stored behind
// the [SecureStorage] interface (platform keystore) as base64 strings; nothing
// in this class logs, prints, or otherwise exposes them. The only way private
// material leaves this class is [materialFor], which hands a
// [V2PrekeyMaterial] (lib/services/messaging/pq_hybrid_v1.dart) to the local
// responder establishment path. Public halves are returned once per call as a
// WS1 upload payload; no network calls happen in this slice (the upload
// client is WS5 slice 2).
//
// Storage layout (every key under the `prekey/` prefix):
//   prekey/spk/<id>      base64 X25519 SPK private key (raw 32 bytes)
//   prekey/spk_id        current SPK id (uuid) — used when materialFor omits
//                        pqSignedPreKeyId for the PQ side and for rotation
//   prekey/spk_window    JSON {"notBefore":"<u64 dec ms>","notAfter":"<u64 dec ms>"}
//   prekey/spk_index     JSON array of every SPK id ever generated (grace)
//   prekey/pqspk/<id>    base64 ML-KEM-1024 PQSPK private key
//   prekey/pqspk_id      current PQSPK id (uuid)
//   prekey/pqspk_window  JSON window, same encoding as prekey/spk_window
//   prekey/pqspk_index   JSON array of every PQSPK id ever generated
//   prekey/opk/<id>      base64 X25519 OPK private key (single use)
//   prekey/opk_index     JSON array of stored (unconsumed) OPK ids
//   prekey/pqopk/<id>    base64 ML-KEM-1024 PQOPK private key (single use)
//   prekey/pqopk_index   JSON array of stored (unconsumed) PQOPK ids
//   prekey/reseed        base64 ML-KEM-1024 reseed KEM private key (overwritten
//                        each rotation; advertised reseedKemKey has no keyId)
//
// Regeneration keeps superseded SPK/PQSPK private keys (rotation grace,
// spec §3.2: old SPKs stay verifiable but are never selected for new
// establishments). One-time prekeys are single-use and are deleted via
// [consumeOneTimePreKey] by the responder path after a flight is accepted.
// [shredAll] wipes every `prekey/` entry this class can have written; it is
// intended for tests and for the WS5 slice-2 wire into clearAllAccountSecrets.
//
// Default-off: nothing here flips a flag or claims quantum resistance.
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../services/messaging/pq_hybrid_v1.dart' show V2PrekeyMaterial;
import '../key_manager.dart';
import '../primitives/ed25519.dart';
import '../primitives/rng.dart';
import '../primitives/sha.dart';
import '../primitives/x25519.dart';
import '../storage/secure_storage.dart';
import 'ml_kem.dart';
import 'pqc_provider.dart';
import 'prekey_bundle.dart';

/// Public result of [PrekeyStore.generateFreshBundle].
///
/// Carries the WS1 upload payload (public material only, spec §3.2) in
/// [bundleJson]: `v`, `identity{x25519 ('05'-prefixed chhayaId hex),
/// ed25519}`, `signedPreKey`, `pqSignedPreKey`, `oneTimePreKeys[]` (100),
/// `pqOneTimePreKeys[]` (100), `reseedKemKey`. All public keys and
/// signatures are lowercase hex (ML-KEM public keys are 3136 hex chars);
/// validity windows are integer milliseconds since the epoch; Ed25519
/// signature preimages are the SD-1 encodings from prekey_bundle.dart.
class V2PrekeyMaterialGeneration {
  /// Creates the generation record wrapping [bundleJson].
  V2PrekeyMaterialGeneration({required this.bundleJson});

  /// The WS1 upload payload. Public material only — safe to hand to the
  /// upload client (slice 2). Never contains private key bytes.
  final Map<String, dynamic> bundleJson;

  /// Convenience accessor for the advertised SPK id.
  String get signedPreKeyId =>
      bundleJson['signedPreKey']['keyId'] as String;

  /// Convenience accessor for the advertised PQSPK id.
  String get pqSignedPreKeyId =>
      bundleJson['pqSignedPreKey']['keyId'] as String;
}

/// Owns the private halves of this client's v2 prekey material.
///
/// Construct with the same [SecureStorage] the rest of the app uses
/// ([SecureStorages.platformDefault] in production, `SecureStorageMock` in
/// tests). Pass [kem] to inject a test provider; the default is the
/// native ML-KEM-1024 adapter, which fails closed where no approved
/// provider exists.
class PrekeyStore {
  /// Creates a store over [storage]. The internal [KeyManager] is used only
  /// to resolve the identity key pair and the identity Ed25519 seed — this
  /// class never reimplements derivation.
  PrekeyStore(SecureStorage storage, {PqKem? kem})
      : _storage = storage,
        // Public parameter name keeps the test seam usable outside this file.
        // ignore: prefer_initializing_formals
        _kem = kem,
        _keyManager = KeyManager(secureBackend: storage);

  static const int _oneTimePreKeyCount = 100;
  static const Duration _spkWindow = Duration(days: 30); // spec §3.2
  static const Duration _pqWindow = Duration(days: 7); // spec §3.2

  static const String _spkIndexKey = 'prekey/spk_index';
  static const String _pqspkIndexKey = 'prekey/pqspk_index';
  static const String _opkIndexKey = 'prekey/opk_index';
  static const String _pqopkIndexKey = 'prekey/pqopk_index';
  static const String _spkIdKey = 'prekey/spk_id';
  static const String _pqspkIdKey = 'prekey/pqspk_id';
  static const String _spkWindowKey = 'prekey/spk_window';
  static const String _pqspkWindowKey = 'prekey/pqspk_window';
  static const String _reseedKey = 'prekey/reseed';

  /// Mirrors the one private storage key [KeyManager] uses for a rotated
  /// Ed25519 identity seed (see [KeyManager.rotateIdentity]). Kept in sync
  /// with key_manager.dart deliberately: when a stored rotated seed exists
  /// it — not the HKDF-derived seed — is the identity signing key that
  /// [KeyManager.getIdentityEd25519PublicKeyBytes] advertises, so the
  /// bundle signatures must be produced with the same seed. The derivation
  /// itself is never reimplemented.
  static const String _rotatedEd25519SeedKey = 'chhaya_identity_ed25519_seed';

  final SecureStorage _storage;
  final PqKem? _kem;
  final KeyManager _keyManager;
  final Uuid _uuid = const Uuid();

  static String _spkKey(String id) => 'prekey/spk/$id';
  static String _pqspkKey(String id) => 'prekey/pqspk/$id';
  static String _opkKey(String id) => 'prekey/opk/$id';
  static String _pqopkKey(String id) => 'prekey/pqopk/$id';

  /// Generates a fresh bundle's worth of prekey material and persists the
  /// private halves.
  ///
  /// Returns the unsigned-on-the-wire public payload (already signed) for
  /// the WS1 upload route (slice 2). Throws if no identity key pair exists
  /// on this device, or if the ML-KEM provider is unavailable — never
  /// fabricates material. All raw private-key bytes this method creates are
  /// wiped before returning; only the base64 copies inside [SecureStorage]
  /// survive.
  Future<V2PrekeyMaterialGeneration> generateFreshBundle() async {
    final kem = _kem ?? MlKem1024();
    if (!await kem.initialize()) {
      throw PqcUnavailableException(kem.name);
    }

    final pair = await _keyManager.getKeyPair();
    if (pair == null) {
      throw StateError(
        'identity key pair missing; cannot advertise a prekey bundle',
      );
    }
    final ed25519Public = await _keyManager.getIdentityEd25519PublicKeyBytes();
    final ed25519Seed = await _identityEd25519Seed();

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final spkNotBefore = now;
    final spkNotAfter = now + _spkWindow.inMilliseconds;
    final pqNotBefore = now;
    final pqNotAfter = now + _pqWindow.inMilliseconds;

    try {
      // --- Signed prekeys -------------------------------------------------
      final spk = await X25519Kex.generateKeyPair();
      final spkId = _uuid.v4();
      final spkSignature = await _signHex(
        signedPreKeySignaturePreimage(SignedPreKey(
          keyId: spkId,
          publicKey: spk.publicKey,
          signature: Uint8List(Ed25519Sign.signatureLength),
          notBeforeMs: spkNotBefore,
          notAfterMs: spkNotAfter,
        )),
        ed25519Seed,
      );
      await _storage.write(
        key: _spkKey(spkId),
        value: base64Encode(spk.privateKey),
      );
      Csprng.wipe(spk.privateKey);
      await _storage.write(key: _spkIdKey, value: spkId);
      await _storage.write(
        key: _spkWindowKey,
        value: _windowJson(spkNotBefore, spkNotAfter),
      );
      await _addToIndex(_spkIndexKey, [spkId]);

      final pqspk = await kem.generateKeyPair();
      final pqspkId = _uuid.v4();
      final pqspkSignature = await _signHex(
        signedPreKeySignaturePreimage(SignedPreKey(
          keyId: pqspkId,
          publicKey: pqspk.publicKey,
          signature: Uint8List(Ed25519Sign.signatureLength),
          notBeforeMs: pqNotBefore,
          notAfterMs: pqNotAfter,
        )),
        ed25519Seed,
      );
      await _storage.write(
        key: _pqspkKey(pqspkId),
        value: base64Encode(pqspk.privateKey),
      );
      Csprng.wipe(pqspk.privateKey);
      await _storage.write(key: _pqspkIdKey, value: pqspkId);
      await _storage.write(
        key: _pqspkWindowKey,
        value: _windowJson(pqNotBefore, pqNotAfter),
      );
      await _addToIndex(_pqspkIndexKey, [pqspkId]);

      // --- One-time prekeys -----------------------------------------------
      final oneTimePreKeys = <Map<String, dynamic>>[];
      final opkIds = <String>[];
      for (var i = 0; i < _oneTimePreKeyCount; i++) {
        final opk = await X25519Kex.generateKeyPair();
        final id = _uuid.v4();
        final signature = await _signHex(
          oneTimePreKeySignaturePreimage(OneTimePreKey(
            keyId: id,
            publicKey: opk.publicKey,
            signature: Uint8List(Ed25519Sign.signatureLength),
          )),
          ed25519Seed,
        );
        await _storage.write(
          key: _opkKey(id),
          value: base64Encode(opk.privateKey),
        );
        Csprng.wipe(opk.privateKey);
        opkIds.add(id);
        oneTimePreKeys.add({
          'keyId': id,
          'publicKey': Sha.hexOf(opk.publicKey),
          'signature': signature,
        });
      }
      await _addToIndex(_opkIndexKey, opkIds);

      final pqOneTimePreKeys = <Map<String, dynamic>>[];
      final pqopkIds = <String>[];
      for (var i = 0; i < _oneTimePreKeyCount; i++) {
        final pqopk = await kem.generateKeyPair();
        final id = _uuid.v4();
        final signature = await _signHex(
          oneTimePreKeySignaturePreimage(OneTimePreKey(
            keyId: id,
            publicKey: pqopk.publicKey,
            signature: Uint8List(Ed25519Sign.signatureLength),
          )),
          ed25519Seed,
        );
        await _storage.write(
          key: _pqopkKey(id),
          value: base64Encode(pqopk.privateKey),
        );
        Csprng.wipe(pqopk.privateKey);
        pqopkIds.add(id);
        pqOneTimePreKeys.add({
          'keyId': id,
          'publicKey': Sha.hexOf(pqopk.publicKey),
          'signature': signature,
        });
      }
      await _addToIndex(_pqopkIndexKey, pqopkIds);

      // --- Reseed KEM key (advertised; rotated with the PQSPK) ------------
      final reseed = await kem.generateKeyPair();
      final reseedSignature = await _signHex(
        reseedKemKeySignaturePreimage(ReseedKemKey(
          publicKey: reseed.publicKey,
          signature: Uint8List(Ed25519Sign.signatureLength),
        )),
        ed25519Seed,
      );
      await _storage.write(
        key: _reseedKey,
        value: base64Encode(reseed.privateKey),
      );
      Csprng.wipe(reseed.privateKey);

      // --- Public upload payload (spec §3.2 / WS1) -------------------------
      final bundleJson = <String, dynamic>{
        'v': 1,
        'identity': {
          'x25519': '05${Sha.hexOf(pair.publicKey)}',
          'ed25519': Sha.hexOf(ed25519Public),
        },
        'signedPreKey': {
          'keyId': spkId,
          'publicKey': Sha.hexOf(spk.publicKey),
          'signature': spkSignature,
          'notBefore': spkNotBefore,
          'notAfter': spkNotAfter,
        },
        'pqSignedPreKey': {
          'keyId': pqspkId,
          'publicKey': Sha.hexOf(pqspk.publicKey),
          'signature': pqspkSignature,
          'notBefore': pqNotBefore,
          'notAfter': pqNotAfter,
        },
        'oneTimePreKeys': oneTimePreKeys,
        'pqOneTimePreKeys': pqOneTimePreKeys,
        'reseedKemKey': {
          'publicKey': Sha.hexOf(reseed.publicKey),
          'signature': reseedSignature,
        },
      };
      return V2PrekeyMaterialGeneration(bundleJson: bundleJson);
    } finally {
      Csprng.wipe(ed25519Seed);
    }
  }

  /// Resolves the private material for a responder establishment.
  ///
  /// [signedPreKeyId] is required and read by id. When [pqSignedPreKeyId]
  /// is omitted the current advertised PQSPK (from the last
  /// [generateFreshBundle]) is used; an unknown explicit id is an error
  /// condition, not a fallback. One-time prekey ids are never auto-picked:
  /// omitted ids mean no one-time prekey in the result; a provided id whose
  /// private half is missing (or corrupt) fails the whole call with null —
  /// nothing is fabricated. Returns null when any required piece is absent.
  Future<V2PrekeyMaterial?> materialFor(
    String signedPreKeyId, {
    String? pqSignedPreKeyId,
    String? oneTimePreKeyId,
    String? pqOneTimePreKeyId,
  }) async {
    final spk = await _readPrivate(_spkKey(signedPreKeyId));
    if (spk == null) {
      return null;
    }
    final effectivePqspkId = pqSignedPreKeyId ??
        await _storage.read(key: _pqspkIdKey);
    if (effectivePqspkId == null) {
      return null;
    }
    final pqspk = await _readPrivate(_pqspkKey(effectivePqspkId));
    if (pqspk == null) {
      return null;
    }

    Uint8List? opk;
    if (oneTimePreKeyId != null) {
      opk = await _readPrivate(_opkKey(oneTimePreKeyId));
      if (opk == null) {
        return null;
      }
    }
    Uint8List? pqopk;
    if (pqOneTimePreKeyId != null) {
      pqopk = await _readPrivate(_pqopkKey(pqOneTimePreKeyId));
      if (pqopk == null) {
        return null;
      }
    }

    return V2PrekeyMaterial(
      signedPreKeyId: signedPreKeyId,
      signedPreKeyPrivateKey: spk,
      pqSignedPreKeyId: effectivePqspkId,
      pqSignedPreKeyPrivateKey: pqspk,
      oneTimePreKeyId: opk == null ? null : oneTimePreKeyId,
      oneTimePreKeyPrivateKey: opk,
      pqOneTimePreKeyId: pqopk == null ? null : pqOneTimePreKeyId,
      pqOneTimePreKeyPrivateKey: pqopk,
    );
  }

  /// Deletes the private halves stored under [keyId] in both one-time
  /// prekey namespaces (`prekey/opk/` and `prekey/pqopk/`). Idempotent:
  /// missing entries and missing indexes are fine. Call after the flight
  /// that consumed the key has been accepted; keys are single-use.
  Future<void> consumeOneTimePreKey(String keyId) async {
    await _storage.delete(key: _opkKey(keyId));
    await _storage.delete(key: _pqopkKey(keyId));
    await _removeFromIndex(_opkIndexKey, keyId);
    await _removeFromIndex(_pqopkIndexKey, keyId);
  }

  /// Diagnostics only: the ids of stored, unconsumed X25519 one-time
  /// prekeys. Read-only; never returns private material. PQ one-time ids
  /// are tracked separately under `prekey/pqopk_index` for [shredAll].
  Future<List<String>> knownOneTimePreKeyIds() => _readIndex(_opkIndexKey);

  /// Wipes every `prekey/` entry this class can have written: all SPK,
  /// PQSPK, OPK and PQOPK private halves referenced by the indexes (plus
  /// their indexes), the id pointers, the validity windows, and the reseed
  /// KEM private key. Test-only in this slice; slice 2 wires this into
  /// clearAllAccountSecrets.
  Future<void> shredAll() async {
    final indexes = <String, String Function(String)>{
      _spkIndexKey: _spkKey,
      _pqspkIndexKey: _pqspkKey,
      _opkIndexKey: _opkKey,
      _pqopkIndexKey: _pqopkKey,
    };
    for (final entry in indexes.entries) {
      for (final id in await _readIndex(entry.key)) {
        await _storage.delete(key: entry.value(id));
      }
      await _storage.delete(key: entry.key);
    }
    for (final key in const [
      _spkIdKey,
      _pqspkIdKey,
      _spkWindowKey,
      _pqspkWindowKey,
      _reseedKey,
    ]) {
      await _storage.delete(key: key);
    }
  }

  /// The identity Ed25519 signing seed, with the same precedence
  /// [KeyManager] uses for the advertised public key: an explicitly stored
  /// (rotated) seed wins; otherwise the seed derived via
  /// [KeyManager.derivePathKey]. Caller must wipe the returned bytes.
  Future<Uint8List> _identityEd25519Seed() async {
    final stored = await _storage.read(key: _rotatedEd25519SeedKey);
    if (stored != null) {
      try {
        return Uint8List.fromList(base64Decode(stored));
      } on FormatException {
        throw StateError('stored identity ed25519 seed is corrupt');
      }
    }
    return _keyManager.derivePathKey(KeyManager.pathIdentityEd25519);
  }

  Future<String> _signHex(Uint8List preimage, Uint8List ed25519Seed) async {
    return Sha.hexOf(await Ed25519Sign.sign(preimage, ed25519Seed));
  }

  String _windowJson(int notBefore, int notAfter) => jsonEncode({
        'notBefore': notBefore.toString(),
        'notAfter': notAfter.toString(),
      });

  Future<Uint8List?> _readPrivate(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) {
      return null;
    }
    try {
      return Uint8List.fromList(base64Decode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<List<String>> _readIndex(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) {
      return <String>[];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw StateError('prekey index corrupt: $key');
    }
    if (decoded is! List || decoded.any((e) => e is! String)) {
      throw StateError('prekey index corrupt: $key');
    }
    return List<String>.from(decoded);
  }

  Future<void> _addToIndex(String key, Iterable<String> ids) async {
    final merged = <String>{...await _readIndex(key), ...ids}.toList()..sort();
    await _storage.write(key: key, value: jsonEncode(merged));
  }

  Future<void> _removeFromIndex(String key, String id) async {
    final existing = await _readIndex(key);
    if (!existing.contains(id)) {
      return;
    }
    await _storage.write(
      key: key,
      value: jsonEncode(existing.where((e) => e != id).toList()),
    );
  }
}
