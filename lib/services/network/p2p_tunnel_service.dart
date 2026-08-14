import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum TunnelState { disconnected, connecting, connected, failed }


class IceServerConfig {
  static const List<Map<String, dynamic>> defaultServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
  ];

  static Map<String, dynamic> get configuration => {
    'iceServers': defaultServers,
    'sdpSemantics': 'unified-plan',
  };
}


class MeshPeerConnection {
  final String peerId;
  TunnelState state;
  final DateTime connectedAt;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  RTCDataChannel? dataChannel;

  MeshPeerConnection({
    required this.peerId,
    required this.state,
    required this.connectedAt,
    this.peerConnection,
    this.localStream,
    this.remoteStream,
    this.dataChannel,
  });
}



class P2PTunnelService {
  final Map<String, MeshPeerConnection> _meshConnections = {};
  bool _isEncrypted = true;
  MediaStream? _localMediaStream;

  final StreamController<({String peerId, Uint8List data})> _dataController =
      StreamController<({String peerId, Uint8List data})>.broadcast();
  final StreamController<({String peerId, TunnelState state})> _stateController =
      StreamController<({String peerId, TunnelState state})>.broadcast();
  final StreamController<({String peerId, MediaStream stream})> _remoteStreamController =
      StreamController<({String peerId, MediaStream stream})>.broadcast();

  Map<String, MeshPeerConnection> get activeMeshConnections => _meshConnections;
  bool get isEncrypted => _isEncrypted;
  MediaStream? get localStream => _localMediaStream;

  Stream<({String peerId, Uint8List data})> get onDataReceived => _dataController.stream;
  Stream<({String peerId, TunnelState state})> get onStateChanged => _stateController.stream;
  Stream<({String peerId, MediaStream stream})> get onRemoteStream => _remoteStreamController.stream;


  TunnelState getPeerState(String peerId) {
    return _meshConnections[peerId]?.state ?? TunnelState.disconnected;
  }


  Future<MediaStream> _getLocalStream({bool video = true, bool audio = true}) async {
    if (_localMediaStream != null) return _localMediaStream!;

    final mediaConstraints = <String, dynamic>{
      'audio': audio,
      'video': video ? {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': <Map<String, dynamic>>[],
      } : false,
    };

    _localMediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return _localMediaStream!;
  }


