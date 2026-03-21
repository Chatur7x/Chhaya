import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/location_safety_service.dart';

/// Safety & Map Screen — maps using OSM tiles and live Chaaya peer locations.
class SafetyMapScreen extends ConsumerStatefulWidget {
  const SafetyMapScreen({super.key});

  @override
  ConsumerState<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends ConsumerState<SafetyMapScreen> {
  final MapController _mapController = MapController();
  bool _sharingLocation = true;
  bool _privateMode = false;
  LatLng _myLocation = const LatLng(37.7749, -122.4194); // Default to SF

  @override
  void initState() {
    super.initState();
    // Simulate initial location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMockGPS();
    });
  }

  void _startMockGPS() {
    // In production, sync with geolocator stream
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted) return false;
      if (_sharingLocation && !_privateMode) {
        final locService = ref.read(locationSafetyServiceProvider);
        final ident = ref.read(identityServiceProvider).currentIdentity;
        if (ident != null) {
          locService.updateMyLocation(
            _myLocation.latitude, _myLocation.longitude,
            0.0, 0.0, 85, ident.deviceId,
          );
        }
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen to real location updates from the service
    final locStream = ref.watch(locationStreamProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: Stack(
        children: [
          // FlutterMap rendering OSM tiles
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.chaaya.app',
                // Dark mode tiles filter
                tileBuilder: (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      -1,  0,  0, 0, 255,
                       0, -1,  0, 0, 255,
                       0,  0, -1, 0, 255,
                       0,  0,  0, 1,   0,
                    ]),
                    child: tileWidget,
                  );
                },
              ),
              MarkerLayer(
                markers: _buildMarkers(locStream.value ?? {}),
              ),
            ],
          ),

          // Top overlay — search + status
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: ChaayaTheme.textMuted, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: TextField(
                            style: TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search places, contacts...',
                              hintStyle: TextStyle(color: ChaayaTheme.textMuted),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        ChaayaTheme.channelBadge('ble'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Circle members strip (Reacting to live location data)
                  if (locStream.value != null)
                    SizedBox(
                      height: 70,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: locStream.value!.length,
                        itemBuilder: (context, i) {
                          final loc = locStream.value!.values.elementAt(i);
                          // For display, using the first letter of deviceId. In real app, map deviceId -> contactName.
                          return _memberBubble(
                            loc.deviceId.substring(0, 3).toUpperCase(),
                            'nearby',
                            loc.batteryLevel,
                            false,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomPanel(),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton(
          mini: true,
          backgroundColor: ChaayaTheme.surfaceLight,
          child: const Icon(Icons.my_location, color: ChaayaTheme.accent),
          onPressed: () {
            _mapController.move(_myLocation, 15.0);
          },
        ),
      ),
    );
  }

  List<Marker> _buildMarkers(Map<String, UserLocation> locations) {
    final markers = <Marker>[];

    // My Location
    markers.add(Marker(
      width: 30, height: 30, point: _myLocation,
      child: Container(
        decoration: BoxDecoration(
          color: ChaayaTheme.accent, shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: ChaayaTheme.accent.withOpacity(0.5), blurRadius: 10)],
        ),
      ),
    ));

    // Peer Locations
    for (final loc in locations.values) {
      if (loc.latitude == _myLocation.latitude && loc.longitude == _myLocation.longitude) continue;
      
      markers.add(Marker(
        width: 36, height: 36,
        point: LatLng(loc.latitude, loc.longitude),
        child: Container(
          decoration: BoxDecoration(
            color: ChaayaTheme.bleColor.withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              loc.deviceId[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  Widget _memberBubble(String name, String status, int battery, bool isMe) {
    return Container(
      width: 60, margin: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isMe ? ChaayaTheme.accent.withOpacity(0.3) : ChaayaTheme.surfaceLight,
                child: Text(name[0], style: TextStyle(color: isMe ? ChaayaTheme.accent : ChaayaTheme.textPrimary, fontWeight: FontWeight.w600)),
              ),
              Positioned(right: 0, bottom: 0, child: ChaayaTheme.statusDot(status)),
            ],
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontSize: 10, color: ChaayaTheme.textSecondary), overflow: TextOverflow.ellipsis),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(battery > 20 ? Icons.battery_full : Icons.battery_alert, size: 10, color: battery > 20 ? ChaayaTheme.safeGreen : ChaayaTheme.sosRed),
              Text('$battery%', style: TextStyle(fontSize: 9, color: battery > 20 ? ChaayaTheme.textMuted : ChaayaTheme.sosRed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      decoration: const BoxDecoration(
        color: ChaayaTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: ChaayaTheme.glassBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _toggleButton(
                icon: _sharingLocation ? Icons.location_on : Icons.location_off,
                label: 'Sharing', isActive: _sharingLocation,
                onTap: () => setState(() => _sharingLocation = !_sharingLocation),
              ),
              _toggleButton(
                icon: Icons.visibility_off, label: 'Private', isActive: _privateMode,
                onTap: () => setState(() => _privateMode = !_privateMode),
              ),
              _toggleButton(
                icon: Icons.add_location, label: 'Check-in', isActive: false, onTap: () {},
              ),
              _toggleButton(
                icon: Icons.history, label: 'History', isActive: false, onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: _triggerSOS,
              style: ElevatedButton.styleFrom(
                backgroundColor: ChaayaTheme.sosRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.sos),
              label: const Text('SOS — Send to Trusted Contacts', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _triggerSOS() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sos, color: ChaayaTheme.sosRed), SizedBox(width: 8),
            Text('Send SOS?', style: ChaayaTheme.heading3),
          ],
        ),
        content: const Text(
          'This will send your GPS location, battery level, and alert all mesh peers.',
          style: ChaayaTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final locService = ref.read(locationSafetyServiceProvider);
              final ident = ref.read(identityServiceProvider).currentIdentity;
              if (ident != null) {
                locService.triggerSOS(ident.deviceId, ident.username, _myLocation.latitude, _myLocation.longitude, 85);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🆘 SOS broadcast sent!'), backgroundColor: ChaayaTheme.sosRed),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isActive ? ChaayaTheme.accent.withOpacity(0.15) : ChaayaTheme.surfaceLight,
              shape: BoxShape.circle,
              border: Border.all(color: isActive ? ChaayaTheme.accent : ChaayaTheme.glassBorder),
            ),
            child: Icon(icon, size: 20, color: isActive ? ChaayaTheme.accent : ChaayaTheme.textMuted),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: isActive ? ChaayaTheme.accent : ChaayaTheme.textMuted)),
        ],
      ),
    );
  }
}

