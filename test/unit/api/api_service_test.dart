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
      expect(body['challengeId'],'challenge');
      expect(body['identityProof'],'identity-proof');
      expect(request.followRedirects,isFalse);
      return http.Response(jsonEncode({'token':'token','userId':'user'}),201);
    }));
    api.setBaseUrl('https://chat.example.com');
    await api.register(chhayaId:'id',displayName:'name',publicKey:'public',encryptedPrivateKey:'ciphertext',recoveryPhraseHash:'proof',deviceId:'device',challengeId:'challenge',identityProof:'identity-proof');
    expect(api.isAuthenticated,isTrue);
  });
  test('login sends the identity challenge and proof',() async {
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async {
      final body=jsonDecode(request.body) as Map<String,dynamic>;
      expect(request.url.path,'/api/v1/auth/login');
      expect(body['challengeId'],'login-challenge');
      expect(body['identityProof'],'login-proof');
      return http.Response(jsonEncode({'token':'token','userId':'user'}),200);
    }));
    api.setBaseUrl('https://chat.example.com');
    await api.login(chhayaId:'id',recoveryPhraseHash:'proof',deviceId:'device',challengeId:'login-challenge',identityProof:'login-proof');
    expect(api.isAuthenticated,isTrue);
  });
  test('server redirects and invalid response types fail explicitly',() async {
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async=>http.Response('',302,headers:{'location':'http://untrusted.example'})));
    api.setBaseUrl('https://chat.example.com');
    await expectLater(api.getConversations(),throwsA(isA<ApiException>().having((e)=>e.statusCode,'status',302)));
  });
  test('pending call invites parse encrypted envelopes from the API',() async {
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async {
      expect(request.url.path,'/api/v1/calls/incoming');
      return http.Response(jsonEncode([{'callId':'call-id','conversationId':'conversation-id','senderId':'peer-id','envelope':'sealed-offer'}]),200);
    }));
    api.setBaseUrl('https://chat.example.com');
    expect(await api.getIncomingCallInvites(),[{'callId':'call-id','conversationId':'conversation-id','senderId':'peer-id','envelope':'sealed-offer'}]);
  });
  test('group roles parse and membership actions use authenticated routes',() async {
    final requests=<http.Request>[];
    final api=ApiService.forTesting(storage:SecureStorageMock(),client:MockClient((request) async {
      requests.add(request);
      if(request.url.path=='/api/v1/auth/register') { return http.Response('{"token":"token","userId":"self"}',201); }
      if(request.url.path=='/api/v1/conversations') { return http.Response(jsonEncode([{
        'id':'group-id','type':'group','name':'Crew','created_at':'2026-01-01T00:00:00.000Z','is_admin':true,
        'participants':[{'id':'self','display_name':'You','chhaya_id':'05${'0'*64}','is_admin':true},{'id':'peer','display_name':'Peer','chhaya_id':'05${'1'*64}','is_admin':false}],
      }]),200); }
      return http.Response('{"ok":true}',200);
    }));
    api.setBaseUrl('https://chat.example.com');
    await api.register(chhayaId:'id',displayName:'You',publicKey:'public',encryptedPrivateKey:'ciphertext',recoveryPhraseHash:'proof',deviceId:'device',challengeId:'challenge',identityProof:'proof');
    final conversations=await api.getConversations();
    expect(conversations.single.adminIds,{'self'});
    expect(conversations.single.participants.single.id,'peer');
    await api.setGroupAdmin('group-id','peer',true);
    await api.removeGroupParticipant('group-id','peer');
    expect(requests[2].method,'PATCH');
    expect(jsonDecode(requests[2].body),{'isAdmin':true});
    expect(requests[3].method,'DELETE');
    expect(requests[3].headers['authorization'],'Bearer token');
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
