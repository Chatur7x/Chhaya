// v2 hybrid establishment (spec §3.1–3.5) round-trip tests for Pqxdh.
// Uses a deterministic test KEM (never for real keys) so the suite runs on
// hosts without the native AWS-LC provider; the native path is covered by
// the AWS-LC-gated test below.
import 'dart:typed_data';

import 'package:chaaya/core/crypto/pqc/ml_kem.dart';
import 'package:chaaya/core/crypto/pqc/negotiation.dart';
import 'package:chaaya/core/crypto/pqc/pqc_provider.dart';
import 'package:chaaya/core/crypto/pqc/pqxdh.dart';
import 'package:chaaya/core/crypto/pqc/prekey_bundle.dart';
import 'package:chaaya/core/crypto/primitives/aes_gcm.dart';
import 'package:chaaya/core/crypto/primitives/x25519.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _KeyPair = ({Uint8List publicKey, Uint8List privateKey});

/// Test-only KEM (deterministic, NOT secure); never use for real keys.
class FakeKem implements PqKem {
  FakeKem(this._tag);
  final List<int> _tag;
  int encapsulateCalls = 0;

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
    encapsulateCalls++;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = (_tag[i % _tag.length] + publicKey[i % publicKey.length] + i) &
          0xFF;
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

/// KEM whose encapsulate always throws; counts attempts (retry assertion).
class CountingFailingKem extends FakeKem {
  CountingFailingKem(super.tag);
  int encapsulateErrorCalls = 0;

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
    Uint8List publicKey,
  ) async {
    encapsulateCalls++;
    encapsulateErrorCalls++;
    throw StateError('KEM encapsulation failed (test)');
  }
}

Uint8List fill(int len, int byte) =>
    Uint8List.fromList(List.filled(len, byte));

String hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

final _spkKeyId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
final _pqspkKeyId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
final _opkKeyId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
final _pqopkKeyId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
final _convId = '11111111-2222-4333-8444-555555555555';

Future<
    ({
      _KeyPair responderIdentity,
      _KeyPair responderSpk,
      _KeyPair responderOpk,
      PrekeyBundle bundle,
    })> _genResponder({bool withOneTimePreKeys = true}) async {
  final identity = await X25519Kex.generateKeyPair();
  final spk = await X25519Kex.generateKeyPair();
  final opk = await X25519Kex.generateKeyPair();
  final now = DateTime.now().millisecondsSinceEpoch;
  final bundle = PrekeyBundle(
    identityX25519: identity.publicKey,
    identityEd25519: fill(32, 0xd4),
    signedPreKey: SignedPreKey(
      keyId: _spkKeyId,
      publicKey: spk.publicKey,
      signature: fill(64, 0x51),
      notBeforeMs: now - 1000,
      notAfterMs: now + 1000 * 60 * 60,
    ),
    pqSignedPreKey: SignedPreKey(
      keyId: _pqspkKeyId,
      publicKey: fill(1568, 0x71),
      signature: fill(64, 0x52),
      notBeforeMs: now - 1000,
      notAfterMs: now + 1000 * 60 * 60,
    ),
    oneTimePreKey: withOneTimePreKeys
        ? OneTimePreKey(
            keyId: _opkKeyId,
            publicKey: opk.publicKey,
            signature: fill(64, 0x53),
          )
        : null,
    pqOneTimePreKey: withOneTimePreKeys
        ? OneTimePreKey(
            keyId: _pqopkKeyId,
            publicKey: fill(1568, 0x72),
            signature: fill(64, 0x54),
          )
        : null,
    lastResortUsed: !withOneTimePreKeys,
    reseedKemKey: ReseedKemKey(
      publicKey: fill(1568, 0x73),
      signature: fill(64, 0x55),
    ),
  );
  return (
    responderIdentity: identity,
    responderSpk: spk,
    responderOpk: opk,
    bundle: bundle,
  );
}

Negotiation _initiatorNegotiation() {
  final n = Negotiation(
    ownOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
    pqAvailable: true,
  );
  n.sendOffer();
  n.receiveBundleEcho(
    echoedOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
    peerOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
    userConsented: false,
  );
  return n;
}

