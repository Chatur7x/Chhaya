import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../contacts/domain/models/contact.dart';

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

class VideoCallScreen extends ConsumerStatefulWidget {
  final Contact peer;
  final bool isIncoming;
  final String? incomingSdp;
  final bool isVideo;

  const VideoCallScreen({
    super.key,
    required this.peer,
    this.isIncoming = false,
    this.incomingSdp,
    this.isVideo = true,
  });

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showComingSoon();
    });
  }

  void _showComingSoon() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.videocam, color: ChaayaTheme.accent, size: 28),
            SizedBox(width: 12),
            Text('Video Calling',
                style: TextStyle(color: ChaayaTheme.textPrimary)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction,
                color: ChaayaTheme.warningYellow, size: 64),
            SizedBox(height: 16),
            Text(
              'Coming Soon',
              style: TextStyle(
                color: ChaayaTheme.accent,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Video calling will be available in a future update when WebRTC compatibility is restored.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ChaayaTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child:
                const Text('OK', style: TextStyle(color: ChaayaTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: const Center(
        child: CircularProgressIndicator(color: ChaayaTheme.accent),
      ),
    );
  }
}
