// Chhaya theme entry point (V14 Part 6 — Claude Light).
//
// Token classes live in their own files and are re-exported here, so
// every existing `import 'chhaya_theme.dart'` keeps working:
//   chhaya_colors.dart      Coral-on-Cream light tokens
//   chhaya_typography.dart  Inter / Tiempos / Departure Mono scale
//   chhaya_spacing.dart     4-based scale (spec sizes present)
//   chhaya_radius.dart      Round posture (spec set 8/12/16/20/9999)
//   chhaya_elevation.dart   Soft warm shadows (+ legacy ChhayaShadows)
//   chhaya_dark_theme.dart  Preserved V13 hacker-terminal (optional)
//
// [ChhayaTheme.materialLight] is the default. [materialDark] is kept
// as a compatibility alias over the preserved dark scheme — wire both
// via ThemeMode.system for an instant, flicker-free switch.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

import 'chhaya_colors.dart';
import 'chhaya_dark_theme.dart';
import 'chhaya_elevation.dart';
import 'chhaya_radius.dart';
import 'chhaya_spacing.dart';
import 'chhaya_typography.dart';

export 'chhaya_colors.dart';
export 'chhaya_dark_theme.dart';
export 'chhaya_elevation.dart';
export 'chhaya_radius.dart';
export 'chhaya_spacing.dart';
export 'chhaya_typography.dart';

class ChhayaTheme {
  ChhayaTheme._();

  static ColorScheme get colorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: ChhayaColors.seed,
      brightness: Brightness.light,
    );
    return base.copyWith(
      surface: ChhayaColors.primaryBackground,
      surfaceContainerLowest: ChhayaColors.primaryBackground,
      surfaceContainerLow: ChhayaColors.secondaryBackground,
      surfaceContainer: ChhayaColors.tertiaryBackground,
      surfaceContainerHigh: ChhayaColors.cardSurfaceElevated,
      surfaceContainerHighest: ChhayaColors.elevatedBackground,
      onSurface: ChhayaColors.labelPrimary,
      onSurfaceVariant: ChhayaColors.labelSecondary,
      outline: ChhayaColors.separator,
      outlineVariant: ChhayaColors.opaqueSeparator,
      primary: ChhayaColors.accent,
      onPrimary: ChhayaColors.onAccent,
      primaryContainer: ChhayaColors.accentDim,
      secondary: ChhayaColors.info,
      secondaryContainer: ChhayaColors.info.withValues(alpha: 0.14),
      error: ChhayaColors.error,
      onError: ChhayaColors.white,
      errorContainer: ChhayaColors.error.withValues(alpha: 0.14),
      tertiary: ChhayaColors.success,
      shadow: ChhayaColors.ink,
      scrim: ChhayaColors.black.withValues(alpha: 0.5),
    );
  }

  static ThemeData get materialLight {
    final scheme = colorScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.xxl),
        ),
      ),
      dividerColor: scheme.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.9),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ChhayaTypography.headlineMedium
            .copyWith(color: scheme.onSurface),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: ChhayaColors.primaryBackground,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: ChhayaColors.primaryBackground,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.94),
        indicatorColor: scheme.primaryContainer,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ChhayaTypography.labelSmall.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return ChhayaTypography.labelSmall
              .copyWith(color: scheme.onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary, size: 24);
          }
          return IconThemeData(color: scheme.onSurfaceVariant, size: 22);
        }),
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl)),
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
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: scheme.primaryContainer,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space4, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ChhayaColors.inputSurface,
        hintStyle: ChhayaTypography.bodyMedium.copyWith(
          color: ChhayaColors.labelTertiary,
          fontSize: 15,
        ),
        labelStyle: ChhayaTypography.labelMedium
            .copyWith(color: scheme.onSurfaceVariant),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ChhayaColors.ink,
        contentTextStyle: ChhayaTypography.bodyMedium
            .copyWith(color: ChhayaColors.white),
        behavior: SnackBarBehavior.floating,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.xs),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor:
              scheme.onSurfaceVariant.withValues(alpha: 0.4),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space6,
            vertical: ChhayaSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.headlineMedium
              .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor:
              scheme.onSurfaceVariant.withValues(alpha: 0.4),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space5,
            vertical: ChhayaSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.headlineMedium
              .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline, width: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space5,
            vertical: ChhayaSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.headlineMedium
              .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: ChhayaTypography.headlineMedium
              .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ChhayaRadius.pill)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
        extendedTextStyle: ChhayaTypography.headlineMedium
            .copyWith(fontWeight: FontWeight.w700),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: ChhayaTypography.labelLarge
            .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: ChhayaTypography.labelLarge
            .copyWith(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        overlayColor: scheme.primaryContainer,
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: ChhayaTypography.labelSmall
            .copyWith(color: scheme.onPrimary),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
    );
  }

  /// Compatibility alias: the preserved V13 dark scheme.
  static ThemeData get materialDark => ChhayaDarkTheme.material;

  static TextTheme _textTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: ChhayaTypography.displayLarge,
      displayMedium: ChhayaTypography.displayMedium,
      displaySmall: ChhayaTypography.displaySmall,
      headlineLarge: ChhayaTypography.headlineLarge,
      headlineMedium: ChhayaTypography.headlineMedium,
      headlineSmall: ChhayaTypography.headlineSmall,
      titleLarge: ChhayaTypography.headlineLarge,
      titleMedium: ChhayaTypography.headlineMedium,
      titleSmall: ChhayaTypography.headlineSmall,
      bodyLarge: ChhayaTypography.bodyLarge,
      bodyMedium: ChhayaTypography.bodyMedium,
      bodySmall: ChhayaTypography.bodySmall,
      labelLarge: ChhayaTypography.labelLarge,
      labelMedium: ChhayaTypography.labelMedium,
      labelSmall: ChhayaTypography.labelSmall,
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      decorationColor: scheme.onSurfaceVariant,
    );
  }
}

