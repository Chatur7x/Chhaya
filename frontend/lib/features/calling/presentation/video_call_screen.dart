import 'package:flutter/material.dart';
import '../../../core/theme/chaaya_theme.dart';

class VideoCallScreen extends StatelessWidget {
  final String peerName;
  final String? peerId;

  const VideoCallScreen({
    super.key,
    required this.peerName,
    this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: ChaayaTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.videocam, color: ChaayaTheme.accent, size: 28),
              SizedBox(width: 12),
              Text('Video Calling',
                  style: TextStyle(color: ChaayaTheme.textPrimary)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction,
                  color: ChaayaTheme.warningYellow, size: 64),
              SizedBox(height: 16),
              Text(
                'Coming Soon',
                style: TextStyle(
                  color: ChaayaTheme.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Video calling will be available in a future update.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ChaayaTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (context.mounted) Navigator.of(context).pop();
              },
              child:
                  const Text('OK', style: TextStyle(color: ChaayaTheme.accent)),
            ),
          ],
        ),
      );
    });

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam, color: ChaayaTheme.accent, size: 64),
            const SizedBox(height: 16),
            Text(
              peerName,
              style: const TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: ChaayaTheme.accent),
          ],
        ),
      ),
    );
  }
}
