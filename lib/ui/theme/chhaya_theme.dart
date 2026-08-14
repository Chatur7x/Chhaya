import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';





class ChhayaColors {
  ChhayaColors._();


  static const Color black = Color(0xFF000000);
  static const Color primaryBackground = Color(0xFF000000);
  static const Color secondaryBackground = Color(0xFF1C1C1E);
  static const Color tertiaryBackground = Color(0xFF2C2C2E);
  static const Color elevatedBackground = Color(0xFF1C1C1E);
  static const Color groupedBackground = Color(0xFF000000);
  static const Color secondaryGroupedBackground = Color(0xFF1C1C1E);


  static const Color cardSurface = Color(0xFF1C1C1E);
  static const Color cardSurfaceElevated = Color(0xFF2C2C2E);
  static const Color sheetBackground = Color(0xFF1C1C1E);


  static const Color labelPrimary = Color(0xFFFFFFFF);
  static const Color labelSecondary = Color(0x99EBEBF5);
  static const Color labelTertiary = Color(0x4DEBEBF5);
  static const Color labelQuaternary = Color(0x29EBEBF5);


  static const Color separator = Color(0x5C545458);
  static const Color opaqueSeparator = Color(0xFF38383A);


  static const Color fillPrimary = Color(0x5C787880);
  static const Color fillSecondary = Color(0x52787880);
  static const Color fillTertiary = Color(0x3D767680);


  static const Color accentBlue = Color(0xFF007AFF);
  static const Color accentGreen = Color(0xFF34C759);
  static const Color accentIndigo = Color(0xFF5856D6);
  static const Color accentOrange = Color(0xFFFF9500);
  static const Color accentPink = Color(0xFFFF2D55);
  static const Color accentPurple = Color(0xFFAF52DE);
  static const Color accentRed = Color(0xFFFF3B30);
  static const Color accentTeal = Color(0xFF5AC8FA);
  static const Color accentYellow = Color(0xFFFFCC00);


  static const Color bubbleSent = Color(0xFF007AFF);
  static const Color bubbleReceived = Color(0xFF2C2C2E);
  static const Color bubbleSentText = Color(0xFFFFFFFF);
  static const Color bubbleReceivedText = Color(0xFFFFFFFF);


  static const Color online = Color(0xFF34C759);
  static const Color offline = Color(0xFF8E8E93);
  static const Color typing = Color(0xFFFF9500);


  static const Color verifiedLevel1 = Color(0xFFFF3B30);
  static const Color verifiedLevel2 = Color(0xFFFFCC00);
  static const Color verifiedLevel3 = Color(0xFF34C759);


  static const Color glassOverlay = Color(0x331C1C1E);
  static const Color glassBorder = Color(0x33FFFFFF);


  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient callGradient = LinearGradient(
    colors: [Color(0xFF34C759), Color(0xFF30D158)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF3B30), Color(0xFFFF2D55)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}





class ChhayaTypography {
  ChhayaTypography._();

  static const String _fontFamily = '.SF Pro Text';
  static const String _displayFontFamily = '.SF Pro Display';


  static const TextStyle largeTitle = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle title1 = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle title2 = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle title3 = TextStyle(
    fontFamily: _displayFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle callout = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.32,
    color: ChhayaColors.labelPrimary,
  );


  static const TextStyle subheadline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    color: ChhayaColors.labelSecondary,
  );


  static const TextStyle footnote = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
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
    letterSpacing: 0.07,
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


  static PageRoute<T> slideRoute<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
    );
  }
}





class ChhayaTheme {
  ChhayaTheme._();


  static CupertinoThemeData get data => const CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: ChhayaColors.accentBlue,
    primaryContrastingColor: ChhayaColors.labelPrimary,
    scaffoldBackgroundColor: ChhayaColors.primaryBackground,
    barBackgroundColor: Color(0xE61C1C1E),
    textTheme: CupertinoTextThemeData(
      primaryColor: ChhayaColors.accentBlue,
      textStyle: ChhayaTypography.body,
      navTitleTextStyle: ChhayaTypography.headline,
      navLargeTitleTextStyle: ChhayaTypography.largeTitle,
      tabLabelTextStyle: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.24,
      ),
    ),
  );
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


  static BoxDecoration elevatedCard({
    double borderRadius = ChhayaRadius.lg,
  }) {
    return BoxDecoration(
      color: ChhayaColors.cardSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: ChhayaShadows.card,
    );
  }


  static BoxDecoration groupedSection({
    double borderRadius = ChhayaRadius.md,
  }) {
    return BoxDecoration(
      color: ChhayaColors.secondaryGroupedBackground,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }
}
