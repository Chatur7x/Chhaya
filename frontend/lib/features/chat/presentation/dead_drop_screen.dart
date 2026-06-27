import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';

/// Dead Drop Screen — GPS-bound encrypted message drops (Req 13)
class DeadDropScreen extends ConsumerStatefulWidget {
  const DeadDropScreen({super.key});

  @override
  ConsumerState<DeadDropScreen> createState() => _DeadDropScreenState();
}

class _DeadDropScreenState extends ConsumerState<DeadDropScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  LatLng? _selectedLocation;
  final List<_DropPin> _drops = [];
  bool _loadingGps = true;

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  Future<void> _initGps() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentPosition = pos;
        _loadingGps = false;
      });
    } catch (e) {
      setState(() => _loadingGps = false);
    }
  }

  Future<void> _createDrop(LatLng location) async {
    final textController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: const Text('Create Dead Drop', style: TextStyle(color: ChaayaTheme.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'This message can only be read within 10m of the dropped location.',
            style: TextStyle(color: ChaayaTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: textController,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: ChaayaTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Secret message...',
              hintStyle: const TextStyle(color: ChaayaTheme.textMuted),
              filled: true,
              fillColor: ChaayaTheme.glass,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Drop'),
          ),
        ],
      ),
    );

    if (confirmed != true || textController.text.trim().isEmpty) return;

    final identity = ref.read(currentIdentityProvider);
    if (identity == null) return;

    final service = ref.read(deadDropServiceProvider);
    await service.createDrop(
      message: textController.text.trim(),
      lat: location.latitude,
      lng: location.longitude,
      senderId: identity.deviceId,
      senderName: identity.username,
    );

    setState(() {
      _drops.add(_DropPin(location: location, isUnlocked: false));
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dead drop created and broadcast to mesh!'),
          backgroundColor: ChaayaTheme.safeGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.surface,
        title: const Text('Dead Drop', style: TextStyle(color: ChaayaTheme.textPrimary, fontWeight: FontWeight.w600)),
        leading: const BackButton(color: ChaayaTheme.accent),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: ChaayaTheme.textMuted),
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: _loadingGps
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: ChaayaTheme.accent),
              SizedBox(height: 16),
              Text('Acquiring GPS...', style: TextStyle(color: ChaayaTheme.textMuted)),
            ]))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition != null
                        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                        : const LatLng(17.385, 78.487),
                    initialZoom: 16,
                    onTap: (_, latLng) => setState(() => _selectedLocation = latLng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    MarkerLayer(markers: [
                      // Current position
                      if (_currentPosition != null)
                        Marker(
                          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          child: const Icon(Icons.my_location, color: ChaayaTheme.bleColor, size: 28),
                        ),
                      // Selected location
                      if (_selectedLocation != null)
                        Marker(
                          point: _selectedLocation!,
                          child: Column(children: [
                            const Icon(Icons.place, color: ChaayaTheme.accent, size: 36),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ChaayaTheme.accent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Drop here', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                          ]),
                        ),
                      // Existing drops
                      for (final drop in _drops)
                        Marker(
                          point: drop.location,
                          child: Icon(
                            drop.isUnlocked ? Icons.lock_open : Icons.lock,
                            color: drop.isUnlocked ? ChaayaTheme.safeGreen : ChaayaTheme.warningYellow,
                            size: 28,
                          ),
                        ),
                    ]),
                  ],
                ),
                // Info card
                if (_currentPosition != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
                      child: Row(children: [
                        const Icon(Icons.gps_fixed, size: 16, color: ChaayaTheme.safeGreen),
                        const SizedBox(width: 8),
                        Text(
                          'GPS accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                          style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 13),
                        ),
                        const Spacer(),
                        const Icon(Icons.tap_and_play, size: 14, color: ChaayaTheme.textMuted),
                        const SizedBox(width: 4),
                        const Text('Tap map to select', style: TextStyle(color: ChaayaTheme.textMuted, fontSize: 12)),
                      ]),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _selectedLocation != null
          ? FloatingActionButton.extended(
              onPressed: () => _createDrop(_selectedLocation!),
              backgroundColor: ChaayaTheme.accent,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Create Drop'),
            )
          : null,
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: ChaayaTheme.surface,
      title: const Text('Dead Drop', style: TextStyle(color: ChaayaTheme.textPrimary)),
      content: const Text(
        'Tap a location on the map to select a drop point.\n\n'
        'Your encrypted message is broadcast to the mesh.\n\n'
        'Only someone physically within 10 metres of the location can decrypt and read it.\n\n'
        'Requires GPS accuracy of 10m or better.',
        style: TextStyle(color: ChaayaTheme.textMuted),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ));
  }
}

class _DropPin {
  final LatLng location;
  final bool isUnlocked;
  const _DropPin({required this.location, required this.isUnlocked});
}
