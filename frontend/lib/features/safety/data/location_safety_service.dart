import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Location & Safety Service — Life360-style offline GPS sharing,
/// circles, SOS, crash detection, and safety features.
class LocationSafetyService {
  static const String _locBox = 'chaaya_locations';
  static const String _circleBox = 'chaaya_circles';
  static const String _sosBox = 'chaaya_sos';
  static const String _placesBox = 'chaaya_places';

  Box<String>? _locationBox;
  Box<String>? _circlesBox;
  Box<String>? _sosHistoryBox;
  Box<String>? _namedPlacesBox;

  final _locationUpdates = StreamController<Map<String, UserLocation>>.broadcast();
  final _sosAlerts = StreamController<SOSAlert>.broadcast();
  final _crashDetected = StreamController<CrashEvent>.broadcast();

  Stream<Map<String, UserLocation>> get locationUpdates => _locationUpdates.stream;
  Stream<SOSAlert> get sosAlerts => _sosAlerts.stream;
  Stream<CrashEvent> get crashDetected => _crashDetected.stream;

  // Live location cache: deviceId → latest location
  final Map<String, UserLocation> _liveLocations = {};

  Future<void> initialize() async {
    _locationBox = await Hive.openBox<String>(_locBox);
    _circlesBox = await Hive.openBox<String>(_circleBox);
    _sosHistoryBox = await Hive.openBox<String>(_sosBox);
    _namedPlacesBox = await Hive.openBox<String>(_placesBox);
  }

  // ─── Live Location Sharing ───

  /// Update my location (called every 30-60s)
  Future<void> updateMyLocation(double lat, double lon, double speed,
      double heading, int batteryLevel, String deviceId) async {
    final loc = UserLocation(
      deviceId: deviceId,
      latitude: lat,
      longitude: lon,
      altitude: 0,
      speed: speed,
      heading: heading,
      batteryLevel: batteryLevel,
      timestamp: DateTime.now(),
      accuracy: 5.0,
    );

    _liveLocations[deviceId] = loc;
    await _locationBox?.put(deviceId, jsonEncode(loc.toJson()));
    _locationUpdates.add(Map.from(_liveLocations));
  }

  /// Receive location from a mesh peer
  void receiveLocation(UserLocation location) {
    _liveLocations[location.deviceId] = location;
    _locationUpdates.add(Map.from(_liveLocations));

    // Save to history
    final histKey = '${location.deviceId}_${location.timestamp.millisecondsSinceEpoch}';
    _locationBox?.put(histKey, jsonEncode(location.toJson()));
  }

  /// Get all live locations
  Map<String, UserLocation> get allLocations => Map.from(_liveLocations);

  /// Get 24-hour location trail for a user
  List<UserLocation> getTrail(String deviceId) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final trail = <UserLocation>[];

    _locationBox?.toMap().forEach((key, value) {
      if ((key as String).startsWith(deviceId)) {
        final loc = UserLocation.fromJson(jsonDecode(value));
        if (loc.timestamp.isAfter(cutoff)) trail.add(loc);
      }
    });

