import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Chhaya Design System v12.1 — Hacker-Terminal Minimalism
///
/// Single accent lock: Signal Green (#4ADE80) on near-black.
/// Flat surfaces, hairline borders, zero gradients, zero glows.
/// Shape lock: sharp corners (buttons 6px, cards 8px, sheets 12px).
/// Mono micro-labels; Inter for body; negative tracking on display.
/// Motion: Apple critically-damped springs, press-down feedback.

class ChhayaColors {
  ChhayaColors._();

  // Core surfaces — near-black with a faint green cast (never pure black)
  static const Color black = Color(0xFF050705);
  static const Color primaryBackground = Color(0xFF050705);
  static const Color secondaryBackground = Color(0xFF0A0D0B);
  static const Color tertiaryBackground = Color(0xFF0E1310);
  static const Color elevatedBackground = Color(0xFF141A15);
  static const Color groupedBackground = Color(0xFF050705);
  static const Color secondaryGroupedBackground = Color(0xFF0A0D0B);

  // Cards & sheets — flat, separated by hairlines not shadows
  static const Color cardSurface = Color(0xFF0D120E);
  static const Color cardSurfaceElevated = Color(0xFF131A14);
  static const Color sheetBackground = Color(0xFF0B0F0C);
  static const Color inputSurface = Color(0xFF0D120E);
  static const Color inputSurfaceFocused = Color(0xFF101711);

  // Labels — high contrast on near-black
  static const Color labelPrimary = Color(0xFFFFFFFF);
  static const Color labelSecondary = Color(0xB3FFFFFF); // 70%
  static const Color labelTertiary = Color(0x66FFFFFF);  // 40%
  static const Color labelQuaternary = Color(0x40FFFFFF); // 25%

  // Dividers & fills — hairlines, not shadows
  static const Color separator = Color(0x14FFFFFF);      // 8%
  static const Color opaqueSeparator = Color(0xFF1C2620);
  static const Color fillPrimary = Color(0x33FFFFFF);    // 20%
  static const Color fillSecondary = Color(0x24FFFFFF);  // 14%
  static const Color fillTertiary = Color(0x14FFFFFF);   // 8%
  static const Color fillQuaternary = Color(0x0AFFFFFF); // 4%

  // SINGLE ACCENT LOCK — Signal Green only
  static const Color accent = Color(0xFF4ADE80);
  static const Color accentDim = Color(0x244ADE80);      // 14%
  static const Color accentStrong = Color(0x3D4ADE80);   // 24%

  // Ink — text/icons placed ON accent surfaces (phosphor-on-dark inverse)
  static const Color onAccent = Color(0xFF04120A);

