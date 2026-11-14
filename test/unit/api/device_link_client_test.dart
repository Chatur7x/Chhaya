// Unit tests for DeviceLinkClient against a fake HTTP layer. Covers all six
// DL-A endpoints, success/error/exception shapes, and the invariant that
// no key material ever appears in exceptions or logs.
import 'dart:convert';

import 'package:chaaya/services/api/device_link_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';
const _hex64 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _hex128 = 'b' * 128;

void main() {
  DeviceLinkClient clientFor(http.Response Function(http.Request) responder,
      {String? token}) {
    return DeviceLinkClient(
      baseUrl: 'https://server.example',
      authToken: token ?? 'token',
      client: MockClient((request) async => responder(request)),
    );
  }

  group('requestLink', () {
    test('201 returns requestId and expiresAt', () async {
      final client = clientFor((request) {
        expect(request.url.toString(), 'https://server.example/api/v1/devices/link/request');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, containsAll(['deviceId', 'deviceName', 'platform', 'devicePublicKey', 'ephemeralPublicKey', 'codeHash']));
        return http.Response(
          jsonEncode({'requestId': _uuid, 'expiresAt': '2026-11-14T12:00:00.000Z'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final result = await client.requestLink(
        deviceId: _uuid,
        deviceName: 'My laptop',
        platform: 'windows',
        devicePublicKey: _hex64,
        ephemeralPublicKey: _hex64,
        codeHash: _hex64,
      );
      expect(result.requestId, _uuid);
      expect(result.expiresAt.isUtc, isTrue);
    });

    test('200 reused pending is accepted', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'requestId': _uuid, 'expiresAt': '2026-11-14T12:00:00.000Z'}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final result = await client.requestLink(
        deviceId: _uuid,
        deviceName: 'Laptop',
        platform: 'windows',
        devicePublicKey: _hex64,
        ephemeralPublicKey: _hex64,
        codeHash: _hex64,
      );
      expect(result.requestId, _uuid);
    });

    test('400 maps to DeviceLinkException with server code', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'invalid', 'code': 'invalid_input'}),
            400,
            headers: {'content-type': 'application/json'},
          ));
      await expectLater(
        () => client.requestLink(
          deviceId: _uuid,
          deviceName: 'L',
          platform: 'windows',
          devicePublicKey: _hex64,
          ephemeralPublicKey: _hex64,
          codeHash: _hex64,
        ),
        throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 400)
            .having((e) => e.errorCode, 'code', 'invalid_input')),
      );
    });

    test('429 rate limit carries code', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Too many requests', 'code': 'rate_limited'}),
            429,
            headers: {'content-type': 'application/json'},
          ));
      await expectLater(
        () => client.requestLink(
          deviceId: _uuid,
          deviceName: 'L',
          platform: 'linux',
          devicePublicKey: _hex64,
          ephemeralPublicKey: _hex64,
          codeHash: _hex64,
        ),
        throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'rate_limited')),
      );
    });

    test('malformed keys are rejected before any network call', () async {
      final client = clientFor((request) => http.Response('{}', 500));
      expect(
        () => client.requestLink(
          deviceId: _uuid,
          deviceName: 'L',
          platform: 'linux',
          devicePublicKey: 'zz',
          ephemeralPublicKey: _hex64,
          codeHash: _hex64,
        ),
        throwsArgumentError,
      );
    });

    test('network error throws DeviceLinkException(0)', () async {
      final client = DeviceLinkClient(
        baseUrl: 'https://server.example',
        client: MockClient((request) => throw const SocketLikeException()),
      );
      await expectLater(
        () => client.requestLink(
          deviceId: _uuid,
          deviceName: 'L',
          platform: 'linux',
          devicePublicKey: _hex64,
          ephemeralPublicKey: _hex64,
          codeHash: _hex64,
        ),
        throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 0)
            .having((e) => e.errorCode, 'code', 'network_error')),
      );
    });

    test('malformed success body throws malformed_json, exception carries nothing sensitive', () async {
      final client = clientFor((request) => http.Response('{"requestId": 7}', 201));
      await expectLater(
        () => client.requestLink(
          deviceId: _uuid,
          deviceName: 'L',
          platform: 'linux',
          devicePublicKey: _hex64,
          ephemeralPublicKey: _hex64,
          codeHash: _hex64,
        ),
        throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'malformed_json')),
      );
    });
  });

  group('approveLink', () {
    test('approve sends payload and parses 200', () async {
      final client = clientFor((request) {
        expect(request.headers['Authorization'], 'Bearer token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'approve');
        expect(body['approval'], isNotEmpty);
        expect(body['approvalSignature'], _hex128);
        expect(body['primEphPub'], _hex64);
        return http.Response(
          jsonEncode({'state': 'approved', 'idempotent': false}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }, token: 'token');
      final result = await client.approveLink(
        requestId: _uuid,
        code: 'abc123',
        action: 'approve',
        approval: base64Encode(List.filled(64, 7)),
        approvalSignature: _hex128,
        primEphPub: _hex64,
      );
      expect(result.state, 'approved');
      expect(result.idempotent, isFalse);
    });

    test('deny succeeds without an approval payload', () async {
      final client = clientFor((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'deny');
        expect(body.containsKey('approval'), isFalse);
        return http.Response(
          jsonEncode({'state': 'denied', 'idempotent': false}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }, token: 'token');
      final result = await client.approveLink(requestId: _uuid, code: 'abc123', action: 'deny');
      expect(result.state, 'denied');
    });

    test('403 code_mismatch surfaces', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Code mismatch', 'code': 'code_mismatch'}),
            403,
            headers: {'content-type': 'application/json'},
          ), token: 'token');
      await expectLater(
        () => client.approveLink(requestId: _uuid, code: 'nope', action: 'deny'),
        throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'code_mismatch')),
      );
    });

    test('410 link_expired surfaces', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Link request expired', 'code': 'link_expired'}),
            410,
            headers: {'content-type': 'application/json'},
          ), token: 'token');
      await expectLater(
        () => client.approveLink(requestId: _uuid, code: 'nope', action: 'deny'),
        throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'link_expired')),
      );
    });

    test('authenticated call without a token throws StateError before any network call', () async {
      var called = false;
      final client = DeviceLinkClient(
        baseUrl: 'https://server.example',
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        () => client.approveLink(requestId: _uuid, code: 'x', action: 'deny'),
        throwsStateError,
      );
      expect(called, isFalse);
    });

    test('exception message contains no secret payload material', () async {
      const secretApproval = 'c2VjcmV0LWFwcHJvdmFsLWJsb2Itc2hvdWxkLW5vdC1sZWFr';
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Code mismatch', 'code': 'code_mismatch', 'echo': secretApproval}),
            403,
            headers: {'content-type': 'application/json'},
          ), token: 'token');
      try {
        await client.approveLink(
          requestId: _uuid,
          code: 'nope',
          action: 'approve',
          approval: secretApproval,
          approvalSignature: _hex128,
          primEphPub: _hex64,
        );
        fail('expected DeviceLinkException');
      } on DeviceLinkException catch (error) {
        expect(error.toString(), isNot(contains(secretApproval)));
        expect(error.toString(), isNot(contains('c2VjcmV0')));
      }
    });
  });

  group('linkStatus', () {
    test('pending parses with expiry', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'state': 'pending', 'expiresAt': '2026-11-14T12:00:00.000Z'}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final status = await client.linkStatus(requestId: _uuid);
      expect(status.state, 'pending');
      expect(status.approval, isNull);
    });

    test('approved requires approval, signature, primEphPub', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({
              'state': 'approved',
              'approval': 'QUJD',
              'approvalSignature': _hex128,
              'primEphPub': _hex64,
              'expiresAt': '2026-11-14T12:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final status = await client.linkStatus(requestId: _uuid);
      expect(status.state, 'approved');
      expect(status.primEphPub, _hex64);
    });

    test('approved with missing primEphPub is malformed', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'state': 'approved', 'approval': 'QUJD', 'approvalSignature': _hex128}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      await expectLater(
        () => client.linkStatus(requestId: _uuid),
        throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'malformed_json')),
      );
    });

    test('410 link_expired surfaces as exception', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Link request expired', 'code': 'link_expired'}),
            410,
            headers: {'content-type': 'application/json'},
          ));
      await expectLater(
        () => client.linkStatus(requestId: _uuid),
        throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 410)),
      );
    });
  });

  group('consumeLink', () {
    test('200 returns userId/deviceId/token', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'userId': 'user-1', 'deviceId': _uuid, 'token': 'device-token'}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final result = await client.consumeLink(requestId: _uuid, code: 'code');
      expect(result.deviceId, _uuid);
      expect(result.token, 'device-token');
    });

    test('409 invalid_state surfaces on replay', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'invalid_state', 'code': 'invalid_state'}),
            409,
            headers: {'content-type': 'application/json'},
          ));
      await expectLater(
        () => client.consumeLink(requestId: _uuid, code: 'code'),
        throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 409)),
      );
    });
  });

  group('listDevices', () {
    test('parses device list with isCurrent and revokedAt', () async {
      final client = clientFor((request) {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://server.example/api/v1/devices');
        return http.Response(
          jsonEncode([
            {
              'deviceId': _uuid,
              'name': 'Primary',
              'platform': 'android',
              'createdAt': '2026-10-01T00:00:00.000Z',
              'lastActiveAt': '2026-11-01T00:00:00.000Z',
              'isCurrent': true,
              'revokedAt': null,
            },
            {
              'deviceId': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'name': 'Old laptop',
              'platform': 'windows',
              'createdAt': '2026-09-01T00:00:00.000Z',
              'lastActiveAt': null,
              'isCurrent': false,
              'revokedAt': '2026-10-15T00:00:00.000Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }, token: 'token');
      final devices = await client.listDevices();
      expect(devices, hasLength(2));
      expect(devices[0].isCurrent, isTrue);
      expect(devices[1].revokedAt, isNotNull);
    });

    test('401 surfaces as DeviceLinkException', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Invalid or expired token', 'code': 'not_authenticated'}),
            401,
            headers: {'content-type': 'application/json'},
          ), token: 'token');
      await expectLater(
        () => client.listDevices(),
        throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 401)),
      );
    });
  });

  group('revokeDevice', () {
    test('200 marks success', () async {
      final client = clientFor((request) {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), 'https://server.example/api/v1/devices/$_uuid');
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(jsonEncode({'revoked': true}), 200,
            headers: {'content-type': 'application/json'});
      }, token: 'token');
      await client.revokeDevice(deviceId: _uuid);
    });

    test('400 use_logout surfaces', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Cannot revoke the device you are calling from; use logout', 'code': 'use_logout'}),
            400,
            headers: {'content-type': 'application/json'},
          ), token: 'token');
      await expectLater(
        () => client.revokeDevice(deviceId: _uuid),
        throwsA(isA<DeviceLinkException>().having((e) => e.errorCode, 'code', 'use_logout')),
      );
    });

    test('404 not_found surfaces', () async {
      final client = clientFor((request) => http.Response(
            jsonEncode({'error': 'Not found', 'code': 'not_found'}),
            404,
            headers: {'content-type': 'application/json'},
          ), token: 'token');
      await expectLater(
        () => client.revokeDevice(deviceId: _uuid),
        throwsA(isA<DeviceLinkException>().having((e) => e.statusCode, 'status', 404)),
      );
    });
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
  @override
  String toString() => 'SocketException: connection refused';
}
