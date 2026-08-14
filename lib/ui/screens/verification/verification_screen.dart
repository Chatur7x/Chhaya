import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/glass_container.dart';
import '../../../core/providers/app_providers.dart';

class VerificationScreen extends ConsumerStatefulWidget {
  final String? contactId;
  const VerificationScreen({super.key, this.contactId});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> with SingleTickerProviderStateMixin {
  int _segmentIndex = 0;
  bool _verified = false;
  bool _scanning = false;
  late AnimationController _scanAnimCtrl;

  @override
  void initState() {
    super.initState();
    _scanAnimCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanAnimCtrl.dispose();
    super.dispose();
  }

  void _simulateScan() async {
    setState(() => _scanning = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;


    if (widget.contactId != null) {
      final db = ref.read(localDatabaseProvider);
      final contacts = ref.read(contactsProvider);
      final idx = contacts.indexWhere((c) => c.id == widget.contactId);
      if (idx != -1) {
        final updated = contacts[idx].copyWith(verificationLevel: 3);
        await db.updateContact(updated);
        ref.read(contactsProvider.notifier).updateContact(updated);
      }
    }

    setState(() { _scanning = false; _verified = true; });
    ChhayaHaptics.success();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final myKey = user?.ChhayaId.publicKey ?? 'unknown';

    return CupertinoPageScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        border: null,
        middle: Text('Verify Contact', style: ChhayaTypography.headline),
      ),
      child: SafeArea(
        child: _verified ? _buildSuccess() : Column(
          children: [
            const SizedBox(height: 16),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _segmentIndex,
                children: const {
                  0: Text('My Code'),
                  1: Text('Scan'),
                },
                onValueChanged: (v) => setState(() => _segmentIndex = v ?? 0),
              ),
            ),

            const SizedBox(height: 32),

            Expanded(
              child: _segmentIndex == 0 ? _buildMyCode(myKey) : _buildScan(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyCode(String key) {
    return Center(
      child: GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: ChhayaColors.labelPrimary, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(
              data: key,
              version: QrVersions.auto,
              size: 200,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: ChhayaColors.primaryBackground),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: ChhayaColors.primaryBackground),
            ),
          ),
          const SizedBox(height: 16),
          Text('Your Chhaya QR Code', style: ChhayaTypography.headline),
          const SizedBox(height: 4),
          Text('Share this with your contact', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)),
        ]),
      ),
    );
  }

  Widget _buildScan() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [

        AnimatedBuilder(
          animation: _scanAnimCtrl,
          builder: (_, __) => Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: ChhayaColors.accentBlue.withValues(alpha: 0.3 + _scanAnimCtrl.value * 0.5), width: 2),
              borderRadius: BorderRadius.circular(20),
              color: ChhayaColors.tertiaryBackground,
            ),
            child: _scanning
                ? const Center(child: CupertinoActivityIndicator(radius: 20))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.qrcode_viewfinder, size: 64, color: ChhayaColors.accentBlue.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('Point camera at QR code', style: ChhayaTypography.footnote.copyWith(color: ChhayaColors.labelTertiary)),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 32),


        CupertinoButton(
          color: ChhayaColors.accentBlue,
          borderRadius: BorderRadius.circular(12),
          onPressed: _scanning ? null : _simulateScan,
          child: const Text('Simulate Scan'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ChhayaColors.accentGreen.withValues(alpha: 0.15),
            ),
            child: const Icon(CupertinoIcons.checkmark_circle_fill, size: 72, color: ChhayaColors.accentGreen),
          ),
          const SizedBox(height: 24),
          Text('Contact Verified!', style: ChhayaTypography.title1.copyWith(color: ChhayaColors.accentGreen)),
          const SizedBox(height: 8),
          Text('Verification level elevated to Level 3', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary)),
          const SizedBox(height: 32),
          CupertinoButton(
            color: ChhayaColors.accentBlue,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
