import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'mesh_message.dart';
import 'message_queue.dart';

/// WiFi Direct Transport — peer-to-peer communication using flutter_p2p_connection v3.
class WifiDirectService {
  final MessageQueue messageQueue;
  final String myDeviceId;
  
  final _host = FlutterP2pHost();
  final _client = FlutterP2pClient();

  bool _isHost = false;
  bool _isConnected = false;
  String? _connectedPeerId;

  final _incomingMessages = StreamController<MeshMessage>.broadcast();
  final _connectionState = StreamController<WifiDirectState>.broadcast();
  final _discoveredPeers = StreamController<List<WifiDirectPeer>>.broadcast();

  Stream<MeshMessage> get incomingMessages => _incomingMessages.stream;
  Stream<WifiDirectState> get connectionState => _connectionState.stream;
  Stream<List<WifiDirectPeer>> get discoveredPeers => _discoveredPeers.stream;

  StreamSubscription? _clientStateSub;
  StreamSubscription? _hostStateSub;
  StreamSubscription? _clientTextSub;
  StreamSubscription? _hostTextSub;

  WifiDirectService({required this.messageQueue, required this.myDeviceId});

  Future<void> initialize() async {
    await _host.initialize();
    await _client.initialize();

    _clientTextSub = _client.streamReceivedTexts().listen(_handleIncomingText);
    _hostTextSub = _host.streamReceivedTexts().listen(_handleIncomingText);

    _hostStateSub = _host.streamHotspotState().listen((state) {
      if (state.isActive) {
        _isConnected = true;
        _connectionState.add(WifiDirectState.connected);
      } else {
        _isConnected = false;
        _connectionState.add(WifiDirectState.disconnected);
      }
    });

    _clientStateSub = _client.streamHotspotState().listen((state) {
      if (state.isActive) {
        _isConnected = true;
        _connectionState.add(WifiDirectState.connected);
      } else {
        _isConnected = false;
        _connectionState.add(WifiDirectState.disconnected);
      }
    });
  }

  void _handleIncomingText(String text) {
    try {
      final bytes = base64Decode(text);
      final msg = MeshMessage.fromBytes(bytes);
      _incomingMessages.add(msg);
    } catch (e) {
      debugPrint('[WiFi-Direct] Failed to parse message: $e');
    }
  }

  /// Start as WiFi Direct group owner (hotspot)
  Future<bool> startAsHost() async {
    try {
      debugPrint('[WiFi-Direct] Starting as group owner...');
      _connectionState.add(WifiDirectState.hosting);
      _isHost = true;
      final state = await _host.createGroup(advertise: true);
      return state.isActive;
    } catch (e) {
      debugPrint('[WiFi-Direct] Host start failed: $e');
      return false;
    }
  }

  /// Discover nearby WiFi Direct peers via BLE
  Future<void> discoverPeers() async {
    try {
      debugPrint('[WiFi-Direct] Discovering peers via BLE...');
      _connectionState.add(WifiDirectState.discovering);
      await _client.startScan((devices) {
        final mapped = devices.map((d) => WifiDirectPeer(
          deviceId: d.deviceAddress,
          name: d.deviceName,
          isGroupOwner: true, 
          rawDevice: d,
        )).toList();
        _discoveredPeers.add(mapped);
      });
    } catch (e) {
      debugPrint('[WiFi-Direct] Discovery failed: $e');
    }
  }

  /// Connect to a discovered peer
  Future<bool> connectToPeer(String peerId, [BleDiscoveredDevice? rawDevice]) async {
    try {
      debugPrint('[WiFi-Direct] Connecting...');
      _connectionState.add(WifiDirectState.connecting);
      if (rawDevice != null) {
        await _client.connectWithDevice(rawDevice);
        _connectedPeerId = peerId;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[WiFi-Direct] Connect failed: $e');
      return false;
    }
  }

  /// Send a mesh message over WiFi Direct (as Base64 text)
  Future<bool> sendMessage(MeshMessage message) async {
    if (!_isConnected) return false;
    try {
      final base64String = base64Encode(message.toBytes());
      if (_isHost) {
        await _host.broadcastText(base64String);
      } else {
        await _client.broadcastText(base64String);
      }
      return true;
    } catch (e) {
      debugPrint('[WiFi-Direct] Send failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_isHost) {
      await _host.removeGroup();
    } else {
      await _client.disconnect();
    }
    _isConnected = false;
    _connectedPeerId = null;
    _connectionState.add(WifiDirectState.disconnected);
  }

  bool get isConnected => _isConnected;
  bool get isHost => _isHost;
  String? get connectedPeerId => _connectedPeerId;

  Future<void> dispose() async {
    await disconnect();
    await _client.stopScan();
    await _clientTextSub?.cancel();
    await _hostTextSub?.cancel();
    await _clientStateSub?.cancel();
    await _hostStateSub?.cancel();
    await _host.dispose();
    await _client.dispose();
    await _incomingMessages.close();
    await _connectionState.close();
    await _discoveredPeers.close();
  }
}

enum WifiDirectState {
  idle,
  discovering,
  hosting,
  connecting,
  connected,
  disconnected,
  error,
}

class WifiDirectPeer {
  final String deviceId;
  final String name;
  final bool isGroupOwner;
  final BleDiscoveredDevice? rawDevice;

  WifiDirectPeer({
    required this.deviceId,
    required this.name,
    this.isGroupOwner = false,
    this.rawDevice,
  });
}