  // Semantic accents (status only, never UI chrome)
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFFF5F56);
  static const Color info = Color(0xFF7C8DA6);

  // Chat bubbles — flat. Sent is solid phosphor, received is dark panel.
  static const Color bubbleSent = Color(0xFF4ADE80);
  static const Color bubbleReceived = Color(0xFF101511);
  static const Color bubbleSentText = Color(0xFF04120A);
  static const Color bubbleReceivedText = Color(0xFFFFFFFF);

  // Status
  static const Color online = Color(0xFF4ADE80);
  static const Color offline = Color(0xFF5B6660);
  static const Color typing = Color(0xFFFBBF24);

  // Verification levels
  static const Color verifiedLevel1 = Color(0xFFFF5F56);
  static const Color verifiedLevel2 = Color(0xFFFBBF24);
  static const Color verifiedLevel3 = Color(0xFF4ADE80);

  // Hairline borders
  static const Color glassOverlay = Color(0xF20D120E);
  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color glassBorderStrong = Color(0x26FFFFFF);

  // Material seed (for ColorScheme.fromSeed)
  static const Color seed = Color(0xFF4ADE80);

  // Flat fills — same names as before so every usage goes flat
  // automatically. No gradients anywhere in this theme. Ever.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF4ADE80), Color(0xFF4ADE80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient auroraGradient = LinearGradient(
    colors: [Color(0xFF4ADE80), Color(0xFF4ADE80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF050705), Color(0xFF050705)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF0D120E), Color(0xFF0D120E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient callGradient = LinearGradient(
    colors: [Color(0xFF050705), Color(0xFF050705)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF5F56), Color(0xFFFF5F56)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient shimmerGradient = LinearGradient(
    colors: [Color(0xFF141A15), Color(0xFF1A221B), Color(0xFF141A15)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const RadialGradient glowGradient = RadialGradient(
    colors: [Color(0x00000000), Color(0x00000000)],
    center: Alignment.topCenter,
    radius: 1.2,
  );
}

class ChhayaTypography {
  ChhayaTypography._();

  static const String _fontFamily = 'Inter';
  static const String _displayFontFamily = 'Inter';
  static const String _monoFontFamily = 'JetBrains Mono';

  // Display
  static const TextStyle displayHero = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 40,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.2,
    height: 0.95,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle displayLarge = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.10,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.15,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.20,
    color: ChhayaColors.labelPrimary,
  );

  // Headlines
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.15,
    height: 1.30,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.35,
    color: ChhayaColors.labelPrimary,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    height: 1.45,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    height: 1.40,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.40,
    color: ChhayaColors.labelSecondary,
  );

  // Labels — micro-labels are MONO (terminal readouts: timestamps,
  // badges, status lines, IDs). Apple §15: tracking is size-specific.
  static const TextStyle labelLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.35,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.35,
    color: ChhayaColors.labelTertiary,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    height: 1.30,
    color: ChhayaColors.labelQuaternary,
  );

  // Code / Mono
  static const TextStyle code = TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.50,
    color: ChhayaColors.accent,
  );

  // Legacy aliases (for migration)
  static const TextStyle largeTitle = displayLarge;
  static const TextStyle title1 = displayMedium;
  static const TextStyle title2 = displaySmall;
  static const TextStyle title3 = headlineLarge;
  static const TextStyle headline = headlineMedium;
  static const TextStyle callout = bodyMedium;
  static const TextStyle subheadline = bodySmall;
  static const TextStyle footnote = labelMedium;
  static const TextStyle caption1 = labelMedium;
  static const TextStyle caption2 = labelSmall;
  static const TextStyle monoCode = code;
}

class ChhayaSpacing {
  ChhayaSpacing._();

  static const double space0 = 0;
  static const double space1 = 4.0;   // xs
  static const double space2 = 8.0;   // sm
  static const double space3 = 12.0;  // md
  static const double space4 = 16.0;  // lg
  static const double space5 = 20.0;  // xl
  static const double space6 = 24.0;  // xxl
  static const double space7 = 28.0;  // xxxl
  static const double space8 = 32.0;  // huge
  static const double space12 = 48.0; // massive
  static const double space16 = 64.0; // colossal

  // Legacy aliases
  static const double xs = space1;
  static const double sm = space2;
  static const double md = space3;
  static const double lg = space4;
  static const double xl = space5;
  static const double xxl = space6;
  static const double xxxl = space7;
  static const double huge = space8;
  static const double massive = space12;
  static const double colossal = space16;
}

class ChhayaRadius {
  ChhayaRadius._();

  // Hacker lock: sharp corners everywhere. Buttons 6px, cards 8px,
  // inputs 6px, sheets 12px. Circles stay circular (avatars, dots).
  static const double xs = 2.0;
  static const double sm = 4.0;
  static const double md = 6.0;
  static const double lg = 8.0;       // Cards
  static const double xl = 10.0;
  static const double xxl = 12.0;     // Bottom sheets
  static const double pill = 6.0;     // Buttons, chips, badges
  static const double circle = 9999.0;
}

class ChhayaAnimation {
  ChhayaAnimation._();