class ChhayaAnimation {
  ChhayaAnimation._();

  static const Curve springCurve = Curves.easeOutExpo;
  static const Curve bounceCurve = Curves.easeOutBack;
  static const Curve decelerateCurve = Curves.decelerate;
  static const Curve dismissCurve = Curves.easeInCubic;
  static const Curve smoothCurve = Curves.easeOutCubic;

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration pageTransition = Duration(milliseconds: 340);
  static const Duration sheetPresent = Duration(milliseconds: 380);
  static const Duration shimmer = Duration(milliseconds: 1500);

  static Duration getDuration(BuildContext context, Duration normal) {
    if (MediaQuery.of(context).disableAnimations) return Duration.zero;
    return normal;
  }

  static Curve getCurve(BuildContext context, Curve normal) {
    if (MediaQuery.of(context).disableAnimations) return Curves.linear;
    return normal;
  }
}

class ChhayaSprings {
  ChhayaSprings._();

  static const SpringDescription standard = SpringDescription(
    mass: 1.0,
    stiffness: 170.0,
    damping: 26.0,
  );

  static const SpringDescription momentum = SpringDescription(
    mass: 1.0,
    stiffness: 170.0,
    damping: 20.8,
  );

  static const SpringDescription sheet = SpringDescription(
    mass: 1.0,
    stiffness: 220.0,
    damping: 23.7,
  );

  static const Curve criticalCurve = Curves.easeOutExpo;
  static const Curve momentumCurve = Curves.easeOutBack;
}

class ChhayaHaptics {
  ChhayaHaptics._();

  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void selection() => HapticFeedback.selectionClick();
  static void vibrate() => HapticFeedback.vibrate();

  static void success() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.lightImpact();
  }

  static void warning() async {
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();
  }

  static void error() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.mediumImpact();
  }
}

class ChhayaBlur {
  ChhayaBlur._();

  static const double surface = 24.0;
  static const double notification = 30.0;
  static const double navigation = 12.0;
  static const double heavy = 40.0;
  static const double light = 10.0;
  static const double glass = 20.0;

  static ImageFilter filter(double sigma) =>
      ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}

class ChhayaPageTransitions {
  ChhayaPageTransitions._();

  static PageRoute<T> materialRoute<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return MaterialPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }

  static PageRoute<T> slideUp<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      pageBuilder: (context, animation, secondaryAnimation) =>
          builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        if (reduceMotion) {
          return FadeTransition(
            opacity: animation.drive(
              Tween<double>(begin: 0.0, end: 1.0)
                  .chain(CurveTween(curve: Curves.easeOut)),
            ),
            child: child,
          );
        }
        const begin = Offset(0.0, 0.04);
        const end = Offset.zero;
        final forward = Tween(begin: begin, end: end)
            .chain(CurveTween(curve: ChhayaSprings.criticalCurve));
        final fade = Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: ChhayaSprings.criticalCurve));
        return FadeTransition(
          opacity: animation.drive(fade),
          child: SlideTransition(
            position: animation.drive(forward),
            child: child,
          ),
        );
      },
      transitionDuration: ChhayaAnimation.pageTransition,
      reverseTransitionDuration: ChhayaAnimation.fast,
    );
  }
}

class ChhayaDecorations {
  ChhayaDecorations._();

  /// Light card — white surface, hairline border, warm shadow.
  /// (Follows the light theme; dark-mode decoration parity is Part 8
  /// polish if the dark theme is retained.)
  static BoxDecoration glassCard({
    double borderRadius = ChhayaRadius.lg,
    Color? color,
    double blurSigma = 24.0,
    bool withBorder = true,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      color: color ?? ChhayaColors.cardSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: withBorder
          ? Border.all(
              color: ChhayaColors.opaqueSeparator,
              width: 1.0,
            )
          : null,
      boxShadow: withShadow ? ChhayaElevation.card : null,
    );
  }

  static BoxDecoration elevatedCard({double borderRadius = ChhayaRadius.lg}) {
    return BoxDecoration(
      color: ChhayaColors.cardSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: ChhayaColors.opaqueSeparator, width: 1.0),
      boxShadow: ChhayaElevation.card,
    );
  }

  static BoxDecoration groupedSection({double borderRadius = ChhayaRadius.md}) {
    return BoxDecoration(
      color: ChhayaColors.secondaryBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: ChhayaColors.separator, width: 0.5),
    );
  }

  static BoxDecoration inputFocused({double borderRadius = ChhayaRadius.lg}) {
    return BoxDecoration(
      color: ChhayaColors.inputSurfaceFocused,
      borderRadius: BorderRadius.circular(borderRadius),
      border:
          Border.all(color: ChhayaColors.accent.withValues(alpha: 0.5), width: 1.2),
    );
  }

  static BoxDecoration heroGlow() {
    return const BoxDecoration(
      gradient: ChhayaColors.glowGradient,
    );
  }

  static BoxDecoration primaryButton({
    double borderRadius = ChhayaRadius.pill,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      gradient: ChhayaColors.accentGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: null,
    );
  }

  static BoxDecoration secondaryButton(
      {double borderRadius = ChhayaRadius.pill}) {
    return BoxDecoration(
      color: ChhayaColors.tertiaryBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
          color: ChhayaColors.opaqueSeparator.withValues(alpha: 0.6), width: 1),
    );
  }

  static BoxDecoration ghostButton({double borderRadius = ChhayaRadius.pill}) {
    return BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }
}
