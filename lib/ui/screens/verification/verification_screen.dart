import 'package:flutter/material.dart';
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
    final myKey = user?.chhayaId.publicKey ?? 'unknown';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        elevation: 0,
        title: Text('Verify Contact', style: ChhayaTypography.headline),
      ),
      body: SafeArea(
        child: _verified
            ? _buildSuccess()
            : DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: TabBar(
                        tabs: const [
                          Tab(text: 'My Code'),
                          Tab(text: 'Scan'),
                        ],
                        labelColor: scheme.onPrimary,
                        unselectedLabelColor: scheme.onSurfaceVariant,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildMyCode(myKey),
                          _buildScan(),
                        ],
                      ),
                    ),
                  ],
                ),
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
          Card(
            color: ChhayaColors.labelPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: QrImageView(
                data: key,
                version: QrVersions.auto,
                size: 200,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: ChhayaColors.primaryBackground),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: ChhayaColors.primaryBackground),
              ),
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
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner, size: 64, color: ChhayaColors.accentBlue.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('Point camera at QR code', style: ChhayaTypography.footnote.copyWith(color: ChhayaColors.labelTertiary)),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 32),


        FilledButton(
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
            child: const Icon(Icons.verified, size: 72, color: ChhayaColors.accentGreen),
          ),
          const SizedBox(height: 24),
          Text('Contact Verified!', style: ChhayaTypography.title1.copyWith(color: ChhayaColors.accentGreen)),
          const SizedBox(height: 8),
          Text('Verification level elevated to Level 3', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary)),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
