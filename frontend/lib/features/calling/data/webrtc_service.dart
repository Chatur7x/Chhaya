import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WebRTCService {
  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  bool get isMuted => false;
  bool get isVideoOff => false;
  bool get isSpeakerOn => true;

  void initialize() {
    debugPrint(
        '[WebRTC] Video calling disabled - flutter_webrtc incompatible with Flutter 3.41+');
  }

  Future<void> startCall(String targetPeerId, {bool isVideo = true}) async {
    _updateState(CallState.calling);
    await Future.delayed(const Duration(seconds: 1));
    _updateState(CallState.ended);
  }

  Future<String> handleOffer(String sdp, String targetPeerId,
      {bool isVideo = true}) async {
    _updateState(CallState.ringing);
    return '';
  }

  Future<void> handleAnswer(String sdp) async {}
  Future<void> handleIceCandidate(Map<String, dynamic> candidateMap) async {}
  Future<void> toggleMute() async {}
  Future<void> toggleVideo() async {}
  Future<void> switchCamera() async {}

  Future<void> endCall() async {
    _updateState(CallState.ended);
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
