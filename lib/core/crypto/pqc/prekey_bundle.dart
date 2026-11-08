// Prekey bundle model + fail-closed parse/verify for Chhaya vNext
// (spec §3.2, WS1's GET /prekeys/:userId/bundle contract).
//
// Public material only. Untrusted JSON in; strictly typed model out or
// exception. Every signature is verified; stale or malformed bundles are
// rejected; missing fields are never fabricated.
import 'dart:typed_data';

import '../primitives/ed25519.dart';
import 'transcript.dart';

/// Thrown for any structural or cryptographic rejection of a bundle.
class PrekeyBundleException implements Exception {
  final String reason;
  const PrekeyBundleException(this.reason);
  @override
  String toString() => 'PrekeyBundleException: $reason';
}

Uint8List _hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw const PrekeyBundleException('odd-length hex string');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    final v = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (v == null) {
      throw const PrekeyBundleException('invalid hex string');
    }
    out[i ~/ 2] = v;
  }
  return out;
}

void _expectHex(String name, String value, int hexLength) {
  if (value.length != hexLength ||
      !RegExp('^[0-9a-f]{$hexLength}\$').hasMatch(value)) {
    throw PrekeyBundleException(
      '$name must be $hexLength lowercase hex chars',
    );
  }
}

void _expectUuid(String name, String value) {
  if (!RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$')
      .hasMatch(value)) {
    throw PrekeyBundleException('$name must be a lowercase canonical UUID');
  }
}

Map<String, dynamic> _expectMap(String name, Object? value) {
  if (value is! Map) {
    throw PrekeyBundleException('$name must be a JSON object');
  }
  return Map<String, dynamic>.from(value);
}

int _expectPositiveInt(String name, Object? value) {
  if (value is! int || value <= 0) {
    throw PrekeyBundleException('$name must be a positive integer');
  }
  return value;
}

bool _expectBool(String name, Object? value) {
  if (value is! bool) {
    throw PrekeyBundleException('$name must be a boolean');
  }
  return value;
}

String _expectString(String name, Object? value) {
  if (value is! String) {
    throw PrekeyBundleException('$name must be a string');
  }
  return value;
}

void _expectExactKeys(
  String name,
  Map<String, dynamic> map,
  Set<String> keys,
) {
  if (!map.keys.toSet().containsAll(keys) || map.length != keys.length) {
    // Unknown fields, missing fields, or both — reject, never guess.
    final missing = keys.difference(map.keys.toSet());
    final extra = map.keys.toSet().difference(keys);
    throw PrekeyBundleException(
      '$name: missing=${missing.isEmpty ? 'none' : missing.join(',')} '
      'extra=${extra.isEmpty ? 'none' : extra.join(',')}',
    );
  }
}

/// A signed (non-one-time) prekey with a validity window (spec §3.2).
class SignedPreKey {
  final String keyId;
  final Uint8List publicKey;
  final Uint8List signature;
  final int notBeforeMs;
  final int notAfterMs;
  const SignedPreKey({
    required this.keyId,
    required this.publicKey,
    required this.signature,
    required this.notBeforeMs,
    required this.notAfterMs,
  });
}

/// A one-time prekey (single-use, no validity window; spec §3.2).
class OneTimePreKey {
  final String keyId;
  final Uint8List publicKey;
  final Uint8List signature;
  const OneTimePreKey({
    required this.keyId,
    required this.publicKey,
    required this.signature,
  });
}

/// Advertised reseed KEM public key (spec §3.9; WS1 carries public+signature).
class ReseedKemKey {
  final Uint8List publicKey;
  final Uint8List signature;
  const ReseedKemKey({required this.publicKey, required this.signature});
}

/// Parsed, structurally valid prekey bundle. Signatures are verified by
/// [verifyPrekeyBundleSignatures]; presence of this object is not proof.
class PrekeyBundle {
  final Uint8List identityX25519; // 32 bytes (chhayaId '05' prefix stripped)
  final Uint8List identityEd25519; // 32 bytes
  final SignedPreKey signedPreKey;
  final SignedPreKey pqSignedPreKey;
  final OneTimePreKey? oneTimePreKey;
  final OneTimePreKey? pqOneTimePreKey;

  /// True iff the last-resort PQSPK is being served in place of a popped
  /// PQ one-time prekey (spec §2.3, §3.2, §4.3).
  final bool lastResortUsed;
  final ReseedKemKey reseedKemKey;

  const PrekeyBundle({
    required this.identityX25519,
    required this.identityEd25519,
    required this.signedPreKey,
    required this.pqSignedPreKey,
    required this.oneTimePreKey,
    required this.pqOneTimePreKey,
    required this.lastResortUsed,
    required this.reseedKemKey,
  });
}

