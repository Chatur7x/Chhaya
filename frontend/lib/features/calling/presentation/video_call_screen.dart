import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/webrtc_service.dart';
import '../../contacts/domain/models/contact.dart';

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
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  bool _isConnected = false;
  bool _showLocalVideo = true;
  int _callDuration = 0;
  Timer? _timer;
  String? _answerSdp;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    final service = ref.read(webrtcServiceProvider);
    await service.initialize();

    ref.listen<CallState>(webrtcServiceProvider.select((s) => s.currentState),
        (prev, next) {
      if (next == CallState.connected) {
        setState(() => _isConnected = true);
        _startTimer();
      } else if (next == CallState.ended) {
        _cleanupAndPop();
      }
    });

    if (widget.isIncoming && widget.incomingSdp != null) {
      _handleIncomingCall();
    } else {
      _startOutgoingCall();
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      final service = ref.read(webrtcServiceProvider);
      await service.startCall(widget.peer.deviceId, isVideo: widget.isVideo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to start call: $e'),
              backgroundColor: ChaayaTheme.sosRed),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _handleIncomingCall() async {
    try {
      final service = ref.read(webrtcServiceProvider);
      _answerSdp = await service.handleOffer(
          widget.incomingSdp!, widget.peer.deviceId,
          isVideo: widget.isVideo);
      _sendAnswer(_answerSdp!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to accept call: $e'),
              backgroundColor: ChaayaTheme.sosRed),
        );
        Navigator.pop(context);
      }
    }
  }

  void _sendAnswer(String answerSdp) {
    debugPrint(
        '[VideoCall] Would send answer via mesh to ${widget.peer.deviceId}');
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  void _cleanupAndPop() {
    _timer?.cancel();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _toggleMute() {
    final service = ref.read(webrtcServiceProvider);
    service.toggleMute();
    setState(() => _isMuted = service.isMuted);
  }

  void _toggleVideo() {
    final service = ref.read(webrtcServiceProvider);
    service.toggleVideo();
    setState(() => _isVideoOff = service.isVideoOff);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  void _switchCamera() {
    final service = ref.read(webrtcServiceProvider);
    service.switchCamera();
    setState(() => _showLocalVideo = !_showLocalVideo);
  }

  void _endCall() {
    final service = ref.read(webrtcServiceProvider);
    service.endCall();
    _cleanupAndPop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(webrtcServiceProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video (Full Screen)
            Positioned.fill(
              child: _buildRemoteVideo(service),
            ),

            // Local Video (Picture-in-Picture)
            if (widget.isVideo)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: _switchCamera,
                  child: Container(
                    width: 120,
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: ChaayaTheme.glassBorder, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildLocalVideo(service),
                  ),
                ),
              ),

            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // Bottom Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteVideo(WebRTCService service) {
    if (_isConnected && service.remote.srcObject != null) {
      return RTCVideoView(
        service.remote,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ChaayaTheme.surface.withOpacity(0.8),
            ChaayaTheme.background,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: ChaayaTheme.surfaceLight,
                shape: BoxShape.circle,
                border: Border.all(
                    color: ChaayaTheme.accent.withOpacity(0.3), width: 3),
              ),
              child: Center(
                child: Text(
                  widget.peer.name[0].toUpperCase(),
                  style:
                      const TextStyle(fontSize: 48, color: ChaayaTheme.accent),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.peer.name,
              style: const TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (!_isConnected)
              const _PulsingStatus(status: 'Connecting...')
            else
              Text(
                _formatDuration(_callDuration),
                style: const TextStyle(
                  color: ChaayaTheme.safeGreen,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalVideo(WebRTCService service) {
    if (service.local.srcObject != null && !_isVideoOff) {
      return RTCVideoView(
        service.local,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return Container(
      color: ChaayaTheme.surface,
      child: const Center(
        child: Icon(Icons.videocam_off, color: ChaayaTheme.textMuted, size: 32),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ChaayaTheme.background.withOpacity(0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: ChaayaTheme.textPrimary),
            onPressed: _endCall,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ChaayaTheme.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ChaayaTheme.glassBorder),
            ),
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_find,
                  size: 16,
                  color: _isConnected
                      ? ChaayaTheme.wifiColor
                      : ChaayaTheme.warningYellow,
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'Connected' : 'Connecting',
                  style: TextStyle(
                    color: _isConnected
                        ? ChaayaTheme.safeGreen
                        : ChaayaTheme.warningYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            ChaayaTheme.background.withOpacity(0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: !_isMuted,
            onTap: _toggleMute,
          ),
          if (widget.isVideo)
            _buildControlButton(
              icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
              label: _isVideoOff ? 'Video On' : 'Video Off',
              isActive: !_isVideoOff,
              onTap: _toggleVideo,
            ),
          _buildControlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
            isActive: _isSpeakerOn,
            onTap: _toggleSpeaker,
          ),
          _buildEndCallButton(),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? ChaayaTheme.surfaceLight
                  : ChaayaTheme.warningYellow.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? ChaayaTheme.glassBorder
                    : ChaayaTheme.warningYellow,
              ),
            ),
            child: Icon(
              icon,
              color: isActive
                  ? ChaayaTheme.textPrimary
                  : ChaayaTheme.warningYellow,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isActive
                  ? ChaayaTheme.textSecondary
                  : ChaayaTheme.warningYellow,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: _endCall,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: ChaayaTheme.sosRed,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'End',
            style: TextStyle(
              color: ChaayaTheme.sosRed,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingStatus extends StatefulWidget {
  final String status;

  const _PulsingStatus({required this.status});

  @override
  State<_PulsingStatus> createState() => _PulsingStatusState();
}

class _PulsingStatusState extends State<_PulsingStatus>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Text(
            widget.status,
            style: const TextStyle(
              color: ChaayaTheme.warningYellow,
              fontSize: 18,
            ),
          ),
        );
      },
    );
  }
}
