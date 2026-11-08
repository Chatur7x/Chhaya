// Canonical length-prefixed transcript for Chhaya vNext hybrid PQXDH (spec §3.3)
// and the §3.4 key-derivation equations.
//
// Byte-level canonical form; both peers compute identical bytes from the
// exchanged flight. Any deviation fails closed: SKs differ, AEAD fails,
// establishment aborts (spec §3.3.2, §3.6). Nothing here is wired into
// production messaging yet; WS3 binds T into AEAD additional data.
import 'dart:convert';
import 'dart:typed_data';

import '../primitives/hkdf.dart';
import '../primitives/sha.dart';

/// Protocol label bound as the first LP field of every transcript.
const String transcriptProtocolLabel = 'Chhaya-PQXDH-v1';

/// Wire/protocol version v2 (spec §3.0, §3.1.2).
const int protocolVersionV2 = 0x02;

/// Curve/kem/hash/aead registry bytes fixed by spec §3.3.
const int curveX25519 = 0x01;
const int kemMlKem1024 = 0x01;
const int hashSha256 = 0x01;
const int aeadAes256Gcm = 0x01;

/// Role bytes (spec §3.3.2). The role byte is the role of the party that
/// encapsulated ML-KEM (the establisher), not the local peer's role — both
/// peers must encode the same value or T differs and establishment fails.
/// Review-pending: the spec does not state this explicitly; see the WS2
/// report. 0x02 is reserved for a future bidirectional flight.
const int roleEstablisher = 0x01;
const int roleBidirectional = 0x02;

/// Selected-suite registry bytes (spec §3.0, §3.3). Spec-pinned only by
/// string; byte assignment is an SD decision (review-pending): the two
/// registered suites in priority order (highest priority first).
const int suiteBytePqxdhV1 = 0x01;
const int suiteByteClassicalConsentV1 = 0x02;

/// `LP(x)` = u16be(len(x)) ‖ x (spec §3.3.1).
Uint8List lp(Uint8List x) {
  if (x.length >= 0x10000) {
    throw ArgumentError.value(x.length, 'x', 'LP payload must be < 65536 bytes');
  }
  return Uint8List.fromList([
    (x.length >> 8) & 0xFF,
    x.length & 0xFF,
    ...x,
  ]);
}

/// `LP32(x)` = u32be(len(x)) ‖ x (spec §3.3.1); for ML-KEM ciphertexts.
Uint8List lp32(Uint8List x) {
  if (x.length > 0xFFFFFFFF) {
    throw ArgumentError.value(x.length, 'x', 'LP32 payload too large');
  }
  return Uint8List.fromList([
    (x.length >> 24) & 0xFF,
    (x.length >> 16) & 0xFF,
    (x.length >> 8) & 0xFF,
    x.length & 0xFF,
    ...x,
  ]);
}

Uint8List _lpString(String s) => lp(Uint8List.fromList(utf8.encode(s)));

/// Inputs to the canonical transcript T (spec §3.3.2, exact field order).
class TranscriptFields {
  const TranscriptFields({
    required this.protocolVersion,
    required this.selectedSuite,
    required this.curve,
    required this.kem,
    required this.hash,
    required this.aead,
    required this.initiatorVersion,
    required this.responderVersion,
    required this.conversationId,
    required this.initiatorX25519,
    required this.responderX25519,
    required this.initiatorEd25519,
    required this.responderEd25519,
    required this.ephemeralX25519,
    required this.signedPreKeyId,
    required this.pqSignedPreKeyId,
    required this.oneTimePreKeyId,
    required this.pqOneTimePreKeyId,
    required this.role,
    required this.mlKemCiphertext,
  });

  final int protocolVersion;
  final int selectedSuite;
  final int curve;
  final int kem;
  final int hash;
  final int aead;
  final int initiatorVersion;
  final int responderVersion;
  final String conversationId;
  final Uint8List initiatorX25519;
  final Uint8List responderX25519;
  final Uint8List initiatorEd25519;
  final Uint8List responderEd25519;
  final Uint8List ephemeralX25519;