SignedPreKey _parseSignedPreKey(
  String name,
  Object? value,
  int publicKeyHexLength,
) {
  final map = _expectMap(name, value);
  _expectExactKeys(
      name, map, {'keyId', 'publicKey', 'signature', 'notBefore', 'notAfter'});
  final keyId = _expectString('$name.keyId', map['keyId']);
  _expectUuid('$name.keyId', keyId);
  final publicKeyHex = _expectString('$name.publicKey', map['publicKey']);
  _expectHex('$name.publicKey', publicKeyHex, publicKeyHexLength);
  final signatureHex = _expectString('$name.signature', map['signature']);
  _expectHex('$name.signature', signatureHex, 128);
  final notBefore = _expectPositiveInt('$name.notBefore', map['notBefore']);
  final notAfter = _expectPositiveInt('$name.notAfter', map['notAfter']);
  if (notAfter <= notBefore) {
    throw PrekeyBundleException('$name: notAfter must be after notBefore');
  }
  return SignedPreKey(
    keyId: keyId,
    publicKey: _hexToBytes(publicKeyHex),
    signature: _hexToBytes(signatureHex),
    notBeforeMs: notBefore,
    notAfterMs: notAfter,
  );
}

OneTimePreKey? _parseOneTimePreKey(
  String name,
  Object? value,
  int publicKeyHexLength,
) {
  if (value == null) return null;
  final map = _expectMap(name, value);
  _expectExactKeys(name, map, {'keyId', 'publicKey', 'signature'});
  final keyId = _expectString('$name.keyId', map['keyId']);
  _expectUuid('$name.keyId', keyId);
  final publicKeyHex = _expectString('$name.publicKey', map['publicKey']);
  _expectHex('$name.publicKey', publicKeyHex, publicKeyHexLength);
  final signatureHex = _expectString('$name.signature', map['signature']);
  _expectHex('$name.signature', signatureHex, 128);
  return OneTimePreKey(
    keyId: keyId,
    publicKey: _hexToBytes(publicKeyHex),
    signature: _hexToBytes(signatureHex),
  );
}

/// Parses the server's bundle JSON (spec §3.2 / WS1 contract). Structural
/// checks only; call [verifyPrekeyBundleSignatures] before use. Any
/// deviation throws [PrekeyBundleException] — nothing is fabricated.
PrekeyBundle parsePrekeyBundle(Object? json) {
  final root = _expectMap('bundle', json);
  _expectExactKeys('bundle', root, {
    'v',
    'identity',
    'signedPreKey',
    'pqSignedPreKey',
    'oneTimePreKey',
    'pqOneTimePreKey',
    'lastResortUsed',
    'reseedKemKey',
  });
  if (_expectPositiveInt('v', root['v']) != 1) {
    throw const PrekeyBundleException('bundle v must be 1');
  }
  final identity = _expectMap('identity', root['identity']);
  _expectExactKeys('identity', identity, {'x25519', 'ed25519'});
  final x25519 = _expectString('identity.x25519', identity['x25519']);
  if (!RegExp(r'^05[0-9a-f]{64}$').hasMatch(x25519)) {
    throw const PrekeyBundleException(
      'identity.x25519 must be 05 followed by 64 lowercase hex chars',
    );
  }
  final ed25519 = _expectString('identity.ed25519', identity['ed25519']);
  _expectHex('identity.ed25519', ed25519, 64);

  final reseed = _expectMap('reseedKemKey', root['reseedKemKey']);
  _expectExactKeys('reseedKemKey', reseed, {'publicKey', 'signature'});
  final reseedPk = _expectString('reseedKemKey.publicKey', reseed['publicKey']);
  _expectHex('reseedKemKey.publicKey', reseedPk, 3136);
  final reseedSig = _expectString('reseedKemKey.signature', reseed['signature']);
  _expectHex('reseedKemKey.signature', reseedSig, 128);

  final lastResortUsed = _expectBool('lastResortUsed', root['lastResortUsed']);
  final pqOnce = _parseOneTimePreKey(
    'pqOneTimePreKey',
    root['pqOneTimePreKey'],
    3136,
  );
  // WS1 sets lastResortUsed == (pqOneTimePreKey == null); enforce the same
  // invariant fail-closed (spec §2.3, §4.3).
  if (lastResortUsed != (pqOnce == null)) {
    throw const PrekeyBundleException(
      'lastResortUsed inconsistent with pqOneTimePreKey presence',
    );
  }

  return PrekeyBundle(
    identityX25519: _hexToBytes(x25519.substring(2)),
    identityEd25519: _hexToBytes(ed25519),
    signedPreKey: _parseSignedPreKey('signedPreKey', root['signedPreKey'], 64),
    pqSignedPreKey:
        _parseSignedPreKey('pqSignedPreKey', root['pqSignedPreKey'], 3136),
    oneTimePreKey:
        _parseOneTimePreKey('oneTimePreKey', root['oneTimePreKey'], 64),
    pqOneTimePreKey: pqOnce,
    lastResortUsed: lastResortUsed,
    reseedKemKey: ReseedKemKey(
      publicKey: _hexToBytes(reseedPk),
      signature: _hexToBytes(reseedSig),
    ),
  );
}

