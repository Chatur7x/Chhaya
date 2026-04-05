import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/mesh/wifi_direct_service.dart';

class CallLog {
  final String peerId;
  final DateTime timestamp;
  final int durationSeconds;
  final bool isMissed;
  final bool isIncoming;

  CallLog({
    required this.peerId,
    required this.timestamp,
    required this.durationSeconds,
    required this.isMissed,
    required this.isIncoming,
  });

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'timestamp': timestamp.toIso8601String(),
        'durationSeconds': durationSeconds,
        'isMissed': isMissed,
        'isIncoming': isIncoming,
      };

  factory CallLog.fromJson(Map<String, dynamic> json) => CallLog(
        peerId: json['peerId'],
        timestamp: DateTime.parse(json['timestamp']),
        durationSeconds: json['durationSeconds'],
        isMissed: json['isMissed'],
        isIncoming: json['isIncoming'],
      );
}

class CallService {
  final WifiDirectService _wifiService;
  late Box _callHistoryBox;

  bool _isInCall = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  CallService({required WifiDirectService wifiService})
      : _wifiService = wifiService;

  Future<void> initialize() async {
    _callHistoryBox = await Hive.openBox('chaaya_call_history');
  }

  bool get isInCall => _isInCall;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  Future<void> startCall(String peerDeviceId) async {
    final peerIp = _wifiService.getPeerAddress(peerDeviceId);
    if (peerIp == null) {
      debugPrint(
          '[CallService] Cannot call $peerDeviceId: No direct WiFi route');
      debugPrint('[CallService] Initiating direct P2P connection...');
    }

    _isInCall = true;
    debugPrint('[CallService] Audio call started to $peerDeviceId');

    _sendCallSignal(peerDeviceId, 'start_call');
  }

  Future<void> endCall(String peerDeviceId, int durationSeconds) async {
    _isInCall = false;
    _logCall(peerDeviceId, durationSeconds, false, false);
    _sendCallSignal(peerDeviceId, 'end_call');
    debugPrint('[CallService] Call ended after ${durationSeconds}s');
  }

  Future<void> setMute(bool mute) async {
    _isMuted = mute;
    debugPrint('[CallService] Mute: $mute');
  }

  Future<void> setSpeakerphoneOn(bool on) async {
    _isSpeakerOn = on;
    debugPrint('[CallService] Speaker: $on');
  }

  void _sendCallSignal(String peerId, String signal) {
    final payload = {
      'type': 'call_signal',
      'signal': signal,
      'from': _wifiService.myDeviceId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    debugPrint('[CallService] Would send signal: $signal to $peerId');
  }

  void _logCall(String peerId, int duration, bool missed, bool incoming) {
    if (!Hive.isBoxOpen('chaaya_call_history')) return;

    final log = CallLog(
      peerId: peerId,
      timestamp: DateTime.now(),
      durationSeconds: duration,
      isMissed: missed,
      isIncoming: incoming,
    );
    _callHistoryBox.add(log.toJson());
  }

  List<CallLog> getCallHistory() {
    if (!Hive.isBoxOpen('chaaya_call_history')) return [];
    return _callHistoryBox.values
        .map((e) => CallLog.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void receiveCallSignal(Map<String, dynamic> signal) {
    final type = signal['signal'];
    debugPrint('[CallService] Received signal: $type');
  }
}
