import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/location_safety_service.dart';

class SafetyMapScreen extends ConsumerStatefulWidget {
  const SafetyMapScreen({super.key});

  @override
  ConsumerState<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends ConsumerState<SafetyMapScreen> {
  final MapController _mapController = MapController();
  bool _sharingLocation = true;
  bool _privateMode = false;
  bool _isDrivingMode = false;
  LatLng _myLocation = const LatLng(37.7749, -122.4194);
  StreamSubscription? _positionStream;
  StreamSubscription? _sosSub;
  StreamSubscription? _geofenceSub;
  StreamSubscription? _wellnessSub;
  StreamSubscription? _drivingSub;
  List<CheckIn> _recentCheckIns = [];
  List<LocationCircle> _circles = [];
  List<NamedPlace> _places = [];
  int _currentBattery = 85;
  String _selectedCircleId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _startRealGPS();
      _listenToAlerts();
    });
  }

  void _loadData() {
    final locService = ref.read(locationSafetyServiceProvider);
    setState(() {
      _circles = locService.getCircles();
      _places = locService.getPlaces();
      _recentCheckIns = locService.getCheckIns();
      _isDrivingMode = locService.isDriving();
      if (_circles.isNotEmpty) _selectedCircleId = _circles.first.id;
    });
  }

  void _listenToAlerts() {
    final locService = ref.read(locationSafetyServiceProvider);
    _sosSub = locService.sosAlerts.listen((alert) {
      if (mounted) _showSOSNotification(alert);
    });
    _geofenceSub = locService.geofenceEvents.listen((event) {
      if (mounted) _showGeofenceNotification(event);
    });
    _wellnessSub = locService.wellnessAlerts.listen((alert) {
      if (mounted) _showWellnessNotification(alert);
    });
    _drivingSub = locService.drivingModeUpdates.listen((isDriving) {
      if (mounted) setState(() => _isDrivingMode = isDriving);
    });
  }

  void _showSOSNotification(SOSAlert alert) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🆘 SOS from ${alert.senderName}!'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
            label: 'View', textColor: Colors.white, onPressed: () {}),
      ),
    );
  }

  void _showGeofenceNotification(GeofenceEvent event) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(event.type == GeofenceType.enter
            ? '📍 Arrived at ${event.place.name}'
            : '📍 Left ${event.place.name}'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showWellnessNotification(WellnessAlert alert) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '⚠️ ${alert.deviceId.substring(0, 8)} inactive for ${alert.inactiveDuration.inMinutes} min'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _startRealGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      final initial = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(
            () => _myLocation = LatLng(initial.latitude, initial.longitude));
        _mapController.move(_myLocation, 15.0);
      }
    } catch (_) {}

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 10),
    ).listen((Position position) {
      if (!mounted) return;
      setState(
          () => _myLocation = LatLng(position.latitude, position.longitude));

      if (_sharingLocation && !_privateMode) {
        final locService = ref.read(locationSafetyServiceProvider);
        final ident = ref.read(identityServiceProvider).currentIdentity;
        if (ident != null) {
          locService.updateMyLocation(
            position.latitude,
            position.longitude,
            position.speed,
            position.heading,
            _currentBattery,
            ident.deviceId,
          );
        }
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
    _mapController.dispose();
    super.dispose();
  }

  void _triggerSOS() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.sos, color: ChaayaTheme.sosRed),
          SizedBox(width: 8),
          Text('Send SOS?')
        ]),
        content: const Text(
            'This will send your GPS, battery level, and alert all Circle members.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final locService = ref.read(locationSafetyServiceProvider);
              final ident = ref.read(identityServiceProvider).currentIdentity;
              if (ident != null) {
                locService.triggerSOS(
                    ident.deviceId,
                    ident.username,
                    _myLocation.latitude,
                    _myLocation.longitude,
                    _currentBattery);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('🆘 SOS broadcast sent to Circle!'),
                    backgroundColor: ChaayaTheme.sosRed),
              );
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
  }

  void _showCheckInDialog() {
    final statusController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check In'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: statusController,
            decoration: const InputDecoration(
              hintText: 'Status message (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final locService = ref.read(locationSafetyServiceProvider);
              final ident = ref.read(identityServiceProvider).currentIdentity;
              if (ident != null) {
                await locService.checkIn(
                    ident.deviceId,
                    ident.username,
                    _myLocation.latitude,
                    _myLocation.longitude,
                    statusController.text);
                setState(() => _recentCheckIns = locService.getCheckIns());
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('✅ Checked in!'),
                        backgroundColor: ChaayaTheme.safeGreen),
                  );
              }
            },
            child: const Text('Check In'),
          ),
        ],
      ),
    );
  }

  void _showHistoryView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _HistoryScreen(
            locationService: ref.read(locationSafetyServiceProvider)),
      ),
    );
  }

  void _showPlacesManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _PlacesScreen(
          places: _places,
          onAdd: (place) async {
            final locService = ref.read(locationSafetyServiceProvider);
            await locService.addPlace(place);
            setState(() => _places = locService.getPlaces());
          },
          onDelete: (placeId) async {
            final locService = ref.read(locationSafetyServiceProvider);
            await locService.deletePlace(placeId);
            setState(() => _places = locService.getPlaces());
          },
          currentLocation: _myLocation,
        ),
      ),
    );
  }

  void _showCirclesManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _CirclesScreen(
          circles: _circles,
          onCreate: (name) async {
            final locService = ref.read(locationSafetyServiceProvider);
            final ident = ref.read(identityServiceProvider).currentIdentity;
            if (ident != null) {
              await locService.createCircle(name, ident.deviceId);
              setState(() => _circles = locService.getCircles());
            }
          },
          onDelete: (id) async {
            final locService = ref.read(locationSafetyServiceProvider);
            await locService.deleteCircle(id);
            setState(() => _circles = locService.getCircles());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locStream = ref.watch(locationStreamProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _myLocation, initialZoom: 14.0),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.chaaya.app',
                tileBuilder: (context, tileWidget, tile) => ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    -1,
                    0,
                    0,
                    0,
                    255,
                    0,
                    -1,
                    0,
                    0,
                    255,
                    0,
                    0,
                    -1,
                    0,
                    255,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
                  child: tileWidget,
                ),
              ),
              MarkerLayer(markers: _buildMarkers(locStream.value ?? {})),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _buildTopBar(),
                const SizedBox(height: 12),
                if (_circles.isNotEmpty) _buildCircleSelector(),
                const SizedBox(height: 8),
                if (locStream.value != null && locStream.value!.isNotEmpty)
                  SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: locStream.value!.length,
                      itemBuilder: (context, i) {
                        final loc = locStream.value!.values.elementAt(i);
                        return _memberBubble(loc.deviceId.substring(0, 6),
                            _getStatus(loc), loc.batteryLevel, false);
                      },
                    ),
                  ),
              ]),
            ),
          ),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomPanel()),
          if (_isDrivingMode)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.directions_car, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('🚗 Driving Mode',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton(
          mini: true,
          backgroundColor: ChaayaTheme.surfaceLight,
          child: const Icon(Icons.my_location, color: ChaayaTheme.accent),
          onPressed: () => _mapController.move(_myLocation, 15.0),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
      child: Row(children: [
        const Icon(Icons.search, color: ChaayaTheme.textMuted, size: 20),
        const SizedBox(width: 10),
        const Expanded(
            child: TextField(
          style: TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
              hintText: 'Search places, contacts...',
              hintStyle: TextStyle(color: ChaayaTheme.textMuted),
              border: InputBorder.none),
        )),
        ChaayaTheme.channelBadge('ble'),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _currentBattery > 20
                ? ChaayaTheme.safeGreen.withOpacity(0.2)
                : ChaayaTheme.sosRed.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _currentBattery > 20 ? Icons.battery_full : Icons.battery_alert,
                size: 14,
                color: _currentBattery > 20
                    ? ChaayaTheme.safeGreen
                    : ChaayaTheme.sosRed),
            const SizedBox(width: 4),
            Text('$_currentBattery%',
                style: TextStyle(
                    fontSize: 12,
                    color: _currentBattery > 20
                        ? ChaayaTheme.safeGreen
                        : ChaayaTheme.sosRed)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCircleSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
      child: Row(children: [
        const Icon(Icons.groups, color: ChaayaTheme.textMuted, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: _selectedCircleId.isEmpty ? null : _selectedCircleId,
            isExpanded: true,
            dropdownColor: ChaayaTheme.surface,
            underline: const SizedBox(),
            hint: const Text('Select Circle',
                style: TextStyle(color: ChaayaTheme.textMuted)),
            items: _circles
                .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name,
                        style:
                            const TextStyle(color: ChaayaTheme.textPrimary))))
                .toList(),
            onChanged: (id) => setState(() => _selectedCircleId = id ?? ''),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.settings, size: 18),
            onPressed: _showCirclesManager,
            color: ChaayaTheme.textMuted),
      ]),
    );
  }

  String _getStatus(UserLocation loc) {
    final diff = DateTime.now().difference(loc.timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  List<Marker> _buildMarkers(Map<String, UserLocation> locations) {
    final markers = <Marker>[];
    markers.add(Marker(
      width: 30,
      height: 30,
      point: _myLocation,
      child: Container(
        decoration: BoxDecoration(
            color: ChaayaTheme.accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: ChaayaTheme.accent.withOpacity(0.5), blurRadius: 10)
            ]),
      ),
    ));
    for (final loc in locations.values) {
      if (loc.latitude == _myLocation.latitude &&
          loc.longitude == _myLocation.longitude) continue;
      markers.add(Marker(
        width: 36,
        height: 36,
        point: LatLng(loc.latitude, loc.longitude),
        child: Container(
          decoration: BoxDecoration(
              color: ChaayaTheme.bleColor.withOpacity(0.8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2)),
          child: Center(
              child: Text(loc.deviceId[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16))),
        ),
      ));
    }
    return markers;
  }

  Widget _memberBubble(String name, String status, int battery, bool isMe) {
    return Container(
      width: 60,
      margin: const EdgeInsets.only(right: 8),
      child: Column(children: [
        Stack(children: [
          CircleAvatar(
              radius: 22,
              backgroundColor: isMe
                  ? ChaayaTheme.accent.withOpacity(0.3)
                  : ChaayaTheme.surfaceLight,
              child: Text(name[0],
                  style: TextStyle(
                      color:
                          isMe ? ChaayaTheme.accent : ChaayaTheme.textPrimary,
                      fontWeight: FontWeight.w600))),
          Positioned(right: 0, bottom: 0, child: ChaayaTheme.statusDot(status)),
        ]),
        const SizedBox(height: 4),
        Text(name,
            style:
                const TextStyle(fontSize: 10, color: ChaayaTheme.textSecondary),
            overflow: TextOverflow.ellipsis),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(battery > 20 ? Icons.battery_full : Icons.battery_alert,
              size: 10,
              color: battery > 20 ? ChaayaTheme.safeGreen : ChaayaTheme.sosRed),
          Text('$battery%',
              style: TextStyle(
                  fontSize: 9,
                  color: battery > 20
                      ? ChaayaTheme.textMuted
                      : ChaayaTheme.sosRed)),
        ]),
      ]),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      decoration: const BoxDecoration(
          color: ChaayaTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: ChaayaTheme.glassBorder))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _toggleButton(
              icon: _sharingLocation ? Icons.location_on : Icons.location_off,
              label: 'Sharing',
              isActive: _sharingLocation,
              onTap: () =>
                  setState(() => _sharingLocation = !_sharingLocation)),
          _toggleButton(
              icon: Icons.visibility_off,
              label: 'Private',
              isActive: _privateMode,
              onTap: () {
                setState(() => _privateMode = !_privateMode);
                ref
                    .read(locationSafetyServiceProvider)
                    .setPrivateMode(_privateMode);
              }),
          _toggleButton(
              icon: Icons.add_location,
              label: 'Check-in',
              isActive: false,
              onTap: _showCheckInDialog),
          _toggleButton(
              icon: Icons.history,
              label: 'History',
              isActive: false,
              onTap: _showHistoryView),
          _toggleButton(
              icon: Icons.place,
              label: 'Places',
              isActive: false,
              onTap: _showPlacesManager),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _triggerSOS,
            style: ElevatedButton.styleFrom(
                backgroundColor: ChaayaTheme.sosRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.sos),
            label: const Text('SOS — Send to Circle',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _toggleButton(
      {required IconData icon,
      required String label,
      required bool isActive,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive
                ? ChaayaTheme.accent.withOpacity(0.15)
                : ChaayaTheme.surfaceLight,
            shape: BoxShape.circle,
            border: Border.all(
                color: isActive ? ChaayaTheme.accent : ChaayaTheme.glassBorder),
          ),
          child: Icon(icon,
              size: 20,
              color: isActive ? ChaayaTheme.accent : ChaayaTheme.textMuted),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: isActive ? ChaayaTheme.accent : ChaayaTheme.textMuted)),
      ]),
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  final LocationSafetyService locationService;
  const _HistoryScreen({required this.locationService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location History')),
      body: ListView.builder(
        itemCount: locationService.getCircles().length,
        itemBuilder: (ctx, i) {
          final circle = locationService.getCircles()[i];
          final trail = locationService.getTrail(circle.creatorId);
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.timeline)),
            title: Text(circle.name),
            subtitle: Text('${trail.length} location points'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          );
        },
      ),
    );
  }
}