/// Canonical signature preimages (SD-1, review-pending):
/// signed prekey: `LP(utf8(keyId)) ‖ LP(publicKey) ‖ u64be(notBeforeMs) ‖
/// u64be(notAfterMs)` (millisecond epochs exceed u32be).
/// one-time prekey: `LP(utf8(keyId)) ‖ LP(publicKey)`.
/// reseed KEM key: `LP(publicKey)`.
Uint8List signedPreKeySignaturePreimage(SignedPreKey key) {
  final out = BytesBuilder();
  out.add(lp(Uint8List.fromList(key.keyId.codeUnits)));
  out.add(lp(key.publicKey));
  out.add(_u64be(key.notBeforeMs));
  out.add(_u64be(key.notAfterMs));
  return out.toBytes();
}

/// Preimage for a one-time prekey signature (see [signedPreKeySignaturePreimage]).
Uint8List oneTimePreKeySignaturePreimage(OneTimePreKey key) {
  final out = BytesBuilder();
  out.add(lp(Uint8List.fromList(key.keyId.codeUnits)));
  out.add(lp(key.publicKey));
  return out.toBytes();
}

/// Preimage for the advertised reseed KEM key signature (SD-1, review-pending).
Uint8List reseedKemKeySignaturePreimage(ReseedKemKey key) => lp(key.publicKey);

Uint8List _u64be(int v) {
  if (v < 0) {
    throw ArgumentError.value(v, 'v', 'must be non-negative');
  }
  final out = Uint8List(8);
  var x = v;
  for (var i = 7; i >= 0; i--) {
    out[i] = x & 0xFF;
    x = x >> 8;
  }
  return out;
}

const int _signedPreKeyMaxWindowMs = 30 * 24 * 60 * 60 * 1000; // spec §3.2
const int _pqSignedPreKeyMaxWindowMs = 7 * 24 * 60 * 60 * 1000; // spec §3.2

/// Validity windows and Ed25519 signatures (spec §3.2). Every signature in
/// the bundle is verified against the identity signing key; any failure
/// throws [PrekeyBundleException].
Future<void> verifyPrekeyBundleSignatures(
  PrekeyBundle bundle, {
  DateTime? now,
}) async {
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  _checkWindow(
    'signedPreKey',
    bundle.signedPreKey,
    _signedPreKeyMaxWindowMs,
    nowMs,
  );
  _checkWindow(
    'pqSignedPreKey',
    bundle.pqSignedPreKey,
    _pqSignedPreKeyMaxWindowMs,
    nowMs,
  );

  final identity = bundle.identityEd25519;
  Future<void> check(
    String name,
    Uint8List preimage,
    Uint8List signature,
  ) async {
    final ok = await Ed25519Sign.verify(preimage, signature, identity);
    if (!ok) {
      throw PrekeyBundleException('$name: signature verification failed');
    }
  }

  await check(
    'signedPreKey',
    signedPreKeySignaturePreimage(bundle.signedPreKey),
    bundle.signedPreKey.signature,
  );
  await check(
    'pqSignedPreKey',
    signedPreKeySignaturePreimage(bundle.pqSignedPreKey),
    bundle.pqSignedPreKey.signature,
  );
  final opk = bundle.oneTimePreKey;
  if (opk != null) {
    await check(
      'oneTimePreKey',
      oneTimePreKeySignaturePreimage(opk),
      opk.signature,
    );
  }
  final pqopk = bundle.pqOneTimePreKey;
  if (pqopk != null) {
    await check(
      'pqOneTimePreKey',
      oneTimePreKeySignaturePreimage(pqopk),
      pqopk.signature,
    );
  }
  await check(
    'reseedKemKey',
    reseedKemKeySignaturePreimage(bundle.reseedKemKey),
    bundle.reseedKemKey.signature,
  );
}

void _checkWindow(
  String name,
  SignedPreKey key,
  int maxWindowMs,
  int nowMs,
) {
  if (key.notAfterMs - key.notBeforeMs > maxWindowMs) {
    throw PrekeyBundleException('$name: validity window exceeds maximum');
  }
  if (nowMs < key.notBeforeMs) {
    throw PrekeyBundleException('$name: not yet valid');
  }
  if (nowMs >= key.notAfterMs) {
    // Expired PQSPK ⇒ reject the bundle (spec §2.2, §3.6).
    throw PrekeyBundleException('$name: expired');
  }
}