  // Curves
  static const Curve springCurve = Curves.easeOutExpo;
  static const Curve bounceCurve = Curves.easeOutBack;
  static const Curve decelerateCurve = Curves.decelerate;
  static const Curve dismissCurve = Curves.easeInCubic;
  static const Curve smoothCurve = Curves.easeOutCubic;

  // Durations
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration pageTransition = Duration(milliseconds: 340);
  static const Duration sheetPresent = Duration(milliseconds: 380);
  static const Duration shimmer = Duration(milliseconds: 1500);

  // Reduced motion helpers
  static Duration getDuration(BuildContext context, Duration normal) {
    if (MediaQuery.of(context).disableAnimations) return Duration.zero;
    return normal;
  }

  static Curve getCurve(BuildContext context, Curve normal) {
    if (MediaQuery.of(context).disableAnimations) return Curves.linear;
    return normal;
  }
}

/// Apple-style spring physics (apple-design §4).
///
/// Apple ships springs as damping-ratio + response, not duration:
/// - Default UI: critically damped (ratio 1.0) — graceful, no overshoot.
/// - Momentum only (flick/throw/drag-release): ratio ~0.8 — slight bounce.
/// Flutter's [SpringDescription] takes mass/stiffness/damping; the values
/// below map to Apple's table (response 0.3–0.4s).
class ChhayaSprings {
  ChhayaSprings._();

  /// Critically damped — the default for all UI motion. No overshoot.
  static const SpringDescription standard = SpringDescription(
    mass: 1.0,
    stiffness: 170.0,
    damping: 26.0, // 2 * sqrt(170) ≈ 26.1 → ratio 1.0
  );

  /// Under-damped — ONLY for momentum-driven motion (flick, drag release,
  /// swipe dismiss). Slight overshoot because the gesture carried momentum.
  static const SpringDescription momentum = SpringDescription(
    mass: 1.0,
    stiffness: 170.0,
    damping: 20.8, // ratio ≈ 0.8
  );

  /// Snappy sheet/drawer spring (Apple: drawer response 0.3, damping 0.8).
  static const SpringDescription sheet = SpringDescription(
    mass: 1.0,
    stiffness: 220.0,
    damping: 23.7, // ratio ≈ 0.8
  );

  /// Cubic approximations for implicit animations (AnimatedContainer etc.)
  /// where a real SpringSimulation isn't available. Matches the springs
  /// above closely enough for 100–400ms UI motion.
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

class ChhayaShadows {
  ChhayaShadows._();

