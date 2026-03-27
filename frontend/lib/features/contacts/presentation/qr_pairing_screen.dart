import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/chaaya_theme.dart';

class QrPairingScreen extends ConsumerStatefulWidget {
  const QrPairingScreen({super.key});

  @override
  ConsumerState<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends ConsumerState<QrPairingScreen> {
  bool _isScanning = false;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final uri = barcode.rawValue!;
        if (uri.startsWith('chaaya://pair')) {
          _scannerController.stop();
          try {
            final contactSvc = ref.read(contactServiceProvider);
            final newContact = await contactSvc.processScannerUri(uri);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Successfully paired with ${newContact.name}!'),
                  backgroundColor: ChaayaTheme.safeGreen,
                ),
              );
              Navigator.pop(context);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to pair: $e'), backgroundColor: Colors.red),
              );
              _scannerController.start();
            }
          }
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactSvc = ref.read(contactServiceProvider);
    final myUri = contactSvc.getMyPairingUri();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
        actions: [
          TextButton.icon(
            icon: Icon(
              _isScanning ? Icons.qr_code : Icons.camera_alt,
              color: ChaayaTheme.safeGreen,
            ),
            label: Text(
              _isScanning ? 'Show My QR' : 'Scan Code',
              style: const TextStyle(color: ChaayaTheme.safeGreen),
            ),
            onPressed: () {
              setState(() {
                _isScanning = !_isScanning;
                if (_isScanning) {
                  _scannerController.start();
                } else {
                  _scannerController.stop();
                }
              });
            },
          ),
        ],
      ),
      body: Center(
        child: _isScanning
            ? MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('My Pairing Code', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('Others can scan this to pair securely over the mesh.', textAlign: TextAlign.center),
                  const SizedBox(height: 40),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: ChaayaTheme.safeGreen.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: QrImageView(
                      data: myUri,
                      version: QrVersions.auto,
                      size: 250.0,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text('No internet needed. Keys are exchanged locally.', style: TextStyle(color: Colors.grey)),
                ],
              ),
      ),
    );
  }
}
