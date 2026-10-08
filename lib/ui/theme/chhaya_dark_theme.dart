// V13 hacker-terminal theme, preserved as the optional dark theme
// (V14 Part 6). Signal Green (#4ADE80) on near-black. Values below are
// verbatim V13 — only the class name changed (ChhayaColors →
/// ChhayaDarkColors) so the light theme owns the canonical names.
// NOTE: radius/spacing/typography scale are shared with the light
// theme (unified design language); this file preserves the dark
// COLOR posture and a working dark Material scheme.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chhaya_radius.dart';
import 'chhaya_spacing.dart';
import 'chhaya_typography.dart';

class ChhayaDarkColors {
  ChhayaDarkColors._();

  static const Color black = Color(0xFF050705);
  static const Color primaryBackground = Color(0xFF050705);
  static const Color secondaryBackground = Color(0xFF0A0D0B);
  static const Color tertiaryBackground = Color(0xFF0E1310);
  static const Color elevatedBackground = Color(0xFF141A15);
  static const Color groupedBackground = Color(0xFF050705);
  static const Color secondaryGroupedBackground = Color(0xFF0A0D0B);

  static const Color cardSurface = Color(0xFF0D120E);
  static const Color cardSurfaceElevated = Color(0xFF131A14);
  static const Color sheetBackground = Color(0xFF0B0F0C);
  static const Color inputSurface = Color(0xFF0D120E);
  static const Color inputSurfaceFocused = Color(0xFF101711);

  static const Color labelPrimary = Color(0xFFFFFFFF);
  static const Color labelSecondary = Color(0xB3FFFFFF);
  static const Color labelTertiary = Color(0x66FFFFFF);
  static const Color labelQuaternary = Color(0x40FFFFFF);

  static const Color separator = Color(0x14FFFFFF);
  static const Color opaqueSeparator = Color(0xFF1C2620);
  static const Color fillPrimary = Color(0x33FFFFFF);
  static const Color fillSecondary = Color(0x24FFFFFF);
  static const Color fillTertiary = Color(0x14FFFFFF);
  static const Color fillQuaternary = Color(0x0AFFFFFF);

  static const Color accent = Color(0xFF4ADE80);
  static const Color accentDim = Color(0x244ADE80);
  static const Color accentStrong = Color(0x3D4ADE80);
  static const Color onAccent = Color(0xFF04120A);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFFF5F56);
  static const Color info = Color(0xFF7C8DA6);

  static const Color bubbleSent = Color(0xFF4ADE80);
  static const Color bubbleReceived = Color(0xFF101511);
  static const Color bubbleSentText = Color(0xFF04120A);
  static const Color bubbleReceivedText = Color(0xFFFFFFFF);

  static const Color online = Color(0xFF4ADE80);
  static const Color offline = Color(0xFF5B6660);
  static const Color typing = Color(0xFFFBBF24);

  static const Color verifiedLevel1 = Color(0xFFFF5F56);
  static const Color verifiedLevel2 = Color(0xFFFBBF24);
  static const Color verifiedLevel3 = Color(0xFF4ADE80);

  static const Color glassOverlay = Color(0xF20D120E);
  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color glassBorderStrong = Color(0x26FFFFFF);
  static const Color seed = Color(0xFF4ADE80);
}

/// Optional V13 dark Material theme. Wire via MaterialApp.darkTheme
/// with ThemeMode.system (instant, no flicker — Flutter handles it).
class ChhayaDarkTheme {
  ChhayaDarkTheme._();

  static ColorScheme get colorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: ChhayaDarkColors.seed,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      surface: ChhayaDarkColors.primaryBackground,
      surfaceContainerLowest: ChhayaDarkColors.primaryBackground,
      surfaceContainerLow: ChhayaDarkColors.secondaryBackground,
      surfaceContainer: ChhayaDarkColors.tertiaryBackground,
      surfaceContainerHigh: ChhayaDarkColors.cardSurfaceElevated,
      surfaceContainerHighest: ChhayaDarkColors.elevatedBackground,
      onSurface: ChhayaDarkColors.labelPrimary,
      onSurfaceVariant: ChhayaDarkColors.labelSecondary,
      outline: ChhayaDarkColors.separator,
      outlineVariant: ChhayaDarkColors.opaqueSeparator,
      primary: ChhayaDarkColors.accent,
      onPrimary: ChhayaDarkColors.onAccent,
      primaryContainer: ChhayaDarkColors.accentDim,
      secondary: ChhayaDarkColors.info,
      secondaryContainer: ChhayaDarkColors.info.withValues(alpha: 0.14),
      error: ChhayaDarkColors.error,
      onError: ChhayaDarkColors.labelPrimary,
      errorContainer: ChhayaDarkColors.error.withValues(alpha: 0.14),
      tertiary: ChhayaDarkColors.success,
      shadow: ChhayaDarkColors.black,
      scrim: ChhayaDarkColors.black.withValues(alpha: 0.7),
    );
  }

  static ThemeData get material {
    final scheme = colorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _darkTextTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.82),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ChhayaTypography.headlineMedium
            .copyWith(color: scheme.onSurface),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: ChhayaDarkColors.primaryBackground,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: ChhayaDarkColors.primaryBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          side: BorderSide(
              color: scheme.outline.withValues(alpha: 0.6), width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ChhayaDarkColors.inputSurface,
        hintStyle: ChhayaTypography.bodyMedium.copyWith(
          color: ChhayaDarkColors.labelQuaternary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space4,
          vertical: ChhayaSpacing.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
              color: scheme.outline.withValues(alpha: 0.4), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
              color: scheme.outline.withValues(alpha: 0.35), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space5,
            vertical: ChhayaSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
        ),
      ),
    );
  }

  /// Dark text roles: same type scale, dark-appropriate colors.
  static TextTheme _darkTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: ChhayaTypography.displayLarge
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      displayMedium: ChhayaTypography.displayMedium
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      displaySmall: ChhayaTypography.displaySmall
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      headlineLarge: ChhayaTypography.headlineLarge
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      headlineMedium: ChhayaTypography.headlineMedium
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      headlineSmall: ChhayaTypography.headlineSmall
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      titleLarge: ChhayaTypography.headlineLarge
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      titleMedium: ChhayaTypography.headlineMedium
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      titleSmall: ChhayaTypography.headlineSmall
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      bodyLarge: ChhayaTypography.bodyLarge
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      bodyMedium: ChhayaTypography.bodyMedium
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      bodySmall: ChhayaTypography.bodySmall
          .copyWith(color: ChhayaDarkColors.labelSecondary),
      labelLarge: ChhayaTypography.labelLarge
          .copyWith(color: ChhayaDarkColors.labelPrimary),
      labelMedium: ChhayaTypography.labelMedium
          .copyWith(color: ChhayaDarkColors.labelTertiary),
      labelSmall: ChhayaTypography.labelSmall
          .copyWith(color: ChhayaDarkColors.labelQuaternary),
    );
  }
}
