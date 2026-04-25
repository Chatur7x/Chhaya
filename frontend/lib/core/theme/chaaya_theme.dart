import 'package:flutter/material.dart';
import 'dart:ui';

/// Chaaya Design System V2
/// Premium dark theme with 3D effects, glassmorphism, and Apple-grade aesthetics.
class ChaayaTheme {
  // ─── Colors ───
  static const Color background = Color(0xFF0A0C10);
  static const Color surface = Color(0xFF141820);
  static const Color surfaceLight = Color(0xFF1C2230);
  static const Color surfaceElevated = Color(0xFF222938);
  static const Color accent = Color(0xFF6C63FF);
  static const Color accentLight = Color(0xFF8B83FF);
  static const Color accentGlow = Color(0x406C63FF);

  // Gradients
  static const Color gradientStart = Color(0xFF6C63FF);
  static const Color gradientEnd = Color(0xFF3B82F6);
  static const Color gradientWarm = Color(0xFFFF6B6B);
  static const Color gradientCool = Color(0xFF48E5C2);

  // Channel indicators
  static const Color bleColor = Color(0xFF3B82F6);
  static const Color wifiColor = Color(0xFF10B981);
  static const Color morseColor = Color(0xFFF59E0B);

  // Status colors
  static const Color sosRed = Color(0xFFEF4444);
  static const Color safeGreen = Color(0xFF10B981);
  static const Color warningYellow = Color(0xFFF59E0B);
  static const Color offlineGray = Color(0xFF6B7280);

  // Contact status
  static const Color nearbyGreen = Color(0xFF10B981);
  static const Color relayYellow = Color(0xFFF59E0B);
  static const Color unreachableGray = Color(0xFF6B7280);

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Glass
  static const Color glassWhite = Color(0x0DFFFFFF);
  static const Color glass = glassWhite;
  static const Color glassBorder = Color(0x1AFFFFFF);
  static const Color glassHighlight = Color(0x33FFFFFF);

  // ─── Theme Data ───
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentLight,
        surface: surface,
        error: sosRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      fontFamily: 'Inter',
      useMaterial3: true,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),

      // Bottom Nav
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: accent,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Cards
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: glassBorder, width: 0.5),
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        hintStyle: const TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 8,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: glassBorder,
        thickness: 0.5,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── 3D Glassmorphism Decorators ───

  /// Premium glassmorphism with blur and 3D border highlights
  static BoxDecoration glassDecoration({
    double borderRadius = 20,
    Color? color,
    bool elevated = false,
  }) {
    return BoxDecoration(
      color: color ?? (elevated ? surfaceElevated : glassWhite),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: elevated ? glassHighlight : glassBorder,
        width: 0.5,
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.05),
                blurRadius: 40,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );
  }

  /// 3D raised card decoration with depth shadows
  static BoxDecoration card3D({
    double borderRadius = 20,
    Color? color,
    Color? glowColor,
  }) {
    return BoxDecoration(
      color: color ?? surfaceLight,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: glassBorder, width: 0.5),
      boxShadow: [
        // Deep shadow
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        // Mid shadow
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
        // Glow (optional)
        if (glowColor != null)
          BoxShadow(
            color: glowColor.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 2),
          ),
      ],
    );
  }

  /// Gradient decoration for premium buttons and headers
  static BoxDecoration gradientDecoration({
    double borderRadius = 16,
    List<Color>? colors,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        colors: colors ?? [gradientStart, gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: (colors?.first ?? gradientStart).withValues(alpha: 0.4),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Inner glow decoration — simulates light coming from inside
  static BoxDecoration innerGlowDecoration({
    double borderRadius = 20,
    Color glowColor = accent,
  }) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: glowColor.withValues(alpha: 0.2),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: glowColor.withValues(alpha: 0.08),
          blurRadius: 40,
          spreadRadius: -5,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // ─── Text Styles ───
  static const TextStyle heading1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    fontFamily: 'Inter',
    letterSpacing: -0.8,
    height: 1.2,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    fontFamily: 'Inter',
    letterSpacing: -0.3,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    fontFamily: 'Inter',
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    fontFamily: 'Inter',
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    fontFamily: 'Inter',
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMuted,
    fontFamily: 'Inter',
  );

  static const TextStyle mono = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    fontFamily: 'JetBrains Mono',
    letterSpacing: 0.5,
  );

  // ─── Channel Badge ───
  static Widget channelBadge(String channel) {
    Color color;
    IconData icon;
    switch (channel.toLowerCase()) {
      case 'ble':
        color = bleColor;
        icon = Icons.bluetooth;
        break;
      case 'wifi':
        color = wifiColor;
        icon = Icons.wifi;
        break;
      case 'morse':
        color = morseColor;
        icon = Icons.flashlight_on;
        break;
      default:
        color = textMuted;
        icon = Icons.signal_cellular_alt;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            channel.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  // ─── Status Dot ───
  static Widget statusDot(String status) {
    Color color;
    switch (status) {
      case 'nearby':
        color = nearbyGreen;
        break;
      case 'relay':
        color = relayYellow;
        break;
      default:
        color = unreachableGray;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );
  }
}

// ─── Premium 3D Widgets ───

/// Frosted glass container with real blur
class FrostedGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  const FrostedGlass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blur = 20,
    this.tint,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 3D raised button with gradient and glow
class Premium3DButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final List<Color>? colors;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const Premium3DButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.colors,
    this.borderRadius = 14,
    this.padding,
  });

  @override
  State<Premium3DButton> createState() => _Premium3DButtonState();
}

class _Premium3DButtonState extends State<Premium3DButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors ?? [ChaayaTheme.gradientStart, ChaayaTheme.gradientEnd];
    return GestureDetector(
      onTapDown: (_) {
        _controller.forward();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        _controller.reverse();
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        _controller.reverse();
        setState(() => _isPressed = false);
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.first.withValues(alpha: _isPressed ? 0.2 : 0.4),
                    blurRadius: _isPressed ? 10 : 20,
                    offset: Offset(0, _isPressed ? 4 : 8),
                  ),
                ],
              ),
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// Animated glow ring — used for SOS, active status etc.
class GlowRing extends StatefulWidget {
  final double size;
  final Color color;
  final Widget? child;

  const GlowRing({
    super.key,
    this.size = 60,
    this.color = ChaayaTheme.accent,
    this.child,
  });

  @override
  State<GlowRing> createState() => _GlowRingState();
}

class _GlowRingState extends State<GlowRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.2 + _controller.value * 0.3),
                blurRadius: 20 + _controller.value * 20,
                spreadRadius: _controller.value * 4,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}
