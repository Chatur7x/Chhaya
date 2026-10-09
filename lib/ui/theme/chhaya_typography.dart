// Claude Light typography (V14 Part 6).
//
// Inter for UI text, Tiempos for display, Departure Mono for technical
// readouts. Legacy member names are preserved (values follow the spec
// scale); new spec names are added alongside. NOTE: Tiempos and
// Departure Mono are not bundled as font assets yet — the family names
// resolve through the platform fallback stack until F6 ships the
// files. No call site changes required when they land.
import 'package:flutter/material.dart';

import 'chhaya_colors.dart';

class ChhayaTypography {
  ChhayaTypography._();

  static const String _fontFamily = 'Inter';
  static const String _displayFontFamily = 'Tiempos';
  static const String _monoFontFamily = 'Departure Mono';

  // Spec scale — Claude Light
  static const TextStyle displayXl = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 44,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
    height: 1.05,
    color: ChhayaColors.ink,
  );

  static const TextStyle displayL = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    height: 1.1,
    color: ChhayaColors.ink,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
    color: ChhayaColors.ink,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.3,
    color: ChhayaColors.ink,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    height: 1.5,
    color: ChhayaColors.ink,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    height: 1.45,
    color: ChhayaColors.ink,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.35,
    color: ChhayaColors.inkMuted,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.35,
    color: ChhayaColors.ink,
  );

  static const TextStyle monoHash = TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.5,
    color: ChhayaColors.coralDeep,
  );

  static const TextStyle monoCode = TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.5,
    color: ChhayaColors.coralDeep,
  );

  // Legacy names (call sites unchanged; display moves to Tiempos)
  static const TextStyle displayHero = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 40,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
    height: 1.0,
    color: ChhayaColors.ink,
  );

  static const TextStyle displayLarge = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    height: 1.1,
    color: ChhayaColors.ink,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    height: 1.15,
    color: ChhayaColors.ink,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    height: 1.2,
    color: ChhayaColors.ink,
  );

  static const TextStyle headlineLarge = headline;
  static const TextStyle headlineMedium = title;
  static const TextStyle headlineSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
    height: 1.35,
    color: ChhayaColors.ink,
  );

  static const TextStyle bodyMedium = bodyLarge;
  static const TextStyle bodySmall = caption;

  static const TextStyle labelLarge = label;
  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.35,
    color: ChhayaColors.inkMuted,
  );
  static const TextStyle labelSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.3,
    color: ChhayaColors.inkMuted,
  );

  static const TextStyle code = monoCode;

  // Legacy aliases (for migration)
  static const TextStyle largeTitle = displayLarge;
  static const TextStyle title1 = displayMedium;
  static const TextStyle title2 = displaySmall;
  static const TextStyle title3 = headlineLarge;
  static const TextStyle headline1 = headline;
  static const TextStyle callout = bodyMedium;
  static const TextStyle subheadline = bodySmall;
  static const TextStyle footnote = labelMedium;
  static const TextStyle caption1 = caption;
  static const TextStyle caption2 = labelSmall;
  static const TextStyle monoCodeAlias = code;
}
