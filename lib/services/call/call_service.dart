import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/chhaya_crypto_engine.dart';
import '../../core/crypto/primitives/hkdf.dart';
import '../../core/crypto/primitives/aes_gcm.dart';
import '../../core/crypto/primitives/rng.dart';
import '../../core/database/local_database.dart';
import '../../core/models/contact.dart';
import '../api/api_service.dart';

class IncomingCall {
  final String callId,conversationId,senderId,envelope;
  final bool video;
  IncomingCall(this.callId,this.conversationId,this.senderId,this.envelope,this.video);
}

class TypingUpdate {
  final String conversationId;
  final String senderId;
  final bool isTyping;
  const TypingUpdate(this.conversationId, this.senderId, this.isTyping);
}

/// Foreground WebRTC calls. Authenticated, encrypted SDP/ICE is relayed by
/// the server. Microphone/camera access starts only after user initiation.
class CallService extends ChangeNotifier {
  final ApiService api;
  final LocalDatabase database;
  final KeyManager keys;
  CallService({required this.api,required this.database,required this.keys});
  final localRenderer=RTCVideoRenderer();
  final remoteRenderer=RTCVideoRenderer();
  final _incoming=StreamController<IncomingCall>.broadcast();
  Stream<IncomingCall> get incoming=>_incoming.stream;
  final _typing=StreamController<TypingUpdate>.broadcast();
  Stream<TypingUpdate> get typing=>_typing.stream;
  WebSocketChannel? _socket;
  Future<void>? _connecting;
  Completer<void>? _joined;
  bool _peerAnswered=false;
  final _candidateOutbox=<Map<String,dynamic>>[];
  RTCPeerConnection? _pc;
  MediaStream? _local;
  String? _callId,_conversationId,_peerId;
  Uint8List? _signalKey;
  bool connected=false,muted=false,videoEnabled=true;
  String status='Ready';
  bool _renderersReady=false,_remoteReady=false;
  Timer? _ringTimeout;
  final _candidates=<RTCIceCandidate>[];
  Future<void> _signalTail=Future.value();

  Future<void> ensureConnected() async {
    if(!api.isAuthenticated||_socket!=null) { return; }
    if(_connecting!=null) { return _connecting; }
    final pending=_connect(); _connecting=pending;
    try { await pending; } catch (_) { await _socket?.sink.close(); _socket=null; rethrow; } finally { _connecting=null; }
  }

  Future<void> sendTyping(String conversationId, bool active) async {
    await ensureConnected();
    final socket = _socket;
    if (socket == null) throw StateError('Signaling connection unavailable');
    socket.sink.add(jsonEncode({
      'type': 'typing',
      'payload': {'conversationId': conversationId, 'active': active},
    }));
  }
  Future<void> _connect() async {
    final uri=Uri.parse(api.baseUrl).replace(scheme:'wss',path:'/signaling');
    final socket=WebSocketChannel.connect(uri);
    await socket.ready.timeout(const Duration(seconds:15));
    _socket=socket;
    _joined=Completer<void>();
    socket.stream.listen((raw){
      _signalTail=_signalTail.then((_)=>_handle(jsonDecode(raw as String) as Map<String,dynamic>))
          .catchError((Object error){ status='Call signaling failed'; notifyListeners(); });
    },onError:(Object error){ _socket=null; status='Signaling offline'; notifyListeners(); },onDone:(){ _socket=null; });
    socket.sink.add(jsonEncode({'type':'join','payload':{'token':api.authToken,'deviceId':api.deviceId},'from':api.userId,'timestamp':DateTime.now().millisecondsSinceEpoch}));
    await _joined!.future.timeout(const Duration(seconds:15));
  }