  // Hacker theme: separation comes from hairlines, not shadows.
  // Only the faintest lift remains; glows are banned (empty lists).
  static List<BoxShadow> get subtle => [
        BoxShadow(
          color: ChhayaColors.black.withValues(alpha: 0.35),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get card => [
        BoxShadow(
          color: ChhayaColors.black.withValues(alpha: 0.40),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get notification => [
        BoxShadow(
          color: ChhayaColors.black.withValues(alpha: 0.50),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get deep => [
        BoxShadow(
          color: ChhayaColors.black.withValues(alpha: 0.50),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get glowBlue => [];

  static List<BoxShadow> get glowIndigo => [];
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

  /// Apple §7 spatial consistency: enter and exit along the SAME path.
  /// Push slides up + fades in; pop slides back down + fades out with a
  /// mirrored curve. Reduced motion (§14): short cross-fade, no slide.
  static PageRoute<T> slideUp<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        if (reduceMotion) {
          // Cross-fade, not slide/spring (apple-design §14).
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

class ChhayaTheme {
  ChhayaTheme._();

  static ColorScheme get colorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: ChhayaColors.seed,
      brightness: Brightness.dark,
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
      onError: ChhayaColors.labelPrimary,
      errorContainer: ChhayaColors.error.withValues(alpha: 0.14),
      tertiary: ChhayaColors.success,
      shadow: ChhayaColors.black,
      scrim: ChhayaColors.black.withValues(alpha: 0.7),
    );
  }

  static ThemeData get materialDark {
    final scheme = colorScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
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
        backgroundColor: scheme.surface.withValues(alpha: 0.82),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ChhayaTypography.headlineMedium.copyWith(color: scheme.onSurface),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: ChhayaColors.primaryBackground,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: ChhayaColors.primaryBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.92),
        indicatorColor: scheme.primaryContainer,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ChhayaTypography.labelSmall.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return ChhayaTypography.labelSmall.copyWith(color: scheme.onSurfaceVariant);
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl)),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6), width: 0.5),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ChhayaColors.inputSurface,
        hintStyle: ChhayaTypography.bodyMedium.copyWith(
          color: ChhayaColors.labelQuaternary,
          fontSize: 15,
        ),
        labelStyle: ChhayaTypography.labelMedium.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space4,
          vertical: ChhayaSpacing.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.4), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.35), width: 1),
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
        backgroundColor: ChhayaColors.cardSurfaceElevated,
        contentTextStyle: ChhayaTypography.bodyMedium.copyWith(color: scheme.onSurface),
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
          if (states.contains(WidgetState.selected)) return scheme.primaryContainer;
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
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space6,
            vertical: ChhayaSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.headlineMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.space5,
            vertical: ChhayaSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.headlineMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
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
          textStyle: ChhayaTypography.headlineMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: ChhayaTypography.headlineMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.pill)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
        extendedTextStyle: ChhayaTypography.headlineMedium.copyWith(fontWeight: FontWeight.w700),
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
        labelStyle: ChhayaTypography.labelLarge.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: ChhayaTypography.labelLarge.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        overlayColor: scheme.primaryContainer,
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: ChhayaTypography.labelSmall.copyWith(color: scheme.onPrimary),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
    );
  }

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

class ChhayaDecorations {
  ChhayaDecorations._();

  /// Flat hacker panel — solid surface, 1px hairline, no blur glow.
  /// (Keeps the GlassContainer name so call sites don't change.)
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
      boxShadow: withShadow ? ChhayaShadows.card : null,
    );
  }

  /// Elevated card — solid surface, hairline border.
  static BoxDecoration elevatedCard({double borderRadius = ChhayaRadius.lg}) {
    return BoxDecoration(
      color: ChhayaColors.cardSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: ChhayaColors.opaqueSeparator, width: 1.0),
      boxShadow: ChhayaShadows.card,
    );
  }

  /// Grouped section — flat container
  static BoxDecoration groupedSection({double borderRadius = ChhayaRadius.md}) {
    return BoxDecoration(
      color: ChhayaColors.secondaryBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: ChhayaColors.separator, width: 0.5),
    );
  }

  /// Input focused state
  static BoxDecoration inputFocused({double borderRadius = ChhayaRadius.lg}) {
    return BoxDecoration(
      color: ChhayaColors.inputSurfaceFocused,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: ChhayaColors.accent.withValues(alpha: 0.5), width: 1.2),
      boxShadow: ChhayaShadows.glowBlue,
    );
  }

  /// Hero glow background
  static BoxDecoration heroGlow() {
    return BoxDecoration(
      gradient: ChhayaColors.glowGradient,
    );
  }

  /// Primary button gradient decoration
  static BoxDecoration primaryButton({
    double borderRadius = ChhayaRadius.pill,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      gradient: ChhayaColors.accentGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: withShadow ? ChhayaShadows.glowBlue : null,
    );
  }

  /// Secondary button decoration
  static BoxDecoration secondaryButton({double borderRadius = ChhayaRadius.pill}) {
    return BoxDecoration(
      color: ChhayaColors.tertiaryBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: ChhayaColors.opaqueSeparator.withValues(alpha: 0.6), width: 1),
    );
  }

  /// Ghost button (no bg, just text)
  static BoxDecoration ghostButton({double borderRadius = ChhayaRadius.pill}) {
    return BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }
}