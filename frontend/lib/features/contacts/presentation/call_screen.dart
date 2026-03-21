import 'package:flutter/material.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/call_service.dart';

/// Voice/Video Call Screen — shows active call with controls.
class CallScreen extends StatefulWidget {
  final String contactName;
  final String contactId;
  final CallType callType;

  const CallScreen({
    super.key,
    required this.contactName,
    required this.contactId,
    this.callType = CallType.voice,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isConnected = false;
  late AnimationController _ringController;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Simulate connection after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isConnected = true);
        _startTimer();
      }
    });
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isConnected) return false;
      setState(() => _seconds++);
      return true;
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _isConnected = false;
    super.dispose();
  }

  String get _durationText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // Channel badge
            ChaayaTheme.channelBadge('wifi'),
            const SizedBox(height: 30),

            // Contact avatar
            AnimatedBuilder(
              animation: _ringController,
              builder: (context, _) {
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        ChaayaTheme.accent.withOpacity(0.3),
                        ChaayaTheme.accent.withOpacity(0.05),
                      ],
                    ),
                    boxShadow: !_isConnected
                        ? [
                            BoxShadow(
                              color: ChaayaTheme.accent.withOpacity(
                                  0.2 + _ringController.value * 0.2),
                              blurRadius: 30 + _ringController.value * 20,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: ChaayaTheme.accent.withOpacity(0.3),
                      child: Text(
                        widget.contactName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Contact name
            Text(widget.contactName, style: ChaayaTheme.heading1),
            const SizedBox(height: 8),

            // Status
            Text(
              _isConnected
                  ? _durationText
                  : 'Connecting via WiFi Direct...',
              style: TextStyle(
                fontSize: 15,
                color: _isConnected
                    ? ChaayaTheme.safeGreen
                    : ChaayaTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),

            // E2E badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: ChaayaTheme.safeGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 12, color: ChaayaTheme.safeGreen),
                  const SizedBox(width: 4),
                  Text(
                    'End-to-end encrypted',
                    style: TextStyle(fontSize: 11, color: ChaayaTheme.safeGreen),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Call controls
            _buildControls(),

            const SizedBox(height: 40),

            // End call
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: ChaayaTheme.sosRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ChaayaTheme.sosRed.withOpacity(0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end, size: 32, color: Colors.white),
              ),
            ),

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _controlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          label: _isMuted ? 'Unmute' : 'Mute',
          isActive: _isMuted,
          onTap: () => setState(() => _isMuted = !_isMuted),
        ),
        _controlButton(
          icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
          label: 'Speaker',
          isActive: _isSpeaker,
          onTap: () => setState(() => _isSpeaker = !_isSpeaker),
        ),
        _controlButton(
          icon: widget.callType == CallType.video ? Icons.videocam : Icons.videocam_off,
          label: 'Video',
          isActive: widget.callType == CallType.video,
          onTap: () {},
        ),
        _controlButton(
          icon: Icons.bluetooth,
          label: 'BLE Audio',
          isActive: false,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? ChaayaTheme.accent.withOpacity(0.2)
                  : ChaayaTheme.surfaceLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? ChaayaTheme.accent : ChaayaTheme.glassBorder,
              ),
            ),
            child: Icon(icon, color: isActive ? ChaayaTheme.accent : ChaayaTheme.textSecondary, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: ChaayaTheme.textMuted)),
        ],
      ),
    );
  }
}

/// Reused AnimatedBuilder
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({super.key, required Animation<double> animation, required this.builder})
      : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}