  Future<Contact> _peer(String conversationId) async {
    final conversation=(await database.getAllConversations()).where((c)=>c.id==conversationId).firstOrNull;
    if(conversation==null||conversation.isGroup||conversation.participants.length!=1) { throw StateError('A direct conversation is required'); }
    final peer=await database.getContact(conversation.participants.single.id)??conversation.participants.single;
    if(!peer.isVerified) { throw StateError('Verify this contact before calling'); }
    return peer;
  }
  Future<Uint8List> _key(Contact peer,String callId) async {
    final pair=await keys.getKeyPair();
    if(pair==null) { throw StateError('Identity is locked'); }
    final hex=peer.chhayaId.publicKey;
    if(!RegExp(r'^05[0-9a-f]{64}$').hasMatch(hex)) { throw StateError('Invalid peer key'); }
    final public=Uint8List.fromList(List.generate(32,(i)=>int.parse(hex.substring(2+i*2,4+i*2),radix:16)));
    final shared=await ChhayaCryptoEngine.deriveSharedSecret(pair.privateKey,public);
    try { return Hkdf.deriveKey(inputKeyMaterial:shared,info:Uint8List.fromList(utf8.encode('Chhaya-call-v1:$callId')),length:32); }
    finally { Csprng.wipe(shared); }
  }
  Uint8List _aad(String type,String callId,String from,String to)=>Uint8List.fromList(utf8.encode(jsonEncode([type,callId,from,to])));
  String _seal(String type,Map<String,dynamic> body)=>base64Encode(AesGcm.encryptBytes(_signalKey!,Uint8List.fromList(utf8.encode(jsonEncode(body))),aad:_aad(type,_callId!,api.userId!,_peerId!)));
  Map<String,dynamic> _open(String type,String id,String sender,String envelope,Uint8List key)=>jsonDecode(utf8.decode(AesGcm.decryptBytes(key,base64Decode(envelope),aad:_aad(type,id,sender,api.userId!)))) as Map<String,dynamic>;

  void _send(String type,Map<String,dynamic> body) {
    if(_socket==null||_callId==null) { throw StateError('Signaling connection unavailable'); }
    _socket!.sink.add(jsonEncode({'type':type,'to':_peerId,'from':api.userId,'timestamp':DateTime.now().millisecondsSinceEpoch,
      'payload':{'callId':_callId,'conversationId':_conversationId,'envelope':_seal(type,body)}}));
  }

  Future<void> call(String conversationId,bool video) async {
    if(_callId!=null) { throw StateError('A call is already active'); }
    final peer=await _peer(conversationId);
    await ensureConnected();
    if(_socket==null) { throw StateError('Connect your server first'); }
    _callId=const Uuid().v4(); _conversationId=conversationId; _peerId=peer.id;
    _signalKey=await _key(peer,_callId!);
    await _prepare(video);
    final offer=await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _send('offer',{'sdp':offer.sdp,'type':offer.type,'video':video});
    _ringTimeout?.cancel();
    _ringTimeout=Timer(const Duration(seconds:60),()=>end());
    status='Calling'; notifyListeners();
  }

  Future<void> accept(IncomingCall incoming) async {
    if(_callId!=null) { throw StateError('A call is already active'); }
    final peer=await _peer(incoming.conversationId);
    _callId=incoming.callId; _conversationId=incoming.conversationId; _peerId=incoming.senderId;
    _signalKey=await _key(peer,incoming.callId);
    final offer=_open('offer',incoming.callId,incoming.senderId,incoming.envelope,_signalKey!);
    _peerAnswered=true;
    await _prepare(offer['video'] as bool? ?? false);
    await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'] as String,offer['type'] as String));
    _remoteReady=true;
    for(final candidate in _candidates) { await _pc!.addCandidate(candidate); }
    _candidates.clear();
    final answer=await _pc!.createAnswer(); await _pc!.setLocalDescription(answer);
    _send('answer',{'sdp':answer.sdp,'type':answer.type});
    status='Connecting'; notifyListeners();
  }

  Future<void> _prepare(bool video) async {
    if(!_renderersReady) { await localRenderer.initialize(); await remoteRenderer.initialize(); _renderersReady=true; }
    _local=await navigator.mediaDevices.getUserMedia({'audio':true,'video':video});
    localRenderer.srcObject=_local;
    _pc=await createPeerConnection({'iceServers':[
      {'urls':'stun:stun.l.google.com:19302'},
      if(const String.fromEnvironment('CHHAYA_TURN_URL').isNotEmpty)
        {'urls':const String.fromEnvironment('CHHAYA_TURN_URL'),'username':const String.fromEnvironment('CHHAYA_TURN_USERNAME'),'credential':const String.fromEnvironment('CHHAYA_TURN_PASSWORD')},
    ]});
    for(final track in _local!.getTracks()) { await _pc!.addTrack(track,_local!); }
    _pc!.onTrack=(event){ if(event.streams.isNotEmpty) { remoteRenderer.srcObject=event.streams.first; notifyListeners(); } };
    _pc!.onIceCandidate=(candidate){ if(candidate.candidate!=null) {
      final payload=<String,dynamic>{'candidate':candidate.candidate,'sdpMid':candidate.sdpMid,'sdpMLineIndex':candidate.sdpMLineIndex};
      if(_peerAnswered) { _send('ice-candidate',payload); } else { _candidateOutbox.add(payload); }
    } };
    _pc!.onIceConnectionState=(state){
      connected=state==RTCIceConnectionState.RTCIceConnectionStateConnected||state==RTCIceConnectionState.RTCIceConnectionStateCompleted;
      status=connected?'Connected':state==RTCIceConnectionState.RTCIceConnectionStateFailed?'Connection failed':'Connecting';
      notifyListeners();
    };
    videoEnabled=video;
  }

