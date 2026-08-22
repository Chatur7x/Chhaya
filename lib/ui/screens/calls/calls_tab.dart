import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
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
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground,
        title: Text('Calls', style: ChhayaTypography.headline),
      ),
      body: SafeArea(
        child: ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: _calls.length,
          itemBuilder: (ctx, i) => _buildCallItem(ctx, _calls[i]),
        ),
      ),
    );
  }

  Widget _buildCallItem(BuildContext context, _CallData call) {
    final missed = call.type == 'Missed';
    final color = missed ? ChhayaColors.accentRed : ChhayaColors.labelSecondary;
    final icon = call.type == 'Incoming'
        ? Icons.call_received
        : call.type == 'Outgoing'
            ? Icons.call_made
            : Icons.call_missed;

    return InkWell(
      onTap: () {
        ChhayaHaptics.selection();
        Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {
          'contactName': call.name,
          'isVideo': call.isVideo,
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.lg, vertical: ChhayaSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ChhayaColors.separator, width: 0.33)),
        ),
        child: Row(
          children: [
            AvatarWidget(name: call.name, size: 44),
            const SizedBox(width: ChhayaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.name, style: ChhayaTypography.body.copyWith(
                    color: missed ? ChhayaColors.accentRed : ChhayaColors.labelPrimary,
                  )),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(
                      call.duration.isEmpty ? call.type : '${call.type} · ${call.duration}',
                      style: ChhayaTypography.caption1.copyWith(color: color),
                    ),
                  ]),
                ],
              ),
            ),
            Icon(
              call.isVideo ? Icons.videocam : Icons.phone,
              color: ChhayaColors.accentBlue,
              size: 22,
            ),
          ],
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
