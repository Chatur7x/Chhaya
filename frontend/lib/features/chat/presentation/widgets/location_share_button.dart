import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/chaaya_theme.dart';

class LocationShareButton extends ConsumerStatefulWidget {
  final String userId;
  final String userName;

  const LocationShareButton({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  ConsumerState<LocationShareButton> createState() =>
      _LocationShareButtonState();
}

class _LocationShareButtonState extends ConsumerState<LocationShareButton> {
  bool _isSharing = false;

  void _toggleSharing() async {
    final service = ref.read(locationShareServiceProvider);

    if (_isSharing) {
      service.stopSharing();
      setState(() => _isSharing = false);
    } else {
      final hasPermission = await service.checkPermissions();
      if (hasPermission) {
        service.startSharing(widget.userId, widget.userName);
        setState(() => _isSharing = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission required'),
              backgroundColor: ChaayaTheme.sosRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isSharing ? Icons.location_on : Icons.location_on_outlined,
        color: _isSharing ? ChaayaTheme.safeGreen : ChaayaTheme.textMuted,
      ),
      onPressed: _toggleSharing,
      tooltip: _isSharing ? 'Stop sharing location' : 'Share location',
    );
  }
}
