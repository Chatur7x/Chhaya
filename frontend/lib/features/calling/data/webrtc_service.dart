import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WebRTCService {
  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;

  bool get isMuted => _isMuted;
  bool get isVideoOff => _isVideoOff;
  bool get isSpeakerOn => _isSpeakerOn;

  void initialize() {
    debugPrint('[WebRTC] Native calling simulated for offline direct connections.');
  }

  Future<void> startCall(String targetPeerId, {bool isVideo = true}) async {
    _updateState(CallState.calling);
    // Simulate dialing/ringing delay
    await Future.delayed(const Duration(seconds: 2));
    _updateState(CallState.connected);
  }

  Future<String> handleOffer(String sdp, String targetPeerId,
      {bool isVideo = true}) async {
    _updateState(CallState.ringing);
    return 'mock_sdp';
  }

  Future<void> handleAnswer(String sdp) async {
    _updateState(CallState.connected);
  }
  
  Future<void> handleIceCandidate(Map<String, dynamic> candidateMap) async {}
  
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
  }
  
  Future<void> toggleVideo() async {
    _isVideoOff = !_isVideoOff;
  }
  
  Future<void> switchCamera() async {}

  Future<void> endCall() async {
    _updateState(CallState.ended);
    await Future.delayed(const Duration(milliseconds: 500));
    _updateState(CallState.idle);
  }

  void _updateState(CallState state) {
    _currentState = state;
    _callStateController.add(state);
  }

  Future<void> dispose() async {
    await _callStateController.close();
  }
}

enum CallState { idle, calling, ringing, connected, ended }

final webrtcServiceProvider = Provider<WebRTCService>((ref) => WebRTCService());