  Future<void> _handle(Map<String,dynamic> message) async {
    if(message['type']=='join') { if(_joined!=null&&!_joined!.isCompleted) _joined!.complete(); return; }
    if(message['type']=='ping') { _socket?.sink.add(jsonEncode({'type':'pong','payload':{}})); return; }
    final type=message['type'] as String?;
    if (type == 'typing') {
      final payload = message['payload'];
      final senderId = message['from'];
      if (payload is Map && senderId is String &&
          payload['conversationId'] is String && payload['active'] is bool) {
        _typing.add(TypingUpdate(
          payload['conversationId'] as String,
          senderId,
          payload['active'] as bool,
        ));
      }
      return;
    }
    if(!['offer','answer','ice-candidate','call-end'].contains(type)) { return; }
    final payload=Map<String,dynamic>.from(message['payload'] as Map);
    final id=payload['callId'] as String;
    final sender=message['from'] as String;
    final conversation=payload['conversationId'] as String;
    if(type=='offer'&&_callId==null) {
      final peer=await _peer(conversation);
      if(peer.id!=sender) { return; }
      final key=await _key(peer,id);
      try {
        final offer=_open('offer',id,sender,payload['envelope'] as String,key);
        _incoming.add(IncomingCall(id,conversation,sender,payload['envelope'] as String,offer['video'] as bool? ?? false));
      } finally { Csprng.wipe(key); }
      return;
    }
    if(id!=_callId||sender!=_peerId||_signalKey==null) { return; }
    final body=_open(type!,id,sender,payload['envelope'] as String,_signalKey!);
    if(type=='answer') {
      _ringTimeout?.cancel();
      _peerAnswered=true;
      for(final candidate in _candidateOutbox) { _send('ice-candidate',candidate); }
      _candidateOutbox.clear();
      await _pc!.setRemoteDescription(RTCSessionDescription(body['sdp'] as String,body['type'] as String));
      _remoteReady=true;
      for(final candidate in _candidates) { await _pc!.addCandidate(candidate); }
      _candidates.clear();
    } else if(type=='ice-candidate') {
      final candidate=RTCIceCandidate(body['candidate'] as String?,body['sdpMid'] as String?,body['sdpMLineIndex'] as int?);
      if(_remoteReady) { await _pc?.addCandidate(candidate); } else { _candidates.add(candidate); }
    } else if(type=='call-end') { await end(notifyPeer:false); }
  }

  Future<void> reject(IncomingCall incoming) async {
    if(_callId!=null) { return; }
    final peer=await _peer(incoming.conversationId);
    final key=await _key(peer,incoming.callId);
    try {
      final encrypted=base64Encode(AesGcm.encryptBytes(key,Uint8List.fromList(utf8.encode('{}')),
          aad:_aad('call-end',incoming.callId,api.userId!,incoming.senderId)));
      _socket?.sink.add(jsonEncode({'type':'call-end','to':incoming.senderId,'payload':{
        'callId':incoming.callId,'conversationId':incoming.conversationId,'envelope':encrypted}}));
    } finally { Csprng.wipe(key); }
  }

  void toggleMute(){ muted=!muted; for(final track in _local?.getAudioTracks()??[]) { track.enabled=!muted; } notifyListeners(); }
  void toggleVideo(){ videoEnabled=!videoEnabled; for(final track in _local?.getVideoTracks()??[]) { track.enabled=videoEnabled; } notifyListeners(); }
  Future<void> end({bool notifyPeer=true}) async {
    if(notifyPeer&&_callId!=null&&_socket!=null&&_signalKey!=null) { _send('call-end',{}); }
    for(final track in _local?.getTracks()??[]) { await track.stop(); }
    await _local?.dispose(); await _pc?.close();
    _local=null; _pc=null; _peerAnswered=false; _candidateOutbox.clear(); _remoteReady=false; _candidates.clear();
    if(_renderersReady) { localRenderer.srcObject=null; remoteRenderer.srcObject=null; }
    _ringTimeout?.cancel();
    if(_signalKey!=null) { Csprng.wipe(_signalKey!); }
    _signalKey=null; _callId=null; _peerId=null; _conversationId=null;
    connected=false; status='Call ended'; notifyListeners();
  }

  @override
  void dispose() {
    final socket = _socket;
    if (socket != null) unawaited(socket.sink.close());
    unawaited(_incoming.close());
    unawaited(_typing.close());
    super.dispose();
  }
}
