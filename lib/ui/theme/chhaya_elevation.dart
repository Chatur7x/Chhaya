// Soft warm elevation (V14 Part 6).
//
// Three shadow levels tinted with ink at low alpha — depth without
// darkness, matched to cream surfaces. Replaces the V13 hairline-only
// posture (which lives on in the dark theme).
import 'package:flutter/material.dart';

import 'chhaya_colors.dart';

class ChhayaElevation {
  ChhayaElevation._();

  static List<BoxShadow> get subtle => [
        BoxShadow(
          color: ChhayaColors.ink.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get card => [
        BoxShadow(
          color: ChhayaColors.ink.withValues(alpha: 0.10),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get notification => [
        BoxShadow(
          color: ChhayaColors.ink.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Legacy shadow accessor (call sites unchanged). Warm light values;
// glows stay banned (empty lists) as in V13.
class ChhayaShadows {
  ChhayaShadows._();

  static List<BoxShadow> get subtle => ChhayaElevation.subtle;
  static List<BoxShadow> get card => ChhayaElevation.card;
  static List<BoxShadow> get notification => ChhayaElevation.notification;
  static List<BoxShadow> get deep => ChhayaElevation.card;
  static List<BoxShadow> get glowBlue => [];
  static List<BoxShadow> get glowIndigo => [];
}
