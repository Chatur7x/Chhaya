// Claude Light theme tests (V14 Part 6).
//
// Verifies: spec tokens exist with exact values, WCAG AA pairs hold,
// the light scheme is light (dark preserved separately), and no
// hardcoded colors leak into screens/widgets (everything must come
// from ChhayaColors).
import 'dart:io';
import 'dart:math' as math;

import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double f(double v) {
    v /= 255.0;
    if (v <= 0.03928) {
      return v / 12.92;
    }
    final t = (v + 0.055) / 1.055;
    return math.pow(t, 2.4).toDouble();
  }

  return 0.2126 * f(c.r * 255) + 0.7152 * f(c.g * 255) + 0.0722 * f(c.b * 255);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  final hi = x > y ? x : y;
  final lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Claude Light tokens', () {
    test('spec hex values are exact', () {
      expect(ChhayaColors.coral, const Color(0xFFD97757));
      expect(ChhayaColors.coralDeep, const Color(0xFFC15F3C));
      expect(ChhayaColors.coralSoft, const Color(0xFFE8A88E));
      expect(ChhayaColors.coralTint, const Color(0xFFF5E5DD));
      expect(ChhayaColors.cream, const Color(0xFFF5F4EF));
      expect(ChhayaColors.surface, const Color(0xFFFAF9F5));
      expect(ChhayaColors.ink, const Color(0xFF1F1E1B));
      expect(ChhayaColors.inkSoft, const Color(0xFF3D3B36));
      expect(ChhayaColors.inkMuted, const Color(0xFF6B6862));
      expect(ChhayaColors.borderSoft, const Color(0xFFE5E2D9));
      expect(ChhayaColors.borderMed, const Color(0xFFD5D1C5));
    });

    test('WCAG AA pairs hold', () {
      expect(_contrast(ChhayaColors.ink, ChhayaColors.cream),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(ChhayaColors.inkSoft, ChhayaColors.cream),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(ChhayaColors.inkMuted, ChhayaColors.cream),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(ChhayaColors.white, ChhayaColors.coral),
          greaterThanOrEqualTo(3.0));
      expect(_contrast(ChhayaColors.white, ChhayaColors.coralDeep),
          greaterThanOrEqualTo(3.0));
    });

    test('light scheme is light, dark preserved', () {
      expect(ChhayaTheme.colorScheme.brightness, Brightness.light);
      expect(ChhayaTheme.materialLight.brightness, Brightness.light);
      expect(ChhayaDarkTheme.material.brightness, Brightness.dark);
      expect(ChhayaDarkColors.accent, const Color(0xFF4ADE80));
    });

    test('no hardcoded colors in screens/widgets', () async {
      final offenders = <String>[];
      for (final dir in ['lib/ui/screens', 'lib/ui/widgets']) {
        await for (final e in Directory(dir).list(recursive: true)) {
          if (!e.path.endsWith('.dart')) {
            continue;
          }
          final src = await File(e.path).readAsString();
          if (src.contains('Color(0x')) {
            offenders.add('${e.path} uses Color(0x…)');
          }
          // Leading \b so `ChhayaColors.white` is not mistaken for
          // Material's `Colors.white`. Only the bare Material palette
          // counts as an offender; the token file itself is exempt.
          for (final m in RegExp(r'\bColors\.(white|black|transparent)\b')
              .allMatches(src)) {
            offenders.add('${e.path} uses Colors.${m.group(1)}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
