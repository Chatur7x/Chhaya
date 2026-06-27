import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:uuid/uuid.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/location_safety_service.dart';
import 'widgets/map_bottom_sheet.dart';
import 'widgets/map_search_bar.dart';
import '../../../core/widgets/animated_builder.dart';

// Apple Maps dark-mode color matrix — tuned for OLED + contrast
const _darkMapMatrix = ColorFilter.matrix([
  0.28, 0, 0, 0, 0,
  0, 0.28, 0, 0, 0,
  0, 0, 0.34, 0, 12,
  0, 0, 0, 1, 0,
]);

// Satellite-style darker matrix for terrain mode
const _satelliteMatrix = ColorFilter.matrix([
  0.5, 0.05, 0, 0, -20,
  0.05, 0.45, 0.05, 0, -20,
  0, 0.05, 0.55, 0, -10,
  0, 0, 0, 1, 0,
]);

enum MapStyle { dark, satellite, terrain }

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
  bool _showTrail = false;
  MapStyle _mapStyle = MapStyle.dark;
  LatLng _myLocation = const LatLng(37.7749, -122.4194);
  StreamSubscription? _positionStream;
  StreamSubscription? _sosSub, _geofenceSub, _wellnessSub, _drivingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  List<CheckIn> _recentCheckIns = [];
  List<LocationCircle> _circles = [];
  List<NamedPlace> _places = [];
  List<LatLng> _trailPoints = [];
  int _currentBattery = 85;
  String _selectedCircleId = '';
  late AnimationController _pulseCtrl;
  late AnimationController _compassCtrl;
  double _heading = 0;
  double _tiltX = 0, _tiltY = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _compassCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _accelSub = accelerometerEventStream().listen((event) {
      if (mounted) {
        setState(() {
          _tiltX = (event.y * 0.03).clamp(-0.08, 0.08);
          _tiltY = (event.x * 0.03).clamp(-0.08, 0.08);
        });
      }
    });
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
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: bg ?? ChaayaTheme.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
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
      setState(() {
        _myLocation = LatLng(p.latitude, p.longitude);
        _heading = p.heading;
        if (_showTrail) _trailPoints.add(_myLocation);
      });
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
    _accelSub?.cancel();
    _pulseCtrl.dispose();
    _compassCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _triggerSOS() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [Icon(Icons.sos, color: ChaayaTheme.sosRed, size: 28), SizedBox(width: 10), Text('Send SOS?', style: TextStyle(fontWeight: FontWeight.w800))]),
        content: const Text('This will broadcast your GPS, battery level, and alert ALL mesh nodes and circle members.', style: TextStyle(color: ChaayaTheme.textSecondary)),
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
            style: ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('SEND SOS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Check In', style: TextStyle(fontWeight: FontWeight.w700)),
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

  String get _tileUrl {
    switch (_mapStyle) {
      case MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapStyle.terrain:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapStyle.dark:
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  ColorFilter? get _tileFilter {
    switch (_mapStyle) {
      case MapStyle.satellite:
        return _satelliteMatrix;
      case MapStyle.terrain:
        return _darkMapMatrix;
      case MapStyle.dark:
      default:
        return _darkMapMatrix;
    }
  }

  List<Marker> _buildMarkers(Map<String, UserLocation> locations) {
    final markers = <Marker>[];
    // My location — Apple Maps pulsing dot with heading indicator
    markers.add(Marker(
      width: 60, height: 60, point: _myLocation,
      child: ChaayaAnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Transform.rotate(
          angle: _heading * 3.14159 / 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Accuracy ring
              Container(
                width: 56 + _pulseCtrl.value * 8,
                height: 56 + _pulseCtrl.value * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ChaayaTheme.accent.withValues(alpha: 0.08 + _pulseCtrl.value * 0.04),
                ),
              ),
              // Direction cone
              Positioned(
                top: 2,
                child: CustomPaint(
                  size: const Size(18, 12),
                  painter: _HeadingConePainter(color: ChaayaTheme.accent.withValues(alpha: 0.4)),
                ),
              ),
              // Core dot
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: ChaayaTheme.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3.5),
                  boxShadow: [
                    BoxShadow(color: ChaayaTheme.accent.withValues(alpha: 0.6), blurRadius: 14, spreadRadius: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    // Other users — premium avatars
    for (final loc in locations.values) {
      if (loc.latitude == _myLocation.latitude && loc.longitude == _myLocation.longitude) continue;
      final isLowBattery = loc.batteryLevel < 20;
      markers.add(Marker(
        width: 48, height: 48,
        point: LatLng(loc.latitude, loc.longitude),
        child: Container(
          decoration: BoxDecoration(
            color: ChaayaTheme.surfaceLight,
            shape: BoxShape.circle,
            border: Border.all(color: isLowBattery ? ChaayaTheme.sosRed : ChaayaTheme.bleColor, width: 2.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
              BoxShadow(color: (isLowBattery ? ChaayaTheme.sosRed : ChaayaTheme.bleColor).withValues(alpha: 0.2), blurRadius: 8),
            ],
          ),
          child: Center(child: Text(
            loc.deviceId[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          )),
        ),
      ));
    }
    // Named places as map pins
    for (final place in _places) {
      markers.add(Marker(
        width: 36, height: 36,
        point: LatLng(place.latitude, place.longitude),
        child: Container(
          decoration: BoxDecoration(
            color: ChaayaTheme.warningYellow.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: ChaayaTheme.warningYellow.withValues(alpha: 0.3), blurRadius: 10)],
          ),
          child: const Icon(Icons.place, color: Colors.white, size: 18),
        ),
      ));
    }
    return markers;
  }

  List<Polyline> _buildTrailLines() {
    if (!_showTrail || _trailPoints.length < 2) return [];
    return [
      Polyline(
        points: _trailPoints,
        color: ChaayaTheme.accent.withValues(alpha: 0.6),
        strokeWidth: 3,
        isDotted: false,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final locStream = ref.watch(locationStreamProvider);
    final matrix3d = Matrix4.identity()
      ..setEntry(3, 2, 0.0005)
      ..rotateX(_tiltX)
      ..rotateY(_tiltY);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: Stack(children: [
        // Map with subtle 3D tilt
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
          transform: matrix3d,
          transformAlignment: Alignment.center,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _myLocation, initialZoom: 14.0),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.chaaya.app',
                tileBuilder: (context, w, _) => _tileFilter != null
                    ? ColorFiltered(colorFilter: _tileFilter!, child: w) : w,
              ),
              PolylineLayer(polylines: _buildTrailLines()),
              // Geofence circles
              CircleLayer(circles: _places.map((p) => CircleMarker(
                point: LatLng(p.latitude, p.longitude),
                radius: p.radiusMeters / 10,
                color: ChaayaTheme.warningYellow.withValues(alpha: 0.08),
                borderColor: ChaayaTheme.warningYellow.withValues(alpha: 0.3),
                borderStrokeWidth: 1.5,
              )).toList()),
              MarkerLayer(markers: _buildMarkers(locStream.value ?? {})),
            ],
          ),
        ),

        // Top Search Bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              MapSearchBar(batteryLevel: _currentBattery),
              if (_circles.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildCircleChips(),
              ],
              if (_isDrivingMode) ...[
                const SizedBox(height: 10),
                _drivingBanner(),
              ],
            ]),
          ),
        ),

        // Right side premium controls (Apple Maps style)
        Positioned(
          right: 16, bottom: 200,
          child: Column(children: [
            _glassFAB(Icons.layers_outlined, () {
              setState(() {
                _mapStyle = MapStyle.values[(_mapStyle.index + 1) % MapStyle.values.length];
              });
            }),
            const SizedBox(height: 12),
            _glassFAB(Icons.timeline, () {
              setState(() => _showTrail = !_showTrail);
            }, isActive: _showTrail),
            const SizedBox(height: 12),
            _glassFAB(Icons.explore_outlined, () => _mapController.rotate(0)),
            const SizedBox(height: 12),
            _glassFAB(Icons.my_location_rounded, () {
              _mapController.move(_myLocation, 16.0);
            }),
          ]),
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
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _circles.length,
        itemBuilder: (_, i) {
          final c = _circles[i];
          final sel = c.id == _selectedCircleId;
          return GestureDetector(
            onTap: () => setState(() => _selectedCircleId = c.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? ChaayaTheme.accent.withValues(alpha: 0.2) : ChaayaTheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? ChaayaTheme.accent : ChaayaTheme.glassBorder, width: sel ? 1.5 : 0.5),
                boxShadow: sel ? [BoxShadow(color: ChaayaTheme.accent.withValues(alpha: 0.15), blurRadius: 10)] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.groups_rounded, size: 16, color: sel ? ChaayaTheme.accent : ChaayaTheme.textMuted),
                const SizedBox(width: 8),
                Text(c.name, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? ChaayaTheme.accent : ChaayaTheme.textSecondary)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _drivingBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: ChaayaTheme.bleColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ChaayaTheme.bleColor.withValues(alpha: 0.3)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.directions_car_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text('Driving Mode Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  Widget _glassFAB(IconData icon, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isActive ? ChaayaTheme.accent.withValues(alpha: 0.2) : ChaayaTheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isActive ? ChaayaTheme.accent.withValues(alpha: 0.5) : ChaayaTheme.glassBorder, width: isActive ? 1.5 : 0.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                if (isActive) BoxShadow(color: ChaayaTheme.accent.withValues(alpha: 0.2), blurRadius: 12),
              ],
            ),
            child: Icon(icon, color: isActive ? ChaayaTheme.accent : ChaayaTheme.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Heading direction cone painter for the blue dot
class _HeadingConePainter extends CustomPainter {
  final Color color;
  _HeadingConePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final p = ui.Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
