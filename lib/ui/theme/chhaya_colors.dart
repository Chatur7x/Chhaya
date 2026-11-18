// Warm cream/coral primitives and semantic mobile UI colors.
// Small text uses ink, action coral, or semantic states tested at >= 4.5:1.
// Decorative coral and pale tints are not small-text foregrounds.
import 'package:flutter/material.dart';

class ChhayaColors {
  ChhayaColors._();

  // Spec palette — Claude Light
  static const Color coral = Color(0xFFD97757);
  static const Color coralAction = Color(0xFFA84D34);
  static const Color coralDeep = Color(0xFFC15F3C);
  static const Color coralSoft = Color(0xFFE8A88E);
  static const Color coralTint = Color(0xFFF5E5DD);
  static const Color cream = Color(0xFFF5F4EF);
  static const Color surface = Color(0xFFFAF9F5);
  static const Color white = Color(0xFFFFFFFF);

  /// Fully transparent. Exists so widgets never need Material's
  /// `Colors.transparent` (see `test/unit/ui/theme_test.dart`, which
  /// rejects `Colors.white|black` and `Color(0x…)` outside this file).
  static const Color transparent = Color(0x00000000);
  static const Color warmGray = Color(0xFFEDEBE4);
  static const Color hoverCream = Color(0xFFEFEDE6);
  static const Color ink = Color(0xFF1F1E1B);
  static const Color inkSoft = Color(0xFF3D3B36);
  static const Color inkMuted = Color(0xFF6B6862);
  static const Color inkFaint = Color(0xFF9A9690);
  static const Color borderSoft = Color(0xFFE5E2D9);
  static const Color borderMed = Color(0xFFD5D1C5);
  static const Color success = Color(0xFF3E6B43);
  static const Color warning = Color(0xFF825B15);
  static const Color error = Color(0xFFA84D34);
  static const Color info = Color(0xFF46677D);

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
  static const Color labelQuaternary = inkMuted;

  static const Color separator = borderSoft;
  static const Color opaqueSeparator = borderMed;
  static const Color fillPrimary = warmGray;
  static const Color fillSecondary = hoverCream;
  static const Color fillTertiary = coralTint;
  static const Color fillQuaternary = surface;

  static const Color accent = coralAction;
  static const Color accentDim = coralTint;
  static const Color accentStrong = coralSoft;
  static const Color onAccent = white;

  static const Color bubbleSent = coralAction;
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
