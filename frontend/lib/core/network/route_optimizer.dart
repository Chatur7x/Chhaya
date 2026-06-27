import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../mesh/node_reputation.dart';

class NetworkNode {
  final String id;
  final String? name;
  final int signalStrength;
  final int bandwidthKbps;
  final double batteryLevel;
  final bool isOnline;
  final bool isRelay;
  final double latencyMs;
  final DateTime lastSeen;

  NetworkNode({
    required this.id,
    this.name,
    required this.signalStrength,
    required this.bandwidthKbps,
    required this.batteryLevel,
    required this.isOnline,
    this.isRelay = false,
    this.latencyMs = 0,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'signalStrength': signalStrength,
        'bandwidthKbps': bandwidthKbps,
        'batteryLevel': batteryLevel,
        'isOnline': isOnline,
        'isRelay': isRelay,
        'latencyMs': latencyMs,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory NetworkNode.fromJson(Map<String, dynamic> json) {
    return NetworkNode(
      id: json['id'],
      name: json['name'],
      signalStrength: json['signalStrength'],
      bandwidthKbps: json['bandwidthKbps'],
      batteryLevel: json['batteryLevel'].toDouble(),
      isOnline: json['isOnline'],
      isRelay: json['isRelay'] ?? false,
      latencyMs: json['latencyMs']?.toDouble() ?? 0,
      lastSeen: DateTime.parse(json['lastSeen']),
    );
  }
}

class NetworkLink {
  final String sourceId;
  final String targetId;
  final int cost;
  final int latencyMs;
  final int bandwidthKbps;
  final int reliability;
  final DateTime lastChecked;

  NetworkLink({
    required this.sourceId,
    required this.targetId,
    required this.cost,
    required this.latencyMs,
    required this.bandwidthKbps,
    required this.reliability,
    required this.lastChecked,
  });

  double get qualityScore {
    final latencyFactor = (2000 - latencyMs.clamp(0, 2000)) / 2000;
    final bandwidthFactor = bandwidthKbps / 1000;
    final reliabilityFactor = reliability / 100;
    return (latencyFactor * 0.4 +
        bandwidthFactor * 0.3 +
        reliabilityFactor * 0.3);
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'cost': cost,
        'latencyMs': latencyMs,
        'bandwidthKbps': bandwidthKbps,
        'reliability': reliability,
        'lastChecked': lastChecked.toIso8601String(),
      };
}

class Route {
  final List<String> nodeIds;
  final int totalCost;
  final double qualityScore;
  final int estimatedLatencyMs;
  final int availableBandwidthKbps;
  final DateTime calculatedAt;
  final String? failureReason;

  Route({
    required this.nodeIds,
    required this.totalCost,
    required this.qualityScore,
    required this.estimatedLatencyMs,
    required this.availableBandwidthKbps,
    required this.calculatedAt,
    this.failureReason,
  });

  bool get isValid => failureReason == null && nodeIds.isNotEmpty;

  int get hopCount => nodeIds.length - 1;

  String get routeString => nodeIds.join(' -> ');

  Map<String, dynamic> toJson() => {
        'nodeIds': nodeIds,
        'totalCost': totalCost,
        'qualityScore': qualityScore,
        'estimatedLatencyMs': estimatedLatencyMs,
        'availableBandwidthKbps': availableBandwidthKbps,
        'calculatedAt': calculatedAt.toIso8601String(),
        'failureReason': failureReason,
      };

  factory Route.fromJson(Map<String, dynamic> json) {
    return Route(
      nodeIds: List<String>.from(json['nodeIds']),
      totalCost: json['totalCost'],
      qualityScore: json['qualityScore'].toDouble(),
      estimatedLatencyMs: json['estimatedLatencyMs'],
      availableBandwidthKbps: json['availableBandwidthKbps'],
      calculatedAt: DateTime.parse(json['calculatedAt']),
      failureReason: json['failureReason'],
    );
  }
}

class RouteMetrics {
  final String routeId;
  final DateTime timestamp;
  final int latencyMs;
  final int packetLoss;
  final bool delivered;

  RouteMetrics({
    required this.routeId,
    required this.timestamp,
    required this.latencyMs,
    required this.packetLoss,
    required this.delivered,
  });
}

class RouteOptimizer {
  final Map<String, NetworkNode> _nodes = {};
  final Map<String, Map<String, NetworkLink>> _links = {};
  final NodeReputationSystem _reputationSystem;
  final Random _random = Random.secure();

  static const int _maxHops = 5;
  static const int _defaultLinkCost = 10;
  static const int _relayBonus = -5;
  static const int _lowBatteryPenalty = 20;
  static const int _weakSignalPenalty = 15;

  final List<RouteMetrics> _routeHistory = [];
  static const int _maxHistorySize = 100;

  final _routeUpdateController = StreamController<Route>.broadcast();
  Stream<Route> get routeUpdates => _routeUpdateController.stream;

  RouteOptimizer(this._reputationSystem);

  void addNode(NetworkNode node) {
    _nodes[node.id] = node;
    if (!_links.containsKey(node.id)) {
      _links[node.id] = {};
    }
  }

  void removeNode(String nodeId) {
    _nodes.remove(nodeId);
    _links.remove(nodeId);
    for (final links in _links.values) {
      links.remove(nodeId);
    }
  }

  void addLink(NetworkLink link) {
    _links[link.sourceId]?[link.targetId] = link;
  }

  void removeLink(String sourceId, String targetId) {
    _links[sourceId]?.remove(targetId);
  }

  void updateNodeStatus(String nodeId,
      {bool? isOnline, double? batteryLevel, int? signalStrength}) {
    final node = _nodes[nodeId];
    if (node != null) {
      _nodes[nodeId] = NetworkNode(
        id: node.id,
        name: node.name,
        signalStrength: signalStrength ?? node.signalStrength,
        bandwidthKbps: node.bandwidthKbps,
        batteryLevel: batteryLevel ?? node.batteryLevel,
        isOnline: isOnline ?? node.isOnline,
        isRelay: node.isRelay,
        latencyMs: node.latencyMs,
        lastSeen: DateTime.now(),
      );
    }
  }

  Route? findBestRoute(String sourceId, String destinationId,
      {Map<String, dynamic>? constraints}) {
    if (!_nodes.containsKey(sourceId) || !_nodes.containsKey(destinationId)) {
      return Route(
        nodeIds: [],
        totalCost: -1,
        qualityScore: 0,
        estimatedLatencyMs: 0,
        availableBandwidthKbps: 0,
        calculatedAt: DateTime.now(),
        failureReason: 'Source or destination not found',
      );
    }

    if (sourceId == destinationId) {
      return Route(
        nodeIds: [sourceId],
        totalCost: 0,
        qualityScore: 100,
        estimatedLatencyMs: 0,
        availableBandwidthKbps: 1000,
        calculatedAt: DateTime.now(),
      );
    }

    final candidates =
        _dijkstraWithConstraints(sourceId, destinationId, constraints);
    if (candidates.isEmpty) {
      return Route(
        nodeIds: [],
        totalCost: -1,
        qualityScore: 0,
        estimatedLatencyMs: 0,
        availableBandwidthKbps: 0,
        calculatedAt: DateTime.now(),
        failureReason: 'No route found',
      );
    }

    return candidates.first;
  }

  List<Route> findKBestRoutes(String sourceId, String destinationId,
      {int k = 3}) {
    if (!_nodes.containsKey(sourceId) || !_nodes.containsKey(destinationId)) {
      return [];
    }

    final candidates = _dijkstraWithConstraints(sourceId, destinationId, null);
    return candidates.take(k).toList();
  }

  List<Route> _dijkstraWithConstraints(String sourceId, String destinationId,
      Map<String, dynamic>? constraints) {
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final visited = <String>{};
    final candidates = <Route>[];

    for (final nodeId in _nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
    }
    distances[sourceId] = 0;

    while (visited.length < _nodes.length) {
      String? minNode;
      double minDist = double.infinity;

      for (final entry in distances.entries) {
        if (!visited.contains(entry.key) && entry.value < minDist) {
          minDist = entry.value;
          minNode = entry.key;
        }
      }

      if (minNode == null || minDist == double.infinity) break;

      visited.add(minNode);

      if (minNode == destinationId) {
        final route = _buildRoute(sourceId, destinationId, previous, distances);
        if (route != null) candidates.add(route);
        if (candidates.length >= 10) break;
        previous[destinationId] = null;
        distances[destinationId] = double.infinity;
        continue;
      }

      final links = _links[minNode] ?? {};
      for (final entry in links.entries) {
        final targetId = entry.key;
        final link = entry.value;

        if (visited.contains(targetId)) continue;

        if (!_nodes[targetId]!.isOnline) continue;

        if (constraints != null) {
          if (constraints.containsKey('minBandwidth') &&
              link.bandwidthKbps < constraints['minBandwidth']) {
            continue;
          }
          if (constraints.containsKey('maxLatency') &&
              link.latencyMs > constraints['maxLatency']) {
            continue;
          }
        }

        final reputation = _reputationSystem.getReputationScore(targetId);
        final reputationFactor = reputation / 100;
        final linkCost = (link.cost + _calculateNodePenalty(targetId)) *
            (1 - reputationFactor * 0.3);

        final newDist = distances[minNode]! + linkCost;
        if (newDist < distances[targetId]!) {
          distances[targetId] = newDist;
          previous[targetId] = minNode;
        }
      }
    }

    candidates.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    return candidates;
  }

  int _calculateNodePenalty(String nodeId) {
    int penalty = 0;
    final node = _nodes[nodeId];
    if (node == null) return 100;

    if (!node.isRelay) {
      penalty += _relayBonus;
    }

    if (node.batteryLevel < 0.2) {
      penalty += _lowBatteryPenalty;
    } else if (node.batteryLevel < 0.5) {
      penalty += (_lowBatteryPenalty / 2).round();
    }

    if (node.signalStrength < -80) {
      penalty += _weakSignalPenalty;
    } else if (node.signalStrength < -60) {
      penalty += (_weakSignalPenalty / 2).round();
    }

    return penalty;
  }

  Route? _buildRoute(String sourceId, String destinationId,
      Map<String, String?> previous, Map<String, double> distances) {
    final path = <String>[];
    String? current = destinationId;

    while (current != null) {
      path.add(current);
      current = previous[current];
    }

    if (path.isEmpty || path.last != sourceId) return null;

    // Reverse: path was built destination→source, we need source→destination
    final reversedPath = path.reversed.toList();

    if (reversedPath.length > _maxHops + 1) return null;

    int totalCost = 0;
    int totalLatency = 0;
    int minBandwidth = 10000;
    double totalQuality = 0;
    int linkCount = 0;

    for (int i = 0; i < reversedPath.length - 1; i++) {
      final link = _links[reversedPath[i]]?[reversedPath[i + 1]];
      if (link != null) {
        totalCost += link.cost;
        totalLatency += link.latencyMs;
        minBandwidth = minBandwidth < link.bandwidthKbps
            ? minBandwidth
            : link.bandwidthKbps;
        totalQuality += link.qualityScore;
        linkCount++;
      }
    }

    return Route(
      nodeIds: reversedPath,
      totalCost: totalCost,
      qualityScore: linkCount > 0 ? totalQuality / linkCount : 0,
      estimatedLatencyMs: totalLatency,
      availableBandwidthKbps: minBandwidth,
      calculatedAt: DateTime.now(),
    );
  }

  Route? findBackupRoute(String primaryRoute, String destinationId) {
    if (primaryRoute.isEmpty) return null;

    final primaryNodes = primaryRoute.split(' -> ');
    if (primaryNodes.length < 2) return null;

    final sourceId = primaryNodes.first;
    final candidates = _dijkstraWithConstraints(sourceId, destinationId, null);

    for (final route in candidates) {
      final hasOverlap = route.nodeIds
          .skip(1)
          .take(route.nodeIds.length - 2)
          .any((node) => primaryNodes.contains(node));
      if (!hasOverlap) {
        return route;
      }
    }

    return candidates.isNotEmpty ? candidates[1] : null;
  }

  void recordRouteUsage(Route route,
      {required int actualLatencyMs,
      required int packetLoss,
      required bool delivered}) {
    _routeHistory.add(RouteMetrics(
      routeId: route.routeString,
      timestamp: DateTime.now(),
      latencyMs: actualLatencyMs,
      packetLoss: packetLoss,
      delivered: delivered,
    ));

    if (_routeHistory.length > _maxHistorySize) {
      _routeHistory.removeAt(0);
    }

    for (final nodeId in route.nodeIds) {
      if (delivered) {
        _reputationSystem.recordRelayAttempt(nodeId, true, actualLatencyMs);
      } else {
        _reputationSystem.recordRelayAttempt(nodeId, false, actualLatencyMs);
      }
    }

    _routeUpdateController.add(route);
  }

  Map<String, dynamic> getRouteStatistics(String routeString) {
    final relevantMetrics =
        _routeHistory.where((m) => m.routeId == routeString).toList();

    if (relevantMetrics.isEmpty) {
      return {
        'totalAttempts': 0,
        'successRate': 0,
        'averageLatency': 0,
        'averagePacketLoss': 0,
      };
    }

    final delivered = relevantMetrics.where((m) => m.delivered).length;
    final avgLatency =
        relevantMetrics.map((m) => m.latencyMs).reduce((a, b) => a + b) /
            relevantMetrics.length;
    final avgPacketLoss =
        relevantMetrics.map((m) => m.packetLoss).reduce((a, b) => a + b) /
            relevantMetrics.length;

    return {
      'totalAttempts': relevantMetrics.length,
      'successfulDeliveries': delivered,
      'successRate': delivered / relevantMetrics.length,
      'averageLatencyMs': avgLatency.round(),
      'averagePacketLossPercent': avgPacketLoss.round(),
    };
  }

  List<NetworkNode> getAvailableRelays() {
    return _nodes.values
        .where((n) => n.isOnline && n.isRelay && n.batteryLevel > 0.1)
        .toList()
      ..sort((a, b) {
        final repA = _reputationSystem.getReputationScore(a.id);
        final repB = _reputationSystem.getReputationScore(b.id);
        return repB.compareTo(repA);
      });
  }

  Map<String, dynamic> getNetworkTopology() {
    return {
      'nodes': _nodes.values.map((n) => n.toJson()).toList(),
      'links': _links.entries
          .map((entry) => {
                'source': entry.key,
                'targets': entry.value.values.map((l) => l.toJson()).toList(),
              })
          .toList(),
      'stats': {
        'totalNodes': _nodes.length,
        'onlineNodes': _nodes.values.where((n) => n.isOnline).length,
        'relays': _nodes.values.where((n) => n.isRelay).length,
      },
    };
  }

  void dispose() {
    _routeUpdateController.close();
  }
}
