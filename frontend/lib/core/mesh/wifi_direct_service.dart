import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'mesh_message.dart';
import 'message_queue.dart';

/// WiFi Direct Transport — peer-to-peer communication for voice, video, and large files.
/// Range: ~200m. Used when BLE bandwidth is insufficient.
class WifiDirectService {
  final MessageQueue messageQueue;
  final String myDeviceId;

  bool _isHost = false;
  bool _isConnected = false;
  String? _connectedPeerId;

  final _incomingMessages = StreamController<MeshMessage>.broadcast();
  final _connectionState = StreamController<WifiDirectState>.broadcast();
  final _discoveredPeers = StreamController<List<WifiDirectPeer>>.broadcast();

  Stream<MeshMessage> get incomingMessages => _incomingMessages.stream;
  Stream<WifiDirectState> get connectionState => _connectionState.stream;
  Stream<List<WifiDirectPeer>> get discoveredPeers => _discoveredPeers.stream;

  WifiDirectService({required this.messageQueue, required this.myDeviceId});

  /// Start as WiFi Direct group owner (hotspot)
  Future<bool> startAsHost() async {
    try {
      debugPrint('[WiFi-Direct] Starting as group owner...');
      _isHost = true;
      _connectionState.add(WifiDirectState.hosting);
      // In production: use flutter_p2p_connection to create group
      return true;
    } catch (e) {
      debugPrint('[WiFi-Direct] Host start failed: $e');
      return false;
    }
  }

  /// Discover nearby WiFi Direct peers
  Future<void> discoverPeers() async {
    try {
      debugPrint('[WiFi-Direct] Discovering peers...');
      _connectionState.add(WifiDirectState.discovering);
      // In production: use flutter_p2p_connection to discover
      // Emit mock peers for now — real device discovery will populate this
    } catch (e) {
      debugPrint('[WiFi-Direct] Discovery failed: $e');
    }
  }

  /// Connect to a peer
  Future<bool> connectToPeer(String peerId) async {
    try {
      debugPrint('[WiFi-Direct] Connecting to $peerId...');
      _connectedPeerId = peerId;
      _isConnected = true;
      _connectionState.add(WifiDirectState.connected);
      return true;
    } catch (e) {
      debugPrint('[WiFi-Direct] Connect failed: $e');
      return false;
    }
  }

  /// Send data over WiFi Direct (high bandwidth — voice, video, large files)
  Future<bool> sendData(List<int> data) async {
    if (!_isConnected) {
      debugPrint('[WiFi-Direct] Not connected');
      return false;
    }
    try {
      // In production: use socket communication over WiFi Direct
      debugPrint('[WiFi-Direct] Sent ${data.length} bytes');
      return true;
    } catch (e) {
      debugPrint('[WiFi-Direct] Send failed: $e');
      return false;
    }
  }

  /// Send a mesh message over WiFi Direct
  Future<bool> sendMessage(MeshMessage message) async {
    final bytes = message.toBytes();
    return sendData(bytes);
  }

  /// Stream audio/video data (for calls and PTT)
  Stream<List<int>> receiveStream() {
    // In production: use TCP/UDP socket over WiFi Direct
    return const Stream.empty();
  }

  /// Disconnect
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPeerId = null;
    _connectionState.add(WifiDirectState.disconnected);
  }

  bool get isConnected => _isConnected;
  bool get isHost => _isHost;
  String? get connectedPeerId => _connectedPeerId;

  Future<void> dispose() async {
    await disconnect();
    await _incomingMessages.close();
    await _connectionState.close();
    await _discoveredPeers.close();
  }
}

/// WiFi Direct connection states
enum WifiDirectState {
  idle,
  discovering,
  hosting,
  connecting,
  connected,
  disconnected,
  error,
}

/// A discovered WiFi Direct peer
class WifiDirectPeer {
  final String deviceId;
  final String name;
  final bool isGroupOwner;

  WifiDirectPeer({
    required this.deviceId,
    required this.name,
    this.isGroupOwner = false,
  });
}
