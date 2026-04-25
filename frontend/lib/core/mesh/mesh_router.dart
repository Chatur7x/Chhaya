import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'mesh_message.dart';
import 'ble_mesh_service.dart';
import 'wifi_direct_service.dart';
import 'store_forward_service.dart';
import '../network/route_optimizer.dart';
import '../network/predictive_failure_detector.dart';

class MeshRouter {
  final BleMeshService bleService;
  final WifiDirectService? wifiService;
  final StoreForwardService? sfService;
  final String myDeviceId;

  /// Route optimizer for intelligent path selection
  RouteOptimizer? routeOptimizer;

  /// Predictive failure detector for proactive rerouting
  PredictiveFailureDetector? failureDetector;

  final Map<String, String> _routingTable = {};

  /// Full hop-count tracking per destination
  final Map<String, int> _hopCounts = {};

  /// Whether to compress messages before sending (saves BLE bandwidth)
  bool enableCompression = true;

  final _channelStatus = StreamController<ChannelStatus>.broadcast();
  Stream<ChannelStatus> get channelStatus => _channelStatus.stream;

  MeshRouter({
    required this.bleService,
    this.wifiService,
    this.sfService,
    required this.myDeviceId,
    this.routeOptimizer,
    this.failureDetector,
  }) {
    // Wire failure detector → proactive rerouting
    failureDetector?.failureStream.listen((prediction) {
      if (prediction.isImminent) {
        _handleImminentFailure(prediction.nodeId);
      }
    });
  }

  Future<SendResult> send(MeshMessage message) async {
    // Compress payload if enabled
    final messageToSend = enableCompression
        ? _compressMessage(message)
        : message;

    // 1. Try optimized route first (if RouteOptimizer is wired)
    if (routeOptimizer != null) {
      final route = routeOptimizer!.findBestRoute(myDeviceId, message.recipientId);
      if (route != null && route.isValid && route.nodeIds.length >= 2) {
        final nextHop = route.nodeIds[1]; // first hop after source
        debugPrint('[Router] Using optimized route: ${route.routeString}');
        _hopCounts[message.recipientId] = route.hopCount;

        if (bleService.isConnected(nextHop)) {
          final success = await bleService.sendMessage(messageToSend);
          if (success) {
            routeOptimizer!.recordRouteUsage(route,
                actualLatencyMs: 100, packetLoss: 0, delivered: true);
            _updateChannelStatus('ble');
            return SendResult(success: true, channel: 'ble', hopCount: route.hopCount);
          }
        }
      }
    }

    // 2. Direct BLE
    if (bleService.connectedPeerIds.isNotEmpty) {
      final success = await bleService.sendMessage(messageToSend);
      if (success) {
        _hopCounts[message.recipientId] = 1;
        _updateChannelStatus('ble');
        return SendResult(success: true, channel: 'ble', hopCount: 1);
      }
    }

    // 3. WiFi Direct
    if (wifiService != null && wifiService!.isConnected) {
      final peerId = wifiService!.connectedPeerId;
      if (peerId != null) {
        debugPrint('[Router] Sending via WiFi Direct');
        final success = await wifiService!.sendMessage(messageToSend);
        if (success) {
          _hopCounts[message.recipientId] = 1;
          _updateChannelStatus('wifi');
          return SendResult(success: true, channel: 'wifi', hopCount: 1);
        }
      }
    }

    // 4. Multi-hop relay
    final result = await _tryRelay(messageToSend);
    if (result.success) {
      return result;
    }

    // 5. Queue for later delivery
    debugPrint('[Router] All channels unavailable, queueing via SFQ');
    if (sfService != null) {
      await sfService!.enqueue(messageToSend);
    } else {
      await bleService.messageQueue.enqueue(messageToSend);
    }
    _updateChannelStatus('queued');
    return SendResult(success: false, channel: 'queued', hopCount: -1);
  }

  Future<SendResult> _tryRelay(MeshMessage message) async {
    // Prefer routing table entries
    final knownNextHop = _routingTable[message.recipientId];
    if (knownNextHop != null && bleService.isConnected(knownNextHop)) {
      final relayed = message.copyWith(
        hopCount: message.hopCount + 1,
        channel: 'ble',
      );
      final success = await bleService.sendMessage(relayed);
      if (success) {
        _updateChannelStatus('relay');
        return SendResult(
            success: true,
            channel: 'relay',
            hopCount: message.hopCount + 1);
      }
    }

    // Try all connected peers as relay
    for (final peerId in bleService.connectedPeerIds) {
      if (peerId != myDeviceId && peerId != knownNextHop) {
        debugPrint('[Router] Relaying via $peerId');
        final relayed = message.copyWith(
          hopCount: message.hopCount + 1,
          channel: 'ble',
        );
        final success = await bleService.sendMessage(relayed);
        if (success) {
          updateRoute(message.recipientId, peerId);
          _updateChannelStatus('relay');
          return SendResult(
              success: true,
              channel: 'relay',
              hopCount: message.hopCount + 1);
        }
      }
    }
    return SendResult(success: false, channel: 'none', hopCount: -1);
  }

  void updateRoute(String destinationId, String nextHopId) {
    _routingTable[destinationId] = nextHopId;
    debugPrint('[Router] Route: $destinationId via $nextHopId');
  }

