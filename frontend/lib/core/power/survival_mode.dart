import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';

enum PowerMode { normal, survival, deepSleep }

class SurvivalConfig {
  final bool bleOnly;
  final bool uiRefreshOff;
  final Duration batchWindow;
  final bool sensorsOff;
  final int screenBrightness;
  final Duration scanInterval;
  final bool compressMessages;

  SurvivalConfig({
    this.bleOnly = true,
    this.uiRefreshOff = true,
    this.batchWindow = const Duration(hours: 1),
    this.sensorsOff = true,
    this.screenBrightness = 10,
    this.scanInterval = const Duration(minutes: 5),
    this.compressMessages = true,
  });

  static SurvivalConfig get aggressive => SurvivalConfig(
        bleOnly: true,
        uiRefreshOff: true,
        batchWindow: const Duration(hours: 2),
        sensorsOff: true,
        screenBrightness: 5,
        scanInterval: const Duration(minutes: 10),
        compressMessages: true,
      );

  static SurvivalConfig get moderate => SurvivalConfig(
        bleOnly: true,
        uiRefreshOff: false,
        batchWindow: const Duration(minutes: 30),
        sensorsOff: false,
        screenBrightness: 15,
        scanInterval: const Duration(minutes: 5),
        compressMessages: true,
      );

  static SurvivalConfig get normal => SurvivalConfig();
}

class SurvivalMode {
  PowerMode _currentMode = PowerMode.normal;
  SurvivalConfig _config = SurvivalConfig();
  final Battery _battery = Battery();

  bool _isEnabled = false;
  DateTime? _enabledAt;
  double _originalBrightness = 1.0;

  final _modeController = StreamController<PowerMode>.broadcast();
  Stream<PowerMode> get modeStream => _modeController.stream;

  final _statsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;

  int _messagesBatched = 0;
  int _messagesSent = 0;
  Duration _totalBatterySavings = Duration.zero;
  DateTime? _lastSyncTime;

  PowerMode get currentMode => _currentMode;
  bool get isEnabled => _isEnabled;
  SurvivalConfig get config => _config;
  int get messagesBatched => _messagesBatched;
  int get messagesSent => _messagesSent;

  Future<void> enable({SurvivalConfig? config}) async {
    if (_isEnabled) return;

    _config = config ?? _calculateConfig();
    _isEnabled = true;
    _enabledAt = DateTime.now();
    _messagesBatched = 0;
    _messagesSent = 0;

    await _applyPowerMode(PowerMode.survival);
    _emitStats();
    debugPrint('Survival Mode enabled');
  }

  Future<void> disable() async {
    if (!_isEnabled) return;

    final duration = DateTime.now().difference(_enabledAt ?? DateTime.now());
    _totalBatterySavings += duration;
    _isEnabled = false;
    _enabledAt = null;

    await _restoreNormalMode();
    _emitStats();
    debugPrint('Survival Mode disabled');
  }

  SurvivalConfig _calculateConfig() {
    return SurvivalConfig.aggressive;
  }

  Future<void> _applyPowerMode(PowerMode mode) async {
    _currentMode = mode;
    _modeController.add(mode);

    switch (mode) {
      case PowerMode.normal:
        break;
      case PowerMode.survival:
        await _applySurvivalSettings();
        break;
      case PowerMode.deepSleep:
        await _applyDeepSleepSettings();
        break;
    }
  }

  Future<void> _applySurvivalSettings() async {
    debugPrint('Applying survival settings: BLE only, batched transmissions');
  }

  Future<void> _applyDeepSleepSettings() async {
    debugPrint('Applying deep sleep settings: minimal activity');
  }

  Future<void> _restoreNormalMode() async {
    debugPrint('Restoring normal mode settings');
  }

  void batchMessage() {
    if (!_isEnabled) return;
    _messagesBatched++;
    _emitStats();
  }

  void flushBatch() {
    if (!_isEnabled || _messagesBatched == 0) return;

    _messagesSent += _messagesBatched;
    _messagesBatched = 0;
    _lastSyncTime = DateTime.now();
    _emitStats();
  }

  Future<void> checkAndAutoEnable() async {
    try {
      final level = await _battery.batteryLevel;
      if (level <= 10) {
        await enable(config: SurvivalConfig.aggressive);
      } else if (level <= 20) {
        if (!_isEnabled) {
          await enable(config: SurvivalConfig.moderate);
        }
      }
    } catch (e) {
      debugPrint('Error checking battery: $e');
    }
  }

  void switchMode(PowerMode mode) {
    _currentMode = mode;
    _modeController.add(mode);
    _emitStats();
  }

  Duration estimateBatteryLife() {
    if (!_isEnabled) return Duration.zero;

    switch (_currentMode) {
      case PowerMode.normal:
        return const Duration(days: 1);
      case PowerMode.survival:
        return const Duration(days: 3);
      case PowerMode.deepSleep:
        return const Duration(days: 7);
    }
  }

  void _emitStats() {
    _statsController.add({
      'mode': _currentMode.name,
      'isEnabled': _isEnabled,
      'messagesBatched': _messagesBatched,
      'messagesSent': _messagesSent,
      'enabledDuration': _enabledAt != null
          ? DateTime.now().difference(_enabledAt!).inMinutes
          : 0,
      'estimatedBatteryLife': estimateBatteryLife().inHours,
      'config': {
        'bleOnly': _config.bleOnly,
        'uiRefreshOff': _config.uiRefreshOff,
        'batchWindow': _config.batchWindow.inMinutes,
        'sensorsOff': _config.sensorsOff,
        'scanInterval': _config.scanInterval.inMinutes,
      },
    });
  }

  Map<String, dynamic> getStatistics() {
    return {
      'currentMode': _currentMode.name,
      'isEnabled': _isEnabled,
      'enabledAt': _enabledAt?.toIso8601String(),
      'messagesBatched': _messagesBatched,
      'messagesSent': _messagesSent,
      'totalBatterySavingsMinutes': _totalBatterySavings.inMinutes,
      'estimatedBatteryLifeHours': estimateBatteryLife().inHours,
    };
  }

  void dispose() {
    _modeController.close();
    _statsController.close();
  }
}
