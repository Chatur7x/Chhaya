import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallState { idle, calling, ringing, connected, ended }

final webrtcServiceProvider = Provider<WebRTCService>((ref) => WebRTCService());

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();

  Stream<CallState> get callStateStream => _callStateController.stream;
  Stream<MediaStream> get remoteStreamStream => _remoteStreamController.stream;

  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  String? _currentPeerId;

  static const RTCConfiguration _defaultConfig = RTCConfiguration({
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'iceCandidatePoolSize': 10,
    'bundlePolicy': RTCBundlePolicy.maxbundle,
    'rtcpMuxPolicy': RTCPChannelMuxPolicy.require,
  });

  Future<void> initialize() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    debugPrint('[WebRTC] Renderers initialized');
  }

  RTCVideoRenderer get local => _localRenderer;
  RTCVideoRenderer get remote => _remoteRenderer;

  Future<void> startCall(String targetPeerId, {bool isVideo = true}) async {
    try {
      _currentPeerId = targetPeerId;
      _updateState(CallState.calling);

      _localStream = await _createMediaStream(isVideo: isVideo);
      await _localRenderer.setSrcStream(_localStream!);

      _peerConnection = await _createPeerConnection(_defaultConfig);
      await _peerConnection!.addStream(_localStream!);

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate != null) {
          _sendIceCandidate(candidate, targetPeerId);
        }
      };

      _peerConnection!.onAddStream = (stream) {
        _remoteStream = stream;
        _remoteRenderer.setSrcStream(stream);
        _remoteStreamController.add(stream);
        _updateState(CallState.connected);
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('[WebRTC] Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _updateState(CallState.connected);
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _updateState(CallState.ended);
        }
      };

      final offer = await _peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': isVideo,
        },
      });

      await _peerConnection!.setLocalDescription(offer);
      _sendOffer(offer, targetPeerId, isVideo);

      debugPrint('[WebRTC] Call started to $targetPeerId');
    } catch (e) {
      debugPrint('[WebRTC] Failed to start call: $e');
      _updateState(CallState.idle);
      rethrow;
    }
  }

  Future<String> handleOffer(String sdp, String targetPeerId,
      {bool isVideo = true}) async {
    try {
      _currentPeerId = targetPeerId;
      _updateState(CallState.ringing);

      _localStream = await _createMediaStream(isVideo: isVideo);
      await _localRenderer.setSrcStream(_localStream!);

      _peerConnection = await _createPeerConnection(_defaultConfig);
      await _peerConnection!.addStream(_localStream!);

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate != null) {
          _sendIceCandidate(candidate, targetPeerId);
        }
      };

      _peerConnection!.onAddStream = (stream) {
        _remoteStream = stream;
        _remoteRenderer.setSrcStream(stream);
        _remoteStreamController.add(stream);
        _updateState(CallState.connected);
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('[WebRTC] Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _updateState(CallState.connected);
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _updateState(CallState.ended);
        }
      };

      final offer = RTCSessionDescription(sdp, 'offer');
      await _peerConnection!.setRemoteDescription(offer);

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      debugPrint('[WebRTC] Processed offer, generated answer');
      return answer.sdp ?? '';
    } catch (e) {
      debugPrint('[WebRTC] Failed to handle offer: $e');
      _updateState(CallState.idle);
      rethrow;
    }
  }

  Future<void> handleAnswer(String sdp) async {
    try {
      final answer = RTCSessionDescription(sdp, 'answer');
      await _peerConnection?.setRemoteDescription(answer);
      debugPrint('[WebRTC] Answer applied');
    } catch (e) {
      debugPrint('[WebRTC] Failed to handle answer: $e');
    }
  }

  Future<void> handleIceCandidate(Map<String, dynamic> candidateMap) async {
    try {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'] ?? '',
        candidateMap['sdpMid'] ?? '',
        candidateMap['sdpMLineIndex'] ?? 0,
      );
      await _peerConnection?.addCandidate(candidate);
      debugPrint('[WebRTC] ICE candidate added');
    } catch (e) {
      debugPrint('[WebRTC] Failed to add ICE candidate: $e');
    }
  }

  Future<MediaStream> _createMediaStream({bool isVideo = true}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': 1280,
              'height': 720,
              'frameRate': 30,
            }
          : false,
    };

    return await navigator.mediaDevices.getUserMedia(mediaConstraints);
  }

  Future<RTCPeerConnection> _createPeerConnection(
      RTCConfiguration config) async {
    return await createPeerConnection(config, {
      'offerAnswerOptions': {
        'VoiceActivityDetection': false,
      },
    });
  }

  void _sendOffer(
      RTCSessionDescription offer, String targetPeerId, bool isVideo) {
    final payload = {
      'type': 'offer',
      'sdp': offer.sdp,
      'targetPeerId': targetPeerId,
      'isVideo': isVideo,
      'timestamp': DateTime.now().toIso8601String(),
    };
    debugPrint('[WebRTC] Would send offer via mesh: $payload');
  }

  void _sendIceCandidate(RTCIceCandidate candidate, String targetPeerId) {
    final payload = {
      'type': 'ice_candidate',
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'targetPeerId': targetPeerId,
    };
    debugPrint(
        '[WebRTC] Would send ICE candidate via mesh: ${payload['candidate']?.toString().substring(0, 30)}...');
  }

  Future<void> toggleMute() async {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    debugPrint('[WebRTC] Mute toggled: $_isMuted');
  }

  Future<void> toggleVideo() async {
    if (_localStream == null) return;
    _isVideoOff = !_isVideoOff;
    _localStream!.getVideoTracks().forEach((track) {
      track.enabled = !_isVideoOff;
    });
    debugPrint('[WebRTC] Video toggled: $_isVideoOff');
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      final helper = CameraHelper.instance;
      final devices = await helper.cameras;
      if (devices.length > 1) {
        final currentFacing = videoTrack.getSettings().facingMode;
        final newFacing = currentFacing == 'user' ? 'environment' : 'user';
        await videoTrack.applyConstraints({
          'facingMode': newFacing,
        });
        debugPrint('[WebRTC] Camera switched to: $newFacing');
      }
    }
  }

  bool get isMuted => _isMuted;
  bool get isVideoOff => _isVideoOff;
  bool get isSpeakerOn => _isSpeakerOn;

  Future<void> endCall() async {
    try {
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      _localStream = null;
      _remoteStream = null;

      await _localRenderer.setSrcStream(null);
      await _remoteRenderer.setSrcStream(null);

      await _peerConnection?.close();
      _peerConnection = null;

      _currentPeerId = null;
      _updateState(CallState.ended);
      _updateState(CallState.idle);

      debugPrint('[WebRTC] Call ended');
    } catch (e) {
      debugPrint('[WebRTC] Error ending call: $e');
    }
  }

  void _updateState(CallState state) {
    _currentState = state;
    _callStateController.add(state);
  }

  Future<void> dispose() async {
    await endCall();
    await _callStateController.close();
    await _remoteStreamController.close();
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }
}