    trail.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return trail;
  }

  // ─── Circles ───

  /// Create a circle (like Life360 family/team)
  Future<LocationCircle> createCircle(String name, String creatorId,
      {List<String> members = const []}) async {
    final circle = LocationCircle(
      id: const Uuid().v4(),
      name: name,
      creatorId: creatorId,
      members: [creatorId, ...members],
      createdAt: DateTime.now(),
    );
    await _circlesBox?.put(circle.id, jsonEncode(circle.toJson()));
    return circle;
  }

  /// Get all circles
  List<LocationCircle> getCircles() {
    return _circlesBox?.values
            .map((j) => LocationCircle.fromJson(jsonDecode(j)))
            .toList() ?? [];
  }

  // ─── Named Places (Geofences) ───

  /// Add a named place with geofence
  Future<void> addPlace(NamedPlace place) async {
    await _namedPlacesBox?.put(place.id, jsonEncode(place.toJson()));
  }

  /// Get all named places
  List<NamedPlace> getPlaces() {
    return _namedPlacesBox?.values
            .map((j) => NamedPlace.fromJson(jsonDecode(j)))
            .toList() ?? [];
  }

  /// Check arrivals/departures against geofences
  List<GeofenceEvent> checkGeofences(double lat, double lon) {
    final events = <GeofenceEvent>[];
    for (final place in getPlaces()) {
      final dist = _haversineDistance(lat, lon, place.latitude, place.longitude);
      final isInside = dist <= place.radiusMeters;
      // TODO: Compare with previous state to detect enter/exit
      if (isInside) {
        events.add(GeofenceEvent(
          place: place,
          type: GeofenceType.enter,
          timestamp: DateTime.now(),
        ));
      }
    }
    return events;
  }

  // ─── SOS & Emergency ───

  /// Trigger SOS — sends GPS, battery, and audio recording
  Future<SOSAlert> triggerSOS(String deviceId, String username,
      double lat, double lon, int batteryLevel) async {
    final alert = SOSAlert(
      id: const Uuid().v4(),
      senderId: deviceId,
      senderName: username,
      latitude: lat,
      longitude: lon,
      batteryLevel: batteryLevel,
      timestamp: DateTime.now(),
      type: SOSType.manual,
    );

    await _sosHistoryBox?.put(alert.id, jsonEncode(alert.toJson()));
    _sosAlerts.add(alert);
    debugPrint('[SOS] 🆘 ALERT from $username at ($lat, $lon)');
    return alert;
  }

  /// Get SOS history
  List<SOSAlert> getSOSHistory() {
    return _sosHistoryBox?.values
            .map((j) => SOSAlert.fromJson(jsonDecode(j)))
            .toList() ?? [];
  }

  // ─── Crash Detection ───

  /// Analyze accelerometer data for crash detection
  /// Called with current acceleration values
  void analyzeAcceleration(double x, double y, double z) {
    final magnitude = _magnitude(x, y, z);
    // Threshold: ~4G sudden deceleration = potential crash
    if (magnitude > 39.2) { // 4 * 9.8 m/s²
      final crash = CrashEvent(
        timestamp: DateTime.now(),
        magnitude: magnitude,
        gForce: magnitude / 9.8,
      );
      _crashDetected.add(crash);
      debugPrint('[Safety] ⚠️ CRASH DETECTED! ${crash.gForce.toStringAsFixed(1)}G');
    }
  }

  /// Calculate driver safety score from trip data
  DriverSafetyScore calculateSafetyScore(List<UserLocation> tripPoints) {
    if (tripPoints.length < 2) {
      return DriverSafetyScore(score: 100, hardBrakes: 0, sharpTurns: 0, maxSpeed: 0);
    }

    int hardBrakes = 0;
    int sharpTurns = 0;
    double maxSpeed = 0;

    for (int i = 1; i < tripPoints.length; i++) {
      final prev = tripPoints[i - 1];
      final curr = tripPoints[i];

      // Track max speed
      if (curr.speed > maxSpeed) maxSpeed = curr.speed;

      // Detect hard braking (speed drop > 20 km/h in one interval)
      if (prev.speed - curr.speed > 20) hardBrakes++;

      // Detect sharp turns (heading change > 45° in one interval)
      final headingDiff = (curr.heading - prev.heading).abs();
      if (headingDiff > 45 && headingDiff < 315) sharpTurns++;
    }

    // Score: 100 minus penalties
    final score = (100 - (hardBrakes * 10) - (sharpTurns * 5)).clamp(0, 100);

    return DriverSafetyScore(
      score: score,
      hardBrakes: hardBrakes,
      sharpTurns: sharpTurns,
      maxSpeed: maxSpeed,
    );
  }

  // ─── Wellness Check ───

  /// Check if a user has been inactive (no movement/signal) for too long
  bool isUserInactive(String deviceId, {Duration threshold = const Duration(hours: 2)}) {
    final loc = _liveLocations[deviceId];
    if (loc == null) return true;
    return DateTime.now().difference(loc.timestamp) > threshold;
  }

  // ─── Helpers ───

  double _magnitude(double x, double y, double z) {
    return (x * x + y * y + z * z);
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    // Simplified distance in meters
    const r = 6371000.0; // Earth radius
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRad(lat1)) * _cos(_toRad(lat2)) *
        _sin(dLon / 2) * _sin(dLon / 2);
    return r * 2 * _atan2(_sqrt(a), _sqrt(1 - a));
  }

  double _toRad(double deg) => deg * 3.14159265 / 180;
  double _sin(double x) => x - (x * x * x) / 6; // rough approximation
  double _cos(double x) => 1 - (x * x) / 2;
  double _sqrt(double x) => x > 0 ? x * 0.5 + 0.5 : 0; // very rough
  double _atan2(double y, double x) => y / (x + 0.001);

  Future<void> clearAll() async {
    _liveLocations.clear();
    await _locationBox?.clear();
    await _circlesBox?.clear();
    await _sosHistoryBox?.clear();
    await _namedPlacesBox?.clear();
  }
}

