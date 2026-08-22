import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Chhaya Material 3 design system.
///
/// Replaces the previous iOS/Cupertino tokens with Android-native Material 3
/// surfaces, color roles, and motion. The palette preserves the secure-messenger
/// identity: true-black background, blue/indigo accent, and high-contrast labels.
class ChhayaColors {
  ChhayaColors._();

  // Core surfaces
  static const Color black = Color(0xFF000000);
  static const Color primaryBackground = Color(0xFF000000);
  static const Color secondaryBackground = Color(0xFF121212);
  static const Color tertiaryBackground = Color(0xFF1E1E1E);
  static const Color elevatedBackground = Color(0xFF1C1C1E);
  static const Color groupedBackground = Color(0xFF000000);
  static const Color secondaryGroupedBackground = Color(0xFF121212);

  // Cards & sheets
  static const Color cardSurface = Color(0xFF121212);
  static const Color cardSurfaceElevated = Color(0xFF1E1E1E);
  static const Color sheetBackground = Color(0xFF121212);

  // Labels
  static const Color labelPrimary = Color(0xFFFFFFFF);
  static const Color labelSecondary = Color(0xB3FFFFFF);
  static const Color labelTertiary = Color(0x66FFFFFF);
  static const Color labelQuaternary = Color(0x33FFFFFF);

  // Dividers & fills
  static const Color separator = Color(0x1FFFFFFF);
  static const Color opaqueSeparator = Color(0xFF38383A);
  static const Color fillPrimary = Color(0x33FFFFFF);
  static const Color fillSecondary = Color(0x24FFFFFF);
  static const Color fillTertiary = Color(0x14FFFFFF);

  // Accents
  static const Color accentBlue = Color(0xFF4DB2F9);
  static const Color accentGreen = Color(0xFF5DDC92);
  static const Color accentIndigo = Color(0xFF8B92F0);
  static const Color accentOrange = Color(0xFFFFB366);
  static const Color accentPink = Color(0xFFFF7A8F);
  static const Color accentPurple = Color(0xFFD09CF6);
  static const Color accentRed = Color(0xFFFF6B6B);
  static const Color accentTeal = Color(0xFF6DE0F2);
  static const Color accentYellow = Color(0xFFFFD54F);

  // Chat bubbles
  static const Color bubbleSent = Color(0xFF2E5BFF);
  static const Color bubbleReceived = Color(0xFF1E1E1E);
  static const Color bubbleSentText = Color(0xFFFFFFFF);
  static const Color bubbleReceivedText = Color(0xFFFFFFFF);

  // Status
  static const Color online = Color(0xFF5DDC92);
  static const Color offline = Color(0xFF8E8E93);
  static const Color typing = Color(0xFFFFB366);

  // Verification levels
  static const Color verifiedLevel1 = Color(0xFFFF6B6B);
  static const Color verifiedLevel2 = Color(0xFFFFD54F);
  static const Color verifiedLevel3 = Color(0xFF5DDC92);

  // Glass effects (kept for overlay surfaces)
  static const Color glassOverlay = Color(0x33121212);
  static const Color glassBorder = Color(0x1FFFFFFF);

  // Material seed color used to derive [ChhayaTheme.colorScheme].
  static const Color seed = Color(0xFF4F46E5);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF4DB2F9), Color(0xFF8B92F0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient callGradient = LinearGradient(
    colors: [Color(0xFF5DDC92), Color(0xFF2ECC71)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFFF7A8F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class ChhayaTypography {
  ChhayaTypography._();

  static const String _fontFamily = 'Roboto';
  static const String _displayFontFamily = 'Roboto';

  static const TextStyle largeTitle = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle title1 = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle title2 = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle title3 = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle callout = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: ChhayaColors.labelPrimary,
  );

  static const TextStyle subheadline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: ChhayaColors.labelSecondary,
  );

  static const TextStyle footnote = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: ChhayaColors.labelSecondary,
  );

  static const TextStyle caption1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: ChhayaColors.labelSecondary,
  );

  static const TextStyle caption2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: ChhayaColors.labelTertiary,
  );
}

class ChhayaSpacing {
  ChhayaSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

class ChhayaRadius {
  ChhayaRadius._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double pill = 100.0;
  static const double circle = 999.0;
}

class ChhayaAnimation {
  ChhayaAnimation._();

  static const Curve springCurve = Curves.easeOutExpo;
  static const Curve bounceCurve = Curves.easeOutBack;
  static const Curve decelerateCurve = Curves.decelerate;
  static const Curve dismissCurve = Curves.easeIn;

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 450);
  static const Duration pageTransition = Duration(milliseconds: 350);
  static const Duration sheetPresent = Duration(milliseconds: 400);
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

  static const double surface = 25.0;
  static const double notification = 30.0;
  static const double navigation = 10.0;
  static const double heavy = 40.0;
  static const double light = 8.0;

  static ImageFilter filter(double sigma) =>
      ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}

class ChhayaShadows {
  ChhayaShadows._();

