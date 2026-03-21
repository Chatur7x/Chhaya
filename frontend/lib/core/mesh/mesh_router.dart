import 'dart:async';
import 'package:flutter/foundation.dart';
import 'mesh_message.dart';
import 'ble_mesh_service.dart';

/// Chaaya Router — Auto-channel selection and message routing.
/// Priority: BLE → WiFi Direct → Morse Code
/// Handles routing table, hop counting, and dedup.
class MeshRouter {
  final BleMeshService bleService;
  final String myDeviceId;

  // Routing table: destination deviceId → next hop deviceId
  final Map<String, String> _routingTable = {};
  
  // Channel status
  final _channelStatus = StreamController<ChannelStatus>.broadcast();
  Stream<ChannelStatus> get channelStatus => _channelStatus.stream;

  MeshRouter({
    required this.bleService,
    required this.myDeviceId,
  });

  /// Send a message through the best available channel
  Future<SendResult> send(MeshMessage message) async {
    // Try BLE first (always available if peers are nearby)
    if (bleService.connectedPeerIds.isNotEmpty) {
      final success = await bleService.sendMessage(message);
      if (success) {
        _channelStatus.add(ChannelStatus(
          activeChannel: 'ble',
          isConnected: true,
          peerCount: bleService.connectedPeerIds.length,
        ));
        return SendResult(success: true, channel: 'ble');
      }
    }

    // WiFi Direct (future implementation)
    // TODO: Phase 2 — WiFi Direct transport

    // Morse code (future implementation)
    // TODO: Phase 6 — Morse code transport

    // All channels failed — queue the message
    debugPrint('[Router] All channels unavailable, queuing message');
    await bleService.messageQueue.enqueue(message);
    _channelStatus.add(ChannelStatus(
      activeChannel: 'none',
      isConnected: false,
      peerCount: 0,
    ));
    return SendResult(success: false, channel: 'queued');
  }

  /// Update routing table when a new peer is discovered
  void updateRoute(String destinationId, String nextHopId) {
    _routingTable[destinationId] = nextHopId;
    debugPrint('[Router] Route: $destinationId → $nextHopId');
  }

  /// Get next hop for a destination
  String? getNextHop(String destinationId) {
    return _routingTable[destinationId];
  }

  /// Get the best channel for a specific contact
  String getBestChannel(String contactDeviceId) {
    if (bleService.isConnected(contactDeviceId)) return 'ble';
    if (_routingTable.containsKey(contactDeviceId)) return 'relay';
    return 'none';
  }

  /// Get hop count to a destination
  int getHopCount(String destinationId) {
    if (bleService.isConnected(destinationId)) return 1;
    if (_routingTable.containsKey(destinationId)) return 2; // approximate
    return -1; // unreachable
  }

  /// Get current channel status
  ChannelStatus getCurrentStatus() {
    return ChannelStatus(
      activeChannel: bleService.connectedPeerIds.isNotEmpty ? 'ble' : 'none',
      isConnected: bleService.connectedPeerIds.isNotEmpty,
      peerCount: bleService.connectedPeerIds.length,
    );
  }

  Future<void> dispose() async {
    await _channelStatus.close();
  }
}

/// Result of a send attempt
class SendResult {
  final bool success;
  final String channel;

  SendResult({required this.success, required this.channel});
}

/// Current channel status
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