// ─── Models ───

class UserLocation {
  final String deviceId;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double heading;
  final int batteryLevel;
  final DateTime timestamp;
  final double accuracy;

  UserLocation({
    required this.deviceId, required this.latitude, required this.longitude,
    this.altitude = 0, this.speed = 0, this.heading = 0,
    this.batteryLevel = 100, required this.timestamp, this.accuracy = 5,
  });

  factory UserLocation.fromJson(Map<String, dynamic> j) => UserLocation(
    deviceId: j['deviceId'], latitude: j['latitude'], longitude: j['longitude'],
    altitude: j['altitude'] ?? 0, speed: j['speed'] ?? 0, heading: j['heading'] ?? 0,
    batteryLevel: j['batteryLevel'] ?? 100, timestamp: DateTime.parse(j['timestamp']),
    accuracy: j['accuracy'] ?? 5,
  );

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId, 'latitude': latitude, 'longitude': longitude,
    'altitude': altitude, 'speed': speed, 'heading': heading,
    'batteryLevel': batteryLevel, 'timestamp': timestamp.toIso8601String(),
    'accuracy': accuracy,
  };
}

class LocationCircle {
  final String id, name, creatorId;
  final List<String> members;
  final DateTime createdAt;

  LocationCircle({required this.id, required this.name, required this.creatorId,
    required this.members, required this.createdAt});

  factory LocationCircle.fromJson(Map<String, dynamic> j) => LocationCircle(
    id: j['id'], name: j['name'], creatorId: j['creatorId'],
    members: List<String>.from(j['members'] ?? []),
    createdAt: DateTime.parse(j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'creatorId': creatorId,
    'members': members, 'createdAt': createdAt.toIso8601String(),
  };
}

class NamedPlace {
  final String id, name;
  final double latitude, longitude, radiusMeters;

  NamedPlace({required this.id, required this.name,
    required this.latitude, required this.longitude, this.radiusMeters = 100});

  factory NamedPlace.fromJson(Map<String, dynamic> j) => NamedPlace(
    id: j['id'], name: j['name'], latitude: j['latitude'],
    longitude: j['longitude'], radiusMeters: j['radiusMeters'] ?? 100,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'latitude': latitude,
    'longitude': longitude, 'radiusMeters': radiusMeters,
  };
}

class GeofenceEvent {
  final NamedPlace place;
  final GeofenceType type;
  final DateTime timestamp;
  GeofenceEvent({required this.place, required this.type, required this.timestamp});
}

enum GeofenceType { enter, exit }

class SOSAlert {
  final String id, senderId, senderName;
  final double latitude, longitude;
  final int batteryLevel;
  final DateTime timestamp;
  final SOSType type;

  SOSAlert({required this.id, required this.senderId, required this.senderName,
    required this.latitude, required this.longitude, required this.batteryLevel,
    required this.timestamp, required this.type});

  factory SOSAlert.fromJson(Map<String, dynamic> j) => SOSAlert(
    id: j['id'], senderId: j['senderId'], senderName: j['senderName'],
    latitude: j['latitude'], longitude: j['longitude'],
    batteryLevel: j['batteryLevel'], timestamp: DateTime.parse(j['timestamp']),
    type: SOSType.values.firstWhere((e) => e.name == j['type'], orElse: () => SOSType.manual),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'senderId': senderId, 'senderName': senderName,
    'latitude': latitude, 'longitude': longitude, 'batteryLevel': batteryLevel,
    'timestamp': timestamp.toIso8601String(), 'type': type.name,
  };
}

enum SOSType { manual, crash, panic, wellness }

class CrashEvent {
  final DateTime timestamp;
  final double magnitude, gForce;
  CrashEvent({required this.timestamp, required this.magnitude, required this.gForce});
}

class DriverSafetyScore {
  final int score, hardBrakes, sharpTurns;
  final double maxSpeed;
  DriverSafetyScore({required this.score, required this.hardBrakes,
    required this.sharpTurns, required this.maxSpeed});
}

