import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class LocationSafetyService {
  static const String _locBoxName = 'chaaya_locations';
  static const String _circleBoxName = 'chaaya_circles';
  static const String _sosBoxName = 'chaaya_sos';
  static const String _placesBoxName = 'chaaya_places';
  static const String _checkinBoxName = 'chaaya_checkins';

  Box<String>? _locationBox;
  Box<String>? _circlesBox;
  Box<String>? _sosHistoryBox;
  Box<String>? _namedPlacesBox;
  Box<String>? _checkinBox;

  final _locationUpdates =
      StreamController<Map<String, UserLocation>>.broadcast();
  final _sosAlerts = StreamController<SOSAlert>.broadcast();
  final _crashDetected = StreamController<CrashEvent>.broadcast();
  final _geofenceEvents = StreamController<GeofenceEvent>.broadcast();
  final _wellnessAlerts = StreamController<WellnessAlert>.broadcast();
  final _checkins = StreamController<CheckIn>.broadcast();
  final _drivingMode = StreamController<bool>.broadcast();

  Stream<Map<String, UserLocation>> get locationUpdates =>
      _locationUpdates.stream;
  Stream<SOSAlert> get sosAlerts => _sosAlerts.stream;
  Stream<CrashEvent> get crashDetected => _crashDetected.stream;
  Stream<GeofenceEvent> get geofenceEvents => _geofenceEvents.stream;
  Stream<WellnessAlert> get wellnessAlerts => _wellnessAlerts.stream;
  Stream<CheckIn> get checkins => _checkins.stream;
  Stream<bool> get drivingModeUpdates => _drivingMode.stream;

  final Map<String, UserLocation> _liveLocations = {};
  bool _isPrivateMode = false;
  bool _isDrivingMode = false;
  DateTime? _lastMovementTime;
  Timer? _wellnessTimer;

  Future<void> initialize() async {
    _locationBox = await Hive.openBox<String>(_locBoxName);
    _circlesBox = await Hive.openBox<String>(_circleBoxName);
    _sosHistoryBox = await Hive.openBox<String>(_sosBoxName);
    _namedPlacesBox = await Hive.openBox<String>(_placesBoxName);
    _checkinBox = await Hive.openBox<String>('chaaya_checkins');
    _startWellnessMonitor();
  }

  void _startWellnessMonitor() {
    _wellnessTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _checkWellness();
    });
  }

  void _checkWellness() {
    for (final entry in _liveLocations.entries) {
      final loc = entry.value;
      final inactive =
          DateTime.now().difference(loc.timestamp) > const Duration(hours: 2);
      if (inactive) {
        final alert = WellnessAlert(
          deviceId: entry.key,
          lastLocation: loc,
          inactiveDuration: DateTime.now().difference(loc.timestamp),
          timestamp: DateTime.now(),
        );
        _wellnessAlerts.add(alert);
      }
    }
  }

  void setPrivateMode(bool enabled) {
    _isPrivateMode = enabled;
    debugPrint('[Safety] Private mode: $enabled');
  }

  bool get isPrivateMode => _isPrivateMode;

  Future<void> updateMyLocation(double lat, double lon, double speed,
      double heading, int batteryLevel, String deviceId) async {
    final wasDriving = _isDrivingMode;

    if (speed > 10) {
      if (!_isDrivingMode) {
        _isDrivingMode = true;
        _drivingMode.add(true);
        debugPrint('[Safety] 🚗 Driving mode ON');
      }
    } else {
      if (_isDrivingMode && wasDriving) {
        _isDrivingMode = false;
        _drivingMode.add(false);
        debugPrint('[Safety] 🚶 Driving mode OFF');
      }
    }

    if (!_isPrivateMode) {
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
      checkGeofences(lat, lon);
    }
  }

  void receiveLocation(UserLocation location) {
    _liveLocations[location.deviceId] = location;
    _locationUpdates.add(Map.from(_liveLocations));
    final histKey =
        '${location.deviceId}_${location.timestamp.millisecondsSinceEpoch}';
    _locationBox?.put(histKey, jsonEncode(location.toJson()));
  }

  Map<String, UserLocation> get allLocations => Map.from(_liveLocations);

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

  List<LocationCircle> getCircles() {
    return _circlesBox?.values
            .map((j) => LocationCircle.fromJson(jsonDecode(j)))
            .toList() ??
        [];
  }

  Future<void> addMemberToCircle(String circleId, String deviceId) async {
    final circles = getCircles();
    final circle = circles.firstWhere((c) => c.id == circleId);
    final updated = LocationCircle(
      id: circle.id,
      name: circle.name,
      creatorId: circle.creatorId,
      members: [...circle.members, deviceId],
      createdAt: circle.createdAt,
    );
    await _circlesBox?.put(circleId, jsonEncode(updated.toJson()));
  }

  Future<void> removeMemberFromCircle(String circleId, String deviceId) async {
    final circles = getCircles();
    final circle = circles.firstWhere((c) => c.id == circleId);
    final updated = LocationCircle(
      id: circle.id,
      name: circle.name,
      creatorId: circle.creatorId,
      members: circle.members.where((m) => m != deviceId).toList(),
      createdAt: circle.createdAt,
    );
    await _circlesBox?.put(circleId, jsonEncode(updated.toJson()));
  }

  Future<void> deleteCircle(String circleId) async {
    await _circlesBox?.delete(circleId);
  }

  Future<CheckIn> checkIn(String deviceId, String username, double lat,
      double lon, String statusMessage) async {
    final checkin = CheckIn(
      id: const Uuid().v4(),
      deviceId: deviceId,
      username: username,
      latitude: lat,
      longitude: lon,
      statusMessage: statusMessage,
      timestamp: DateTime.now(),
    );
    await _checkinBox?.put(checkin.id, jsonEncode(checkin.toJson()));
    _checkins.add(checkin);
    debugPrint('[CheckIn] $username checked in: $statusMessage');
    return checkin;
  }

  List<CheckIn> getCheckIns({String? circleId}) {
    final checkins = _checkinBox?.values
            .map((j) => CheckIn.fromJson(jsonDecode(j)))
            .toList() ??
        [];
    if (circleId != null) {
      final circle = getCircles().firstWhere((c) => c.id == circleId,
          orElse: () => LocationCircle(
                id: '',
                name: '',
                creatorId: '',
                members: [],
                createdAt: DateTime.now(),
              ));
      return checkins
          .where((c) => circle.members.contains(c.deviceId))
          .toList();
    }
    return checkins..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> addPlace(NamedPlace place) async {
    await _namedPlacesBox?.put(place.id, jsonEncode(place.toJson()));
  }

  List<NamedPlace> getPlaces() {
    return _namedPlacesBox?.values
            .map((j) => NamedPlace.fromJson(jsonDecode(j)))
            .toList() ??
        [];
  }

  Future<void> deletePlace(String placeId) async {
    await _namedPlacesBox?.delete(placeId);
  }

  final Map<String, bool> _geofenceStates = {};

  List<GeofenceEvent> checkGeofences(double lat, double lon) {
    final events = <GeofenceEvent>[];
    for (final place in getPlaces()) {
      final dist =
          _haversineDistance(lat, lon, place.latitude, place.longitude);
      final isInside = dist <= place.radiusMeters;
      final wasInside = _geofenceStates[place.id] ?? false;

      if (isInside && !wasInside) {
        final event = GeofenceEvent(
            place: place, type: GeofenceType.enter, timestamp: DateTime.now());
        events.add(event);
        _geofenceEvents.add(event);
        _geofenceStates[place.id] = true;
        debugPrint('[Geofence] Entered ${place.name}');
      } else if (!isInside && wasInside) {
        final event = GeofenceEvent(
            place: place, type: GeofenceType.exit, timestamp: DateTime.now());
        events.add(event);
        _geofenceEvents.add(event);
        _geofenceStates[place.id] = false;
        debugPrint('[Geofence] Exited ${place.name}');
      }
    }
    return events;
  }

  Future<SOSAlert> triggerSOS(String deviceId, String username, double lat,
      double lon, int batteryLevel,
      {SOSType type = SOSType.manual}) async {
    final alert = SOSAlert(
      id: const Uuid().v4(),
      senderId: deviceId,
      senderName: username,
      latitude: lat,
      longitude: lon,
      batteryLevel: batteryLevel,
      timestamp: DateTime.now(),
      type: type,
    );
    await _sosHistoryBox?.put(alert.id, jsonEncode(alert.toJson()));
    _sosAlerts.add(alert);
    debugPrint(
        '[SOS] 🆘 ${type.name.toUpperCase()} ALERT from $username at ($lat, $lon)');
    return alert;
  }

  List<SOSAlert> getSOSHistory() {
    return _sosHistoryBox?.values
            .map((j) => SOSAlert.fromJson(jsonDecode(j)))
            .toList() ??
        [];
  }

  void analyzeAcceleration(double x, double y, double z) {
    final magnitude = sqrt(x * x + y * y + z * z);
    if (magnitude > 39.2) {
      final crash = CrashEvent(
          timestamp: DateTime.now(),
          magnitude: magnitude,
          gForce: magnitude / 9.8);
      _crashDetected.add(crash);
      debugPrint(
          '[Safety] ⚠️ CRASH DETECTED! ${crash.gForce.toStringAsFixed(1)}G');
    }
  }

  DriverSafetyScore calculateSafetyScore(List<UserLocation> tripPoints) {
    if (tripPoints.length < 2)
      return DriverSafetyScore(
          score: 100, hardBrakes: 0, sharpTurns: 0, maxSpeed: 0);
    int hardBrakes = 0, sharpTurns = 0;
    double maxSpeed = 0;
    for (int i = 1; i < tripPoints.length; i++) {
      final prev = tripPoints[i - 1], curr = tripPoints[i];
      if (curr.speed > maxSpeed) maxSpeed = curr.speed;
      if (prev.speed - curr.speed > 20) hardBrakes++;
      final headingDiff = (curr.heading - prev.heading).abs();
      if (headingDiff > 45 && headingDiff < 315) sharpTurns++;
    }
    return DriverSafetyScore(
        score: (100 - (hardBrakes * 10) - (sharpTurns * 5)).clamp(0, 100),
        hardBrakes: hardBrakes,
        sharpTurns: sharpTurns,
        maxSpeed: maxSpeed);
  }

  bool isUserInactive(String deviceId,
      {Duration threshold = const Duration(hours: 2)}) {
    final loc = _liveLocations[deviceId];
    if (loc == null) return true;
    return DateTime.now().difference(loc.timestamp) > threshold;
  }

  bool isDriving() => _isDrivingMode;

  Future<void> sendWellnessPing(String targetDeviceId) async {
    debugPrint('[Wellness] Ping sent to $targetDeviceId');
  }

  Future<RoadsideAlert> checkRoadsideAssistance(
      double lat, double lon, double speed) async {
    if (speed < 1 && _lastMovementTime != null) {
      final stationaryDuration = DateTime.now().difference(_lastMovementTime!);
      if (stationaryDuration.inMinutes > 10) {
        final alert = RoadsideAlert(
          id: const Uuid().v4(),
          latitude: lat,
          longitude: lon,
          stationaryMinutes: stationaryDuration.inMinutes,
          timestamp: DateTime.now(),
        );
        debugPrint(
            '[Roadside] ⚠️ Stationary alert: ${alert.stationaryMinutes} minutes');
        return alert;
      }
    }
    if (speed > 1) _lastMovementTime = DateTime.now();
    return RoadsideAlert(
        id: '',
        latitude: lat,
        longitude: lon,
        stationaryMinutes: 0,
        timestamp: DateTime.now());
  }

  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1), dLon = _toRad(lon2 - lon1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRad(lat1)) *
            _cos(_toRad(lat2)) *
            _sin(dLon / 2) *
            _sin(dLon / 2);
    return r * 2 * _atan2(_sqrt(a), _sqrt(1 - a));
  }

  double _toRad(double deg) => deg * 3.14159265 / 180;
  double _sin(double x) => x - (x * x * x) / 6;
  double _cos(double x) => 1 - (x * x) / 2;
  double _sqrt(double x) => x > 0 ? x * 0.5 + 0.5 : 0;
  double _atan2(double y, double x) => y / (x + 0.001);

  Future<void> clearAll() async {
    _liveLocations.clear();
    await _locationBox?.clear();
    await _circlesBox?.clear();
    await _sosHistoryBox?.clear();
    await _namedPlacesBox?.clear();
    if (_checkinBox != null) await _checkinBox!.clear();
  }

  void dispose() {
    _wellnessTimer?.cancel();
    _locationUpdates.close();
    _sosAlerts.close();
    _crashDetected.close();
    _geofenceEvents.close();
    _wellnessAlerts.close();
    _checkins.close();
    _drivingMode.close();
  }
}

