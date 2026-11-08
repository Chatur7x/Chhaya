// PrekeyBundleClient tests: fetch → parse → verify, fail-closed on every
// non-200, malformed body, or bad signature; no retries.
import 'dart:convert';

import 'package:chaaya/core/crypto/pqc/prekey_bundle.dart';
import 'package:chaaya/services/api/prekey_bundle_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'bundle_test_helpers.dart';

String _json(Object? body) => jsonEncode(body);

void main() {
  late BundleFixture fixture;

  setUpAll(() async {
    fixture = await BundleFixture.create();
  });

  PrekeyBundleClient clientFor(http.Client mock) => PrekeyBundleClient(
        baseUrl: 'https://chhaya.example.com',
        authToken: 'test-token',
        client: mock,
      );

  group('request construction', () {
    test('issues an authenticated GET to the WS1 endpoint', () async {
      final bundle = await fixture.bundleJson();
      late http.BaseRequest captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_json(bundle), 200);
      });
      await clientFor(mock).fetchBundle(BundleFixture.peerUserId);
      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'https://chhaya.example.com/api/v1/prekeys/'
        '${BundleFixture.peerUserId}/bundle',
      );
      expect(captured.headers['Authorization'], 'Bearer test-token');
      expect(captured.followRedirects, isFalse);
    });

    test('non-UUID userId is rejected before any network call', () async {
      var called = false;
      final mock = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      expect(
        () => clientFor(mock).fetchBundle('not-a-uuid'),
        throwsArgumentError,
      );
      expect(called, isFalse);
    });

    test('plain-HTTP base URL is rejected', () {
      expect(
        () => PrekeyBundleClient(
          baseUrl: 'http://chhaya.example.com',
          authToken: 't',
        ),
        throwsArgumentError,
      );
    });
  });

  group('fail-closed responses', () {
    test('valid 200 body parses and verifies', () async {
      final bundle = await fixture.bundleJson();
      final mock = MockClient((req) async => http.Response(_json(bundle), 200));
      final parsed =
          await clientFor(mock).fetchBundle(BundleFixture.peerUserId);
      expect(parsed.pqSignedPreKey.keyId,
          'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
      expect(parsed.lastResortUsed, isFalse);
    });

    test('last-resort 200 body parses and verifies', () async {
      final bundle = await fixture.bundleJson(lastResort: true);
      final mock = MockClient((req) async => http.Response(_json(bundle), 200));
      final parsed =
          await clientFor(mock).fetchBundle(BundleFixture.peerUserId);
      expect(parsed.lastResortUsed, isTrue);
      expect(parsed.pqOneTimePreKey, isNull);
    });

    test('409 pq_last_resort_expired surfaces its error code', () async {
      final mock = MockClient(
        (req) async =>
            http.Response(_json({'error': 'pq_last_resort_expired'}), 409),
      );
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(
          isA<PrekeyBundleFetchException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.errorCode, 'errorCode', 'pq_last_resort_expired'),
        ),
      );
    });

    test('404 bundle-unavailable fails closed', () async {
      final mock = MockClient(
        (req) async =>
            http.Response(_json({'error': 'prekey_bundle_unavailable'}), 404),
      );
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(
          isA<PrekeyBundleFetchException>()
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('503 feature-disabled fails closed', () async {
      final mock = MockClient(
        (req) async =>
            http.Response(_json({'error': 'feature_disabled'}), 503),
      );
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(isA<PrekeyBundleFetchException>()),
      );
    });

    test('401 unauthorized fails closed', () async {
      final mock = MockClient(
        (req) async => http.Response(_json({'error': 'unauthorized'}), 401),
      );
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(
          isA<PrekeyBundleFetchException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('non-JSON error body keeps status-derived code', () async {
      final mock = MockClient((req) async => http.Response('garbage', 500));
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(
          isA<PrekeyBundleFetchException>()
              .having((e) => e.errorCode, 'errorCode', 'http_500'),
        ),
      );
    });

    test('malformed JSON in a 200 body fails closed', () async {
      final mock = MockClient((req) async => http.Response('{not json', 200));
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(
          isA<PrekeyBundleFetchException>()
              .having((e) => e.errorCode, 'errorCode', 'malformed_json'),
        ),
      );
    });

    test('a 200 body with a tampered signature fails closed', () async {
      final bundle = await fixture.bundleJson(
        corruptPqSignedPreKeySignature: true,
      );
      final mock = MockClient((req) async => http.Response(_json(bundle), 200));
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('a structurally incomplete 200 body fails closed', () async {
      final bundle = await fixture.bundleJson();
      bundle.remove('pqSignedPreKey');
      final mock = MockClient((req) async => http.Response(_json(bundle), 200));
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(isA<PrekeyBundleException>()),
      );
    });

    test('network failure maps to fail-closed exception, no fabricated data',
        () async {
      final mock = MockClient((req) async => throw Exception('boom'));
      await expectLater(
        () => clientFor(mock).fetchBundle(BundleFixture.peerUserId),
        throwsA(
          isA<PrekeyBundleFetchException>()
              .having((e) => e.errorCode, 'errorCode', 'network_error'),
        ),
      );
    });
  });
}
