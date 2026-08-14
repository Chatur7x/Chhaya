import 'package:flutter/cupertino.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

class ChhayaPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  const ChhayaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<ChhayaPrimaryButton> createState() => _ChhayaPrimaryButtonState();
}

class _ChhayaPrimaryButtonState extends State<ChhayaPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        ChhayaHaptics.medium();
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: ChhayaAnimation.fast,
        curve: ChhayaAnimation.springCurve,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            gradient: ChhayaColors.accentGradient,
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
            boxShadow: [
              BoxShadow(
                color: ChhayaColors.accentBlue.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const CupertinoActivityIndicator(color: ChhayaColors.labelPrimary)
                : Text(
                    widget.label,
                    style: ChhayaTypography.headline.copyWith(
                      color: ChhayaColors.labelPrimary,
                      fontSize: 17,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class ChhayaSecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  const ChhayaSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<ChhayaSecondaryButton> createState() => _ChhayaSecondaryButtonState();
}

class _ChhayaSecondaryButtonState extends State<ChhayaSecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        ChhayaHaptics.light();
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: ChhayaAnimation.fast,
        curve: ChhayaAnimation.springCurve,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: ChhayaColors.fillTertiary,
            borderRadius: BorderRadius.circular(ChhayaRadius.pill),
            border: Border.all(color: ChhayaColors.accentBlue.withValues(alpha: 0.3), width: 1),
          ),
          child: Center(
            child: widget.isLoading
                ? const CupertinoActivityIndicator(color: ChhayaColors.accentBlue)
                : Text(
                    widget.label,
                    style: ChhayaTypography.headline.copyWith(
                      color: ChhayaColors.accentBlue,
                      fontSize: 17,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
