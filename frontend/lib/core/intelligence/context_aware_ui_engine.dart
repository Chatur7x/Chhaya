import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';

enum AppContext {
  normal,
  emergency,
  travel,
  lowBattery,
  offline,
  stealth,
  disaster,
  tactical,
}

class ContextState {
  final AppContext context;
  final double confidence;
  final Map<String, dynamic> signals;
  final DateTime timestamp;

  ContextState({
    required this.context,
    required this.confidence,
    required this.signals,
    required this.timestamp,
  });

  ContextState copyWith({
    AppContext? context,
    double? confidence,
    Map<String, dynamic>? signals,
    DateTime? timestamp,
  }) {
    return ContextState(
      context: context ?? this.context,
      confidence: confidence ?? this.confidence,
      signals: signals ?? this.signals,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class AutoSuggestion {
  final String message;
  final String action;
  final String? icon;
  final DateTime createdAt;
  bool dismissed;

  AutoSuggestion({
    required this.message,
    required this.action,
    this.icon,
    required this.createdAt,
    this.dismissed = false,
  });
}

class ContextAwareUIEngine {
  AppContext _currentContext = AppContext.normal;
  final Map<AppContext, double> _contextWeights = {};
  final List<AutoSuggestion> _suggestions = [];

  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _locationSubscription;

  final _contextController = StreamController<ContextState>.broadcast();
  Stream<ContextState> get contextStream => _contextController.stream;

  final _suggestionController = StreamController<AutoSuggestion>.broadcast();
  Stream<AutoSuggestion> get suggestionStream => _suggestionController.stream;

  Battery _battery = Battery();
  Position? _lastPosition;
  double _lastMovementSpeed = 0;
  DateTime? _lastMovementTime;
  int _connectedNodes = 0;
  bool _isNetworkOnline = false;
  bool _hasActiveSOSNearby = false;

  static const Duration _updateInterval = Duration(seconds: 5);
  Timer? _updateTimer;

  AppContext get currentContext => _currentContext;
  List<AutoSuggestion> get suggestions =>
      _suggestions.where((s) => !s.dismissed).toList();

  Future<void> initialize() async {
    _initializeAccelerometer();
    _initializeLocation();
    _startPeriodicUpdate();
    await _evaluateContext();
    debugPrint('ContextAwareUIEngine initialized');
  }

  void _initializeAccelerometer() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final magnitude =
          (event.x * event.x + event.y * event.y + event.z * event.z);
      if (magnitude > 400) {
        _detectSuddenMovement();
      }
    });
  }

