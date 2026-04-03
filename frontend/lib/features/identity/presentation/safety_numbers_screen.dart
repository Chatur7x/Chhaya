import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../contacts/domain/models/contact.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/key_verification_service.dart';

class SafetyNumbersScreen extends ConsumerStatefulWidget {
  final String myPublicKeyBase64;
  final Contact peerContact;

  const SafetyNumbersScreen({
    super.key,
    required this.myPublicKeyBase64,
    required this.peerContact,
  });

  @override
  ConsumerState<SafetyNumbersScreen> createState() =>
      _SafetyNumbersScreenState();
}

class _SafetyNumbersScreenState extends ConsumerState<SafetyNumbersScreen> {
  bool _isVerified = false;
  bool _isScanning = false;
  String _scannedValue = '';

  String get _safetyNumber {
    final keyService = ref.read(keyVerificationServiceProvider);
    return keyService.generateSafetyNumber(
      widget.myPublicKeyBase64,
      widget.peerContact.publicKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final safetyNumber = _safetyNumber;

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Verify Safety Number'),
        backgroundColor: ChaayaTheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _toggleScanner,
            tooltip: 'Scan safety number QR',
          ),
        ],
      ),
      body: _isScanning ? _buildScanner() : _buildMainContent(safetyNumber),
    );
  }

  Widget _buildMainContent(String safetyNumber) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.verified_user,
              size: 80, color: ChaayaTheme.accentLight),
          const SizedBox(height: 32),
          Text(
            'Verify with ${widget.peerContact.name}',
            style: const TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'To verify that your offline communications are end-to-end encrypted and immune to interception, '
            'compare these numbers with your contact.',
            style: TextStyle(color: ChaayaTheme.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ChaayaTheme.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ChaayaTheme.glassBorder),
            ),
            child: Column(
              children: [
                Text(
                  safetyNumber,
                  style: const TextStyle(
                    color: ChaayaTheme.textPrimary,
                    fontSize: 26,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Safety Number',
                  style: TextStyle(
                    color: ChaayaTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_scannedValue.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildVerificationResult(safetyNumber),
          ],
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: ChaayaTheme.accent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isVerified
                        ? ChaayaTheme.safeGreen
                        : ChaayaTheme.safeGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _markAsVerified(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isVerified ? Icons.check_circle : Icons.verified_user,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isVerified ? 'Verified' : 'Mark Verified',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationResult(String safetyNumber) {
    final keyService = ref.read(keyVerificationServiceProvider);
    final isMatch = keyService.verifySafetyNumber(safetyNumber, _scannedValue);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMatch
            ? ChaayaTheme.safeGreen.withOpacity(0.1)
            : ChaayaTheme.sosRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMatch
              ? ChaayaTheme.safeGreen.withOpacity(0.3)
              : ChaayaTheme.sosRed.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMatch ? Icons.check_circle : Icons.error,
            color: isMatch ? ChaayaTheme.safeGreen : ChaayaTheme.sosRed,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isMatch
                  ? 'Safety number verified successfully!'
                  : 'Safety number mismatch. This may indicate a potential security issue.',
              style: TextStyle(
                color: isMatch ? ChaayaTheme.safeGreen : ChaayaTheme.sosRed,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  setState(() {
                    _scannedValue = barcode.rawValue!;
                    _isScanning = false;
                  });
                  break;
                }
              }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          color: ChaayaTheme.surface,
          child: Column(
            children: [
              const Text(
                'Scan your contact\'s safety number QR code',
                style: TextStyle(color: ChaayaTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _toggleScanner,
                child: const Text('Cancel Scan'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleScanner() {
    setState(() {
      _isScanning = !_isScanning;
      if (!_isScanning) {
        _scannedValue = '';
      }
    });
  }

  void _markAsVerified() {
    setState(() {
      _isVerified = true;
    });

    widget.peerContact.isTrusted = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.peerContact.name} marked as verified'),
        backgroundColor: ChaayaTheme.safeGreen,
      ),
    );

    Navigator.pop(context);
  }
}
