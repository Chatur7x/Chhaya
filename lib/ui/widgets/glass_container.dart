import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/pressable.dart';

export 'chhaya_input.dart';

/// GlassContainer — Frosted glass card with backdrop blur
/// Primary card style for the app. Uses 24px blur, 78% card surface, subtle border.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final bool withShadow;
  final bool withBorder;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = ChhayaRadius.lg,
    this.blurSigma = 24.0,
    this.color,
    this.padding = const EdgeInsets.all(ChhayaSpacing.space4),
    this.withShadow = true,
    this.withBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? ChhayaPalette.of(context).cardSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: withBorder ? Border.all(color: ChhayaPalette.of(context).borderSoft) : null,
      ),
      child: child,
    );
  }
}

/// ChhayaCard — Solid elevated card (no blur)
/// Used for settings tiles, list items, simple containers.
class ChhayaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final Border? border;

  const ChhayaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ChhayaSpacing.space4),
    this.radius = ChhayaRadius.lg,
    this.onTap,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: ChhayaDecorations.elevatedCard(borderRadius: radius).copyWith(
        color: color ?? ChhayaPalette.of(context).cardSurface,
        border: border ?? Border.all(
          color: ChhayaPalette.of(context).opaqueSeparator.withValues(alpha: 0.45),
          width: 0.7,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return PressableScale(
        onTap: () {
          ChhayaHaptics.selection();
          onTap!();
        },
        child: card,
      );
    }
    return card;
  }
}

/// SettingsSwitch — Standardized settings switch tile
class SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      secondary: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(ChhayaRadius.xs),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: ChhayaType.of(context).bodyMedium),
      value: value,
      onChanged: (v) {
        ChhayaHaptics.selection();
        onChanged(v);
      },
      activeTrackColor: iconColor.withValues(alpha: 0.3),
      activeThumbColor: iconColor,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      inactiveThumbColor: scheme.outline,
      contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: 2),
    );
  }
}