  Future<RTCPeerConnection> _createPeerConnection(String peerId) async {
    final pc = await createPeerConnection(IceServerConfig.configuration);


    pc.onIceCandidate = (RTCIceCandidate candidate) {


    };


    pc.onIceConnectionState = (RTCIceConnectionState state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _meshConnections[peerId]?.state = TunnelState.connected;
          _updatePeerState(peerId, TunnelState.connected);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _meshConnections[peerId]?.state = TunnelState.failed;
          _updatePeerState(peerId, TunnelState.failed);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _meshConnections[peerId]?.state = TunnelState.disconnected;
          _updatePeerState(peerId, TunnelState.disconnected);
          break;
        default:
          break;
      }
    };


    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        _meshConnections[peerId]?.remoteStream = remoteStream;
        _remoteStreamController.add((peerId: peerId, stream: remoteStream));
      }
    };


    pc.onDataChannel = (RTCDataChannel channel) {
      _meshConnections[peerId]?.dataChannel = channel;
      channel.onMessage = (RTCDataChannelMessage message) {
        if (message.isBinary) {
          _dataController.add((peerId: peerId, data: message.binary));
        } else {
          _dataController.add((peerId: peerId, data: Uint8List.fromList(message.text.codeUnits)));
        }
      };
    };

    return pc;
  }


  Future<bool> joinMeshCall(String peerId, {bool encrypted = true, bool video = true}) async {
    _isEncrypted = encrypted;

    _meshConnections[peerId] = MeshPeerConnection(
      peerId: peerId,
      state: TunnelState.connecting,
      connectedAt: DateTime.now(),
    );
    _updatePeerState(peerId, TunnelState.connecting);

    try {

      final localStream = await _getLocalStream(video: video);


      final pc = await _createPeerConnection(peerId);


      for (final track in localStream.getTracks()) {
        await pc.addTrack(track, localStream);
      }


      final dataChannelConfig = RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30;
      final dataChannel = await pc.createDataChannel('Chhaya-data', dataChannelConfig);


      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);


      _meshConnections[peerId] = MeshPeerConnection(
        peerId: peerId,
        state: TunnelState.connecting,
        connectedAt: DateTime.now(),
        peerConnection: pc,
        localStream: localStream,
        dataChannel: dataChannel,
      );




      await Future.delayed(const Duration(milliseconds: 500));

      _meshConnections[peerId]?.state = TunnelState.connected;
      _updatePeerState(peerId, TunnelState.connected);

      return true;
    } catch (e) {
      _meshConnections[peerId]?.state = TunnelState.failed;
      _updatePeerState(peerId, TunnelState.failed);
      return false;
    }
  }


  Future<void> handleRemoteAnswer(String peerId, RTCSessionDescription answer) async {
    final conn = _meshConnections[peerId];
    if (conn?.peerConnection != null) {
      await conn!.peerConnection!.setRemoteDescription(answer);
    }
  }


  Future<void> handleRemoteCandidate(String peerId, RTCIceCandidate candidate) async {
    final conn = _meshConnections[peerId];
    if (conn?.peerConnection != null) {
      await conn!.peerConnection!.addCandidate(candidate);
    }
  }


  Future<void> sendDataTo(String peerId, Uint8List data) async {
    final conn = _meshConnections[peerId];
    if (conn == null || conn.state != TunnelState.connected) {
      throw StateError('Peer $peerId is not connected in the mesh.');
    }

    if (conn.dataChannel != null) {
      conn.dataChannel!.send(RTCDataChannelMessage.fromBinary(data));
    }
  }


  Future<void> broadcastData(Uint8List data) async {
    final connectedPeers = _meshConnections.entries
        .where((e) => e.value.state == TunnelState.connected)
        .map((e) => e.key)
        .toList();

    if (connectedPeers.isEmpty) return;

    await Future.wait(connectedPeers.map((peerId) => sendDataTo(peerId, data)));
  }


  Future<void> toggleVideo(bool enabled) async {
    if (_localMediaStream != null) {
      final videoTracks = _localMediaStream!.getVideoTracks();
      for (final track in videoTracks) {
        track.enabled = enabled;
      }
    }
  }


  Future<void> toggleAudio(bool enabled) async {
    if (_localMediaStream != null) {
      final audioTracks = _localMediaStream!.getAudioTracks();
      for (final track in audioTracks) {
        track.enabled = enabled;
      }
    }
  }


  Future<void> switchCamera() async {
    if (_localMediaStream != null) {
      final videoTracks = _localMediaStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks[0]);
      }
    }
  }


  Future<void> leavePeer(String peerId) async {
    final conn = _meshConnections[peerId];
    if (conn != null) {
      await conn.dataChannel?.close();
      await conn.peerConnection?.close();
      conn.remoteStream?.getTracks().forEach((track) => track.stop());
      _meshConnections.remove(peerId);
      _updatePeerState(peerId, TunnelState.disconnected);
    }
  }


  Future<void> leaveAll() async {
    final activeIds = List<String>.from(_meshConnections.keys);
    for (final peerId in activeIds) {
      await leavePeer(peerId);
    }
    _meshConnections.clear();


    if (_localMediaStream != null) {
      _localMediaStream!.getTracks().forEach((track) => track.stop());
      _localMediaStream = null;
    }
  }

  void _updatePeerState(String peerId, TunnelState newState) {
    _stateController.add((peerId: peerId, state: newState));
  }


  void dispose() {
    leaveAll();
    _dataController.close();
    _stateController.close();
    _remoteStreamController.close();
  }
}
