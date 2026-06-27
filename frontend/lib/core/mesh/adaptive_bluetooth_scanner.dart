import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'dart:math';
import '../network/predictive_failure_detector.dart';

enum DeviceRole { peer, relay, coordinator }

enum ScanMode { aggressive, balanced, conservative, sleep }

class AdaptiveBLEScanner {
  static const String _serviceUUID = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  final Battery _battery = Battery();

  ScanMode _currentMode = ScanMode.balanced;
  DeviceRole _deviceRole = DeviceRole.peer;
  Timer? _scanTimer;
  Timer? _dutyCycleTimer;
  int _batteryLevel = 100;
  bool _isMoving = false;
  bool _isScanning = false;
  int _scanIntervalMs = 5000;
  int _scanDurationMs = 2000;

  final _discoveredDevices =
      StreamController<List<BluetoothDevice>>.broadcast();
  final _connectionState = StreamController<Map<String, bool>>.broadcast();
  final _batteryState = StreamController<int>.broadcast();
  final _scanModeChanged = StreamController<ScanMode>.broadcast();

  Stream<List<BluetoothDevice>> get discoveredDevices =>
      _discoveredDevices.stream;
  Stream<Map<String, bool>> get connectionState => _connectionState.stream;
  Stream<int> get batteryLevel => _batteryState.stream;
  Stream<ScanMode> get scanModeChanges => _scanModeChanged.stream;

  ScanMode get currentMode => _currentMode;
  DeviceRole get deviceRole => _deviceRole;
  bool get isScanning => _isScanning;

  final Map<String, DateTime> _lastSeen = {};
  final Map<String, int> _connectionAttempts = {};
  final Map<String, bool> _connectedDevices = {};

  void initialize() {
    _startMovementDetection();
    _startBatteryMonitoring();
    _applyScanMode(_currentMode);
  }

