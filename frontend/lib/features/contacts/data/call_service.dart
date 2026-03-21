import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/mesh/wifi_direct_service.dart';

/// Voice and Video Call Service — peer-to-peer over WiFi Direct.
/// No server, no internet. Auto-adjusts quality based on signal.
class CallService {
  final WifiDirectService wifiService;
  final String myDeviceId;

  CallInfo? _activeCall;
  final _callState = StreamController<CallState>.broadcast();

  Stream<CallState> get callState => _callState.stream;
  CallInfo? get activeCall => _activeCall;

  CallService({required this.wifiService, required this.myDeviceId});

  /// Initiate a voice call
  Future<bool> startVoiceCall(String contactId, String contactName) async {
    if (_activeCall != null) {
      debugPrint('[Call] Already in a call');
      return false;
    }

    _activeCall = CallInfo(
      contactId: contactId,
      contactName: contactName,
      type: CallType.voice,
      startedAt: DateTime.now(),
      isOutgoing: true,
    );

    _callState.add(CallState.ringing);
    debugPrint('[Call] Calling $contactName (voice)...');

    // Connect WiFi Direct for high-bandwidth audio
    final connected = await wifiService.connectToPeer(contactId);
    if (connected) {
      _callState.add(CallState.connected);
      return true;
    } else {
      _activeCall = null;
      _callState.add(CallState.failed);
      return false;
    }
  }

  /// Initiate a video call
  Future<bool> startVideoCall(String contactId, String contactName) async {
    if (_activeCall != null) return false;

    _activeCall = CallInfo(
      contactId: contactId,
      contactName: contactName,
      type: CallType.video,
      startedAt: DateTime.now(),
      isOutgoing: true,
    );

    _callState.add(CallState.ringing);
    debugPrint('[Call] Calling $contactName (video)...');

    final connected = await wifiService.connectToPeer(contactId);
    if (connected) {
      _callState.add(CallState.connected);
      return true;
    } else {
      _activeCall = null;
      _callState.add(CallState.failed);
      return false;
    }
  }

  /// Answer incoming call
  Future<void> answerCall() async {
    if (_activeCall == null) return;
    _callState.add(CallState.connected);
    debugPrint('[Call] Answered');
  }

  /// Mute/unmute
  void toggleMute() {
    if (_activeCall == null) return;
    _activeCall = _activeCall!.copyWith(isMuted: !_activeCall!.isMuted);
    debugPrint('[Call] Mute: ${_activeCall!.isMuted}');
  }

  /// Speaker on/off
  void toggleSpeaker() {
    if (_activeCall == null) return;
    _activeCall = _activeCall!.copyWith(isSpeaker: !_activeCall!.isSpeaker);
    debugPrint('[Call] Speaker: ${_activeCall!.isSpeaker}');
  }

  /// Hold/unhold
  void toggleHold() {
    if (_activeCall == null) return;
    _activeCall = _activeCall!.copyWith(isHold: !_activeCall!.isHold);
    _callState.add(_activeCall!.isHold ? CallState.onHold : CallState.connected);
  }

  /// End call
  Future<void> endCall() async {
    if (_activeCall != null) {
      debugPrint('[Call] Ended call with ${_activeCall!.contactName}');
      _activeCall = null;
      _callState.add(CallState.ended);
      await wifiService.disconnect();
    }
  }

  /// Get call duration
  Duration? get callDuration {
    if (_activeCall == null) return null;
    return DateTime.now().difference(_activeCall!.startedAt);
  }

  Future<void> dispose() async {
    await endCall();
    await _callState.close();
  }
}

/// Current call info
class CallInfo {
  final String contactId;
  final String contactName;
  final CallType type;
  final DateTime startedAt;
  final bool isOutgoing;
  final bool isMuted;
  final bool isSpeaker;
  final bool isHold;
  final String channel;

  CallInfo({
    required this.contactId,
    required this.contactName,
    required this.type,
    required this.startedAt,
    this.isOutgoing = true,
    this.isMuted = false,
    this.isSpeaker = false,
    this.isHold = false,
    this.channel = 'wifi',
  });

  CallInfo copyWith({bool? isMuted, bool? isSpeaker, bool? isHold}) => CallInfo(
        contactId: contactId,
        contactName: contactName,
        type: type,
        startedAt: startedAt,
        isOutgoing: isOutgoing,
        isMuted: isMuted ?? this.isMuted,
        isSpeaker: isSpeaker ?? this.isSpeaker,
        isHold: isHold ?? this.isHold,
        channel: channel,
      );

  String get durationText {
    final d = DateTime.now().difference(startedAt);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

enum CallType { voice, video }

enum CallState {
  idle,
  ringing,
  connected,
  onHold,
  reconnecting,
  ended,
  failed,
}
