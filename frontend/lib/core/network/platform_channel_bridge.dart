import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side Platform Channel Bridge (Req 17).
/// Provides typed Dart API to all three Java native modules.
class PlatformChannelBridge {
  static const _bleChannel    = MethodChannel('com.chaaya.meshlink/ble');
  static const _ksChannel     = MethodChannel('com.chaaya.meshlink/keystore');
  static const _panicChannel  = MethodChannel('com.chaaya.meshlink/panic');

  // Incoming event handlers
  void Function(String deviceId, List<int> data)? onBleData;
  void Function(String deviceId, String name, int rssi)? onDeviceDiscovered;
  void Function(String deviceId, bool connected)? onConnectionChanged;
  void Function(bool success)? onWipeComplete;
  void Function(String error)? onWipeError;

  static final PlatformChannelBridge _instance = PlatformChannelBridge._();
  PlatformChannelBridge._();
  factory PlatformChannelBridge() => _instance;

  void initialize() {
    _bleChannel.setMethodCallHandler(_handleBleCallback);
    _panicChannel.setMethodCallHandler(_handlePanicCallback);
    debugPrint('[Bridge] Platform Channel Bridge initialized');
  }

  // ─── BLE Methods (Req 17a) ───

  Future<void> startScan() => _callOrTimeout(_bleChannel, 'startScan');
  Future<void> stopScan()  => _callOrTimeout(_bleChannel, 'stopScan');

  Future<void> startAdvertise() => _callOrTimeout(_bleChannel, 'startAdvertise');
  Future<void> stopAdvertise()  => _callOrTimeout(_bleChannel, 'stopAdvertise');

  Future<void> connectToDevice(String deviceId) =>
      _callOrTimeout(_bleChannel, 'connect', {'deviceId': deviceId});

  Future<void> disconnect(String deviceId) =>
      _callOrTimeout(_bleChannel, 'disconnect', {'deviceId': deviceId});

  Future<void> writeToDevice(String deviceId, List<int> data) =>
      _callOrTimeout(_bleChannel, 'write', {'deviceId': deviceId, 'data': data});

  Future<List<String>> getConnectedDevices() async {
    final result = await _callOrTimeout(_bleChannel, 'getConnectedDevices');
    return List<String>.from(result ?? []);
  }

  // ─── KeyStore Methods (Req 17b) ───

  Future<void> generateKey({String alias = 'chaaya_identity'}) =>
      _callOrTimeout(_ksChannel, 'generateKey', {'alias': alias});

  Future<String?> getPublicKey({String alias = 'chaaya_identity'}) async {
    final result = await _callOrTimeout(_ksChannel, 'getPublicKey', {'alias': alias});
    return result as String?;
  }

  Future<String?> signData(List<int> data, {String alias = 'chaaya_identity'}) async {
    final result = await _callOrTimeout(_ksChannel, 'signData', {
      'alias': alias,
      'data': data,
    });
    return result as String?;
  }

  Future<void> deleteKey({String alias = 'chaaya_identity'}) =>
      _callOrTimeout(_ksChannel, 'deleteKey', {'alias': alias});

  Future<List<String>> listKeys() async {
    final result = await _callOrTimeout(_ksChannel, 'listKeys');
    return List<String>.from(result ?? []);
  }

  // ─── Panic Methods (Req 17c) ───

  /// Trigger panic wipe from Dart (e.g. settings button — Req 14)
  Future<void> triggerPanicWipe() =>
      _callOrTimeout(_panicChannel, 'triggerWipe');

  // ─── Private helpers ───

  Future<dynamic> _callOrTimeout(
    MethodChannel ch,
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return await ch.invokeMethod(method, args).timeout(
        const Duration(seconds: 5), // Req 17.5
        onTimeout: () => throw PlatformException(
          code: 'TIMEOUT',
          message: 'Method $method timed out after 5 seconds',
        ),
      );
    } on PlatformException catch (e) {
      // Req 17.4 — propagate as typed Dart exception
      throw ChaayaPlatformException(
        code: e.code,
        message: e.message ?? 'Platform error in $method',
        details: e.details,
      );
    }
  }

  Future<dynamic> _handleBleCallback(MethodCall call) async {
    switch (call.method) {
      case 'onData':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onBleData?.call(
          args['deviceId'] as String,
          List<int>.from(args['data'] as List),
        );
        break;
      case 'onDeviceDiscovered':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onDeviceDiscovered?.call(
          args['deviceId'] as String,
          args['name'] as String,
          args['rssi'] as int,
        );
        break;
      case 'onConnectionChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onConnectionChanged?.call(
          args['deviceId'] as String,
          args['connected'] as bool,
        );
        break;
    }
  }

  Future<dynamic> _handlePanicCallback(MethodCall call) async {
    switch (call.method) {
      case 'onWipeComplete':
        onWipeComplete?.call(call.arguments as bool);
        break;
      case 'onWipeError':
        onWipeError?.call(call.arguments as String);
        break;
    }
  }
}

/// Typed exception for platform channel errors (Req 17.4)
class ChaayaPlatformException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  ChaayaPlatformException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'ChaayaPlatformException[$code]: $message';
}
