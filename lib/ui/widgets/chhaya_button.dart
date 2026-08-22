import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

class ChhayaPrimaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: isLoading ? null : () {
          ChhayaHaptics.medium();
          onPressed();
        },
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ChhayaColors.labelPrimary,
                ),
              )
            : Text(
                label,
                style: ChhayaTypography.headline.copyWith(
                  color: ChhayaColors.labelPrimary,
                  fontSize: 17,
                ),
              ),
      ),
    );
  }
}

class ChhayaSecondaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: isLoading ? null : () {
          ChhayaHaptics.light();
          onPressed();
        },
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ChhayaColors.accentBlue,
                ),
              )
            : Text(
                label,
                style: ChhayaTypography.headline.copyWith(
                  color: ChhayaColors.accentBlue,
                  fontSize: 17,
                ),
              ),
      ),
    );
  }
}
