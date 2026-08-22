import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';

class CallScreen extends StatefulWidget {
  final String contactName;
  final String? contactAvatar;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.contactName,
    this.contactAvatar,
    this.isVideo = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {

  String _status = 'Calling…';
  bool _connected = false;
  bool _ended = false;
  int _seconds = 0;
  Timer? _timer;


  bool _muted = false;
  bool _speaker = false;
  bool _videoOn = false;


  int _voiceMode = 0;
  static const _voiceModes = ['Natural', 'Low Pitch', 'High Pitch', 'Robotic'];
  static const _voiceIcons = [Icons.waves, Icons.arrow_downward, Icons.arrow_upward, Icons.settings];


  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _videoOn = widget.isVideo;
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

    Timer(const Duration(seconds: 2), () {
      if (mounted && !_ended) {
        setState(() {
          _status = 'Connected';
          _connected = true;
        });
        ChhayaHaptics.success();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  String get _timerText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _endCall() {
    _timer?.cancel();
    setState(() {
      _ended = true;
      _status = 'Call Ended';
      _connected = false;
    });
    ChhayaHaptics.medium();
    Timer(const Duration(seconds: 1), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Stack(
        children: [

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ChhayaColors.accentIndigo.withValues(alpha: 0.15),
                  ChhayaColors.primaryBackground,
                  ChhayaColors.primaryBackground,
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),


                AvatarWidget(name: widget.contactName, size: 120, showGradientRing: true),
                const SizedBox(height: ChhayaSpacing.xl),


                Text(widget.contactName, style: ChhayaTypography.title1),
                const SizedBox(height: ChhayaSpacing.sm),


                Text(
                  _connected ? '$_status  $_timerText' : _status,
                  style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary),
                ),


                if (_connected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: ChhayaColors.accentPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '🎙 ${_voiceModes[_voiceMode]}',
                        style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentPurple),
                      ),
                    ),
                  ),

                const Spacer(flex: 3),


                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: ChhayaColors.secondaryBackground.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _controlButton(
                            icon: _muted ? Icons.mic_off : Icons.mic,
                            label: 'Mute',
                            active: _muted,
                            onTap: () => setState(() { _muted = !_muted; ChhayaHaptics.selection(); }),
                          ),
                          _controlButton(
                            icon: Icons.volume_up,
                            label: 'Speaker',
                            active: _speaker,
                            onTap: () => setState(() { _speaker = !_speaker; ChhayaHaptics.selection(); }),
                          ),
                          _controlButton(
                            icon: _voiceIcons[_voiceMode],
                            label: 'Voice',
                            active: _voiceMode > 0,
                            activeColor: ChhayaColors.accentPurple,
                            onTap: () => setState(() {
                              _voiceMode = (_voiceMode + 1) % _voiceModes.length;
                              ChhayaHaptics.medium();
                            }),
                          ),
                          _controlButton(
                            icon: Icons.videocam,
                            label: 'Video',
                            active: _videoOn,
                            onTap: () => setState(() { _videoOn = !_videoOn; ChhayaHaptics.selection(); }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: ChhayaSpacing.xxl),


                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) => Transform.scale(
                    scale: _ended ? 1.0 : 1.0 + _pulseCtrl.value * 0.05,
                    child: child,
                  ),
                  child: FilledButton(
                    onPressed: _endCall,
                    style: FilledButton.styleFrom(
                      backgroundColor: ChhayaColors.accentRed,
                      foregroundColor: ChhayaColors.labelPrimary,
                      minimumSize: const Size(72, 72),
                      maximumSize: const Size(72, 72),
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.call_end, size: 32),
                  ),
                ),

                const SizedBox(height: 8),
                Text('End Call', style: ChhayaTypography.caption1),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final color = active ? (activeColor ?? ChhayaColors.accentBlue) : ChhayaColors.labelPrimary;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color.withValues(alpha: 0.2) : ChhayaColors.fillTertiary,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: ChhayaTypography.caption2.copyWith(color: ChhayaColors.labelSecondary)),
        ],
      ),
    );
  }
}