  static List<BoxShadow> get subtle => [
    BoxShadow(
      color: ChhayaColors.black.withValues(alpha: 0.12),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get card => [
    BoxShadow(
      color: ChhayaColors.black.withValues(alpha: 0.2),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: ChhayaColors.black.withValues(alpha: 0.06),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get notification => [
    BoxShadow(
      color: ChhayaColors.black.withValues(alpha: 0.3),
      blurRadius: 30,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get deep => [
    BoxShadow(
      color: ChhayaColors.black.withValues(alpha: 0.35),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}

class ChhayaPageTransitions {
  ChhayaPageTransitions._();

  /// Material fade-through route for full-screen pages.
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

  /// Shared-axis style page route (Android default feel).
  static PageRoute<T> slideUp<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 0.05);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        final fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
        return FadeTransition(
          opacity: animation.drive(fadeTween),
          child: SlideTransition(
            position: animation.drive(tween),
            child: child,
          ),
        );
      },
      transitionDuration: ChhayaAnimation.pageTransition,
    );
  }
}

class ChhayaTheme {
  ChhayaTheme._();

  /// Material 3 dark color scheme with Chhaya's true-black surface and
  /// blue/indigo accents.
  static ColorScheme get colorScheme {
    return ColorScheme.fromSeed(
      seedColor: ChhayaColors.seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: ChhayaColors.primaryBackground,
      surfaceContainerLowest: ChhayaColors.primaryBackground,
      surfaceContainerLow: ChhayaColors.secondaryBackground,
      surfaceContainer: ChhayaColors.tertiaryBackground,
      surfaceContainerHigh: ChhayaColors.cardSurfaceElevated,
      surfaceContainerHighest: ChhayaColors.cardSurfaceElevated,
      onSurface: ChhayaColors.labelPrimary,
      onSurfaceVariant: ChhayaColors.labelSecondary,
      outline: ChhayaColors.separator,
      outlineVariant: ChhayaColors.opaqueSeparator,
      primary: ChhayaColors.accentBlue,
      onPrimary: ChhayaColors.labelPrimary,
      primaryContainer: ChhayaColors.accentBlue.withValues(alpha: 0.2),
      secondary: ChhayaColors.accentIndigo,
      secondaryContainer: ChhayaColors.accentIndigo.withValues(alpha: 0.2),
      error: ChhayaColors.accentRed,
      onError: ChhayaColors.labelPrimary,
      errorContainer: ChhayaColors.accentRed.withValues(alpha: 0.2),
      tertiary: ChhayaColors.accentTeal,
      shadow: ChhayaColors.black,
      scrim: ChhayaColors.black.withValues(alpha: 0.6),
    );
  }

  /// Complete Material 3 [ThemeData] for the Chhaya dark UI.
  static ThemeData get materialDark {
    final scheme = colorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerHigh),
      dividerColor: scheme.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: ChhayaTypography.headline.copyWith(color: scheme.onSurface),
        surfaceTintColor: scheme.surfaceTint,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(ChhayaTypography.caption2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl)),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: scheme.surfaceContainerLow,
        selectedTileColor: scheme.primaryContainer,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: ChhayaTypography.callout.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.lg,
          vertical: ChhayaSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: ChhayaTypography.callout.copyWith(color: scheme.onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.sm),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.xxl,
            vertical: ChhayaSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.headline,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.xl,
            vertical: ChhayaSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.callout.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(
            horizontal: ChhayaSpacing.xl,
            vertical: ChhayaSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          textStyle: ChhayaTypography.callout.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: ChhayaTypography.callout.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CircleBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: ChhayaTypography.largeTitle,
      displayMedium: ChhayaTypography.title1,
      displaySmall: ChhayaTypography.title2,
      headlineLarge: ChhayaTypography.title2,
      headlineMedium: ChhayaTypography.title3,
      headlineSmall: ChhayaTypography.title3,
      titleLarge: ChhayaTypography.title3,
      titleMedium: ChhayaTypography.headline,
      titleSmall: ChhayaTypography.callout.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: ChhayaTypography.body,
      bodyMedium: ChhayaTypography.callout,
      bodySmall: ChhayaTypography.subheadline,
      labelLarge: ChhayaTypography.footnote.copyWith(fontWeight: FontWeight.w600),
      labelMedium: ChhayaTypography.caption1,
      labelSmall: ChhayaTypography.caption2,
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      decorationColor: scheme.onSurfaceVariant,
    );
  }
}

class ChhayaDecorations {
  ChhayaDecorations._();

  static BoxDecoration glassCard({
    double borderRadius = ChhayaRadius.lg,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? ChhayaColors.glassOverlay,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: ChhayaColors.glassBorder.withValues(alpha: 0.10),
        width: 0.5,
      ),
    );
  }

  static BoxDecoration elevatedCard({double borderRadius = ChhayaRadius.lg}) {
    return BoxDecoration(
      color: ChhayaColors.cardSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: ChhayaShadows.card,
    );
  }

  static BoxDecoration groupedSection({double borderRadius = ChhayaRadius.md}) {
    return BoxDecoration(
      color: ChhayaColors.secondaryGroupedBackground,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }
}
