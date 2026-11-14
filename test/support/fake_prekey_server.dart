// Test-only fake prekey server: in-memory stand-in for WS1's bundle
// distribution (`GET /prekeys/:userId/bundle`) for unit and loopback
// integration tests. Every bundle is correctly signed with a real Ed25519
// key and passes the client's real parse + signature-verification path, so
// tests exercise the same cryptography as production.
//
// NOT for production: keys are generated fresh per enrollment and kept in
// memory. The client-side prekey upload + private-key storage flow does
// not exist yet, so this seam is what makes v2 testable end to end today.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chaaya/core/crypto/primitives/ed25519.dart';
import 'package:chaaya/core/crypto/primitives/rng.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:chaaya/core/crypto/pqc/prekey_bundle.dart';
import 'package:chaaya/core/crypto/pqc/pqc_provider.dart';
import 'package:chaaya/services/api/prekey_bundle_client.dart';
import 'package:chaaya/services/messaging/pq_hybrid_v1.dart';
import 'package:cryptography/cryptography.dart';

Uint8List _fill(int len, int byte) =>
    Uint8List.fromList(List.filled(len, byte));

Uint8List _random(int len) => Csprng.instance.bytes(len);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A fully signed fake server account's bundle material.
class EnrolledAccount {
  EnrolledAccount._({
    required this.userId,
    required this.identityX25519,
    required this.identityEd25519Public,
    required this.signedPreKeyId,
    required this.pqSignedPreKeyId,
    required this.oneTimePreKeyId,
    required this.pqOneTimePreKeyId,
  });

  final String userId;
  final Uint8List identityX25519; // 32 bytes, '05'-prefix stripped
  final Uint8List identityEd25519Public; // 32 bytes
  final String signedPreKeyId;
  final String pqSignedPreKeyId;
  final String oneTimePreKeyId;
  final String pqOneTimePreKeyId;

  late final Map<String, dynamic> _json;
  late final V2PrekeyMaterial _material;

  Future<PrekeyBundle> fetch({DateTime? now}) async {
    final bundle = parsePrekeyBundle(jsonDecode(jsonEncode(_json)));
    await verifyPrekeyBundleSignatures(bundle, now: now);
    return bundle;
  }

  V2PrekeyMaterial get material => _material;
}

class FakePrekeyServer {
  final Map<String, EnrolledAccount> _byUserId = {};
  final Map<String, EnrolledAccount> _byIdentityHex = {};

  /// Enrolls an account bound to [identityX25519] (32 bytes, contact's
  /// chhayaId public key without the '05' prefix). A fresh random
  /// seed-backed Ed25519 identity is generated per account.
  Future<EnrolledAccount> enroll(
    String userId,
    Uint8List identityX25519,
  ) async {
    final existing = _byUserId[userId];
    if (existing != null) {
      if (!_bytesEq(existing.identityX25519, identityX25519)) {
        throw ArgumentError('userId already enrolled with a different identity');
      }
      return existing;
    }
    final edSeed = _random(32);
    final algorithm = Ed25519();
    final edKeyPair = await algorithm.newKeyPairFromSeed(edSeed);
    final edPub = Uint8List.fromList((await edKeyPair.extractPublicKey()).bytes);
    final spk = await X25519Kex.generateKeyPair();
    final opk = await X25519Kex.generateKeyPair();
    final spkId = _uuid();
    final pqspkId = _uuid();
    final opkId = _uuid();
    final pqopkId = _uuid();
    final now = DateTime.now().millisecondsSinceEpoch;
    final day = const Duration(days: 1).inMilliseconds;

    Future<Map<String, dynamic>> signedKeyJson({
      required String keyId,
      required List<int> publicKey,
      required int notBefore,
      required int notAfter,
    }) async {
      final preimage = signedPreKeySignaturePreimage(SignedPreKey(
        keyId: keyId,
        publicKey: Uint8List.fromList(publicKey),
        signature: Uint8List(64),
        notBeforeMs: notBefore,
        notAfterMs: notAfter,
      ));
      final signature = await Ed25519Sign.sign(preimage, edSeed);
      return {
        'keyId': keyId,
        'publicKey': _hex(publicKey),
        'signature': _hex(signature),
        'notBefore': notBefore,
        'notAfter': notAfter,
      };
    }

    Future<Map<String, dynamic>> oneTimeKeyJson({
      required String keyId,
      required List<int> publicKey,
    }) async {
      final preimage = oneTimePreKeySignaturePreimage(OneTimePreKey(
        keyId: keyId,
        publicKey: Uint8List.fromList(publicKey),
        signature: Uint8List(64),
      ));
      final signature = await Ed25519Sign.sign(preimage, edSeed);
      return {
        'keyId': keyId,
        'publicKey': _hex(publicKey),
        'signature': _hex(signature),
      };
    }

    final pqspkPublic = _fill(1568, 0x71);
    final pqopkPublic = _fill(1568, 0x72);
    final reseedPublic = _fill(1568, 0x73);
    final reseedPreimage = reseedKemKeySignaturePreimage(
      ReseedKemKey(publicKey: reseedPublic, signature: Uint8List(64)),
    );
    final reseedSignature = await Ed25519Sign.sign(reseedPreimage, edSeed);

    final json = <String, dynamic>{
      'v': 1,
      'identity': {
        'x25519': '05${_hex(identityX25519)}',
        'ed25519': _hex(edPub),
      },
      'signedPreKey': await signedKeyJson(
        keyId: spkId,
        publicKey: spk.publicKey,
        notBefore: now - day,
        notAfter: now - day + 25 * day,
      ),
      'pqSignedPreKey': await signedKeyJson(
        keyId: pqspkId,
        publicKey: pqspkPublic,
        notBefore: now - day,
        notAfter: now - day + 5 * day,
      ),
      'oneTimePreKey': await oneTimeKeyJson(
        keyId: opkId,
        publicKey: opk.publicKey,
      ),
      'pqOneTimePreKey': await oneTimeKeyJson(
        keyId: pqopkId,
        publicKey: pqopkPublic,
      ),
      'lastResortUsed': false,
      'reseedKemKey': {
        'publicKey': _hex(reseedPublic),
        'signature': _hex(reseedSignature),
      },
    };

    final account = EnrolledAccount._(
      userId: userId,
      identityX25519: Uint8List.fromList(identityX25519),
      identityEd25519Public: edPub,
      signedPreKeyId: spkId,
      pqSignedPreKeyId: pqspkId,
      oneTimePreKeyId: opkId,
      pqOneTimePreKeyId: pqopkId,
    );
    // pqSignedPreKey/pqOneTimePreKey private halves are never used by the
    // FakeKem, so random placeholders are fine.
    account._material = V2PrekeyMaterial(
      signedPreKeyId: spkId,
      signedPreKeyPrivateKey: Uint8List.fromList(spk.privateKey),
      pqSignedPreKeyId: pqspkId,
      pqSignedPreKeyPrivateKey: _fill(32, 0x21),
      oneTimePreKeyId: opkId,
      oneTimePreKeyPrivateKey: Uint8List.fromList(opk.privateKey),
      pqOneTimePreKeyId: pqopkId,
      pqOneTimePreKeyPrivateKey: _fill(32, 0x22),
    );
    account._json = json;
    _byUserId[userId] = account;
    _byIdentityHex[_hex(identityX25519)] = account;
    return account;
  }

