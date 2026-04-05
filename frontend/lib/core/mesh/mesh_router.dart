import 'dart:async';
import 'package:flutter/foundation.dart';
import 'mesh_message.dart';
import 'ble_mesh_service.dart';
import 'wifi_direct_service.dart';
import 'store_forward_service.dart';

class MeshRouter {
  final BleMeshService bleService;
  final WifiDirectService? wifiService;
  final StoreForwardService? sfService;
  final String myDeviceId;

  final Map<String, String> _routingTable = {};

  final _channelStatus = StreamController<ChannelStatus>.broadcast();
  Stream<ChannelStatus> get channelStatus => _channelStatus.stream;

  MeshRouter({
    required this.bleService,
    this.wifiService,
    this.sfService,
    required this.myDeviceId,
  });

  Future<SendResult> send(MeshMessage message) async {
    if (bleService.connectedPeerIds.isNotEmpty) {
      final success = await bleService.sendMessage(message);
      if (success) {
        _updateChannelStatus('ble');
        return SendResult(success: true, channel: 'ble');
      }
    }

    if (wifiService != null && wifiService!.isConnected) {
      final peerId = wifiService!.connectedPeerId;
      if (peerId != null) {
        debugPrint('[Router] Sending via WiFi Direct');
        final success = await wifiService!.sendMessage(message);
        if (success) {
          _updateChannelStatus('wifi');
          return SendResult(success: true, channel: 'wifi');
        }
      }
    }

    final result = await _tryRelay(message);
    if (result.success) {
      return result;
    }

    debugPrint('[Router] All channels unavailable, queueing via SFQ');
    if (sfService != null) {
      await sfService!.enqueue(message);
    } else {
      await bleService.messageQueue.enqueue(message);
    }
    _updateChannelStatus('queued');
    return SendResult(success: false, channel: 'queued');
  }

  Future<SendResult> _tryRelay(MeshMessage message) async {
    for (final peerId in bleService.connectedPeerIds) {
      if (peerId != myDeviceId) {
        debugPrint('[Router] Relaying via $peerId');
        final relayed = message.copyWith(
          hopCount: message.hopCount + 1,
          channel: 'ble',
        );
        final success = await bleService.sendMessage(relayed);
        if (success) {
          updateRoute(message.recipientId, peerId);
          _updateChannelStatus('relay');
          return SendResult(success: true, channel: 'relay');
        }
      }
    }
    return SendResult(success: false, channel: 'none');
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

  int getHopCount(String destinationId) {
    if (bleService.isConnected(destinationId)) return 1;
    if (wifiService != null && wifiService!.isConnected) {
      final peerId = wifiService!.connectedPeerId;
      if (peerId == destinationId) return 1;
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

  SendResult({required this.success, required this.channel});
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