  String? getNextHop(String destinationId) {
    return _routingTable[destinationId];
  }

  String getBestChannel(String contactDeviceId) {
    if (bleService.isConnected(contactDeviceId)) return 'ble';
    if (wifiService != null && wifiService!.isConnected) {
      final peerId = wifiService!.connectedPeerId;
      if (peerId == contactDeviceId) return 'wifi';
    }
    if (_routingTable.containsKey(contactDeviceId)) return 'relay';
    return 'none';
  }

  /// Returns actual tracked hop count for a destination, not a static guess.
  int getHopCount(String destinationId) {
    // Check tracked hop counts first
    if (_hopCounts.containsKey(destinationId)) {
      return _hopCounts[destinationId]!;
    }
    // Check direct connections
    if (bleService.isConnected(destinationId)) return 1;
    if (wifiService != null && wifiService!.isConnected) {
      final peerId = wifiService!.connectedPeerId;
      if (peerId == destinationId) return 1;
    }
    // Try RouteOptimizer for multi-hop
    if (routeOptimizer != null) {
      final route =
          routeOptimizer!.findBestRoute(myDeviceId, destinationId);
      if (route != null && route.isValid) {
        _hopCounts[destinationId] = route.hopCount;
        return route.hopCount;
      }
    }
    if (_routingTable.containsKey(destinationId)) return 2;
    return -1;
  }

  List<String> getAvailableChannels() {
    final channels = <String>[];
    if (bleService.connectedPeerIds.isNotEmpty) channels.add('ble');
    if (wifiService != null && wifiService!.isConnected) channels.add('wifi');
    return channels;
  }

  /// Compress a message payload using gzip to save BLE bandwidth.
  MeshMessage _compressMessage(MeshMessage message) {
    try {
      final contentBytes = utf8.encode(message.content);
      if (contentBytes.length < 64) return message; // not worth compressing
      final compressed = gzip.encode(contentBytes);
      // Only use compressed version if it's actually smaller
      if (compressed.length < contentBytes.length) {
        return message.copyWith(
          content: base64Encode(compressed),
          metadata: {
            ...?message.metadata,
            'compressed': true,
            'originalSize': contentBytes.length,
          },
        );
      }
    } catch (e) {
      debugPrint('[Router] Compression failed: $e');
    }
    return message;
  }

  /// Decompress a received message if it was compressed.
  static String decompressContent(MeshMessage message) {
    if (message.metadata?['compressed'] == true) {
      try {
        final compressed = base64Decode(message.content);
        final decompressed = gzip.decode(compressed);
        return utf8.decode(decompressed);
      } catch (e) {
        debugPrint('[Router] Decompression failed: $e');
      }
    }
    return message.content;
  }

  /// Handle imminent node failure by preemptively finding alternative routes.
  void _handleImminentFailure(String failingNodeId) {
    debugPrint('[Router] Node $failingNodeId failing — finding alternatives');

    // Find all destinations that route through the failing node
    final affectedDestinations = _routingTable.entries
        .where((e) => e.value == failingNodeId)
        .map((e) => e.key)
        .toList();

    for (final dest in affectedDestinations) {
      _routingTable.remove(dest);
      _hopCounts.remove(dest);

      // Try to find new route via RouteOptimizer
      if (routeOptimizer != null) {
        routeOptimizer!.updateNodeStatus(failingNodeId, isOnline: false);
        final newRoute = routeOptimizer!.findBestRoute(myDeviceId, dest);
        if (newRoute != null && newRoute.isValid && newRoute.nodeIds.length >= 2) {
          updateRoute(dest, newRoute.nodeIds[1]);
          _hopCounts[dest] = newRoute.hopCount;
          debugPrint('[Router] Rerouted $dest via ${newRoute.nodeIds[1]}');
        }
      }
    }
  }

  void _updateChannelStatus(String activeChannel) {
    int wifiPeers = (wifiService?.isConnected ?? false) ? 1 : 0;
    _channelStatus.add(ChannelStatus(
      activeChannel: activeChannel,
      isConnected: bleService.connectedPeerIds.isNotEmpty || wifiPeers > 0,
      peerCount: bleService.connectedPeerIds.length + wifiPeers,
    ));
  }

  ChannelStatus getCurrentStatus() {
    int wifiPeers = (wifiService?.isConnected ?? false) ? 1 : 0;
    return ChannelStatus(
      activeChannel: bleService.connectedPeerIds.isNotEmpty
          ? 'ble'
          : (wifiPeers > 0 ? 'wifi' : 'none'),
      isConnected: bleService.connectedPeerIds.isNotEmpty || wifiPeers > 0,
      peerCount: bleService.connectedPeerIds.length + wifiPeers,
    );
  }

  Future<void> dispose() async {
    await _channelStatus.close();
  }
}

class SendResult {
  final bool success;
  final String channel;
  final int hopCount;

  SendResult({
    required this.success,
    required this.channel,
    this.hopCount = -1,
  });
}

class ChannelStatus {
  final String activeChannel;
  final bool isConnected;
  final int peerCount;

  ChannelStatus({
    required this.activeChannel,
    required this.isConnected,
    required this.peerCount,
  });
}
