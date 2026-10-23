import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('registration omits null optionals and never follows redirects',() async {
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async {
      final body=jsonDecode(request.body) as Map<String,dynamic>;
      expect(body.containsKey('deviceName'),isFalse);
      expect(body.containsKey('fcmToken'),isFalse);
      expect(request.followRedirects,isFalse);
      return http.Response(jsonEncode({'token':'token','userId':'user'}),201);
    }));
    api.setBaseUrl('https://chat.example.com');
    await api.register(chhayaId:'id',displayName:'name',publicKey:'public',encryptedPrivateKey:'ciphertext',recoveryPhraseHash:'proof',deviceId:'device',challengeId:'challenge',identityProof:'identity-proof');
    expect(api.isAuthenticated,isTrue);
  });
  test('server redirects and invalid response types fail explicitly',() async {
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async=>http.Response('',302,headers:{'location':'http://untrusted.example'})));
    api.setBaseUrl('https://chat.example.com');
    await expectLater(api.getConversations(),throwsA(isA<ApiException>().having((e)=>e.statusCode,'status',302)));
  });
  test('401 clears a stored session instead of retrying stale credentials',() async {
    final storage=SecureStorageMock({'chhaya_auth_token':'stale'});
    final api=ApiService.forTesting(storage:storage,client:MockClient((request) async=>http.Response('{"error":"expired"}',401)));
    await api.init(); api.setBaseUrl('https://chat.example.com');
    expect(api.isAuthenticated,isTrue);
    await expectLater(api.getConversations(),throwsA(isA<ApiException>()));
    expect(api.isAuthenticated,isFalse);
    expect(await storage.read(key:'chhaya_auth_token'),isNull);
  });
  test('server address must be an HTTPS origin without embedded credentials',(){
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async=>http.Response('',200)));
    for(final url in ['http://chat.example.com','https://user:password@chat.example.com','https://chat.example.com/path','https://chat.example.com?secret=1']) {
      expect(()=>api.setBaseUrl(url),throwsArgumentError);
    }
    api.setBaseUrl('https://chat.example.com/');
    expect(api.baseUrl,'https://chat.example.com');
  });
}
