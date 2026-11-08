// Prekey bundle parse + signature verification tests (spec §3.2, WS1
// contract). Structural checks are synchronous and fail closed; signature
// checks are against a test-only identity Ed25519 key.
import 'dart:convert';

import 'package:chaaya/core/crypto/pqc/prekey_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundle_test_helpers.dart';

void main() {
  late BundleFixture fixture;

  setUpAll(() async {
    fixture = await BundleFixture.create();
  });

  group('structural parse', () {
    test('accepts a well-formed fully signed bundle', () async {
      final json = await fixture.bundleJson();
      final bundle = parsePrekeyBundle(jsonDecode(jsonEncode(json)));
      expect(bundle.identityX25519.length, 32);
      expect(bundle.identityEd25519.length, 32);
      expect(bundle.oneTimePreKey, isNotNull);
      expect(bundle.pqOneTimePreKey, isNotNull);
      expect(bundle.lastResortUsed, isFalse);
    });

    test('accepts the last-resort shape (no PQOPK, flag set)', () async {
      final json = await fixture.bundleJson(lastResort: true);
      final bundle = parsePrekeyBundle(jsonDecode(jsonEncode(json)));
      expect(bundle.pqOneTimePreKey, isNull);
      expect(bundle.lastResortUsed, isTrue);
    });

    test('never fabricates: every missing field rejects the bundle', () async {
      final baseline = await fixture.bundleJson();
      for (final key in [
        'v',
        'identity',
        'signedPreKey',
        'pqSignedPreKey',
        'oneTimePreKey',
        'pqOneTimePreKey',
        'lastResortUsed',
        'reseedKemKey',
      ]) {
        final json = Map<String, dynamic>.from(baseline)..remove(key);
        expect(
          () => parsePrekeyBundle(json),
          throwsA(isA<PrekeyBundleException>()),
          reason: 'missing $key must reject the bundle',
        );
      }
    });

    test('extra/unknown fields reject the bundle (no silent tolerance)',
        () async {
      final json = await fixture.bundleJson(
        overrides: {'attackerField': 'x'},
      );
      expect(
        () => parsePrekeyBundle(json),
        throwsA(isA<PrekeyBundleException>()),
      );
      final spk = Map<String, dynamic>.from(
        (await fixture.bundleJson())['signedPreKey'] as Map<String, dynamic>,
      )..['privateKey'] = '00' * 32; // private material at the worst layer
      final json2 = await fixture.bundleJson(overrides: {'signedPreKey': spk});
      expect(
        () => parsePrekeyBundle(json2),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('type confusion is rejected, never coerced', () async {
      final baseline = await fixture.bundleJson();

      for (final entry in [
        ('v', 2),
        ('v', '1'),
        ('lastResortUsed', 'false'),
        ('lastResortUsed', 0),
      ]) {
        final json = Map<String, dynamic>.from(baseline)
          ..[entry.$1] = entry.$2;
        expect(
          () => parsePrekeyBundle(json),
          throwsA(isA<PrekeyBundleException>()),
        );
      }
      // notBefore as string must not be coerced to int
      final spk = Map<String, dynamic>.from(
        baseline['signedPreKey'] as Map<String, dynamic>,
      )..['notBefore'] = '12345';
      final json = Map<String, dynamic>.from(baseline)..['signedPreKey'] = spk;
      expect(
        () => parsePrekeyBundle(json),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('identity must carry the chhayaId 05 prefix and lowercase hex',
        () async {
      final json = await fixture.bundleJson();
      final missingPrefix = Map<String, dynamic>.from(json)
        ..['identity'] = {
          'x25519': hex(fill(32, 0xb1)),
          'ed25519': fixture.identityEd25519Hex,
        };
      expect(
        () => parsePrekeyBundle(missingPrefix),
        throwsA(isA<PrekeyBundleException>()),
      );
      final uppercase = Map<String, dynamic>.from(json)
        ..['identity'] = {
          'x25519': '05${'A1' * 32}',
          'ed25519': fixture.identityEd25519Hex,
        };
      expect(
        () => parsePrekeyBundle(uppercase),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('keyId must be lowercase canonical UUID', () async {
      final json = await fixture.bundleJson();
      for (final bad in [
        'not-a-uuid',
        'AAAAAAAA-2222-4333-8444-555555555555',
        'aaaaaaaa_aaaa_4aaa_8aaa_aaaaaaaaaaaa',
      ]) {
        final spk = Map<String, dynamic>.from(
          json['signedPreKey'] as Map<String, dynamic>,
        )..['keyId'] = bad;
        final copy = Map<String, dynamic>.from(json)..['signedPreKey'] = spk;
        expect(
          () => parsePrekeyBundle(copy),
          throwsA(isA<PrekeyBundleException>()),
          reason: 'keyId "$bad" must reject',
        );
      }
    });

    test('lastResortUsed must agree with pqOneTimePreKey presence', () async {
      final withOpk = await fixture.bundleJson(lastResort: true);
      // flag says last-resort but a PQOPK is present → reject
      final inconsistent = Map<String, dynamic>.from(withOpk)
        ..['pqOneTimePreKey'] = (await fixture.bundleJson())['pqOneTimePreKey'];
      expect(
        () => parsePrekeyBundle(inconsistent),
        throwsA(isA<PrekeyBundleException>()),
      );
      // flag says OPK-popped but none present → reject
      final missing = await fixture.bundleJson(lastResort: false)
        ..['pqOneTimePreKey'] = null;
      expect(
        () => parsePrekeyBundle(missing),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('ML-KEM public keys must be 3136 lowercase hex chars', () async {
      final json = await fixture.bundleJson();
      final pqspk = Map<String, dynamic>.from(
        json['pqSignedPreKey'] as Map<String, dynamic>,
      )..['publicKey'] = '00' * 64; // wrong length and wrong kind of key
      final copy =
          Map<String, dynamic>.from(json)..['pqSignedPreKey'] = pqspk;
      expect(
        () => parsePrekeyBundle(copy),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('notAfter must be after notBefore', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final json = await fixture.bundleJson();
      final spk = Map<String, dynamic>.from(
        json['signedPreKey'] as Map<String, dynamic>,
      )
        ..['notAfter'] = now - 100000
        ..['notBefore'] = now;
      final copy = Map<String, dynamic>.from(json)..['signedPreKey'] = spk;
      expect(
        () => parsePrekeyBundle(copy),
        throwsA(isA<PrekeyBundleException>()),
      );
    });
  });

  group('signature + window verification', () {
    test('valid bundle verifies', () async {
      final json = await fixture.bundleJson();
      final bundle = parsePrekeyBundle(json);
      await verifyPrekeyBundleSignatures(bundle);
    });

    test('strip-signature bundle is rejected', () async {
      final json = await fixture.bundleJson(
        corruptPqSignedPreKeySignature: true,
      );
      final bundle = parsePrekeyBundle(json);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('all-zero stripped signature is rejected', () async {
      final json = await fixture.bundleJson();
      final spk = Map<String, dynamic>.from(
        json['signedPreKey'] as Map<String, dynamic>,
      )..['signature'] = '00' * 64;
      final copy = Map<String, dynamic>.from(json)..['signedPreKey'] = spk;
      final bundle = parsePrekeyBundle(copy);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('reseed KEM key signature is verified too', () async {
      final json = await fixture.bundleJson(corruptReseedSignature: true);
      final bundle = parsePrekeyBundle(json);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('bundle signed by a different identity is rejected', () async {
      final other = await BundleFixture.create(seedOffset: 0x10);
      final json = await other.bundleJson();
      // Keep the other signature set but swap in our fixture's identity:
      // the signatures were produced by 'other's key and must not verify.
      final tampered = Map<String, dynamic>.from(json)
        ..['identity'] = {
          'x25519': fixture.identityX25519Hex,
          'ed25519': fixture.identityEd25519Hex,
        };
      final bundle = parsePrekeyBundle(tampered);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('expired PQSPK bundle is rejected', () async {
      final past = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      final json = await fixture.bundleJson(nowMs: past);
      final bundle = parsePrekeyBundle(json);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('PQSPK validity window wider than 7 days is rejected', () async {
      final json = await fixture.bundleJson(pqspkWindowDays: 9);
      final bundle = parsePrekeyBundle(json);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('SPK validity window wider than 30 days is rejected', () async {
      final json = await fixture.bundleJson(spkWindowDays: 45);
      final bundle = parsePrekeyBundle(json);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('not-yet-valid bundle is rejected', () async {
      final future = DateTime.now()
          .add(const Duration(days: 3))
          .millisecondsSinceEpoch;
      final json = await fixture.bundleJson(nowMs: future);
      final bundle = parsePrekeyBundle(json);
      await expectLater(
        () => verifyPrekeyBundleSignatures(bundle),
        throwsA(isA<PrekeyBundleException>()),
      );
    });
  });
}
