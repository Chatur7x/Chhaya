// Claude Light color tokens (V14 Part 6).
//
// Coral (#D97757) on Cream (#F5F4EF). All legacy member names are
// preserved so every call site compiles unchanged — values are
// re-mapped from the V13 hacker-terminal to the light palette.
// The V13 dark values live on untouched in chhaya_dark_theme.dart.
//
// WCAG AA (verified, see test/unit/ui/theme_test.dart):
//   PASS normal text: ink/cream 15.1, inkSoft/cream 10.2,
//     inkMuted/cream 5.0, ink/surface 15.8
//   PASS UI components (3:1): white/coral 3.1, white/coralDeep 4.2,
//     coralDeep/cream 3.8, success/cream 3.6, error/cream 3.8,
//     info/cream 3.3
//   RESTRICTED (documented, never sole indicators):
//     inkFaint/cream 2.7 — hairlines and decorative marks only,
//       never text, never the only affordance.
//     coral/cream 2.8 — large graphics and accents only, never text
//       (use coralDeep for small semibold labels).
//     warning/cream 2.3 — status dots must always pair with an ink
//       text label; warning is never color-alone.
import 'package:flutter/material.dart';

class ChhayaColors {
  ChhayaColors._();

  // Spec palette — Claude Light
  static const Color coral = Color(0xFFD97757);
  static const Color coralDeep = Color(0xFFC15F3C);
  static const Color coralSoft = Color(0xFFE8A88E);
  static const Color coralTint = Color(0xFFF5E5DD);
  static const Color cream = Color(0xFFF5F4EF);
  static const Color surface = Color(0xFFFAF9F5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color warmGray = Color(0xFFEDEBE4);
  static const Color hoverCream = Color(0xFFEFEDE6);
  static const Color ink = Color(0xFF1F1E1B);
  static const Color inkSoft = Color(0xFF3D3B36);
  static const Color inkMuted = Color(0xFF6B6862);
  static const Color inkFaint = Color(0xFF9A9690);
  static const Color borderSoft = Color(0xFFE5E2D9);
  static const Color borderMed = Color(0xFFD5D1C5);
  static const Color success = Color(0xFF5C8A5C);
  static const Color warning = Color(0xFFC89A3C);
  static const Color error = Color(0xFFC15F3C);
  static const Color info = Color(0xFF6B8AA5);

  // Legacy names, re-mapped to Light (call sites unchanged)
  static const Color black = Color(0xFF050705); // scrims only
  static const Color primaryBackground = cream;
  static const Color secondaryBackground = surface;
  static const Color tertiaryBackground = white;
  static const Color elevatedBackground = white;
  static const Color groupedBackground = cream;
  static const Color secondaryGroupedBackground = surface;

  static const Color cardSurface = white;
  static const Color cardSurfaceElevated = white;
  static const Color sheetBackground = surface;
  static const Color inputSurface = white;
  static const Color inputSurfaceFocused = coralTint;

  static const Color labelPrimary = ink;
  static const Color labelSecondary = inkSoft;
  static const Color labelTertiary = inkMuted;
  static const Color labelQuaternary = inkFaint;

  static const Color separator = borderSoft;
  static const Color opaqueSeparator = borderMed;
  static const Color fillPrimary = warmGray;
  static const Color fillSecondary = hoverCream;
  static const Color fillTertiary = coralTint;
  static const Color fillQuaternary = surface;

  static const Color accent = coral;
  static const Color accentDim = coralTint;
  static const Color accentStrong = coralSoft;
  static const Color onAccent = white;

  static const Color bubbleSent = coral;
  static const Color bubbleReceived = white;
  static const Color bubbleSentText = white;
  static const Color bubbleReceivedText = ink;

  static const Color online = success;
  static const Color offline = inkFaint;
  static const Color typing = warning;

  static const Color verifiedLevel1 = error;
  static const Color verifiedLevel2 = warning;
  static const Color verifiedLevel3 = success;

  static const Color glassOverlay = Color(0xF2FAF9F5);
  static const Color glassBorder = borderSoft;
  static const Color glassBorderStrong = borderMed;

  static const Color seed = coral;

  // Flat fills — same names as before. No gradients anywhere.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [coral, coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient auroraGradient = LinearGradient(
    colors: [coralSoft, coralTint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [cream, surface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [white, white],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient callGradient = LinearGradient(
    colors: [cream, surface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [error, error],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient shimmerGradient = LinearGradient(
    colors: [warmGray, white, warmGray],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const RadialGradient glowGradient = RadialGradient(
    colors: [Color(0x00000000), Color(0x00000000)],
    center: Alignment.topCenter,
    radius: 1.2,
  );
}
