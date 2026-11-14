// Feature flag for the v2 hybrid PQXDH path (spec §5 WS2/WS5):
// `chhaya_pq_hybrid_v1`, default OFF. This task wires the code path and its
// tests; it does NOT enable v2 for production traffic and adds no UI flip.
//
// When the flag is off, v2 offers/establishment never fire; legacy
// persisted sessions remain decryptable. The `_state` deterministic
// establishment was deleted (spec §3.11) — flag-off means a fresh
// conversation fails closed rather than silently re-deriving old keys.
//
// The static seams exist ONLY for tests (unit + loopback integration), with
// one exception: `productionPrekeyProvider`, which the messaging layer wires
// to the on-device prekey store (WS5 slice 2) and which fails closed when no
// material is stored. The flag is read lazily on every use.
import 'dart:async';
import 'dart:typed_data';

import '../../core/crypto/pqc/prekey_bundle.dart';
import '../../core/crypto/pqc/pqc_provider.dart';
import '../api/prekey_bundle_client.dart';

/// Test-only responder prekey private material (the production prekey
/// upload + private-key storage flow does not exist yet — see the WS3
/// report follow-ups). Never populate in production builds.
class V2PrekeyMaterial {
  V2PrekeyMaterial({
    required this.signedPreKeyId,
    required this.signedPreKeyPrivateKey,
    required this.pqSignedPreKeyId,
    required this.pqSignedPreKeyPrivateKey,
    this.oneTimePreKeyId,
    this.oneTimePreKeyPrivateKey,
    this.pqOneTimePreKeyId,
    this.pqOneTimePreKeyPrivateKey,
  });

  final String signedPreKeyId;
  final Uint8List signedPreKeyPrivateKey;
  final String pqSignedPreKeyId;
  final Uint8List pqSignedPreKeyPrivateKey;
  final String? oneTimePreKeyId;
  final Uint8List? oneTimePreKeyPrivateKey;
  final String? pqOneTimePreKeyId;
  final Uint8List? pqOneTimePreKeyPrivateKey;
}

class PqHybridV1 {
  PqHybridV1._();

  static const String flagName = 'chhaya_pq_hybrid_v1';

  /// Test-only overrides; production MUST leave these null.
  static bool? testEnabled;
  static PqKem? testKem;
  static Future<PrekeyBundle> Function(String userId)? testBundleFetcher;

  /// Resolves the responder prekey material for the LOCAL account, keyed by
  /// our X25519 identity public key (tests enroll one account per side).
  /// Takes precedence over [productionPrekeyProvider].
  static V2PrekeyMaterial? Function(Uint8List ourIdentityPublicKey)?
      testPrekeyProvider;

  /// Production responder prekey material resolver (WS5 slice 2). Wired by
  /// the messaging layer to the on-device [PrekeyStore]; null in tests
  /// unless a test sets it. Receives the hex X25519 identity public key and
  /// the SPK/PQSPK ids the flight being accepted names (plus any one-time
  /// prekey ids). Returns null when material is unavailable — callers then
  /// fail closed exactly as before. Never logs key material.
  static Future<V2PrekeyMaterial?> Function(
    String identityPublicKey, {
    required String signedPreKeyId,
    required String pqSignedPreKeyId,
    String? oneTimePreKeyId,
    String? pqOneTimePreKeyId,
  })? productionPrekeyProvider;

  /// Test bridge for the Ed25519 identity public key bound into the v2
  /// transcript (spec §3.3). When set, callers use this instead of the
  /// device KeyManager so the bundle advertised by the fake server and the
  /// transcript agree.
  static Uint8List? Function(Uint8List ourIdentityPublicKey)?
      testEd25519PublicKey;

  static bool testUserConsented = false;

  /// Lazy production bundle fetcher for an authenticated API session.
  /// Returns null when there is no usable session (no auth token, bad
  /// baseUrl) so callers can fall back to the test seam. Fail-closed.
  static Future<PrekeyBundle> Function(String userId)? productionBundleFetcher({
    required bool apiAuthenticated,
    required String? authToken,
    required String baseUrl,
  }) {
    if (!apiAuthenticated || authToken == null) return null;
    final token = authToken;
    return (userId) =>
        PrekeyBundleClient(baseUrl: baseUrl, authToken: token).fetchBundle(userId);
  }

  /// Lazily evaluated on every access; absence ⇒ default OFF.
  static Future<bool> enabled() async =>
      testEnabled ?? const bool.fromEnvironment(flagName);

  static Future<bool> userConsented() async => testUserConsented;

  /// Clears every test seam; call from test tearDown.
  static void resetForTest() {
    testEnabled = null;
    testKem = null;
    testBundleFetcher = null;
    testPrekeyProvider = null;
    productionPrekeyProvider = null;
    testEd25519PublicKey = null;
    testUserConsented = false;
  }
}
