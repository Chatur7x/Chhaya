import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/pressable.dart';

/// ChhayaPrimaryButton — Main CTA button
/// Coral fill, white text, pill radius, haptic feedback.
class ChhayaPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final bool expanded;
  final double? width;

  const ChhayaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 54,
    this.expanded = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final double buttonHeight = height < 44.0 ? 44.0 : height;

    final Widget child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: ChhayaColors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: ChhayaColors.white),
                const SizedBox(width: ChhayaSpacing.space1),
              ],
              Flexible(
                child: Text(
                  label,
                  style: ChhayaTypography.headlineMedium.copyWith(
                    color: ChhayaColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return PressableScale(
      haptic: false, // inner button already haptics on commit
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: SizedBox(
          height: buttonHeight,
          width: expanded ? double.infinity : width,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ChhayaColors.coral,
              foregroundColor: ChhayaColors.white,
              disabledBackgroundColor: ChhayaColors.warmGray,
              disabledForegroundColor: ChhayaColors.inkFaint,
              elevation: 0,
              shadowColor: ChhayaColors.coral.withValues(alpha: 0),
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(
                horizontal: ChhayaSpacing.space6,
                vertical: ChhayaSpacing.space3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ChhayaRadius.pill),
              ),
            ),
            onPressed: isLoading
                ? null
                : () {
                    ChhayaHaptics.light();
                    onPressed();
                  },
            child: child,
          ),
        ),
      ),
    );
  }
}

