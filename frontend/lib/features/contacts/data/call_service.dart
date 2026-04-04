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

  CallService({
    required WifiDirectService wifiService,
  }) : _wifiService = wifiService;

  Future<void> initialize() async {
    _callHistoryBox = await Hive.openBox('chaaya_call_history');
  }

  Future<void> startCall(String peerDeviceId) async {
    final peerIp = _wifiService.getPeerAddress(peerDeviceId);
    if (peerIp == null) {
      debugPrint(
          '[CallService] Cannot call $peerDeviceId: No direct WiFi route');
      throw Exception('Peer unreachable on WiFi Direct');
    }
    debugPrint('[CallService] Would start call via WiFi Direct to $peerIp');
  }

  Future<void> setMute(bool mute) async {
    debugPrint('[CallService] Mute toggled: $mute');
  }

  Future<void> setSpeakerphoneOn(bool on) async {
    debugPrint('[CallService] Speaker toggled: $on');
  }

  Future<void> endCall(String peerDeviceId, int durationSeconds) async {
    _logCall(peerDeviceId, durationSeconds, false, false);
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
}
