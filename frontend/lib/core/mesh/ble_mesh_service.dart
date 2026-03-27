import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'mesh_message.dart';
import 'message_queue.dart';

/// BLE Mesh Service — Core transport layer for Chaaya.
/// Handles device discovery, connection, message sending/receiving,
/// and multi-hop relay routing over Bluetooth Low Energy.
class BleMeshService {
  // Chaaya BLE Service UUID
  static const String meshServiceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const String meshCharUuid = '12345678-1234-5678-1234-56789abcdef1';

  final MessageQueue messageQueue;
  final String _myDeviceId;
  
  // State
  bool _isScanning = false;
  bool _batterySaving = false;
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Set<String> _seenMessageIds = {}; // deduplication
  
  // Streams
  final _discoveredDevices = StreamController<List<MeshPeer>>.broadcast();
  final _incomingMessages = StreamController<MeshMessage>.broadcast();
  final _connectionStatus = StreamController<Map<String, MeshPeerStatus>>.broadcast();
  
  Stream<List<MeshPeer>> get discoveredDevices => _discoveredDevices.stream;
  Stream<MeshMessage> get incomingMessages => _incomingMessages.stream;
  Stream<Map<String, MeshPeerStatus>> get connectionStatus => _connectionStatus.stream;

  BleMeshService({
    required this.messageQueue,
    required String myDeviceId,
  }) : _myDeviceId = myDeviceId;

