import 'package:flutter/material.dart';
import '../theme/chhaya_theme.dart';

/// These bars represent measured recorder levels, never a decorative loop.
class AudioLevelWaveform extends StatelessWidget {
  const AudioLevelWaveform({super.key, required this.levels});
  final List<double> levels;
  @override
  Widget build(BuildContext context) => Semantics(label: 'Microphone input level',
    child: SizedBox(height: 64, width: double.infinity,
      child: CustomPaint(painter: _LevelPainter(
        ChhayaMotion.reduced(context) && levels.isNotEmpty ? [levels.last] : levels,
        ChhayaPalette.of(context).accent))),
  );
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.levels, this.color);
  final List<double> levels;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color=color..strokeWidth=3..strokeCap=StrokeCap.round;
    final samples = levels.isEmpty ? [0.0] : levels;
    final width = size.width / 32;
    final start = 32-samples.length;
    for (var i=0;i<samples.length;i++) {
      final value=samples[i].clamp(0.0,1.0);
      final height=3+value*(size.height-8);
      final x=(start+i+0.5)*width;
      canvas.drawLine(Offset(x,(size.height-height)/2),Offset(x,(size.height+height)/2),paint);
    }
  }
  @override
  bool shouldRepaint(covariant _LevelPainter oldDelegate) => oldDelegate.levels!=levels || oldDelegate.color!=color;
}