  /// Production-shaped bundle fetch: throws for unknown users.
  Future<PrekeyBundle> fetch(String userId, {DateTime? now}) async {
    final account = _byUserId[userId];
    if (account == null) {
      throw const PrekeyBundleFetchException(404, 'not_found');
    }
    return account.fetch(now: now);
  }

  /// Responder prekey material keyed by our X25519 identity public key.
  V2PrekeyMaterial? materialFor(Uint8List ourIdentityPublicKey) =>
      _byIdentityHex[_hex(ourIdentityPublicKey)]?.material;

  /// Ed25519 identity public key for the X25519 identity (as advertised in
  /// the fake bundle). Used to keep the v2 transcript consistent.
  Uint8List? ed25519PublicFor(Uint8List ourIdentityPublicKey) =>
      _byIdentityHex[_hex(ourIdentityPublicKey)]?.identityEd25519Public;

  /// Wires the PqHybridV1 test seams to this server. Call [resetForTest] in
  /// tearDown.
  void wireInto({bool enabled = true}) {
    PqHybridV1.testEnabled = enabled;
    PqHybridV1.testKem = FakeKem(_fill(32, 0x31));
    PqHybridV1.testBundleFetcher = fetch;
    PqHybridV1.testPrekeyProvider = materialFor;
    PqHybridV1.testEd25519PublicKey = ed25519PublicFor;
  }
}

bool _bytesEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _uuid() {
  final bytes = _random(16);
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String h(int b) => b.toRadixString(16).padLeft(2, '0');
  return '${h(bytes[0])}${h(bytes[1])}${h(bytes[2])}${h(bytes[3])}-'
      '${h(bytes[4])}${h(bytes[5])}-${h(bytes[6])}${h(bytes[7])}-'
      '${h(bytes[8])}${h(bytes[9])}-'
      '${List.generate(6, (i) => h(bytes[10 + i])).join()}';
}

/// Test-only KEM (deterministic, NOT secure); never use for real keys.
class FakeKem implements PqKem {
  FakeKem(this._tag);
  final List<int> _tag;

  @override
  String get name => 'FakeKem';
  @override
  bool get isAvailable => true;
  @override
  Future<bool> initialize() async => true;

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  ) async {
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] =
          (_tag[i % _tag.length] + publicKey[i % publicKey.length] + i) & 0xFF;
    }
    return (ciphertext: Uint8List.fromList(out), sharedSecret: out);
  }

  @override
  Future<Uint8List> decapsulate(
    Uint8List privateKey,
    Uint8List ciphertext,
  ) async =>
      Uint8List.fromList(ciphertext);

  @override
  Future<({Uint8List publicKey, Uint8List privateKey})>
      generateKeyPair() async {
    final pub = Uint8List(32);
    final priv = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      pub[i] = (_tag[i % _tag.length] + i * 7 + 11) & 0xFF;
      priv[i] = (_tag[i % _tag.length] + i * 13 + 29) & 0xFF;
    }
    return (publicKey: pub, privateKey: priv);
  }
}
