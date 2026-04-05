import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class NavigationWaypoint {
  final String nodeId;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  NavigationWaypoint({
    required this.nodeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
      };
}

class MultiHopRoute {
  final String destinationId;
  final String destinationName;
  final List<NavigationWaypoint> waypoints;
  final double totalDistance;
  final Duration estimatedTime;
  final DateTime calculatedAt;

  MultiHopRoute({
    required this.destinationId,
    required this.destinationName,
    required this.waypoints,
    required this.totalDistance,
    required this.estimatedTime,
    required this.calculatedAt,
  });

  String get routeDescription {
    if (waypoints.isEmpty) return 'Direct to $destinationName';
    return waypoints.map((w) => w.name).join(' -> ') + ' -> $destinationName';
  }

  int get hopCount => waypoints.length + 1;

  Map<String, dynamic> toJson() => {
        'destinationId': destinationId,
        'destinationName': destinationName,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'totalDistance': totalDistance,
        'estimatedTimeMinutes': estimatedTime.inMinutes,
        'hopCount': hopCount,
        'calculatedAt': calculatedAt.toIso8601String(),
      };
}

class MultiHopNavigator {
  final Map<String, Position> _nodeLocations = {};
  final Map<String, bool> _nodeOnline = {};

  final _routeController = StreamController<MultiHopRoute>.broadcast();
  Stream<MultiHopRoute> get routeStream => _routeController.stream;

  static const double _defaultHopDistance = 100;

  void updateNodeLocation(
      String nodeId, double latitude, double longitude, bool isOnline) {
    _nodeLocations[nodeId] = Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    _nodeOnline[nodeId] = isOnline;
  }

  List<String> getOnlineNodes() {
    return _nodeLocations.keys.where((id) => _nodeOnline[id] ?? false).toList();
  }

  MultiHopRoute? findRouteToNode(
    String destinationId,
    String destinationName, {
    double? currentLat,
    double? currentLng,
  }) {
    final onlineNodes = getOnlineNodes();
    if (onlineNodes.isEmpty) return null;

    final waypoints = <NavigationWaypoint>[];
    double totalDistance = 0;

    double currentLatValue = currentLat ?? 0;
    double currentLngValue = currentLng ?? 0;

    if (currentLat == null || currentLng == null) {
      final position = _nodeLocations.entries.firstOrNull;
      if (position != null) {
        currentLatValue = position.value.latitude;
        currentLngValue = position.value.longitude;
      }
    }

    final destLocation = _nodeLocations[destinationId];
    if (destLocation == null) return null;

    final directDistance = _calculateDistance(
      currentLatValue,
      currentLngValue,
      destLocation.latitude,
      destLocation.longitude,
    );

    if (directDistance <= _defaultHopDistance || onlineNodes.length < 2) {
      return MultiHopRoute(
        destinationId: destinationId,
        destinationName: destinationName,
        waypoints: [],
        totalDistance: directDistance,
        estimatedTime: Duration(minutes: (directDistance / 80 * 60).round()),
        calculatedAt: DateTime.now(),
      );
    }

    final sortedNodes = onlineNodes.where((id) => id != destinationId).toList()
      ..sort((a, b) {
        final distA = _calculateDistance(
            currentLatValue,
            currentLngValue,
            _nodeLocations[a]?.latitude ?? 0,
            _nodeLocations[a]?.longitude ?? 0);
        final distB = _calculateDistance(
            currentLatValue,
            currentLngValue,
            _nodeLocations[b]?.latitude ?? 0,
            _nodeLocations[b]?.longitude ?? 0);
        return distA.compareTo(distB);
      });

    double remainingLat = currentLatValue;
    double remainingLng = currentLngValue;

    for (final nodeId in sortedNodes.take(3)) {
      final nodeLocation = _nodeLocations[nodeId];
      if (nodeLocation == null) continue;

      final distance = _calculateDistance(
        remainingLat,
        remainingLng,
        nodeLocation.latitude,
        nodeLocation.longitude,
      );

      if (distance <= _defaultHopDistance * 1.5) {
        waypoints.add(NavigationWaypoint(
          nodeId: nodeId,
          name: 'Via $nodeId',
          latitude: nodeLocation.latitude,
          longitude: nodeLocation.longitude,
          timestamp: DateTime.now(),
        ));

        totalDistance += distance;
        remainingLat = nodeLocation.latitude;
        remainingLng = nodeLocation.longitude;
      }
    }

    final finalDistance = _calculateDistance(
      remainingLat,
      remainingLng,
      destLocation.latitude,
      destLocation.longitude,
    );
    totalDistance += finalDistance;

    final route = MultiHopRoute(
      destinationId: destinationId,
      destinationName: destinationName,
      waypoints: waypoints,
      totalDistance: totalDistance,
      estimatedTime: Duration(minutes: (totalDistance / 80 * 60).round()),
      calculatedAt: DateTime.now(),
    );

    _routeController.add(route);
    return route;
  }

  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * 3.14159265359 / 180;
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorCos(x);
  double _sqrt(double x) => x > 0 ? _newtonSqrt(x) : 0;
  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265359;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265359;
    if (x == 0 && y > 0) return 3.14159265359 / 2;
    if (x == 0 && y < 0) return -3.14159265359 / 2;
    return 0;
  }

  double _atan(double x) {
    if (x.abs() > 1) return (x > 0 ? 1 : -1) * 3.14159265359 / 2 - _atan(1 / x);
    double result = x, term = x;
    for (int i = 1; i < 15; i++) {
      term *= -x * x;
      result += term / (2 * i + 1);
    }
    return result;
  }

  double _taylorSin(double x) {
    x = x % (2 * 3.14159265359);
    if (x > 3.14159265359) x -= 2 * 3.14159265359;
    double result = x, term = x;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  double _taylorCos(double x) {
    x = x % (2 * 3.14159265359);
    double result = 1, term = 1;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  double _newtonSqrt(double x) {
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) guess = (guess + x / guess) / 2;
    return guess;
  }

  void dispose() {
    _routeController.close();
  }
}
