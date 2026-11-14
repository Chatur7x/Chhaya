// PrekeyUploadClient tests (WS5 slice 2): POST shape, fail-closed on
// non-2xx, server error codes surfaced, no key material leaks into errors,
// no retries.
import 'dart:convert';

import 'package:chaaya/services/api/prekey_upload_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _json(Object? body) => jsonEncode(body);

// A canary that must never appear in any thrown error message.
const _canary = 'CANARY-PRIVATE-MATERIAL-9f3b2c';

final _bundle = <String, dynamic>{
  'v': 1,
  'identity': {'x25519': '05ab', 'ed25519': 'cd'},
  'signedPreKey': {
    'keyId': 'spk-1',
    'publicKey': 'aa',
    'signature': 'bb',
    'notBefore': 1,
    'notAfter': 2,
  },
  'pqSignedPreKey': {
    'keyId': 'pqspk-1',
    'publicKey': 'cc',
    'signature': 'dd',
    'notBefore': 1,
    'notAfter': 2,
  },
  'oneTimePreKeys': <Map<String, dynamic>>[],
  'pqOneTimePreKeys': <Map<String, dynamic>>[],
  'reseedKemKey': {'publicKey': 'ee', 'signature': 'ff'},
};

final _rotation = <String, dynamic>{
  'signedPreKey': {
    'keyId': 'spk-2',
    'publicKey': 'aa',
    'signature': 'bb',
    'notBefore': 1,
    'notAfter': 2,
  },
};

void main() {
  PrekeyUploadClient clientFor(http.Client mock) => PrekeyUploadClient(
        baseUrl: 'https://chhaya.example.com',
        authToken: 'test-token',
        client: mock,
      );

  group('request construction', () {
    test('uploadBundle POSTs JSON to the WS1 endpoint with auth', () async {
      late http.BaseRequest captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_json({'oneTimeInserted': {'ec': 0, 'pq': 0}}), 200);
      });
      await clientFor(mock).uploadBundle(_bundle);
      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://chhaya.example.com/api/v1/prekeys');
      expect(captured.headers['Authorization'], 'Bearer test-token');
      expect(captured.headers['Content-Type'], 'application/json');
      expect(captured.followRedirects, isFalse);
    });

    test('rotatePrekeys POSTs JSON to the rotate endpoint', () async {
      late http.BaseRequest captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_json({'reseedKemKeyRotated': false}), 200);
      });
      await clientFor(mock).rotatePrekeys(_rotation);
      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://chhaya.example.com/api/v1/prekeys/rotate');
      expect(captured.headers['Content-Type'], 'application/json');
    });

    test('plain-HTTP base URL is rejected', () {
      expect(
        () => PrekeyUploadClient(
          baseUrl: 'http://chhaya.example.com',
          authToken: 't',
        ),
        throwsArgumentError,
      );
    });
  });

  group('fail-closed responses', () {
    test('201 Created is accepted as success', () async {
      final mock = MockClient((req) async => http.Response('{}', 201));
      await clientFor(mock).uploadBundle(_bundle);
    });

    test('503 feature_disabled surfaces its error code', () async {
      final mock = MockClient(
        (req) async =>
            http.Response(_json({'error': 'feature_disabled'}), 503),
      );
      await expectLater(
        () => clientFor(mock).uploadBundle(_bundle),
        throwsA(
          isA<PrekeyUploadException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.errorCode, 'errorCode', 'feature_disabled'),
        ),
      );
    });

    test('rotate 503 feature_disabled surfaces its error code', () async {
      final mock = MockClient(
        (req) async =>
            http.Response(_json({'error': 'feature_disabled'}), 503),
      );
      await expectLater(
        () => clientFor(mock).rotatePrekeys(_rotation),
        throwsA(
          isA<PrekeyUploadException>()
              .having((e) => e.errorCode, 'errorCode', 'feature_disabled'),
        ),
      );
    });

    test('non-JSON error body keeps status-derived code', () async {
      final mock = MockClient((req) async => http.Response('garbage', 500));
      await expectLater(
        () => clientFor(mock).uploadBundle(_bundle),
        throwsA(
          isA<PrekeyUploadException>()
              .having((e) => e.errorCode, 'errorCode', 'http_500'),
        ),
      );
    });

    test('network failure maps to fail-closed exception', () async {
      final mock = MockClient((req) async => throw Exception('boom'));
      await expectLater(
        () => clientFor(mock).uploadBundle(_bundle),
        throwsA(
          isA<PrekeyUploadException>()
              .having((e) => e.errorCode, 'errorCode', 'network_error'),
        ),
      );
    });

    test('error messages never contain request-body material', () async {
      final body = <String, dynamic>{..._bundle, 'canary': _canary};
      final mock = MockClient(
        (req) async =>
            http.Response(_json({'error': 'feature_disabled'}), 503),
      );
      try {
        await clientFor(mock).uploadBundle(body);
        fail('expected PrekeyUploadException');
      } on PrekeyUploadException catch (e) {
        expect(e.toString(), isNot(contains(_canary)));
        expect(e.errorCode, isNot(contains(_canary)));
      }
    });

    test('no automatic retry: a failing endpoint is hit exactly once',
        () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        return http.Response(_json({'error': 'feature_disabled'}), 503);
      });
      await expectLater(
        () => clientFor(mock).uploadBundle(_bundle),
        throwsA(isA<PrekeyUploadException>()),
      );
      expect(calls, 1);
    });
  });
}
