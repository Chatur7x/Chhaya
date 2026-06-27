import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../features/contacts/data/contact_service.dart';
import '../../features/contacts/domain/models/contact.dart';

class PathResult {
  final List<String> path; // EXCLUDING the start node, INCLUDING the target
  final int distance;

  PathResult(this.path, this.distance);
}

class PathDiscoveryService {
  // Graph mapping deviceId -> set of neighbor deviceIds
  final Map<String, Set<String>> _graph = {};
  final ContactService _contactService;
  final String _myDeviceId;

  final _contactStatusController = StreamController<Map<String, ContactStatus>>.broadcast();
  Stream<Map<String, ContactStatus>> get contactStatuses => _contactStatusController.stream;

  PathDiscoveryService({
    required ContactService contactService,
    required String myDeviceId,
  })  : _contactService = contactService,
        _myDeviceId = myDeviceId;

  // Sync received from another node (A -> B, C)
  void updateGraphAndCalculate(String originId, List<String> neighbors) {
    if (!_graph.containsKey(originId)) {
      _graph[originId] = {};
    }
    _graph[originId]!.addAll(neighbors);

    // Bidirectional
    for (var n in neighbors) {
      if (!_graph.containsKey(n)) _graph[n] = {};
      _graph[n]!.add(originId);
    }
    
    _recalculateStatuses();
  }

  // Update direct neighbors (from BLE/WiFi)
  void updateDirectNeighbors(List<String> neighbors) {
    _graph[_myDeviceId] = neighbors.toSet();
    for (var n in neighbors) {
      if (!_graph.containsKey(n)) _graph[n] = {};
      _graph[n]!.add(_myDeviceId);
    }
    _recalculateStatuses();
  }

  void _recalculateStatuses() {
    final distances = _runDijkstra();
    final allContacts = _contactService.getAll();
    final statusMap = <String, ContactStatus>{};

    for (final contact in allContacts) {
      final dist = distances[contact.deviceId];
      if (dist == null || dist < 0) {
        contact.status = ContactStatus.unreachable;
      } else if (dist == 1) {
        contact.status = ContactStatus.nearby;
      } else if (dist <= 3) { // Max 3 hops relay (1->2->3->target)
        contact.status = ContactStatus.viaRelay;
      } else {
        contact.status = ContactStatus.unreachable; // Too far
      }
      statusMap[contact.deviceId] = contact.status;
    }

    _contactStatusController.add(statusMap);
  }

  Map<String, int> _runDijkstra() {
    final distances = <String, int>{};
    final unvisited = <String>{};

    for (final node in _graph.keys) {
      distances[node] = 999999;
      unvisited.add(node);
    }
    
    if (!_graph.containsKey(_myDeviceId)) return {};

    distances[_myDeviceId] = 0;

    while (unvisited.isNotEmpty) {
      // Find node with min distance
      String minNode = '';
      int minDist = 999999;
      for (final n in unvisited) {
        if (distances[n]! < minDist) {
          minDist = distances[n]!;
          minNode = n;
        }
      }

      if (minNode.isEmpty || minDist == 999999) break;

      unvisited.remove(minNode);

      final neighbors = _graph[minNode] ?? {};
      for (final neighbor in neighbors) {
        if (!unvisited.contains(neighbor)) continue;
        final alt = distances[minNode]! + 1; // Unweighted edges
        if (alt < distances[neighbor]!) {
          distances[neighbor] = alt;
        }
      }
    }
    return distances;
  }

  PathResult? getPathToTarget(String targetId) {
    if (!_graph.containsKey(_myDeviceId) || !_graph.containsKey(targetId)) return null;

    final distances = <String, int>{};
    final previous = <String, String>{};
    final unvisited = <String>{};

    for (final node in _graph.keys) {
      distances[node] = 999999;
      unvisited.add(node);
    }
    
    distances[_myDeviceId] = 0;

    while (unvisited.isNotEmpty) {
      String minNode = '';
      int minDist = 999999;
      for (final n in unvisited) {
        if (distances[n]! < minDist) {
          minDist = distances[n]!;
          minNode = n;
        }
      }

      if (minNode.isEmpty || minNode == targetId) break;
      unvisited.remove(minNode);

      final neighbors = _graph[minNode] ?? {};
      for (final neighbor in neighbors) {
        if (!unvisited.contains(neighbor)) continue;
        final alt = distances[minNode]! + 1;
        if (alt < distances[neighbor]!) {
          distances[neighbor] = alt;
          previous[neighbor] = minNode;
        }
      }
    }

    if (!previous.containsKey(targetId) && targetId != _myDeviceId) {
      return null;
    }

    final path = <String>[];
    String? current = targetId;
    while (current != null && current != _myDeviceId) {
      path.insert(0, current);
      current = previous[current];
    }
    
    return PathResult(path, distances[targetId]!);
  }
}