class UserLocation {
  final String deviceId, name;
  final double latitude, longitude, altitude, speed, heading;
  final int batteryLevel;
  final DateTime timestamp;
  final double accuracy;

  UserLocation({
    required this.deviceId,
    this.name = '',
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.speed = 0,
    this.heading = 0,
    this.batteryLevel = 100,
    required this.timestamp,
    this.accuracy = 5,
  });

  factory UserLocation.fromJson(Map<String, dynamic> j) => UserLocation(
        deviceId: j['deviceId'],
        name: j['name'] ?? '',
        latitude: j['latitude'],
        longitude: j['longitude'],
        altitude: j['altitude'] ?? 0,
        speed: j['speed'] ?? 0,
        heading: j['heading'] ?? 0,
        batteryLevel: j['batteryLevel'] ?? 100,
        timestamp: DateTime.parse(j['timestamp']),
        accuracy: j['accuracy'] ?? 5,
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'batteryLevel': batteryLevel,
        'timestamp': timestamp.toIso8601String(),
        'accuracy': accuracy,
      };
}

class LocationCircle {
  final String id, name, creatorId;
  final List<String> members;
  final DateTime createdAt;

  LocationCircle(
      {required this.id,
      required this.name,
      required this.creatorId,
      required this.members,
      required this.createdAt});