  /// Signed (classical) prekey id.
  final String signedPreKeyId;

  /// Signed PQ prekey id.
  final String pqSignedPreKeyId;

  /// EC one-time prekey id, or `null` when no OPK was used — encoded LP("").
  final String? oneTimePreKeyId;

  /// PQ one-time prekey id, or `null` when the last-resort PQSPK was used.
  final String? pqOneTimePreKeyId;

  /// Role of the establisher (spec §3.3.2); `roleEstablisher` for the
  /// initiator-driven v2 flight.
  final int role;

  /// ML-KEM-1024 encapsulation ciphertext toward the peer's prekey.
  final Uint8List mlKemCiphertext;
}

void _checkU8(String name, int v) {
  if (v < 0 || v > 0xFF) {
    throw ArgumentError.value(v, name, 'Must fit in one unsigned byte');
  }
}

void _checkFixed32(String name, Uint8List v) {
  if (v.length != 32) {
    throw ArgumentError.value(v.length, name, 'Must be exactly 32 bytes');
  }
}

Uint8List _checkConvId(String name, String v) {
  if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      .hasMatch(v)) {
    throw ArgumentError.value(
      v,
      name,
      'conv_id must be a lowercase canonical UUID string',
    );
  }
  return Uint8List.fromList(utf8.encode(v));
}

/// Variant of [buildTranscript] for the v2 establishment flight: binds the
/// fixed §3.3 constants (v2 protocol, X25519, ML-KEM-1024, SHA-256,
/// AES-256-GCM, role = establisher). Both peers call this to obtain the
/// identical T; it is the only T assembly in the codebase.
Uint8List buildEstablishmentTranscript({
  required int selectedSuiteByte,
  required int initiatorVersion,
  required int responderVersion,
  required String conversationId,
  required Uint8List initiatorX25519,
  required Uint8List responderX25519,
  required Uint8List initiatorEd25519,
  required Uint8List responderEd25519,
  required Uint8List ephemeralX25519,
  required String signedPreKeyId,
  required String pqSignedPreKeyId,
  required String? oneTimePreKeyId,
  required String? pqOneTimePreKeyId,
  required Uint8List mlKemCiphertext,
}) {
  return buildTranscript(
    TranscriptFields(
      protocolVersion: protocolVersionV2,
      selectedSuite: selectedSuiteByte,
      curve: curveX25519,
      kem: kemMlKem1024,
      hash: hashSha256,
      aead: aeadAes256Gcm,
      initiatorVersion: initiatorVersion,
      responderVersion: responderVersion,
      conversationId: conversationId,
      initiatorX25519: initiatorX25519,
      responderX25519: responderX25519,
      initiatorEd25519: initiatorEd25519,
      responderEd25519: responderEd25519,
      ephemeralX25519: ephemeralX25519,
      signedPreKeyId: signedPreKeyId,
      pqSignedPreKeyId: pqSignedPreKeyId,
      oneTimePreKeyId: oneTimePreKeyId,
      pqOneTimePreKeyId: pqOneTimePreKeyId,
      role: roleEstablisher, // CT sender (initiator) — identical on both peers
      mlKemCiphertext: mlKemCiphertext,
    ),
  );
}

