import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// ChhayaCard — White surface card with hairline border and warm shadow.
/// Tappable when [onTap] is set: press scale + haptic via GestureDetector.
class ChhayaCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const ChhayaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ChhayaSpacing.space4),
    this.onTap,
  });

  @override
  State<ChhayaCard> createState() => _ChhayaCardState();
}

class _ChhayaCardState extends State<ChhayaCard> {
  bool _pressed = false;

  void _handleTap() {
    ChhayaHaptics.light();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      decoration: BoxDecoration(
        color: ChhayaColors.white,
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        border: Border.all(
          color: ChhayaColors.borderMed,
          width: 0.75,
        ),
        boxShadow: ChhayaElevation.card,
      ),
      padding: widget.padding,
      child: widget.child,
    );

    if (widget.onTap == null) {
      return content;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: GestureDetector(
        onTap: _handleTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: content,
        ),
      ),
    );
  }
}

/// ChhayaSectionCard — Cream section card with a title row.
/// Title text always uses [ChhayaTypography.title].
class ChhayaSectionCard extends StatefulWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Widget? trailing;

  const ChhayaSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(ChhayaSpacing.space4),
    this.onTap,
    this.trailing,
  });

  @override
  State<ChhayaSectionCard> createState() => _ChhayaSectionCardState();
}

class _ChhayaSectionCardState extends State<ChhayaSectionCard> {
  bool _pressed = false;

  void _handleTap() {
    ChhayaHaptics.light();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      decoration: BoxDecoration(
        color: ChhayaColors.cream,
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        border: Border.all(
          color: ChhayaColors.borderMed,
          width: 0.75,
        ),
        boxShadow: ChhayaElevation.card,
      ),
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: ChhayaTypography.title,
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
          const SizedBox(height: ChhayaSpacing.space2),
          widget.child,
        ],
      ),
    );

    if (widget.onTap == null) {
      return content;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: GestureDetector(
        onTap: _handleTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: content,
        ),
      ),
    );
  }
}
