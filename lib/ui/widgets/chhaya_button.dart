import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/pressable.dart';

/// ChhayaPrimaryButton — Main CTA button
/// Gradient accent, pill radius, glow shadow, haptic feedback
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
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: ChhayaColors.onAccent,
              valueColor: disableAnimations
                  ? const AlwaysStoppedAnimation<Color>(ChhayaColors.onAccent)
                  : null,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: ChhayaColors.onAccent),
                const SizedBox(width: ChhayaSpacing.space1),
              ],
              Text(
                label,
                style: ChhayaTypography.headlineMedium.copyWith(
                  color: ChhayaColors.onAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );

    return PressableScale(
      haptic: false, // inner button already haptics on commit
      child: SizedBox(
        height: height,
        width: expanded ? double.infinity : width,
        child: DecoratedBox(
          decoration: ChhayaDecorations.primaryButton(
            borderRadius: ChhayaRadius.pill,
            withShadow: !disableAnimations,
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ChhayaRadius.pill),
              ),
              padding: EdgeInsets.zero,
            ),
            onPressed: isLoading ? null : () {
              if (!disableAnimations) ChhayaHaptics.medium();
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
/// Surface bg, divider border, pill radius
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
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      height: height,
      width: expanded ? double.infinity : width,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: ChhayaColors.secondaryBackground,
          side: BorderSide(
            color: ChhayaColors.opaqueSeparator.withValues(alpha: 0.6),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: isLoading ? null : () {
          if (!disableAnimations) ChhayaHaptics.light();
          onPressed();
        },
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ChhayaColors.accent,
                  valueColor: disableAnimations
                      ? const AlwaysStoppedAnimation<Color>(ChhayaColors.accent)
                      : null,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: ChhayaColors.labelPrimary),
                    const SizedBox(width: ChhayaSpacing.space1),
                  ],
                  Text(
                    label,
                    style: ChhayaTypography.headlineMedium.copyWith(
                      color: ChhayaColors.labelPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
        minimumSize: const Size(0, 36),
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
    this.size = 42,
    this.tooltip,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final child = isLoading
        ? SizedBox(
            width: size * 0.4,
            height: size * 0.4,
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
            size: size * 0.48,
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
        width: size,
        height: size,
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
        onPressed: isLoading ? null : () {
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
      onPressed: isLoading ? null : () {
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
            Icon(icon, size: 14, color: selected ? ChhayaColors.onAccent : ChhayaColors.labelSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: ChhayaTypography.caption1.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? ChhayaColors.onAccent : ChhayaColors.labelSecondary,
            ),
          ),
        ],
      ),
      selected: selected,
      selectedColor: selectedColor ?? ChhayaColors.accent,
      backgroundColor: backgroundColor ?? ChhayaColors.cardSurface,
      side: BorderSide(
        color: selected ? Colors.transparent : ChhayaColors.glassBorder.withValues(alpha: 0.14),
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