/// Builds the canonical transcript T (spec §3.3.2). The only builder in
/// the codebase — the static transcript-binding gate enforces this.
Uint8List buildTranscript(TranscriptFields f) {
  _checkU8('protocolVersion', f.protocolVersion);
  _checkU8('selectedSuite', f.selectedSuite);
  _checkU8('curve', f.curve);
  _checkU8('kem', f.kem);
  _checkU8('hash', f.hash);
  _checkU8('aead', f.aead);
  _checkU8('initiatorVersion', f.initiatorVersion);
  _checkU8('responderVersion', f.responderVersion);
  _checkU8('role', f.role);
  _checkFixed32('initiatorX25519', f.initiatorX25519);
  _checkFixed32('responderX25519', f.responderX25519);
  _checkFixed32('initiatorEd25519', f.initiatorEd25519);
  _checkFixed32('responderEd25519', f.responderEd25519);
  _checkFixed32('ephemeralX25519', f.ephemeralX25519);
  if (f.signedPreKeyId.isEmpty || f.pqSignedPreKeyId.isEmpty) {
    throw ArgumentError('Signed prekey ids must not be empty');
  }
  final convId = _checkConvId('conversationId', f.conversationId);
  return Uint8List.fromList([
    ..._lpString(transcriptProtocolLabel),
    f.protocolVersion,
    f.selectedSuite,
    f.curve,
    f.kem,
    f.hash,
    f.aead,
    f.initiatorVersion,
    f.responderVersion,
    ...lp(convId),
    ...f.initiatorX25519,
    ...f.responderX25519,
    ...f.initiatorEd25519,
    ...f.responderEd25519,
    ...f.ephemeralX25519,
    ..._lpString(f.signedPreKeyId),
    ..._lpString(f.pqSignedPreKeyId),
    ..._lpString(f.oneTimePreKeyId ?? ''),
    ..._lpString(f.pqOneTimePreKeyId ?? ''),
    f.role,
    ...lp32(f.mlKemCiphertext),
  ]);
}

/// `salt = SHA256(T)` (spec §3.4).
Uint8List transcriptHash(Uint8List transcript) => Sha.hash256(transcript);

/// `SK = HKDF-SHA256(ikm = 0xFF*32 ‖ DH1‖DH2‖DH3[‖DH4]‖SS, salt =
/// SHA256(T), info = "Chhaya-PQXDH-v1" ‖ suiteString, len = 32)`
/// (spec §3.1.4, §3.4 — OQ-2 resolved).
Uint8List deriveSessionKey({
  required Uint8List dh1,
  required Uint8List dh2,
  required Uint8List dh3,
  Uint8List? dh4,
  required Uint8List sharedSecret,
  required Uint8List transcript,
  required String suiteString,
}) {
  for (final entry in {'dh1': dh1, 'dh2': dh2, 'dh3': dh3}.entries) {
    _checkFixed32(entry.key, entry.value);
  }
  if (dh4 != null) _checkFixed32('dh4', dh4);
  _checkFixed32('sharedSecret', sharedSecret);
  final ikm = Uint8List.fromList([
    ...List.filled(32, 0xFF),
    ...dh1,
    ...dh2,
    ...dh3,
    if (dh4 != null) ...dh4,
    ...sharedSecret,
  ]);
  try {
    return Hkdf.deriveKey(
      inputKeyMaterial: ikm,
      salt: transcriptHash(transcript),
      info: Uint8List.fromList(
        utf8.encode('Chhaya-PQXDH-v1$suiteString'),
      ),
      length: 32,
    );
  } finally {
    ikm.fillRange(0, ikm.length, 0);
  }
}

/// Consented classical fallback, domain-separated (spec §3.4):
/// `SK_fb = HKDF(ikm = DHsClassical, salt = SHA256(T),
/// info = "Chhaya-Classical-Fallback-v1" ‖ suiteByte, len = 32)`.
Uint8List deriveClassicalFallbackKey({
  required Uint8List classicalSharedSecret,
  required Uint8List transcript,
  required int suiteByte,
}) {
  if (classicalSharedSecret.length < 32) {
    throw ArgumentError.value(
      classicalSharedSecret.length,
      'classicalSharedSecret',
      'Must be at least 32 bytes',
    );
  }
  _checkU8('suiteByte', suiteByte);
  return Hkdf.deriveKey(
    inputKeyMaterial: classicalSharedSecret,
    salt: transcriptHash(transcript),
    info: Uint8List.fromList([
      ...utf8.encode('Chhaya-Classical-Fallback-v1'),
      suiteByte,
    ]),
    length: 32,
  );
}
