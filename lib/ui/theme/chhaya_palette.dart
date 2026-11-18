import 'package:flutter/material.dart';
import 'chhaya_colors.dart';
import 'chhaya_typography.dart';

/// Semantic colors follow the interpolated Material scheme during appearance changes.
class ChhayaPalette {
  const ChhayaPalette(this.scheme);
  final ColorScheme scheme;
  static ChhayaPalette of(BuildContext context) => ChhayaPalette(Theme.of(context).colorScheme);
  double get _dark => ((245 - scheme.surface.r * 255) / 221).clamp(0.0, 1.0).toDouble();
  Color _mix(Color light, Color dark) => Color.lerp(light, dark, _dark)!;
  Color get accent => scheme.primary;
  Color get coralAction => scheme.primary;
  Color get coralDeep => scheme.primary;
  Color get coral => _mix(ChhayaColors.coral, const Color(0xFFF0A38B));
  Color get coralTint => scheme.primaryContainer;
  Color get cream => scheme.surface;
  Color get primaryBackground => scheme.surface;
  Color get surface => scheme.surfaceContainerLow;
  Color get secondaryBackground => scheme.surfaceContainerLow;
  Color get sheetBackground => scheme.surfaceContainerHigh;
  Color get cardSurface => scheme.surfaceContainerHigh;
  Color get cardSurfaceElevated => scheme.surfaceContainerHighest;
  Color get inputSurface => scheme.surfaceContainerHighest;
  Color get ink => scheme.onSurface;
  Color get inkSoft => scheme.onSurfaceVariant;
  Color get inkMuted => _mix(ChhayaColors.inkMuted, const Color(0xFFC2BDB2));
  Color get inkFaint => _mix(ChhayaColors.inkFaint, const Color(0xFF9F9B92));
  Color get labelPrimary => ink;
  Color get labelSecondary => inkSoft;
  Color get labelTertiary => inkMuted;
  Color get labelQuaternary => inkMuted;
  Color get borderSoft => scheme.outlineVariant;
  Color get borderMed => scheme.outline;
  Color get separator => scheme.outlineVariant;
  Color get opaqueSeparator => scheme.outline;
  Color get glassBorder => scheme.outlineVariant;
  Color get warmGray => scheme.surfaceContainer;
  Color get fillPrimary => scheme.surfaceContainer;
  Color get fillTertiary => scheme.primaryContainer;
  Color get hoverCream => scheme.surfaceContainer;
  Color get onAccent => scheme.onPrimary;
  Color get white => scheme.onPrimary;
  Color get bubbleSent => scheme.primary;
  Color get bubbleSentText => scheme.onPrimary;
  Color get bubbleReceived => scheme.surfaceContainerHigh;
  Color get bubbleReceivedText => scheme.onSurface;
  Color get transparent => ChhayaColors.transparent;
  Color get success => _mix(ChhayaColors.success, const Color(0xFFA4CEA2));
  Color get warning => _mix(ChhayaColors.warning, const Color(0xFFE8C37E));
  Color get error => scheme.error;
  Color get info => _mix(ChhayaColors.info, const Color(0xFFA9CADD));
  Color get verifiedLevel1 => error;
  Color get verifiedLevel2 => warning;
  Color get verifiedLevel3 => success;
  LinearGradient get accentGradient => LinearGradient(colors: [accent, accent]);
  RadialGradient get glowGradient => const RadialGradient(colors: [ChhayaColors.transparent, ChhayaColors.transparent]);
}

class ChhayaType {
  ChhayaType(this.palette, {this.platform = TargetPlatform.android});
  final TargetPlatform platform;
  final ChhayaPalette palette;
  static ChhayaType of(BuildContext context) => ChhayaType(ChhayaPalette.of(context), platform: Theme.of(context).platform);
  TextStyle _adapt(TextStyle style) => ChhayaTypography.forPlatform(style, platform).copyWith(
    color:
    style.color == ChhayaColors.ink ? palette.ink :
    style.color == ChhayaColors.inkMuted ? palette.inkMuted :
    style.color == ChhayaColors.accent || style.color == ChhayaColors.coralDeep ? palette.accent : style.color);
  TextStyle get displayXl => _adapt(ChhayaTypography.displayXl);
  TextStyle get displayL => _adapt(ChhayaTypography.displayL);
  TextStyle get headline => _adapt(ChhayaTypography.headline);
  TextStyle get title => _adapt(ChhayaTypography.title);
  TextStyle get bodyLarge => _adapt(ChhayaTypography.bodyLarge);
  TextStyle get body => _adapt(ChhayaTypography.body);
  TextStyle get caption => _adapt(ChhayaTypography.caption);
  TextStyle get label => _adapt(ChhayaTypography.label);
  TextStyle get monoHash => _adapt(ChhayaTypography.monoHash);
  TextStyle get monoCode => _adapt(ChhayaTypography.monoCode);
  TextStyle get displayHero => _adapt(ChhayaTypography.displayHero);
  TextStyle get displayLarge => _adapt(ChhayaTypography.displayLarge);
  TextStyle get displayMedium => _adapt(ChhayaTypography.displayMedium);
  TextStyle get displaySmall => _adapt(ChhayaTypography.displaySmall);
  TextStyle get headlineLarge => _adapt(ChhayaTypography.headlineLarge);
  TextStyle get headlineMedium => _adapt(ChhayaTypography.headlineMedium);
  TextStyle get headlineSmall => _adapt(ChhayaTypography.headlineSmall);
  TextStyle get bodyMedium => _adapt(ChhayaTypography.bodyMedium);
  TextStyle get bodySmall => _adapt(ChhayaTypography.bodySmall);
  TextStyle get labelLarge => _adapt(ChhayaTypography.labelLarge);
  TextStyle get labelMedium => _adapt(ChhayaTypography.labelMedium);
  TextStyle get labelSmall => _adapt(ChhayaTypography.labelSmall);
  TextStyle get code => _adapt(ChhayaTypography.code);
  TextStyle get largeTitle => _adapt(ChhayaTypography.largeTitle);
  TextStyle get title1 => _adapt(ChhayaTypography.title1);
  TextStyle get title2 => _adapt(ChhayaTypography.title2);
  TextStyle get title3 => _adapt(ChhayaTypography.title3);
  TextStyle get headline1 => _adapt(ChhayaTypography.headline1);
  TextStyle get callout => _adapt(ChhayaTypography.callout);
  TextStyle get subheadline => _adapt(ChhayaTypography.subheadline);
  TextStyle get footnote => _adapt(ChhayaTypography.footnote);
  TextStyle get caption1 => _adapt(ChhayaTypography.caption1);
  TextStyle get caption2 => _adapt(ChhayaTypography.caption2);
  TextStyle get monoCodeAlias => _adapt(ChhayaTypography.monoCodeAlias);
}