  void _startMovementDetection() {
    Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          final wasMoving = _isMoving;
          _isMoving = position.speed > 1.0;

          if (wasMoving != _isMoving) {
            _onMovementChange();
          }
        }
      } catch (_) {}
    });
  }

  void _onMovementChange() {
    if (_isMoving) {
      setScanMode(ScanMode.aggressive);
    } else {
      setScanMode(ScanMode.balanced);
    }
  }

  void _startBatteryMonitoring() {
    // Get initial battery level asynchronously
    _fetchBatteryLevel();

    Timer.periodic(const Duration(minutes: 5), (_) {
      _fetchBatteryLevel();
    });
  }

  Future<void> _fetchBatteryLevel() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      _batteryState.add(_batteryLevel);
      _adjustForBatteryLevel();
    } catch (e) {
      debugPrint('[AdaptiveScanner] Battery read error: $e');
      // Keep last known value
    }
  }

  void _adjustForBatteryLevel() {
    if (_batteryLevel < 10) {
      setScanMode(ScanMode.sleep);
    } else if (_batteryLevel < 20) {
      setScanMode(ScanMode.conservative);
    } else if (_batteryLevel < 50) {
      if (_currentMode == ScanMode.aggressive) {
        setScanMode(ScanMode.balanced);
      }
    }
  }

  void setScanMode(ScanMode mode) {
    if (_currentMode == mode) return;

    _currentMode = mode;
    _applyScanMode(mode);
    _scanModeChanged.add(mode);
    debugPrint(
        '[AdaptiveScanner] Mode changed to: $mode (battery: $_batteryLevel%)');
  }

  void _applyScanMode(ScanMode mode) {
    _scanTimer?.cancel();
    _dutyCycleTimer?.cancel();

    switch (mode) {
      case ScanMode.aggressive:
        _scanIntervalMs = 2000;
        _scanDurationMs = 1500;
        _startContinuousScan();
        break;

      case ScanMode.balanced:
        _scanIntervalMs = 5000;
        _scanDurationMs = 2000;
        _startDutyCyclicScan();
        break;

      case ScanMode.conservative:
        _scanIntervalMs = 15000;
        _scanDurationMs = 1000;
        _startDutyCyclicScan();
        break;

      case ScanMode.sleep:
        _scanIntervalMs = 60000;
        _scanDurationMs = 500;
        _deviceRole = DeviceRole.peer;
        _startDutyCyclicScan();
        break;
    }
  }

  void _startContinuousScan() {
    _dutyCycleTimer?.cancel();
    startScan();
  }

  void _startDutyCyclicScan() {
    _dutyCycleTimer =
        Timer.periodic(Duration(milliseconds: _scanIntervalMs), (_) {
      if (!_isScanning) {
        startScan();
        Future.delayed(Duration(milliseconds: _scanDurationMs), stopScan);
      }
    });
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    final isSupported = await FlutterBluePlus.isSupported;
    if (isSupported == false) {
      debugPrint('[AdaptiveScanner] BLE not supported');
      return;
    }

    _isScanning = true;

    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        debugPrint('[AdaptiveScanner] BLE adapter off');
        _isScanning = false;
        return;
      }

      FlutterBluePlus.scanResults.listen((results) {
        final devices = results
            .where((r) => r.advertisementData.serviceUuids
                .any((uuid) => uuid.str.contains(_serviceUUID)))
            .map((r) => r.device)
            .toList();

        for (final device in devices) {
          _lastSeen[device.remoteId.str] = DateTime.now();
        }

        _discoveredDevices.add(devices);
      });

      await FlutterBluePlus.startScan(
        timeout: Duration(milliseconds: _scanDurationMs),
        continuousUpdates: true,
      );
    } catch (e) {
      debugPrint('[AdaptiveScanner] Scan error: $e');
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    _isScanning = false;

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[AdaptiveScanner] Stop scan error: $e');
    }
  }

  void setDeviceRole(DeviceRole role) {
    _deviceRole = role;

    switch (role) {
      case DeviceRole.coordinator:
        setScanMode(ScanMode.aggressive);
        break;
      case DeviceRole.relay:
        if (_batteryLevel > 30) {
          setScanMode(ScanMode.balanced);
        }
        break;
      case DeviceRole.peer:
        _adjustForBatteryLevel();
        break;
    }

    debugPrint('[AdaptiveScanner] Role set to: $role');
  }

  List<BluetoothDevice> getActiveDevices() {
    final now = DateTime.now();
    final activeThreshold = Duration(minutes: 5);

    return _lastSeen.entries
        .where((e) => now.difference(e.value) < activeThreshold)
        .map((e) => e.key)
        .toList()
        .cast<BluetoothDevice>();
  }

  bool isDeviceActive(String deviceId) {
    final lastSeen = _lastSeen[deviceId];
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen) < const Duration(minutes: 5);
  }

  void recordConnectionAttempt(String deviceId, bool success) {
    _connectionAttempts[deviceId] =
        (_connectionAttempts[deviceId] ?? 0) + (success ? 1 : 0);
  }

  double getConnectionSuccessRate(String deviceId) {
    final attempts = _connectionAttempts[deviceId] ?? 0;
    if (attempts == 0) return 1.0;
    final successes = min(attempts, successCount(deviceId));
    return successes / attempts;
  }

  int successCount(String deviceId) {
    return (_connectionAttempts[deviceId] ?? 0) ~/ 2;
  }

  /// Optional: wire to PredictiveFailureDetector for proactive scanning.
  PredictiveFailureDetector? _failureDetector;
  StreamSubscription? _failureSubscription;

  /// Connect a PredictiveFailureDetector.
  /// When imminent node failures are detected, scanner auto-switches
  /// to aggressive mode to discover replacement relay nodes.
  void wireFailureDetector(PredictiveFailureDetector detector) {
    _failureDetector = detector;
    _failureSubscription?.cancel();
    _failureSubscription = detector.failureStream.listen((prediction) {
      if (prediction.isImminent || prediction.isWarning) {
        debugPrint(
            '[AdaptiveScanner] Node ${prediction.nodeId} failing '
            '(${(prediction.probability * 100).round()}%) — aggressive scan');
        setScanMode(ScanMode.aggressive);
        // After 30 seconds, revert to normal battery-based mode
        Future.delayed(const Duration(seconds: 30), () {
          _adjustForBatteryLevel();
        });
      }
    });
  }

  /// Feed BLE scan RSSI data into the failure detector.
  /// Call this when processing scan results.
  void _feedFailureDetector(String deviceId, int rssi) {
    _failureDetector?.recordSignal(deviceId, rssi.toDouble());
  }

  Map<String, dynamic> getNetworkStats() {
    return {
      'scanMode': _currentMode.name,
      'deviceRole': _deviceRole.name,
      'batteryLevel': _batteryLevel,
      'isScanning': _isScanning,
      'isMoving': _isMoving,
      'activeDevices': getActiveDevices().length,
      'scanIntervalMs': _scanIntervalMs,
      'scanDurationMs': _scanDurationMs,
    };
  }

  void dispose() {
    _scanTimer?.cancel();
    _dutyCycleTimer?.cancel();
    _failureSubscription?.cancel();
    _discoveredDevices.close();
    _connectionState.close();
    _batteryState.close();
    _scanModeChanged.close();
  }
}