  factory LocationCircle.fromJson(Map<String, dynamic> j) => LocationCircle(
        id: j['id'],
        name: j['name'],
        creatorId: j['creatorId'],
        members: List<String>.from(j['members'] ?? []),
        createdAt: DateTime.parse(j['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'creatorId': creatorId,
        'members': members,
        'createdAt': createdAt.toIso8601String(),
      };
}

class NamedPlace {
  final String id, name, icon;
  final double latitude, longitude, radiusMeters;

  NamedPlace(
      {required this.id,
      required this.name,
      this.icon = 'place',
      required this.latitude,
      required this.longitude,
      this.radiusMeters = 100});

  factory NamedPlace.fromJson(Map<String, dynamic> j) => NamedPlace(
        id: j['id'],
        name: j['name'],
        icon: j['icon'] ?? 'place',
        latitude: j['latitude'],
        longitude: j['longitude'],
        radiusMeters: j['radiusMeters'] ?? 100,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      };
}

class GeofenceEvent {
  final NamedPlace place;
  final GeofenceType type;
  final DateTime timestamp;
  GeofenceEvent(
      {required this.place, required this.type, required this.timestamp});
}

enum GeofenceType { enter, exit }

class SOSAlert {
  final String id, senderId, senderName;
  final double latitude, longitude;
  final int batteryLevel;
  final DateTime timestamp;
  final SOSType type;

  SOSAlert(
      {required this.id,
      required this.senderId,
      required this.senderName,
      required this.latitude,
      required this.longitude,
      required this.batteryLevel,
      required this.timestamp,
      required this.type});

  factory SOSAlert.fromJson(Map<String, dynamic> j) => SOSAlert(
        id: j['id'],
        senderId: j['senderId'],
        senderName: j['senderName'],
        latitude: j['latitude'],
        longitude: j['longitude'],
        batteryLevel: j['batteryLevel'],
        timestamp: DateTime.parse(j['timestamp']),
        type: SOSType.values.firstWhere((e) => e.name == j['type'],
            orElse: () => SOSType.manual),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'latitude': latitude,
        'longitude': longitude,
        'batteryLevel': batteryLevel,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
      };
}

enum SOSType { manual, crash, panic, wellness, roadside }

class CrashEvent {
  final DateTime timestamp;
  final double magnitude, gForce;
  CrashEvent(
      {required this.timestamp, required this.magnitude, required this.gForce});
}

class DriverSafetyScore {
  final int score, hardBrakes, sharpTurns;
  final double maxSpeed;
  DriverSafetyScore(
      {required this.score,
      required this.hardBrakes,
      required this.sharpTurns,
      required this.maxSpeed});
}

class CheckIn {
  final String id, deviceId, username, statusMessage;
  final double latitude, longitude;
  final DateTime timestamp;

  CheckIn(
      {required this.id,
      required this.deviceId,
      required this.username,
      required this.latitude,
      required this.longitude,
      required this.statusMessage,
      required this.timestamp});

  factory CheckIn.fromJson(Map<String, dynamic> j) => CheckIn(
        id: j['id'],
        deviceId: j['deviceId'],
        username: j['username'],
        latitude: j['latitude'],
        longitude: j['longitude'],
        statusMessage: j['statusMessage'],
        timestamp: DateTime.parse(j['timestamp']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'username': username,
        'latitude': latitude,
        'longitude': longitude,
        'statusMessage': statusMessage,
        'timestamp': timestamp.toIso8601String(),
      };
}

class WellnessAlert {
  final String deviceId;
  final UserLocation lastLocation;
  final Duration inactiveDuration;
  final DateTime timestamp;

  WellnessAlert(
      {required this.deviceId,
      required this.lastLocation,
      required this.inactiveDuration,
      required this.timestamp});
}

class RoadsideAlert {
  final String id;
  final double latitude, longitude;
  final int stationaryMinutes;
  final DateTime timestamp;

  RoadsideAlert(
      {required this.id,
      required this.latitude,
      required this.longitude,
      required this.stationaryMinutes,
      required this.timestamp});
}
