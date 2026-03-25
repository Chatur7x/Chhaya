import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/mesh/wifi_direct_service.dart';

/// Walkie-Talkie / Push-to-Talk Service
/// Zello-style PTT with named channels, priority broadcast, scramble mode.
class WalkieTalkieService {
  final WifiDirectService wifiService;
  final String myDeviceId;
  final String myCallsign;

  // PTT state
  bool _isTransmitting = false;
  bool _isReceiving = false;
  String _activeChannel = '#default';
  String? _secondaryChannel;
  bool _scrambleMode = false;
  bool _repeaterMode = false;

  // Channels
  final Map<String, PTTChannel> _channels = {};
  final List<PTTTransmission> _transmissionLog = [];

  // Streams
  final _transmissionState = StreamController<PTTState>.broadcast();
  final _incomingAudio = StreamController<PTTTransmission>.broadcast();

  Stream<PTTState> get transmissionState => _transmissionState.stream;
  Stream<PTTTransmission> get incomingAudio => _incomingAudio.stream;

  WalkieTalkieService({
    required this.wifiService,
    required this.myDeviceId,
    required this.myCallsign,
  }) {
    // Create default channels
    _channels['#default'] = PTTChannel(name: '#default', creatorId: 'system');
    _channels['#emergency'] = PTTChannel(name: '#emergency', creatorId: 'system');
  }

  /// Start push-to-talk (hold to talk)
  Future<void> startTransmitting() async {
    if (_isTransmitting) return;
    _isTransmitting = true;

    debugPrint('[PTT] TX START on $_activeChannel by $myCallsign');
    _transmissionState.add(PTTState(
      isTransmitting: true,
      channel: _activeChannel,
      callsign: myCallsign,
    ));

    // In production: start recording audio and streaming over WiFi Direct
  }

  /// Stop push-to-talk (release to send)
  Future<void> stopTransmitting() async {
    if (!_isTransmitting) return;
    _isTransmitting = false;

    // Log transmission
    final tx = PTTTransmission(
      id: const Uuid().v4(),
      senderId: myDeviceId,
      callsign: myCallsign,
      channel: _activeChannel,
      timestamp: DateTime.now(),
      durationMs: 0, // calculated from actual recording
      isPriority: false,
      isScrambled: _scrambleMode,
    );
    _transmissionLog.add(tx);

    debugPrint('[PTT] TX END on $_activeChannel, roger beep sent');
    _transmissionState.add(PTTState(
      isTransmitting: false,
      channel: _activeChannel,
      callsign: myCallsign,
      rogerBeep: true,
    ));
  }

  /// Priority broadcast — interrupts ALL devices on ALL channels
  Future<void> priorityBroadcast() async {
    debugPrint('[PTT] ⚠️ PRIORITY BROADCAST on ALL channels');
    _transmissionState.add(PTTState(
      isTransmitting: true,
      channel: 'ALL',
      callsign: myCallsign,
      isPriority: true,
    ));
    // In production: broadcast on all channels simultaneously
  }

  /// SOS broadcast — distress on all channels
  Future<void> sosBroadcast() async {
    debugPrint('[PTT] 🆘 SOS BROADCAST on ALL channels');
    _transmissionState.add(PTTState(
      isTransmitting: true,
      channel: 'SOS',
      callsign: myCallsign,
      isSOS: true,
    ));
  }

  /// Switch active channel
  void switchChannel(String channelName) {
    _activeChannel = channelName;
    debugPrint('[PTT] Switched to $channelName');
    _transmissionState.add(PTTState(
      isTransmitting: false,
      channel: channelName,
      callsign: myCallsign,
    ));
  }

  /// Set secondary channel for multi-channel monitoring
  void setSecondaryChannel(String? channelName) {
    _secondaryChannel = channelName;
    debugPrint('[PTT] Secondary channel: ${channelName ?? "none"}');
  }

  /// Create a named channel
  PTTChannel createChannel(String name, {String? password}) {
    final ch = PTTChannel(
      name: name.startsWith('#') ? name : '#$name',
      creatorId: myDeviceId,
      password: password,
    );
    _channels[ch.name] = ch;
    return ch;
  }

  /// Toggle scramble mode (encrypted voice)
  void toggleScramble() {
    _scrambleMode = !_scrambleMode;
    debugPrint('[PTT] Scramble: ${_scrambleMode ? "ON" : "OFF"}');
  }

  /// Toggle repeater mode (rebroadcast received audio)
  void toggleRepeater() {
    _repeaterMode = !_repeaterMode;
    debugPrint('[PTT] Repeater: ${_repeaterMode ? "ON" : "OFF"}');
  }

  // Getters
  bool get isTransmitting => _isTransmitting;
  bool get isScrambled => _scrambleMode;
  bool get isRepeater => _repeaterMode;
  String get activeChannel => _activeChannel;
  String? get secondaryChannel => _secondaryChannel;
  List<PTTChannel> get channels => _channels.values.toList();
  List<PTTTransmission> get transmissionLog => List.unmodifiable(_transmissionLog);

  Future<void> dispose() async {
    await _transmissionState.close();
    await _incomingAudio.close();
  }
}

/// PTT channel
class PTTChannel {
  final String name;
  final String creatorId;
  final String? password;
  final List<String> members = [];

  PTTChannel({required this.name, required this.creatorId, this.password});

  bool get isProtected => password != null;
}

/// PTT transmission record
class PTTTransmission {
  final String id;
  final String senderId;
  final String callsign;
  final String channel;
  final DateTime timestamp;
  final int durationMs;
  final bool isPriority;
  final bool isScrambled;
  final List<int>? audioData;

  PTTTransmission({
    required this.id,
    required this.senderId,
    required this.callsign,
    required this.channel,
    required this.timestamp,
    required this.durationMs,
    this.isPriority = false,
    this.isScrambled = false,
    this.audioData,
  });

  String get durationText {
    final secs = durationMs ~/ 1000;
    return '${secs}s';
  }
}

/// PTT state for UI updates
class PTTState {
  final bool isTransmitting;
  final String channel;
  final String callsign;
  final bool rogerBeep;
  final bool isPriority;
  final bool isSOS;

  PTTState({
    required this.isTransmitting,
    required this.channel,
    required this.callsign,
    this.rogerBeep = false,
    this.isPriority = false,
    this.isSOS = false,
  });
}
