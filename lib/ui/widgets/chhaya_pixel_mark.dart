import 'package:flutter/material.dart';
import '../theme/chhaya_theme.dart';

/// Brand geometry, drawn on a seven-cell grid without an image dependency.
/// Decorative only; adjacent text supplies the accessible product name.
class ChhayaPixelMark extends StatelessWidget {
  const ChhayaPixelMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PixelMarkPainter()),
    ),
  );
}

class _PixelMarkPainter extends CustomPainter {
  static const _rows = [
    '0111110',
    '1100011',
    '1000001',
    '1010101',
    '1000001',
    '1111110',
    '0100000',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 7;
    final paint = Paint()
      ..color = ChhayaColors.accent
      ..isAntiAlias = false;
    for (var y = 0; y < _rows.length; y++) {
      for (var x = 0; x < _rows[y].length; x++) {
        if (_rows[y][x] == '1') {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelMarkPainter oldDelegate) => false;
}