Negotiation _responderNegotiation() {
  final n = Negotiation(
    ownOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
    pqAvailable: true,
  );
  n.sendOffer();
  n.receiveBundleEcho(
    echoedOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
    peerOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
    userConsented: false,
  );
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v2 establishment round trip (spec §3.3–§3.5)', () {
    test('both peers derive the identical SK and T from public material',
        () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final kem = FakeKem(fill(32, 0x31));
      final out = await Pqxdh.establishHybridV2(
        negotiation: _initiatorNegotiation(),
        ourIdentityPrivateKey: initiatorIdentity.privateKey,
        ourIdentityPublicKey: initiatorIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xc3),
        responderBundle: responder.bundle,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );

      // The responder rebuilds T from public material + own prekey keys.
      final in_ = await Pqxdh.acceptHybridV2(
        negotiation: _responderNegotiation(),
        ourIdentityPrivateKey: responder.responderIdentity.privateKey,
        ourIdentityPublicKey: responder.responderIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xd4),
        peerIdentityX25519: initiatorIdentity.publicKey,
        peerEd25519PublicKey: fill(32, 0xc3),
        ourSignedPreKeyPrivateKey: responder.responderSpk.privateKey,
        signedPreKeyId: _spkKeyId,
        ourPqSignedPreKeyPrivateKey: fill(1568, 0x71),
        pqSignedPreKeyId: _pqspkKeyId,
        ourPqOneTimePreKeyPrivateKey: fill(1568, 0x72),
        pqOneTimePreKeyId: _pqopkKeyId,
        ourOneTimePreKeyPrivateKey: responder.responderOpk.privateKey,
        oneTimePreKeyId: _opkKeyId,
        peerEphemeralPublicKey: out.ephemeralPublicKey,
        mlKemCiphertext: out.mlKemCiphertext,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );
      expect(hex(in_.secret.secret), hex(out.secret.secret));
      expect(hex(in_.transcript), hex(out.transcript));
      expect(out.secret.pqUsed, isTrue);
      expect(out.secret.consentedFallback, isFalse);
      expect(out.mlKemCiphertext, isNotEmpty,
          reason: 'the CT must be returned, never discarded');
    });

    test('last-resort path (no one-time prekeys) both peers agree', () async {
      final responder = await _genResponder(withOneTimePreKeys: false);
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final kem = FakeKem(fill(32, 0x32));
      final out = await Pqxdh.establishHybridV2(
        negotiation: _initiatorNegotiation(),
        ourIdentityPrivateKey: initiatorIdentity.privateKey,
        ourIdentityPublicKey: initiatorIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xc3),
        responderBundle: responder.bundle,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );
      expect(out.mlKemCiphertext, isNotEmpty);

      final in_ = await Pqxdh.acceptHybridV2(
        negotiation: _responderNegotiation(),
        ourIdentityPrivateKey: responder.responderIdentity.privateKey,
        ourIdentityPublicKey: responder.responderIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xd4),
        peerIdentityX25519: initiatorIdentity.publicKey,
        peerEd25519PublicKey: fill(32, 0xc3),
        ourSignedPreKeyPrivateKey: responder.responderSpk.privateKey,
        signedPreKeyId: _spkKeyId,
        ourPqSignedPreKeyPrivateKey: fill(1568, 0x71),
        pqSignedPreKeyId: _pqspkKeyId,
        peerEphemeralPublicKey: out.ephemeralPublicKey,
        mlKemCiphertext: out.mlKemCiphertext,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );
      expect(hex(in_.secret.secret), hex(out.secret.secret));
    });

    test('tampered CT yields a different SK (downgrade tripwire)', () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final kem = FakeKem(fill(32, 0x33));
      final out = await Pqxdh.establishHybridV2(
        negotiation: _initiatorNegotiation(),
        ourIdentityPrivateKey: initiatorIdentity.privateKey,
        ourIdentityPublicKey: initiatorIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xc3),
        responderBundle: responder.bundle,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );

      final tamperedCt = Uint8List.fromList(out.mlKemCiphertext)..[0] ^= 0x01;
      final in_ = await Pqxdh.acceptHybridV2(
        negotiation: _responderNegotiation(),
        ourIdentityPrivateKey: responder.responderIdentity.privateKey,
        ourIdentityPublicKey: responder.responderIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xd4),
        peerIdentityX25519: initiatorIdentity.publicKey,
        peerEd25519PublicKey: fill(32, 0xc3),
        ourSignedPreKeyPrivateKey: responder.responderSpk.privateKey,
        signedPreKeyId: _spkKeyId,
        ourPqSignedPreKeyPrivateKey: fill(1568, 0x71),
        pqSignedPreKeyId: _pqspkKeyId,
        ourPqOneTimePreKeyPrivateKey: fill(1568, 0x72),
        pqOneTimePreKeyId: _pqopkKeyId,
        ourOneTimePreKeyPrivateKey: responder.responderOpk.privateKey,
        oneTimePreKeyId: _opkKeyId,
        peerEphemeralPublicKey: out.ephemeralPublicKey,
        mlKemCiphertext: tamperedCt,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );
      // FakeKem decapsulation is identity: a tampered CT yields a different
      // SS, hence a different SK and different transcript — AEAD would fail.
      expect(hex(in_.secret.secret), isNot(hex(out.secret.secret)));
      expect(hex(in_.transcript), isNot(hex(out.transcript)));
    });

    test('establishes AEAD under SK with header || T as AD (SD-4)', () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final kem = FakeKem(fill(32, 0x34));
      final out = await Pqxdh.establishHybridV2(
        negotiation: _initiatorNegotiation(),
        ourIdentityPrivateKey: initiatorIdentity.privateKey,
        ourIdentityPublicKey: initiatorIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xc3),
        responderBundle: responder.bundle,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );
      final in_ = await Pqxdh.acceptHybridV2(
        negotiation: _responderNegotiation(),
        ourIdentityPrivateKey: responder.responderIdentity.privateKey,
        ourIdentityPublicKey: responder.responderIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xd4),
        peerIdentityX25519: initiatorIdentity.publicKey,
        peerEd25519PublicKey: fill(32, 0xc3),
        ourSignedPreKeyPrivateKey: responder.responderSpk.privateKey,
        signedPreKeyId: _spkKeyId,
        ourPqSignedPreKeyPrivateKey: fill(1568, 0x71),
        pqSignedPreKeyId: _pqspkKeyId,
        ourPqOneTimePreKeyPrivateKey: fill(1568, 0x72),
        pqOneTimePreKeyId: _pqopkKeyId,
        ourOneTimePreKeyPrivateKey: responder.responderOpk.privateKey,
        oneTimePreKeyId: _opkKeyId,
        peerEphemeralPublicKey: out.ephemeralPublicKey,
        mlKemCiphertext: out.mlKemCiphertext,
        conversationId: _convId,
        userConsented: false,
        pqKem: kem,
      );

      final header = fill(48, 0x99);
      final aad = Uint8List.fromList([...header, ...out.transcript]);
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encrypted =
          AesGcm.encryptBytes(out.secret.secret, plaintext, aad: aad);
      final decrypted =
          AesGcm.decryptBytes(in_.secret.secret, encrypted, aad: aad);
      expect(decrypted, plaintext);
      expect(
        () => AesGcm.decryptBytes(
          in_.secret.secret,
          encrypted,
          aad: Uint8List.fromList(header),
        ),
        throwsA(anything),
      );
    });
  });

  group('fail-closed behaviour (spec §3.6)', () {
    test('PQ selected but KEM unavailable aborts — never classical', () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      await expectLater(
        () => Pqxdh.establishHybridV2(
          negotiation: _initiatorNegotiation(),
          ourIdentityPrivateKey: initiatorIdentity.privateKey,
          ourIdentityPublicKey: initiatorIdentity.publicKey,
          ourEd25519PublicKey: fill(32, 0xc3),
          responderBundle: responder.bundle,
          conversationId: _convId,
          userConsented: false,
          pqKem: null, // provider unavailable
        ),
        throwsA(isA<NegotiationAborted>()),
      );
    });

    test('consented classical establishes flagged nonPQ when PQ absent',
        () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final classicalOnly = [Suite.classicalConsentV1];

      Negotiation consented() {
        final n = Negotiation(
          ownOffers: classicalOnly,
          pqAvailable: false,
        );
        n.sendOffer();
        n.receiveBundleEcho(
          echoedOffers: classicalOnly,
          peerOffers: classicalOnly,
          userConsented: true,
        );
        return n;
      }

      final out = await Pqxdh.establishHybridV2(
        negotiation: consented(),
        ourIdentityPrivateKey: initiatorIdentity.privateKey,
        ourIdentityPublicKey: initiatorIdentity.publicKey,
        ourEd25519PublicKey: fill(32, 0xc3),
        responderBundle: responder.bundle,
        conversationId: _convId,
        userConsented: true,
      );
      expect(out.secret.pqUsed, isFalse);
      expect(out.secret.consentedFallback, isTrue);
      expect(out.secret.secret.length, 32);
      expect(out.mlKemCiphertext, isEmpty);
    });

    test('classical consent path never runs without explicit consent flag',
        () async {
      final classicalOnly = [Suite.classicalConsentV1];
      final n = Negotiation(
        ownOffers: classicalOnly,
        pqAvailable: false,
      );
      n.sendOffer();
      // Without consent the selection itself aborts.
      expect(
        () => n.receiveBundleEcho(
          echoedOffers: classicalOnly,
          peerOffers: classicalOnly,
          userConsented: false,
        ),
        throwsA(isA<NegotiationAborted>()),
      );
    });

    test('KEM encapsulation failure means exactly one attempt (no retry)',
        () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final kem = CountingFailingKem(fill(32, 0x35));
      await expectLater(
        () => Pqxdh.establishHybridV2(
          negotiation: _initiatorNegotiation(),
          ourIdentityPrivateKey: initiatorIdentity.privateKey,
          ourIdentityPublicKey: initiatorIdentity.publicKey,
          ourEd25519PublicKey: fill(32, 0xc3),
          responderBundle: responder.bundle,
          conversationId: _convId,
          userConsented: false,
          pqKem: kem,
        ),
        throwsA(isA<NegotiationAborted>()),
      );
      expect(kem.encapsulateErrorCalls, 1,
          reason: 'the establishment must not retry');
    });

    test('wrong offer echo aborts before any KEM call', () async {
      final responder = await _genResponder();
      final initiatorIdentity = await X25519Kex.generateKeyPair();
      final kem = FakeKem(fill(32, 0x36));
      final n = Negotiation(
        ownOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
        pqAvailable: true,
      );
      n.sendOffer();
      expect(
        () => n.receiveBundleEcho(
          // Responder echoed a weakened offer list.
          echoedOffers: const [Suite.classicalConsentV1],
          peerOffers: const [Suite.chhayaPqxdhV1, Suite.classicalConsentV1],
          userConsented: true,
        ),
        throwsA(isA<NegotiationAborted>()),
      );
      await expectLater(
        () => Pqxdh.establishHybridV2(
          negotiation: n,
          ourIdentityPrivateKey: initiatorIdentity.privateKey,
          ourIdentityPublicKey: initiatorIdentity.publicKey,
          ourEd25519PublicKey: fill(32, 0xc3),
          responderBundle: responder.bundle,
          conversationId: _convId,
          userConsented: true,
          pqKem: kem,
        ),
        throwsStateError,
      );
      expect(kem.encapsulateCalls, 0);
    });
  });

  group('native provider path (unavailable on this host)', () {
    test('AWS-LC ML-KEM round trip when provider is present', () async {
      final kem = MlKem1024();
      if (!await kem.initialize()) {
        markTestSkipped(
          'No native AWS-LC provider on this host (Windows dev machine); '
          'PQ round trip is covered above with a test-only KEM. The native '
          'path must be verified on an Android arm64 device or CI runner.',
        );
        return;
      }
      final responder = await kem.generateKeyPair();
      final (ciphertext: ct, sharedSecret: ss1) =
          await kem.encapsulate(responder.publicKey);
      final ss2 = await kem.decapsulate(responder.privateKey, ct);
      expect(ss1, ss2);
      responder.privateKey.fillRange(0, responder.privateKey.length, 0);
    });
  });
}