  /// Start scanning for nearby Chaaya devices
  Future<void> startDiscovery() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint('[BLE] Bluetooth not supported on this device');
        return;
      }

      // Wait for Bluetooth to be on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        debugPrint('[BLE] Bluetooth is off. Please turn it on.');
        return;
      }

      debugPrint('[BLE] Starting mesh discovery...');

      // Scan with configurable interval for battery saving
      final scanDuration = _batterySaving 
          ? const Duration(seconds: 4) 
          : const Duration(seconds: 10);

      FlutterBluePlus.startScan(
        timeout: scanDuration,
        withServices: [Guid(meshServiceUuid)],
      );

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        final peers = results
            .where((r) => r.advertisementData.serviceUuids
                .contains(Guid(meshServiceUuid)))
            .map((r) => MeshPeer(
                  device: r.device,
                  name: r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'Chaaya Device',
                  rssi: r.rssi,
                  lastSeen: DateTime.now(),
                ))
            .toList();

        _discoveredDevices.add(peers);
      });
    } catch (e) {
      debugPrint('[BLE] Discovery error: $e');
    }
  }

  /// Stop scanning
  Future<void> stopDiscovery() async {
    _isScanning = false;
    await FlutterBluePlus.stopScan();
  }

  /// Connect to a specific Chaaya peer
  Future<bool> connectToPeer(BluetoothDevice device) async {
    try {
      debugPrint('[BLE] Connecting to ${device.platformName}...');
      await device.connect(timeout: const Duration(seconds: 10));
      
      _connectedDevices[device.remoteId.str] = device;
      debugPrint('[BLE] Connected to ${device.platformName}');

      // Discover services
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid == Guid(meshServiceUuid)) {
          // Listen for incoming messages on the mesh characteristic
          for (final char in service.characteristics) {
            if (char.uuid == Guid(meshCharUuid)) {
              await char.setNotifyValue(true);
              char.onValueReceived.listen((bytes) {
                _handleIncomingData(bytes, device.remoteId.str);
              });
            }
          }
        }
      }

      // Flush queued messages for this device
      _flushQueueForDevice(device.remoteId.str);
      _broadcastConnections();

      return true;
    } catch (e) {
      debugPrint('[BLE] Connection failed: $e');
      return false;
    }
  }

  void _broadcastConnections() {
    final statusMap = <String, MeshPeerStatus>{};
    for (var id in _connectedDevices.keys) {
      statusMap[id] = MeshPeerStatus.nearby;
    }
    _connectionStatus.add(statusMap);
  }

  /// Send a message over BLE mesh
  Future<bool> sendMessage(MeshMessage message) async {
    final bytes = message.toBytes();

    // Check if recipient is directly connected
    if (_connectedDevices.containsKey(message.recipientId)) {
      return await _sendDirect(message.recipientId, bytes);
    }

    // Try relaying through connected peers
    for (final entry in _connectedDevices.entries) {
      if (entry.key != _myDeviceId) {
        final relayed = message.copyWith(
          hopCount: message.hopCount + 1,
          channel: 'ble',
        );
        final success = await _sendDirect(entry.key, relayed.toBytes());
        if (success) {
          debugPrint('[BLE] Relaying message via ${entry.key}');
          return true;
        }
      }
    }

    // No connected peers — queue the message
    debugPrint('[BLE] No peers available, queuing message');
    await messageQueue.enqueue(message);
    return false;
  }

  /// Direct send to a connected device
  Future<bool> _sendDirect(String deviceId, List<int> bytes) async {
    try {
      final device = _connectedDevices[deviceId];
      if (device == null) return false;

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid == Guid(meshServiceUuid)) {
          for (final char in service.characteristics) {
            if (char.uuid == Guid(meshCharUuid)) {
              // Split into chunks if needed (BLE MTU ~512 bytes)
              if (bytes.length <= 512) {
                await char.write(bytes);
              } else {
                // Chunked transfer
                for (var i = 0; i < bytes.length; i += 512) {
                  final end = (i + 512 < bytes.length) ? i + 512 : bytes.length;
                  await char.write(bytes.sublist(i, end));
                  await Future.delayed(const Duration(milliseconds: 50));
                }
              }
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint('[BLE] Send failed: $e');
      return false;
    }
  }

  /// Handle incoming BLE data
  void _handleIncomingData(List<int> bytes, String fromDeviceId) {
    try {
      final message = MeshMessage.fromBytes(bytes);

      // Deduplication — skip if we've seen this message
      if (_seenMessageIds.contains(message.id)) return;
      _seenMessageIds.add(message.id);

      // Keep dedup set manageable (max 1000 entries)
      if (_seenMessageIds.length > 1000) {
        _seenMessageIds.clear();
      }

      if (message.recipientId == _myDeviceId) {
        // Message is for us
        debugPrint('[BLE] Received message: ${message.content}');
        _incomingMessages.add(message);
      } else if (message.hopCount < message.maxHops) {
        // Not for us — relay if under hop limit
        debugPrint('[BLE] Relaying message (hop ${message.hopCount + 1})');
        final relayed = message.copyWith(hopCount: message.hopCount + 1);
        sendMessage(relayed);
      } else {
        debugPrint('[BLE] Message exceeded max hops, dropping');
      }
    } catch (e) {
      debugPrint('[BLE] Parse error: $e');
    }
  }

  /// Flush queued messages for a newly connected device
  void _flushQueueForDevice(String deviceId) {
    final queued = messageQueue.getForRecipient(deviceId);
    for (final msg in queued) {
      sendMessage(msg).then((success) {
        if (success) {
          messageQueue.dequeue(msg.id);
        }
      });
    }
  }

  /// Toggle battery saving mode
  void setBatterySaving(bool enabled) {
    _batterySaving = enabled;
    debugPrint('[BLE] Battery saving: ${enabled ? "ON" : "OFF"}');
  }

  /// Get currently connected peers
  List<String> get connectedPeerIds => _connectedDevices.keys.toList();

  /// Check if a specific device is connected
  bool isConnected(String deviceId) => _connectedDevices.containsKey(deviceId);

  /// Disconnect from all peers
  Future<void> disconnectAll() async {
    for (final device in _connectedDevices.values) {
      await device.disconnect();
    }
    _connectedDevices.clear();
  }

  Future<void> dispose() async {
    await stopDiscovery();
    await disconnectAll();
    await _discoveredDevices.close();
    await _incomingMessages.close();
    await _connectionStatus.close();
  }
}

/// Represents a discovered BLE mesh peer
class MeshPeer {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final DateTime lastSeen;

  MeshPeer({
    required this.device,
    required this.name,
    required this.rssi,
    required this.lastSeen,
  });

  /// Signal strength as a percentage (approximate)
  int get signalStrength {
    if (rssi >= -50) return 100;
    if (rssi >= -60) return 80;
    if (rssi >= -70) return 60;
    if (rssi >= -80) return 40;
    if (rssi >= -90) return 20;
    return 10;
  }
}

/// Peer connection status
enum MeshPeerStatus {
  nearby,      // direct BLE connection
  relay,       // reachable via relay hops
  unreachable, // not currently reachable
}

