import 'dart:io';

import 'package:chaaya/core/crypto/chhaya_crypto_engine.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final portText = Platform.environment['CHHAYA_TEST_API_PORT'];
  final port = portText == null ? null : int.tryParse(portText);

  test(
    'Flutter client registers and logs in against a real local backend',
    skip:
        port == null
            ? 'Set CHHAYA_TEST_API_PORT for the local integration backend'
            : false,
    () async {
      SharedPreferences.setMockInitialValues({});
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final identity = await ChhayaCryptoEngine.generateKeyPair();
      final keys = KeyManager(secureBackend: SecureStorageMock());
      await keys.storeKeyPair(identity);
      final profile = UserProfile(
        chhayaId: ChhayaId.fromPublicKey('05${identity.publicKeyHex}'),
        displayName: 'Local integration',
        recoveryPhrase: const ['local', 'integration', 'test', 'phrase'],
        createdAt: DateTime.now(),
      );
      final network = http.Client();
      addTearDown(network.close);
      // The production client requires HTTPS. This injected transport forwards
      // only to a disposable loopback HTTP backend; it does not test TLS.
      final api = ApiService.forTesting(
        storage: SecureStorageMock(),
        client: MockClient((request) async {
          final target = Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: port,
            path: request.url.path,
            query: request.url.hasQuery ? request.url.query : null,
          );
          final forwarded =
              http.Request(request.method, target)
                ..headers.addAll(request.headers)
                ..bodyBytes = request.bodyBytes;
          return http.Response.fromStream(await network.send(forwarded));
        }),
      );
      await api.connectAccount('https://integration.invalid', profile, keys);
      final userId = api.userId;
      expect(userId, isNotNull);
      expect(
        (await api.getCurrentUser()).chhayaId.publicKey,
        profile.chhayaId.publicKey,
      );
      await api.logout();
      await api.connectAccount('https://integration.invalid', profile, keys);
      expect(api.isAuthenticated, isTrue);
      expect(api.userId, userId);
      await api.logout();
    },
  );
}
