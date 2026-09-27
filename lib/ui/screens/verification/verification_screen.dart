import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/ui/widgets/glass_container.dart';
import 'package:chaaya/core/providers/app_providers.dart';

class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> with TickerProviderStateMixin {
  late AnimationController _scanAnimCtrl;
  late AnimationController _successAnimCtrl;
  bool _scanning = false;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _scanAnimCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _successAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _scanAnimCtrl.dispose();
    _successAnimCtrl.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _scanning = true);
    ChhayaHaptics.light();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _scanning = false;
          _verified = true;
        });
        _successAnimCtrl.forward();
        ChhayaHaptics.success();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final chhayaIdText = user?.chhayaId.publicKey ?? '—';
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground,
        title: Text('Verify Contact', style: ChhayaTypography.displayMedium.copyWith(fontSize: 24)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(ChhayaSpacing.space4),
          child: Column(
            children: [
              // Your QR Code
              GlassContainer(
                padding: const EdgeInsets.all(ChhayaSpacing.space5),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(width: 32, height: 32, decoration: BoxDecoration(color: ChhayaColors.accentDim, borderRadius: BorderRadius.circular(ChhayaRadius.xl)), child: const Icon(Icons.qr_code_rounded, size: 18, color: ChhayaColors.accent)),
                        const SizedBox(width: ChhayaSpacing.space3),
                        Text('Your Chhaya ID', style: ChhayaTypography.headlineMedium),
                      ],
                    ),
                    const SizedBox(height: ChhayaSpacing.space4),
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: ChhayaColors.primaryBackground,
                        borderRadius: BorderRadius.circular(ChhayaRadius.xl),
                        border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.12)),
                      ),
                      child: Center(
                        child: Text(chhayaIdText, style: ChhayaTypography.code.copyWith(fontSize: 10, color: ChhayaColors.labelSecondary)),
                      ),
                    ),
                    const SizedBox(height: ChhayaSpacing.space3),
                    Text('Scan this to verify me', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelTertiary)),
                    const SizedBox(height: ChhayaSpacing.space2),
                    ChhayaGhostButton(
                      label: 'Share QR Code',
                      icon: Icons.share_rounded,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ChhayaSpacing.space5),

              // Scan their QR
              GlassContainer(
                padding: const EdgeInsets.all(ChhayaSpacing.space5),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(width: 32, height: 32, decoration: BoxDecoration(color: ChhayaColors.info.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(ChhayaRadius.xl)), child: const Icon(Icons.qr_code_scanner_rounded, size: 18, color: ChhayaColors.info)),
                        const SizedBox(width: ChhayaSpacing.space3),
                        Text('Verify Contact', style: ChhayaTypography.headlineMedium),
                      ],
                    ),
                    const SizedBox(height: ChhayaSpacing.space4),
                    AnimatedBuilder(
                      animation: _scanAnimCtrl,
                      builder: (context, child) {
                        return Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _scanning
                                  ? ChhayaColors.accent.withValues(alpha: 0.30 + _scanAnimCtrl.value * 0.5)
                                  : ChhayaColors.accent.withValues(alpha: 0.20),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(ChhayaRadius.xl),
                            color: ChhayaColors.cardSurface,
                          ),
                          child: _verified
                              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 64, height: 64, decoration: BoxDecoration(color: ChhayaColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(ChhayaRadius.xl)), child: Icon(Icons.verified_rounded, size: 36, color: ChhayaColors.success)), const SizedBox(height: ChhayaSpacing.space3), Text('Verified!', style: ChhayaTypography.headlineMedium.copyWith(color: ChhayaColors.success))]))
                              : _scanning
                                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)), const SizedBox(height: ChhayaSpacing.space3), Text('Verifying…', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w700))]))
                                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 64, height: 64, decoration: BoxDecoration(color: ChhayaColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.qr_code_scanner_rounded, size: 36, color: ChhayaColors.accent.withValues(alpha: 0.8))), const SizedBox(height: ChhayaSpacing.space3), Text('Point camera at QR', style: ChhayaTypography.headlineMedium.copyWith(fontSize: 13)), const SizedBox(height: 2), Text('End-to-end verification', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary))]),
                        );
                      },
                    ),
                    const SizedBox(height: ChhayaSpacing.space4),
                    if (!_verified) ...[
                      ChhayaPrimaryButton(label: 'Start Scanning', icon: Icons.qr_code_scanner_rounded, onPressed: _startScan),
                      const SizedBox(height: ChhayaSpacing.space2),
                      ChhayaGhostButton(label: 'Enter ID Manually', icon: Icons.keyboard_rounded, onPressed: () {}),
                    ] else ...[
                      AnimatedBuilder(
                        animation: _successAnimCtrl,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: disableAnimations ? 1.0 : (0.8 + _successAnimCtrl.value * 0.2),
                            child: Opacity(
                              opacity: _successAnimCtrl.value,
                              child: child!,
                            ),
                          );
                        },
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ChhayaColors.success,
                            border: Border.all(color: ChhayaColors.success, width: 2),
                          ),
                          child: const Icon(Icons.verified_rounded, size: 64, color: ChhayaColors.onAccent),
                        ),
                      ),
                      const SizedBox(height: ChhayaSpacing.space4),
                      Text('Contact Verified!', style: ChhayaTypography.displaySmall.copyWith(fontSize: 22, color: ChhayaColors.success)),
                      const SizedBox(height: ChhayaSpacing.space2),
                      GlassContainer(
                        child: Column(children: [
                          Text('Level 3 • Fully Verified', style: ChhayaTypography.headlineMedium.copyWith(color: ChhayaColors.success, fontSize: 13)),
                          const SizedBox(height: ChhayaSpacing.space1),
                          Text('Man-in-the-middle protection active.\nYour double-ratchet is now trusted.', textAlign: TextAlign.center, style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelSecondary)),
                        ]),
                      ),
                      const SizedBox(height: ChhayaSpacing.space4),
                      ChhayaPrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
                    ],
                    const SizedBox(height: ChhayaSpacing.space3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
                      decoration: BoxDecoration(color: ChhayaColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(ChhayaRadius.pill), border: Border.all(color: ChhayaColors.success.withValues(alpha: 0.2))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.visibility_off_rounded, size: 14, color: ChhayaColors.success),
                        const SizedBox(width: ChhayaSpacing.space1),
                        Text('Share in person for max trust', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.success, fontWeight: FontWeight.w700, fontSize: 11)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}