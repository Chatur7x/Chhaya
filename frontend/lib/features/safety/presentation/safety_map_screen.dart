import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/location_safety_service.dart';
import 'widgets/map_bottom_sheet.dart';
import 'widgets/map_search_bar.dart';

// Apple Maps dark-mode color matrix
const _darkMapMatrix = ColorFilter.matrix([
  0.3, 0, 0, 0, 0,
  0, 0.3, 0, 0, 0,
  0, 0, 0.35, 0, 10,
  0, 0, 0, 1, 0,
]);

class SafetyMapScreen extends ConsumerStatefulWidget {
  const SafetyMapScreen({super.key});
  @override
  ConsumerState<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends ConsumerState<SafetyMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _sharingLocation = true;
  bool _privateMode = false;
  bool _isDrivingMode = false;
  LatLng _myLocation = const LatLng(37.7749, -122.4194);
  StreamSubscription? _positionStream;
  StreamSubscription? _sosSub, _geofenceSub, _wellnessSub, _drivingSub;
  List<CheckIn> _recentCheckIns = [];
  List<LocationCircle> _circles = [];
  List<NamedPlace> _places = [];
  int _currentBattery = 85;
  String _selectedCircleId = '';
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _startRealGPS();
      _listenToAlerts();
    });
  }

  void _loadData() {
    final svc = ref.read(locationSafetyServiceProvider);
    setState(() {
      _circles = svc.getCircles();
      _places = svc.getPlaces();
      _recentCheckIns = svc.getCheckIns();
      _isDrivingMode = svc.isDriving();
      if (_circles.isNotEmpty) _selectedCircleId = _circles.first.id;
    });
  }

  void _listenToAlerts() {
    final svc = ref.read(locationSafetyServiceProvider);
    _sosSub = svc.sosAlerts.listen((a) {
      if (mounted) _snack('🆘 SOS from ${a.senderName}!', ChaayaTheme.sosRed);
    });
    _geofenceSub = svc.geofenceEvents.listen((e) {
      if (mounted) _snack(e.type == GeofenceType.enter
          ? '📍 Arrived at ${e.place.name}' : '📍 Left ${e.place.name}', null);
    });
    _wellnessSub = svc.wellnessAlerts.listen((a) {
      if (mounted) _snack('⚠️ Inactive alert: ${a.deviceId.substring(0, 8)}', Colors.orange);
    });
    _drivingSub = svc.drivingModeUpdates.listen((d) {
      if (mounted) setState(() => _isDrivingMode = d);
    });
  }

  void _snack(String msg, Color? bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _startRealGPS() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    try {
      final p = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _myLocation = LatLng(p.latitude, p.longitude));
        _mapController.move(_myLocation, 15.0);
      }
    } catch (_) {}
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 10),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(p.latitude, p.longitude));
      if (_sharingLocation && !_privateMode) {
        final svc = ref.read(locationSafetyServiceProvider);
        final id = ref.read(identityServiceProvider).currentIdentity;
        if (id != null) svc.updateMyLocation(p.latitude, p.longitude, p.speed, p.heading, _currentBattery, id.deviceId);
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _sosSub?.cancel();
    _geofenceSub?.cancel();
    _wellnessSub?.cancel();
    _drivingSub?.cancel();
    _pulseCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _triggerSOS() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.sos, color: ChaayaTheme.sosRed), SizedBox(width: 8), Text('Send SOS?')]),
        content: const Text('This will send your GPS, battery level, and alert all Circle members.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final svc = ref.read(locationSafetyServiceProvider);
              final id = ref.read(identityServiceProvider).currentIdentity;
              if (id != null) svc.triggerSOS(id.deviceId, id.username, _myLocation.latitude, _myLocation.longitude, _currentBattery);
              _snack('🆘 SOS broadcast sent!', ChaayaTheme.sosRed);
            },
            style: ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
  }

  void _showCheckInDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Check In'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Status (optional)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            Navigator.pop(ctx);
            final svc = ref.read(locationSafetyServiceProvider);
            final id = ref.read(identityServiceProvider).currentIdentity;
            if (id != null) {
              await svc.checkIn(id.deviceId, id.username, _myLocation.latitude, _myLocation.longitude, ctrl.text);
              setState(() => _recentCheckIns = svc.getCheckIns());
              _snack('✅ Checked in!', ChaayaTheme.safeGreen);
            }
          }, child: const Text('Check In')),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(Map<String, UserLocation> locations) {
    final markers = <Marker>[];
    // My location — pulsing blue dot (Apple Maps style)
    markers.add(Marker(
      width: 44, height: 44, point: _myLocation,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ChaayaTheme.accent.withValues(alpha: 0.12 + _pulseCtrl.value * 0.08),
          ),
          child: Center(child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: ChaayaTheme.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: ChaayaTheme.accent.withValues(alpha: 0.5), blurRadius: 12)],
            ),
          )),
        ),
      ),
    ));
    // Other users
    for (final loc in locations.values) {
      if (loc.latitude == _myLocation.latitude && loc.longitude == _myLocation.longitude) continue;
      markers.add(Marker(
        width: 40, height: 40,
        point: LatLng(loc.latitude, loc.longitude),
        child: Container(
          decoration: BoxDecoration(
            color: ChaayaTheme.surfaceLight,
            shape: BoxShape.circle,
            border: Border.all(color: ChaayaTheme.bleColor, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Center(child: Text(
            loc.deviceId[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          )),
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final locStream = ref.watch(locationStreamProvider);
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: Stack(children: [
        // Map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _myLocation, initialZoom: 14.0),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.chaaya.app',
              tileBuilder: (context, w, _) => ColorFiltered(colorFilter: _darkMapMatrix, child: w),
            ),
            MarkerLayer(markers: _buildMarkers(locStream.value ?? {})),
          ],
        ),
        // Search bar (Apple Maps style)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              MapSearchBar(batteryLevel: _currentBattery),
              if (_circles.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildCircleChips(),
              ],
              if (_isDrivingMode) ...[
                const SizedBox(height: 8),
                _drivingBanner(),
              ],
            ]),
          ),
        ),
        // My-location FAB
        Positioned(
          right: 16, bottom: 180,
          child: _glassFAB(Icons.my_location, () => _mapController.move(_myLocation, 15.0)),
        ),
        // Compass FAB
        Positioned(
          right: 16, bottom: 240,
          child: _glassFAB(Icons.explore_outlined, () => _mapController.rotate(0)),
        ),
        // Bottom sheet
        MapBottomSheet(
          sharingLocation: _sharingLocation,
          privateMode: _privateMode,
          isDriving: _isDrivingMode,
          battery: _currentBattery,
          recentCheckIns: _recentCheckIns,
          onToggleSharing: () => setState(() => _sharingLocation = !_sharingLocation),
          onTogglePrivate: () {
            setState(() => _privateMode = !_privateMode);
            ref.read(locationSafetyServiceProvider).setPrivateMode(_privateMode);
          },
          onCheckIn: _showCheckInDialog,
          onHistory: () {},
          onPlaces: () {},
          onCircles: () {},
          onSOS: _triggerSOS,
        ),
      ]),
    );
  }

  Widget _buildCircleChips() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _circles.length,
        itemBuilder: (_, i) {
          final c = _circles[i];
          final sel = c.id == _selectedCircleId;
          return GestureDetector(
            onTap: () => setState(() => _selectedCircleId = c.id),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? ChaayaTheme.accent.withValues(alpha: 0.2) : ChaayaTheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? ChaayaTheme.accent : ChaayaTheme.glassBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.groups, size: 14, color: sel ? ChaayaTheme.accent : ChaayaTheme.textMuted),
                const SizedBox(width: 6),
                Text(c.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? ChaayaTheme.accent : ChaayaTheme.textSecondary)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _drivingBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: ChaayaTheme.bleColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.directions_car, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Driving Mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  Widget _glassFAB(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: ChaayaTheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ChaayaTheme.glassBorder),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: ChaayaTheme.accent, size: 20),
          ),
        ),
      ),
    );
  }
}
