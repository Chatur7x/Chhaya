import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/identity/identity_service.dart';
import '../../../core/providers/app_providers.dart';

/// QR Pairing Screen — scan or show QR to pair contacts.
/// Step 1: Show your QR code (username + publicKey + deviceId)
/// Step 2: Scan the other person's QR code
/// Step 3: Cryptographic handshake → contact saved locally
class QRPairingScreen extends ConsumerStatefulWidget {
  const QRPairingScreen({super.key});

  @override
  ConsumerState<QRPairingScreen> createState() => _QRPairingScreenState();
}

class _QRPairingScreenState extends ConsumerState<QRPairingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isPairing = false;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleQRScanned(String data) async {
    if (_isPairing || _paired) return;
    setState(() => _isPairing = true);

    try {
      final peerIdentity = IdentityService.parseQRData(data);
      if (peerIdentity == null) {
        _showError('Invalid QR code — not a Chaaya identity');
        return;
      }

      final contactService = ref.read(contactServiceProvider);

      // Check if already paired
      if (contactService.isContact(peerIdentity.deviceId)) {
        _showError('Already paired with ${peerIdentity.username}');
        return;
      }

      // Add contact
      await contactService.addContact(peerIdentity);

      // Refresh contact list
      ref.read(contactListProvider.notifier).state = contactService.getAll();

      setState(() => _paired = true);

      // Show success
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ChaayaTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: ChaayaTheme.safeGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 32, color: ChaayaTheme.safeGreen),
                ),
                const SizedBox(height: 16),
                Text(
                  'Paired with ${peerIdentity.username}',
                  style: ChaayaTheme.heading3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can now send messages, files,\nand share your location.',
                  textAlign: TextAlign.center,
                  style: ChaayaTheme.bodyMedium,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('Done', style: TextStyle(color: ChaayaTheme.accent)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showError('Pairing error: $e');
    } finally {
      if (mounted) setState(() => _isPairing = false);
    }
  }

  void _showError(String message) {
    setState(() => _isPairing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(currentIdentityProvider);
    final identityService = ref.read(identityServiceProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Pair Contact'),
        backgroundColor: ChaayaTheme.background,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChaayaTheme.accent,
          labelColor: ChaayaTheme.accent,
          unselectedLabelColor: ChaayaTheme.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'My QR Code'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Show my QR code
          _buildMyQRTab(identity, identityService),
          // Tab 2: Scan QR code
          _buildScanTab(),
        ],
      ),
    );
  }

  Widget _buildMyQRTab(MeshIdentity? identity, IdentityService identityService) {
    if (identity == null) {
      return const Center(child: Text('No identity found'));
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Share this QR code with\nthe person you want to pair with',
            textAlign: TextAlign.center,
            style: ChaayaTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: ChaayaTheme.accent.withOpacity(0.2),
                  blurRadius: 30,
                ),
              ],
            ),
            child: QrImageView(
              data: identityService.getQRData(),
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0D0F14),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0D0F14),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            identity.username,
            style: ChaayaTheme.heading2,
          ),
          const SizedBox(height: 4),
          Text(
            'Key: ${identityService.getFingerprint()}',
            style: ChaayaTheme.mono,
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    if (_paired) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ChaayaTheme.safeGreen.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 40, color: ChaayaTheme.safeGreen),
            ),
            const SizedBox(height: 16),
            const Text('Paired successfully!', style: ChaayaTheme.heading3),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                _handleQRScanned(barcode.rawValue!);
                break;
              }
            }
          },
        ),
        // Scan overlay
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: ChaayaTheme.accent, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        // Bottom label
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: ChaayaTheme.surface.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point camera at a Chaaya QR code',
                style: TextStyle(color: ChaayaTheme.textSecondary, fontSize: 14),
              ),
            ),
          ),
        ),
        if (_isPairing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: ChaayaTheme.accent),
            ),
          ),
      ],
    );
  }
}

