import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/pressable.dart';

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
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: disableAnimations
            ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
            : ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: ChhayaDecorations.glassCard(
            borderRadius: borderRadius,
            color: color,
            withShadow: withShadow,
            withBorder: withBorder,
          ),
          child: child,
        ),
      ),
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
        color: color ?? ChhayaColors.cardSurface,
        border: border ?? Border.all(
          color: ChhayaColors.opaqueSeparator.withValues(alpha: 0.45),
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

/// ChhayaInput — Standardized text input
/// Uses input surface, lg radius, accent focus ring.
class ChhayaInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int? maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool autofocus;
  final String? label;
  final String? helperText;
  final String? errorText;
  final TextCapitalization textCapitalization;
  final TextStyle? style;

  const ChhayaInput({
    super.key,
    required this.controller,
    required this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.label,
    this.helperText,
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      maxLines: maxLines,
      autofocus: autofocus,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      style: style ?? ChhayaTypography.bodyMedium.copyWith(fontSize: 15),
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        counterText: '',
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 20, color: ChhayaColors.labelTertiary)
            : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: ChhayaColors.inputSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space4,
          vertical: ChhayaSpacing.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
            color: hasError
                ? ChhayaColors.error
                : ChhayaColors.glassBorder.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
            color: hasError
                ? ChhayaColors.error
                : ChhayaColors.glassBorder.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
            color: hasError ? ChhayaColors.error : ChhayaColors.accent,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: ChhayaColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(color: ChhayaColors.error, width: 1.5),
        ),
      ),
    );
  }
}

/// SectionHeader — Standardized section header with optional action
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space1, ChhayaSpacing.space6, ChhayaSpacing.space1, ChhayaSpacing.space2),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: ChhayaTypography.labelSmall.copyWith(
              letterSpacing: 1.0,
              color: ChhayaColors.labelTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: ChhayaTypography.labelMedium.copyWith(
                  color: ChhayaColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// SettingsTile — Standardized settings list tile
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(ChhayaRadius.xs),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          title: Text(title, style: ChhayaTypography.bodyMedium),
          subtitle: subtitle != null
              ? Text(subtitle!, style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary))
              : null,
          trailing: trailing ?? (onTap != null
              ? const Icon(Icons.chevron_right_rounded, color: ChhayaColors.labelTertiary, size: 14)
              : null),
          onTap: onTap != null
              ? () {
                  ChhayaHaptics.selection();
                  onTap!();
                }
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: 2),
        ),
        if (showDivider)
          Divider(
            height: 0,
            thickness: 0.5,
            color: ChhayaColors.separator,
            indent: 56,
          ),
      ],
    );
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
      title: Text(title, style: ChhayaTypography.bodyMedium),
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