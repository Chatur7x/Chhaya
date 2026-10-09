import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// ChhayaInput — Standardized text input.
///
/// White fill, [ChhayaRadius.lg] corners, a 1px [ChhayaColors.borderMed]
/// enabled border, a 1.5px [ChhayaColors.coralDeep] focused border, and
/// [ChhayaColors.error] borders whenever [errorText] is set. Hint text
/// uses the body style in [ChhayaColors.inkMuted], with content padding
/// of [ChhayaSpacing.space4] horizontal / [ChhayaSpacing.space3]
/// vertical.
///
/// The constructor mirrors the `ChhayaInput` in `glass_container.dart`
/// so existing call sites compile unchanged; [obscureText] is an
/// optional alias for [obscure] (when set, it wins).
class ChhayaInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final bool? obscureText;
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
    this.obscureText,
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
      obscureText: obscureText ?? obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      maxLines: maxLines,
      autofocus: autofocus,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      style: style ?? ChhayaTypography.body,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ChhayaTypography.body.copyWith(
          color: ChhayaColors.inkMuted,
        ),
        helperText: helperText,
        errorText: errorText,
        counterText: '',
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 20, color: ChhayaColors.inkMuted)
            : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: ChhayaColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChhayaSpacing.space4,
          vertical: ChhayaSpacing.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
            color: hasError ? ChhayaColors.error : ChhayaColors.borderMed,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
            color: hasError ? ChhayaColors.error : ChhayaColors.borderMed,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: BorderSide(
            color: hasError ? ChhayaColors.error : ChhayaColors.coralDeep,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: const BorderSide(color: ChhayaColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChhayaRadius.lg),
          borderSide: const BorderSide(color: ChhayaColors.error, width: 1.5),
        ),
      ),
    );
  }
}