/// ChhayaSecondaryButton — Secondary action button
/// White fill, coralDeep text, borderMed border, pill radius, haptic.
class ChhayaSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final bool expanded;
  final double? width;

  const ChhayaSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 54,
    this.expanded = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final double buttonHeight = height < 44.0 ? 44.0 : height;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: SizedBox(
        height: buttonHeight,
        width: expanded ? double.infinity : width,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: ChhayaColors.white,
            foregroundColor: ChhayaColors.coralDeep,
            disabledBackgroundColor: ChhayaColors.warmGray,
            side: const BorderSide(
              color: ChhayaColors.borderMed,
              width: 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ChhayaRadius.pill),
            ),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(
              horizontal: ChhayaSpacing.space6,
              vertical: ChhayaSpacing.space3,
            ),
          ),
          onPressed: isLoading
              ? null
              : () {
                  ChhayaHaptics.light();
                  onPressed();
                },
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: ChhayaColors.coralDeep,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: ChhayaColors.coralDeep),
                      const SizedBox(width: ChhayaSpacing.space1),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: ChhayaTypography.headlineMedium.copyWith(
                          color: ChhayaColors.coralDeep,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// ChhayaPillButton — Compact icon + label pill
/// Coral fill by default, white text, pill radius, haptic on press.
class ChhayaPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final Color background;
  final Color foreground;

  const ChhayaPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.height = 44,
    this.background = ChhayaColors.coral,
    this.foreground = ChhayaColors.white,
  });

  @override
  Widget build(BuildContext context) {
    final double buttonHeight = height < 44.0 ? 44.0 : height;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: SizedBox(
        height: buttonHeight,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: ChhayaColors.warmGray,
            disabledForegroundColor: ChhayaColors.inkFaint,
            elevation: 0,
            shadowColor: ChhayaColors.coral.withValues(alpha: 0),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(
              horizontal: ChhayaSpacing.space4,
              vertical: ChhayaSpacing.space2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ChhayaRadius.pill),
            ),
          ),
          onPressed: isLoading
              ? null
              : () {
                  ChhayaHaptics.light();
                  onPressed();
                },
          child: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foreground,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: foreground),
                      const SizedBox(width: ChhayaSpacing.space1),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: ChhayaTypography.headlineSmall.copyWith(
                          color: foreground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// ChhayaGhostButton — Tertiary/inline button
/// Transparent, accent text, pill radius
class ChhayaGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const ChhayaGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return TextButton(
      onPressed: () {
        if (!disableAnimations) ChhayaHaptics.selection();
        onPressed();
      },
      style: TextButton.styleFrom(
        foregroundColor: ChhayaColors.accent,
        padding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space2,
          vertical: ChhayaSpacing.space1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.pill),
        ),
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: ChhayaColors.accent),
            const SizedBox(width: ChhayaSpacing.space1),
          ],
          Text(
            label,
            style: ChhayaTypography.footnote.copyWith(
              color: ChhayaColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ChhayaIconButton — Icon-only button
/// Circle, fill tertiary, glass border, haptic
class ChhayaIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final Color? background;
  final double size;
  final String? tooltip;
  final bool isLoading;

  const ChhayaIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.background,
    this.size = 44,
    this.tooltip,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final double buttonSize = size < 44.0 ? 44.0 : size;

    final child = isLoading
        ? SizedBox(
            width: buttonSize * 0.4,
            height: buttonSize * 0.4,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color ?? ChhayaColors.accent,
              valueColor: disableAnimations
                  ? AlwaysStoppedAnimation<Color>(color ?? ChhayaColors.accent)
                  : null,
            ),
          )
        : Icon(
            icon,
            size: buttonSize * 0.48,
            color: color ?? ChhayaColors.labelPrimary,
          );

    final button = InkWell(
      onTap: isLoading
          ? null
          : () {
              if (!disableAnimations) ChhayaHaptics.light();
              onPressed();
            },
      customBorder: const CircleBorder(),
      child: Container(
        width: buttonSize,
        height: buttonSize,
        decoration: BoxDecoration(
          color: background ?? ChhayaColors.fillTertiary,
          shape: BoxShape.circle,
          border: Border.all(
            color: ChhayaColors.glassBorder.withValues(alpha: 0.12),
          ),
        ),
        child: Center(child: child),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// ChhayaFAB — Floating Action Button (extended)
class ChhayaFAB extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool extended;
  final bool isLoading;

  const ChhayaFAB({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.extended = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final scheme = Theme.of(context).colorScheme;

    if (extended) {
      return FloatingActionButton.extended(
        onPressed: isLoading
            ? null
            : () {
                if (!disableAnimations) ChhayaHaptics.medium();
                onPressed();
              },
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.xl),
        ),
        extendedPadding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space6,
          vertical: ChhayaSpacing.space3,
        ),
        label: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.onPrimary,
                  valueColor: disableAnimations
                      ? AlwaysStoppedAnimation<Color>(scheme.onPrimary)
                      : null,
                ),
              )
            : Text(
                label,
                style: ChhayaTypography.headlineMedium.copyWith(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
        icon: icon != null && !isLoading
            ? Icon(icon, size: 18, color: scheme.onPrimary)
            : null,
      );
    }

    return FloatingActionButton(
      onPressed: isLoading
          ? null
          : () {
              if (!disableAnimations) ChhayaHaptics.medium();
              onPressed();
            },
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ChhayaRadius.xl),
      ),
      child: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: scheme.onPrimary,
                valueColor: disableAnimations
                    ? AlwaysStoppedAnimation<Color>(scheme.onPrimary)
                    : null,
              ),
            )
          : Icon(icon ?? Icons.add_rounded, size: 24, color: scheme.onPrimary),
    );
  }
}

/// ChhayaChip — Choice/Filter chip with consistent styling
class ChhayaChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onSelected;
  final IconData? icon;
  final Color? selectedColor;
  final Color? backgroundColor;

  const ChhayaChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.icon,
    this.selectedColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 14,
                color: selected
                    ? ChhayaColors.onAccent
                    : ChhayaColors.labelSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: ChhayaTypography.caption1.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? ChhayaColors.onAccent
                  : ChhayaColors.labelSecondary,
            ),
          ),
        ],
      ),
      selected: selected,
      selectedColor: selectedColor ?? ChhayaColors.accent,
      backgroundColor: backgroundColor ?? ChhayaColors.cardSurface,
      side: BorderSide(
        color: selected
            ? ChhayaColors.transparent
            : ChhayaColors.glassBorder.withValues(alpha: 0.14),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ChhayaRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ChhayaSpacing.space3,
        vertical: ChhayaSpacing.space1,
      ),
      onSelected: onSelected != null
          ? (_) {
              if (!disableAnimations) ChhayaHaptics.selection();
              onSelected!();
            }
          : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
