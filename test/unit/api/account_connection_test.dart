import 'dart:convert';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in [
    (existing: false, coldStart: false),
    (existing: true, coldStart: false),
    (existing: false, coldStart: true),
  ]) {
    final existingAccount = scenario.existing;
    test(
      'connect account sends valid challenge proofs for ${existingAccount ? 'login' : 'registration'}${scenario.coldStart ? ' after a slow server wake' : ''}',
      () async {
        SharedPreferences.setMockInitialValues({});
        final identity = await ChhayaCryptoEngine.generateKeyPair();
        final serverKey = await ChhayaCryptoEngine.generateKeyPair();
        final keys = KeyManager(secureBackend: SecureStorageMock());
        await keys.storeKeyPair(identity);
        final profile = UserProfile(
          chhayaId: ChhayaId.fromPublicKey('05${identity.publicKeyHex}'),
          displayName: 'Alice',
          recoveryPhrase: const ['test', 'recovery', 'phrase'],
          createdAt: DateTime.utc(2026),
        );
        const nonce =
            'abababababababababababababababababababababababababababababababab';
        const challengeId = '11111111-1111-4111-8111-111111111111';
        final paths = <String>[];
        String? challengePurpose;
        String? challengeDevice;
        final api = ApiService.forTesting(
          storage: SecureStorageMock(),
          client: MockClient((request) async {
            paths.add(request.url.path);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (request.url.path.endsWith('/challenge')) {
              if (scenario.coldStart) {
                await Future<void>.delayed(const Duration(seconds: 16));
              }
              challengePurpose = body['purpose'] as String;
              challengeDevice = body['deviceId'] as String;
              expect(body['publicKey'], identity.publicKeyHex);
              return http.Response(
                jsonEncode({
                  'challengeId': challengeId,
                  'serverPublicKey': serverKey.publicKeyHex,
                  'nonce': nonce,
                }),
                200,
              );
            }
            final purpose =
                request.url.path.endsWith('/register') ? 'register' : 'login';
            expect(challengePurpose, purpose);
            expect(body['deviceId'], challengeDevice);
            expect(body['challengeId'], challengeId);
            final shared = await ChhayaCryptoEngine.deriveSharedSecret(
              serverKey.privateKey,
              identity.publicKey,
            );
            final transcript =
                'chhaya-auth-v1|$purpose|$challengeId|$challengeDevice|${identity.publicKeyHex}|${serverKey.publicKeyHex}|$nonce';
            expect(
              body['identityProof'],
              crypto.Hmac(
                crypto.sha256,
                shared,
              ).convert(utf8.encode(transcript)).toString(),
            );
            if (purpose == 'register' && existingAccount) {
              return http.Response('{"error":"User already exists"}', 409);
            }
            return http.Response(
              '{"token":"test-token","userId":"user-id"}',
              purpose == 'register' ? 201 : 200,
            );
          }),
        );
        await api.connectAccount('https://chat.example.com', profile, keys);
        expect(api.isAuthenticated, isTrue);
        expect(
          paths,
          existingAccount
              ? [
                '/api/v1/auth/challenge',
                '/api/v1/auth/register',
                '/api/v1/auth/challenge',
                '/api/v1/auth/login',
              ]
              : ['/api/v1/auth/challenge', '/api/v1/auth/register'],
        );
      },
    );
  }
}
