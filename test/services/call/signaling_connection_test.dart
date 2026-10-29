import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/call/call_service.dart';

class TestApi extends ApiService {
 TestApi():super.forTesting(storage: SecureStorageMock(), client: MockClient((_) async=>http.Response('{}',200)));
 @override bool get isAuthenticated=>true;
 @override String get baseUrl=>'https://example.com';
 @override Future<List<Map<String,dynamic>>> getIncomingCallInvites() async=>[];
}
class TestSink implements WebSocketSink {
 final sent=<String>[];
 @override void add(dynamic data)=>sent.add(data as String);
 @override Future<void> close([int? closeCode,String? closeReason]) async {}
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class TestSocket implements WebSocketChannel {
 final events=StreamController<dynamic>();
 @override final TestSink sink=TestSink();
 @override Stream<dynamic> get stream=>events.stream;
 @override Future<void> get ready=>Future.value();
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('concurrent signaling actions wait until authenticated join completes',() async {
  final socket=TestSocket();var connections=0;
  final service=CallService(api:TestApi(),database:LocalDatabase(),
   keys:KeyManager(secureBackend:SecureStorageMock()),
   connectSocket:(_){connections++;return socket;});
  addTearDown(() async {service.dispose();await socket.events.close();});
  var firstReady=false;var secondReady=false;
  final first=service.ensureConnected().then((_){firstReady=true;});
  await Future<void>.delayed(Duration.zero);
  expect(socket.sink.sent.map((e)=>jsonDecode(e)['type']),['join']);
  final second=service.ensureConnected().then((_){secondReady=true;});
  await Future<void>.delayed(Duration.zero);
  expect(firstReady,false);expect(secondReady,false);expect(connections,1);
  socket.events.add(jsonEncode({'type':'join','payload':{'status':'ok'}}));
  await Future.wait([first,second]);
  expect(firstReady,true);expect(secondReady,true);
 });
}

