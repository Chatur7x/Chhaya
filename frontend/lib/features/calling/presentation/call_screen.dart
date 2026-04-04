import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../contacts/domain/models/contact.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';

class CallScreen extends ConsumerStatefulWidget {
  final Contact peer;
  final bool isIncoming;

  const CallScreen({super.key, required this.peer, this.isIncoming = false});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCallActive = false;
  int _callDuration = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.isIncoming) {
      _startCall();
    }
  }

  Future<void> _startCall() async {
    try {
      await ref.read(callServiceProvider).startCall(widget.peer.deviceId);
      setState(() => _isCallActive = true);
      _startTimer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Call failed: $e'),
              backgroundColor: ChaayaTheme.sosRed),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration++;
      });
    });
  }

  void _endCall() async {
    _timer?.cancel();
    await ref
        .read(callServiceProvider)
        .endCall(widget.peer.deviceId, _callDuration);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    ref.read(callServiceProvider).setMute(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    ref.read(callServiceProvider).setSpeakerphoneOn(_isSpeakerOn);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // User Avatar
            CircleAvatar(
              radius: 60,
              backgroundColor: ChaayaTheme.surfaceLight,
              child: Text(
                widget.peer.name[0].toUpperCase(),
                style: const TextStyle(fontSize: 48, color: ChaayaTheme.accent),
              ),
            ),
            const SizedBox(height: 24),
            // Identifying Information
            Text(
              widget.peer.name,
              style: const TextStyle(
                  color: ChaayaTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'ID: ${widget.peer.deviceId.substring(0, 8)}',
              style: const TextStyle(
                  color: ChaayaTheme.textSecondary, fontSize: 16),
            ),

            // Status and Duration
            const SizedBox(height: 40),
            if (!_isCallActive && !widget.isIncoming)
              const Text('Connecting direct P2P link...',
                  style: TextStyle(color: ChaayaTheme.wifiColor, fontSize: 18))
            else if (_isCallActive)
              Text(_formatDuration(_callDuration),
                  style: const TextStyle(
                      color: ChaayaTheme.safeGreen,
                      fontSize: 24,
                      fontWeight: FontWeight.w500)),

            const Spacer(),

            // Connection Quality Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: ChaayaTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ChaayaTheme.glassBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi, color: ChaayaTheme.wifiColor, size: 16),
                  SizedBox(width: 8),
                  Text('Direct WiFi Link Active',
                      style: TextStyle(color: ChaayaTheme.textSecondary)),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Call Controls
            Container(
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                color: ChaayaTheme.surface,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _buildControlBtn(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted
                        ? ChaayaTheme.warningYellow
                        : ChaayaTheme.textPrimary,
                    onPressed: _toggleMute,
                  ),

                  // Video Call (Coming Soon)
                  _buildControlBtn(
                    icon: Icons.video_call,
                    color: ChaayaTheme.textMuted,
                    onPressed: () => _showVideoComingSoon(context),
                  ),

                  // End Call (big red button)
                  FloatingActionButton.large(
                    heroTag: 'end_call',
                    backgroundColor: ChaayaTheme.sosRed,
                    onPressed: _endCall,
                    child: const Icon(Icons.call_end,
                        color: Colors.white, size: 36),
                  ),

                  // Speaker
                  _buildControlBtn(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    color: _isSpeakerOn
                        ? ChaayaTheme.accentLight
                        : ChaayaTheme.textPrimary,
                    onPressed: _toggleSpeaker,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showVideoComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video calling coming soon!'),
        backgroundColor: ChaayaTheme.accent,
      ),
    );
  }

  Widget _buildControlBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ChaayaTheme.surfaceLight,
          shape: BoxShape.circle,
          border: Border.all(color: ChaayaTheme.glassBorder),
        ),
        child: Icon(icon, color: color, size: 32),
      ),
    );
  }
}
