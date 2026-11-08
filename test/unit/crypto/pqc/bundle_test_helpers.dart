// Shared fixture helpers for prekey-bundle tests. Builds a structurally
// valid, correctly signed bundle from a known Ed25519 seed so both the
// parser/verifier tests and the fetch-client tests exercise the same path.
// Test-only deterministic keys; never used for real accounts.
import 'dart:typed_data';

import 'package:chaaya/core/crypto/pqc/prekey_bundle.dart';
import 'package:chaaya/core/crypto/primitives/ed25519.dart';
import 'package:cryptography/cryptography.dart';

Uint8List fill(int len, int byte) =>
    Uint8List.fromList(List.filled(len, byte));

String hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class BundleFixture {
  BundleFixture._(this.identitySeed, this.identityPublicKey);

  final Uint8List identitySeed;
  final Uint8List identityPublicKey;

  static const peerUserId = '11111111-2222-4333-8444-555555555555';

  static Future<BundleFixture> create({int seedOffset = 0}) async {
    final seed = Uint8List.fromList(
      List.generate(32, (i) => (0x40 + i + seedOffset) & 0xff),
    );
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final pub = await keyPair.extractPublicKey();
    return BundleFixture._(seed, Uint8List.fromList(pub.bytes));
  }

  Future<Uint8List> sign(Uint8List preimage) =>
      Ed25519Sign.sign(preimage, identitySeed);

  String get identityX25519Hex => '05${hex(fill(32, 0xb1))}';
  String get identityEd25519Hex => hex(identityPublicKey);

  /// Builds the §3.2/WS1 bundle JSON, correctly signed unless a
  /// `corrupt*` flag is set. [nowMs] defaults to now; pass a past value to
  /// test expiry. [spkWindowDays]/[pqspkWindowDays] widen the signed
  /// validity windows (correctly signed) to exercise window rejection.
  Future<Map<String, dynamic>> bundleJson({
    int? nowMs,
    bool lastResort = false,
    bool corruptPqSignedPreKeySignature = false,
    bool corruptReseedSignature = false,
    int? spkWindowDays,
    int? pqspkWindowDays,
    Map<String, dynamic>? overrides,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final day = const Duration(days: 1).inMilliseconds;

    final spk = await _signedKeyJson(
      keyId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      publicKey: fill(32, 0x61),
      notBefore: now - day,
      notAfter: now - day +
          (spkWindowDays != null ? spkWindowDays * day : 20 * day),
    );
    final pqspk = await _signedKeyJson(
      keyId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      publicKey: fill(1568, 0x71),
      notBefore: now - day,
      notAfter: now - day +
          (pqspkWindowDays != null ? pqspkWindowDays * day : 5 * day),
      corruptSignature: corruptPqSignedPreKeySignature,
    );
    final opkJson = await _oneTimeKeyJson(
      keyId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      publicKey: fill(32, 0x62),
    );
    final pqopkJson = await _oneTimeKeyJson(
      keyId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      publicKey: fill(1568, 0x72),
    );
    final reseedPk = fill(1568, 0x73);
    var reseedSig = await sign(
      reseedKemKeySignaturePreimage(
        ReseedKemKey(publicKey: reseedPk, signature: fill(64, 0)),
      ),
    );
    if (corruptReseedSignature) {
      reseedSig = Uint8List.fromList(reseedSig)..[0] ^= 0x01;
    }

    final json = <String, dynamic>{
      'v': 1,
      'identity': {
        'x25519': identityX25519Hex,
        'ed25519': identityEd25519Hex,
      },
      'signedPreKey': spk,
      'pqSignedPreKey': pqspk,
      'oneTimePreKey': opkJson,
      'pqOneTimePreKey': lastResort ? null : pqopkJson,
      'lastResortUsed': lastResort,
      'reseedKemKey': {
        'publicKey': hex(reseedPk),
        'signature': hex(reseedSig),
      },
    };
    if (overrides != null) {
      json.addAll(overrides);
    }
    return json;
  }

  Future<Map<String, dynamic>> _signedKeyJson({
    required String keyId,
    required Uint8List publicKey,
    required int notBefore,
    required int notAfter,
    bool corruptSignature = false,
  }) async {
    final preimage = signedPreKeySignaturePreimage(SignedPreKey(
      keyId: keyId,
      publicKey: publicKey,
      signature: Uint8List(64),
      notBeforeMs: notBefore,
      notAfterMs: notAfter,
    ));
    var signature = await sign(preimage);
    if (corruptSignature) {
      signature = Uint8List.fromList(signature)..[0] ^= 0x01;
    }
    return {
      'keyId': keyId,
      'publicKey': hex(publicKey),
      'signature': hex(signature),
      'notBefore': notBefore,
      'notAfter': notAfter,
    };
  }

  Future<Map<String, dynamic>> _oneTimeKeyJson({
    required String keyId,
    required Uint8List publicKey,
  }) async {
    final preimage = oneTimePreKeySignaturePreimage(OneTimePreKey(
      keyId: keyId,
      publicKey: publicKey,
      signature: Uint8List(64),
    ));
    return {
      'keyId': keyId,
      'publicKey': hex(publicKey),
      'signature': hex(await sign(preimage)),
    };
  }
}
