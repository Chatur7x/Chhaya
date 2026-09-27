import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String contactName;
  final String? contactAvatar;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.contactName,
    this.contactAvatar,
    required this.isVideo,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> with TickerProviderStateMixin {
  bool _muted = false;
  bool _speaker = false;
  bool _videoEnabled = true;
  bool _connected = false;
  int _seconds = 0;
  Timer? _timer;
  late AnimationController _pulseCtrl;
  int _voiceMode = 0;
  static const _voiceModes = ['Standard', 'Whisper', 'Loud & Clear'];
  static const _voiceIcons = [Icons.volume_up_rounded, Icons.volume_down_rounded, Icons.mic_rounded];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _connected = true);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connected) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Stack(
        children: _buildStackChildren(context, disableAnimations),
      ),
    );
  }

  List<Widget> _buildStackChildren(BuildContext context, bool disableAnimations) {
    final stackChildren = <Widget>[];
    
    // Background gradient
    stackChildren.add(
      Container(
        decoration: BoxDecoration(gradient: ChhayaColors.callGradient),
      ),
    );

    // Subtle pattern overlay
    if (!disableAnimations) {
      stackChildren.add(
        Positioned.fill(
          child: Opacity(
            opacity: 0.03,
            child: Image.asset(
              'assets/images/noise.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.transparent),
            ),
          ),
        ),
      );
    }

    stackChildren.add(
      Positioned.fill(
        child: SafeArea(
          child: Column(
            children: _buildColumnChildren(context, disableAnimations),
          ),
        ),
      ),
    );

    return stackChildren;
  }

  List<Widget> _buildColumnChildren(BuildContext context, bool disableAnimations) {
    final columnChildren = <Widget>[];
    
    columnChildren.add(const SizedBox(height: ChhayaSpacing.space2));
    columnChildren.add(_buildStatusBar(context, disableAnimations));
    columnChildren.add(const Spacer());
    columnChildren.add(_buildContactInfo(context, disableAnimations));
    columnChildren.add(const Spacer());
    columnChildren.add(_buildControls(context, disableAnimations));
    
    return columnChildren;
  }

  Widget _buildStatusBar(BuildContext context, bool disableAnimations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
            decoration: BoxDecoration(
              color: _connected ? ChhayaColors.online.withValues(alpha: 0.14) : ChhayaColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(ChhayaRadius.pill),
              border: Border.all(color: (_connected ? ChhayaColors.online : ChhayaColors.accent).withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: _connected ? ChhayaColors.online : ChhayaColors.accent, shape: BoxShape.circle)),
              const SizedBox(width: ChhayaSpacing.space2),
              Text(_connected ? 'Encrypted \u2022 P2P' : 'Securing\u2026', style: ChhayaTypography.labelSmall.copyWith(color: _connected ? ChhayaColors.online : ChhayaColors.accent, fontWeight: FontWeight.w800, fontSize: 10)),
            ]),
          ),
          if (widget.isVideo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
              decoration: BoxDecoration(
                color: ChhayaColors.info.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                border: Border.all(color: ChhayaColors.info.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: ChhayaColors.info, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Video', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.info, fontWeight: FontWeight.w800, fontSize: 10)),
              ]),
            ),
          ],
        ),
    );
  }

  Widget _buildContactInfo(BuildContext context, bool disableAnimations) {
    return Column(
      children: [
        AvatarWidget(
          name: widget.contactName,
          size: widget.isVideo ? 132 : 110,
          showGradientRing: true,
          showShadow: !disableAnimations,
        ),
        const SizedBox(height: ChhayaSpacing.space3),
        Text(
          widget.contactName,
          style: ChhayaTypography.displayMedium.copyWith(fontSize: widget.isVideo ? 28 : 24),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ChhayaSpacing.space1),
        AnimatedSwitcher(
          duration: disableAnimations ? Duration.zero : ChhayaAnimation.normal,
          child: Text(
            _connected ? _formatDuration(_seconds) : 'Connecting\u2026',
            key: ValueKey(_connected),
            style: ChhayaTypography.headlineSmall.copyWith(color: ChhayaColors.labelSecondary, fontSize: 14),
          ),
        ),
        if (widget.isVideo && _connected) 
          Column(
            children: [
              const SizedBox(height: ChhayaSpacing.space2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
                decoration: BoxDecoration(
                  color: ChhayaColors.info.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                  border: Border.all(color: ChhayaColors.info.withValues(alpha: 0.2)),
                ),
                child: Text('VOX:$_voiceMode • WEBRTC', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.info, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ],
          ),
        ],
    );
  }

  Widget _buildControls(BuildContext context, bool disableAnimations) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space4, ChhayaSpacing.space3, ChhayaSpacing.space4, ChhayaSpacing.space5),
      child: Column(
        children: [
          if (widget.isVideo) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildControlButton(icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded, label: 'Mute', active: _muted, activeColor: ChhayaColors.error, onTap: () => setState(() { _muted = !_muted; ChhayaHaptics.medium(); })),
                const SizedBox(width: ChhayaSpacing.space4),
                _buildControlButton(icon: _speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded, label: 'Speaker', active: _speaker, activeColor: ChhayaColors.accent, onTap: () => setState(() { _speaker = !_speaker; ChhayaHaptics.medium(); })),
                const SizedBox(width: ChhayaSpacing.space4),
                _buildControlButton(icon: _videoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded, label: 'Video', active: _videoEnabled, activeColor: ChhayaColors.info, onTap: () => setState(() { _videoEnabled = !_videoEnabled; ChhayaHaptics.medium(); })),
                const SizedBox(width: ChhayaSpacing.space4),
                _buildControlButton(icon: _voiceIcons[_voiceMode], label: 'Voice', active: _voiceMode > 0, activeColor: ChhayaColors.info, onTap: () => setState(() { _voiceMode = (_voiceMode + 1) % _voiceModes.length; ChhayaHaptics.medium(); })),
              ],
            ),
            const SizedBox(height: ChhayaSpacing.space4),
          ],
          // End call button
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ChhayaColors.dangerGradient,
            ),
            child: IconButton(
              icon: const Icon(Icons.call_end_rounded, size: 28, color: ChhayaColors.onAccent),
              onPressed: () {
                ChhayaHaptics.heavy();
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required String label, required bool active, required Color activeColor, required VoidCallback onTap}) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final color = active ? activeColor : ChhayaColors.labelPrimary;
    final bgColor = active ? activeColor.withValues(alpha: 0.15) : ChhayaColors.cardSurface.withValues(alpha: 0.8);
    final borderColor = active ? activeColor.withValues(alpha: 0.3) : ChhayaColors.glassBorder.withValues(alpha: 0.12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: disableAnimations ? Duration.zero : ChhayaAnimation.fast,
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
        const SizedBox(height: ChhayaSpacing.space1),
        Text(label, style: ChhayaTypography.labelSmall.copyWith(color: color, fontWeight: active ? FontWeight.w700 : FontWeight.w500, fontSize: 11)),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}