  void _initializeLocation() {
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.medium),
    ).listen((position) {
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _lastMovementSpeed = distance / 5;
        _lastMovementTime = DateTime.now();
      }
      _lastPosition = position;
    });
  }

  void _startPeriodicUpdate() {
    _updateTimer = Timer.periodic(_updateInterval, (_) => _evaluateContext());
  }

  void _detectSuddenMovement() {
    _addSuggestion(
      'Sudden movement detected',
      'Check surroundings',
      '!',
    );
  }

  Future<void> _evaluateContext() async {
    _contextWeights.clear();

    _contextWeights[AppContext.emergency] = _evaluateEmergency();
    _contextWeights[AppContext.lowBattery] = await _evaluateBattery();
    _contextWeights[AppContext.offline] = _evaluateOffline();
    _contextWeights[AppContext.travel] = _evaluateTravel();
    _contextWeights[AppContext.disaster] = _evaluateDisaster();
    _contextWeights[AppContext.tactical] = _evaluateTactical();
    _contextWeights[AppContext.stealth] = _evaluateStealth();
    _contextWeights[AppContext.normal] = _evaluateNormal();

    final maxEntry =
        _contextWeights.entries.reduce((a, b) => a.value > b.value ? a : b);

    if (maxEntry.value > 0.5) {
      _currentContext = maxEntry.key;
    } else {
      _currentContext = AppContext.normal;
    }

    _checkAutoSuggestions();

    _contextController.add(ContextState(
      context: _currentContext,
      confidence: maxEntry.value,
      signals: Map.from(_contextWeights),
      timestamp: DateTime.now(),
    ));
  }

  double _evaluateEmergency() {
    if (_hasActiveSOSNearby) return 1.0;
    return 0.0;
  }

  Future<double> _evaluateBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (level <= 10) return 1.0;
      if (level <= 20) return 0.7;
      if (level <= 30) return 0.4;
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double _evaluateOffline() {
    if (!_isNetworkOnline && _connectedNodes == 0) return 1.0;
    if (!_isNetworkOnline) return 0.7;
    return 0.0;
  }

  double _evaluateTravel() {
    if (_lastMovementSpeed > 5) return 0.8;
    if (_lastMovementSpeed > 2) return 0.5;
    return 0.0;
  }

  double _evaluateDisaster() {
    return 0.0;
  }

  double _evaluateTactical() {
    if (_connectedNodes >= 5) return 0.6;
    return 0.0;
  }

  double _evaluateStealth() {
    return 0.0;
  }

  double _evaluateNormal() {
    double weight = 1.0;

    for (final entry in _contextWeights.entries) {
      if (entry.key != AppContext.normal && entry.value > 0.3) {
        weight -= entry.value * 0.3;
      }
    }

    return weight.clamp(0.0, 1.0);
  }

  void _checkAutoSuggestions() {
    if (_currentContext == AppContext.offline && _connectedNodes == 0) {
      _addSuggestion(
        "You're offline",
        "Enable relay mode?",
        "!",
      );
    }

    if (_currentContext == AppContext.lowBattery) {
      _addSuggestion(
        "Low battery",
        "Switch to Survival Mode?",
        "!",
      );
    }

    if (_hasActiveSOSNearby) {
      _addSuggestion(
        "SOS signal nearby",
        "Respond to emergency?",
        "!",
      );
    }

    if (_lastMovementTime != null) {
      final hoursSinceMovement =
          DateTime.now().difference(_lastMovementTime!).inHours;
      if (hoursSinceMovement >= 6) {
        _addSuggestion(
          "No movement detected for $hoursSinceMovement hours",
          "Send check-in?",
          "?",
        );
      }
    }
  }

  void _addSuggestion(String message, String action, [String? icon]) {
    if (_suggestions.any((s) => s.message == message && !s.dismissed)) return;

    final suggestion = AutoSuggestion(
      message: message,
      action: action,
      icon: icon,
      createdAt: DateTime.now(),
    );

    _suggestions.insert(0, suggestion);
    if (_suggestions.length > 10) {
      _suggestions.removeLast();
    }

    _suggestionController.add(suggestion);
  }

  void updateNetworkStatus(
      {required bool isOnline, required int connectedNodes}) {
    _isNetworkOnline = isOnline;
    _connectedNodes = connectedNodes;
    _evaluateContext();
  }

  void updateSOSStatus(bool hasNearbySOS) {
    _hasActiveSOSNearby = hasNearbySOS;
    if (hasNearbySOS) {
      _currentContext = AppContext.emergency;
      _contextController.add(ContextState(
        context: AppContext.emergency,
        confidence: 1.0,
        signals: _contextWeights,
        timestamp: DateTime.now(),
      ));
    }
  }

  void setContextManually(AppContext context) {
    _currentContext = context;
    _contextController.add(ContextState(
      context: context,
      confidence: 1.0,
      signals: {'manual': true},
      timestamp: DateTime.now(),
    ));
  }

  void dismissSuggestion(int index) {
    if (index < _suggestions.length) {
      _suggestions[index].dismissed = true;
    }
  }

  void dismissSuggestionByMessage(String message) {
    final suggestion = _suggestions.firstWhere(
      (s) => s.message == message,
      orElse: () =>
          AutoSuggestion(message: '', action: '', createdAt: DateTime.now()),
    );
    suggestion.dismissed = true;
  }

  ThemeData getThemeForContext(AppContext context, ThemeData baseTheme) {
    switch (context) {
      case AppContext.emergency:
      case AppContext.disaster:
        return _createEmergencyTheme(baseTheme);
      case AppContext.lowBattery:
        return _createDarkTheme(baseTheme);
      case AppContext.tactical:
        return _createTacticalTheme(baseTheme);
      case AppContext.stealth:
        return _createStealthTheme(baseTheme);
      default:
        return baseTheme;
    }
  }

  ThemeData _createEmergencyTheme(ThemeData base) {
    return base.copyWith(
      primaryColor: Colors.red,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.red,
        brightness: Brightness.light,
      ),
    );
  }

  ThemeData _createDarkTheme(ThemeData base) {
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: base.colorScheme.primary,
        brightness: Brightness.dark,
      ),
    );
  }

  ThemeData _createTacticalTheme(ThemeData base) {
    return base.copyWith(
      primaryColor: Colors.green.shade800,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green.shade800,
        brightness: Brightness.dark,
      ),
    );
  }

  ThemeData _createStealthTheme(ThemeData base) {
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Colors.black,
        surface: Colors.black,
      ),
    );
  }

  Map<String, dynamic> getContextReport() {
    return {
      'currentContext': _currentContext.name,
      'confidence': _contextWeights[_currentContext] ?? 0,
      'allContexts': _contextWeights,
      'batteryLevel': _suggestions.isNotEmpty ? 'checking' : null,
      'connectedNodes': _connectedNodes,
      'isOnline': _isNetworkOnline,
      'hasNearbySOS': _hasActiveSOSNearby,
      'lastMovement': _lastMovementTime?.toIso8601String(),
    };
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _locationSubscription?.cancel();
    _updateTimer?.cancel();
    _contextController.close();
    _suggestionController.close();
  }
}