class _PlacesScreen extends StatelessWidget {
  final List<NamedPlace> places;
  final Function(NamedPlace) onAdd;
  final Function(String) onDelete;
  final LatLng currentLocation;

  const _PlacesScreen(
      {required this.places,
      required this.onAdd,
      required this.onDelete,
      required this.currentLocation});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Places')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPlaceDialog(context),
        child: const Icon(Icons.add),
      ),
      body: places.isEmpty
          ? const Center(
              child: Text('No places defined',
                  style: TextStyle(color: ChaayaTheme.textMuted)))
          : ListView.builder(
              itemCount: places.length,
              itemBuilder: (ctx, i) {
                final place = places[i];
                return ListTile(
                  leading: CircleAvatar(child: Icon(_getIconData(place.icon))),
                  title: Text(place.name),
                  subtitle: Text('${place.radiusMeters.toInt()}m radius'),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => onDelete(place.id)),
                );
              },
            ),
    );
  }

  void _showAddPlaceDialog(BuildContext context) {
    final nameController = TextEditingController();
    double radius = 100;
    String selectedIcon = 'home';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Place'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Place Name', hintText: 'Home, Work, Base...')),
            const SizedBox(height: 16),
            Text('Radius: ${radius.toInt()}m'),
            Slider(
                value: radius,
                min: 50,
                max: 500,
                divisions: 9,
                onChanged: (v) => setDialogState(() => radius = v)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                children: ['home', 'work', 'place', 'flag', 'star']
                    .map((icon) => ChoiceChip(
                          label: Icon(_getIconData(icon), size: 18),
                          selected: selectedIcon == icon,
                          onSelected: (s) =>
                              setDialogState(() => selectedIcon = icon),
                        ))
                    .toList()),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  onAdd(NamedPlace(
                      id: const Uuid().v4(),
                      name: nameController.text,
                      icon: selectedIcon,
                      latitude: currentLocation.latitude,
                      longitude: currentLocation.longitude,
                      radiusMeters: radius));
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String icon) {
    switch (icon) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'place':
        return Icons.place;
      case 'flag':
        return Icons.flag;
      case 'star':
        return Icons.star;
      default:
        return Icons.place;
    }
  }
}

class _CirclesScreen extends StatelessWidget {
  final List<LocationCircle> circles;
  final Function(String) onCreate;
  final Function(String) onDelete;

  const _CirclesScreen(
      {required this.circles, required this.onCreate, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Circles')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
      body: circles.isEmpty
          ? const Center(
              child: Text('No circles created',
                  style: TextStyle(color: ChaayaTheme.textMuted)))
          : ListView.builder(
              itemCount: circles.length,
              itemBuilder: (ctx, i) {
                final circle = circles[i];
                return ListTile(
                  leading:
                      CircleAvatar(child: Text('${circle.members.length}')),
                  title: Text(circle.name),
                  subtitle: Text('${circle.members.length} members'),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => onDelete(circle.id)),
                );
              },
            ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Circle'),
        content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
                labelText: 'Circle Name', hintText: 'Family, Team, Rescue...')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                onCreate(nameController.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
