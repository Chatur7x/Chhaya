import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/ui/widgets/glass_container.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  static final _calls = [
    _CallData('Priya Sharma', 'Incoming', '15 min', false, false),
    _CallData('Arjun Mehta', 'Outgoing', '2 min', true, false),
    _CallData('Dev Team', 'Missed', '', false, true),
    _CallData('Neha Gupta', 'Outgoing', '8 min', true, true),
    _CallData('Rahul Kapoor', 'Incoming', '45 min', false, false),
    _CallData('Ananya Reddy', 'Missed', '', true, false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppBar(
          backgroundColor: ChhayaColors.primaryBackground,
          elevation: 0,
          title: Text('Calls', style: ChhayaTypography.displayMedium.copyWith(fontSize: 24)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: ChhayaSpacing.space3),
              child: ChhayaIconButton(
                icon: Icons.video_call_rounded,
                onPressed: () {},
                size: 38,
                background: ChhayaColors.cardSurface,
                color: ChhayaColors.accent,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(
            ChhayaSpacing.space4,
            ChhayaSpacing.space2,
            ChhayaSpacing.space4,
            ChhayaSpacing.space12,
          ),
          children: [
            GlassContainer(
              padding: const EdgeInsets.all(ChhayaSpacing.space4),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: ChhayaColors.accent,
                    borderRadius: BorderRadius.circular(ChhayaRadius.md),
                  ),
                  child: const Icon(Icons.shield_rounded, size: 20, color: ChhayaColors.onAccent),
                ),
                const SizedBox(width: ChhayaSpacing.space3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('P2P Encrypted Calls', style: ChhayaTypography.headlineMedium.copyWith(fontSize: 13)),
                    Text('WebRTC • No server in the middle', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary, fontSize: 11)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space2, vertical: ChhayaSpacing.space1),
                  decoration: BoxDecoration(
                    color: ChhayaColors.online.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                    border: Border.all(color: ChhayaColors.online.withValues(alpha: 0.2)),
                  ),
                  child: Text('● Live', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.online, fontWeight: FontWeight.w800, fontSize: 10)),
                ),
              ]),
            ),
            const SizedBox(height: ChhayaSpacing.space5),
            Text(
              'RECENT',
              style: ChhayaTypography.labelSmall.copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w700, color: ChhayaColors.labelTertiary),
            ),
            const SizedBox(height: ChhayaSpacing.space3),
            ..._calls.map((c) => Padding(padding: const EdgeInsets.only(bottom: ChhayaSpacing.space2), child: _buildCallCard(context, c))),
          ],
        ),
      ),
    );
  }

  Widget _buildCallCard(BuildContext context, _CallData call) {
    final missed = call.type == 'Missed';
    final color = missed ? ChhayaColors.error : ChhayaColors.labelSecondary;
    final icon = call.type == 'Incoming' ? Icons.call_received_rounded : call.type == 'Outgoing' ? Icons.call_made_rounded : Icons.call_missed_rounded;
    return Container(
      decoration: BoxDecoration(
        color: ChhayaColors.cardSurface,
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        border: Border.all(color: missed ? ChhayaColors.error.withValues(alpha: 0.15) : ChhayaColors.glassBorder.withValues(alpha: 0.10), width: 0.8),
      ),
      child: InkWell(
        onTap: () {
          ChhayaHaptics.selection();
          Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': call.name, 'isVideo': call.isVideo});
        },
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(ChhayaSpacing.space3),
          child: Row(children: [
            AvatarWidget(name: call.name, size: 48),
            const SizedBox(width: ChhayaSpacing.space3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  call.name,
                  style: ChhayaTypography.headlineMedium.copyWith(fontSize: 14, color: missed ? ChhayaColors.error : ChhayaColors.labelPrimary),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(icon, size: 12, color: color),
                  ),
                  const SizedBox(width: ChhayaSpacing.space2),
                  Text(
                    call.duration.isEmpty ? call.type : '${call.type} • ${call.duration}',
                    style: ChhayaTypography.labelMedium.copyWith(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ]),
              ]),
            ),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: (call.isVideo ? ChhayaColors.info : ChhayaColors.success).withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: (call.isVideo ? ChhayaColors.info : ChhayaColors.success).withValues(alpha: 0.2)),
              ),
              child: Icon(
                call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                size: 18,
                color: call.isVideo ? ChhayaColors.info : ChhayaColors.success,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CallData {
  final String name, type, duration;
  final bool isVideo, missed;
  const _CallData(this.name, this.type, this.duration, this.isVideo, this.missed);
}