import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/sync/vector_clock.dart';

enum IntelReportType { danger, safe, resource, infrastructure }

class IntelReport {
  final String id;
  final String reporterId;
  final IntelReportType type;
  final double latitude;
  final double longitude;
  final double radius;
  final int confidence;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> verifiedBy;
  final String? description;
  final VectorClock vectorClock;

  IntelReport({
    required this.id,
    required this.reporterId,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.confidence,
    required this.createdAt,
    required this.expiresAt,
    required this.verifiedBy,
    this.description,
    required this.vectorClock,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get ttlRemaining {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  IntelReport copyWith({
    String? id,
    String? reporterId,
    IntelReportType? type,
    double? latitude,
    double? longitude,
    double? radius,
    int? confidence,
    DateTime? createdAt,
    DateTime? expiresAt,
    List<String>? verifiedBy,
    String? description,
    VectorClock? vectorClock,
  }) {
    return IntelReport(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      description: description ?? this.description,
      vectorClock: vectorClock ?? this.vectorClock,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'reporterId': reporterId,
        'type': type.name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'verifiedBy': verifiedBy,
        'description': description,
        'vectorClock': vectorClock.toJson(),
      };

  factory IntelReport.fromJson(Map<String, dynamic> json) {
    return IntelReport(
      id: json['id'],
      reporterId: json['reporterId'],
      type: IntelReportType.values.firstWhere((e) => e.name == json['type']),
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      radius: json['radius'].toDouble(),
      confidence: json['confidence'],
      createdAt: DateTime.parse(json['createdAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      verifiedBy: List<String>.from(json['verifiedBy'] ?? []),
      description: json['description'],
      vectorClock: VectorClock.fromJson(json['vectorClock']),
    );
  }
}

class CrowdIntelligence {
  final Map<String, IntelReport> _reports = {};
  final Map<String, double> _reporterReputation = {};

  static const int _maxReportsPerType = 100;
  static const int _baseConfidence = 50;

  final _reportController = StreamController<IntelReport>.broadcast();
  Stream<IntelReport> get reportStream => _reportController.stream;

  final _expiryController = StreamController<IntelReport>.broadcast();
  Stream<IntelReport> get expiryStream => _expiryController.stream;

  String createReport({
    required String reporterId,
    required IntelReportType type,
    required double latitude,
    required double longitude,
    required double radius,
    String? description,
    Duration? ttl,
  }) {
    final id = 'INTEL_${DateTime.now().millisecondsSinceEpoch}';
    final ttlDuration = ttl ?? _getDefaultTTL(type);

    final report = IntelReport(
      id: id,
      reporterId: reporterId,
      type: type,
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      confidence: _calculateConfidence(reporterId),
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(ttlDuration),
      verifiedBy: [reporterId],
      description: description,
      vectorClock: VectorClock(reporterId),
    );

    _reports[id] = report;
    _reportController.add(report);
    debugPrint('Intel report created: $id');

    return id;
  }

  Duration _getDefaultTTL(IntelReportType type) {
    switch (type) {
      case IntelReportType.danger:
        return const Duration(hours: 2);
      case IntelReportType.safe:
        return const Duration(hours: 24);
      case IntelReportType.resource:
        return const Duration(hours: 12);
      case IntelReportType.infrastructure:
        return const Duration(hours: 24);
    }
  }

  int _calculateConfidence(String reporterId) {
    final reputation = _reporterReputation[reporterId] ?? 0.5;
    return (_baseConfidence * reputation).round().clamp(10, 100);
  }

  void verifyReport(String reportId, String verifierId) {
    final report = _reports[reportId];
    if (report == null || report.verifiedBy.contains(verifierId)) return;

    final updated = report.copyWith(
      verifiedBy: [...report.verifiedBy, verifierId],
      confidence: (report.confidence + 10).clamp(0, 100),
    );

    _reports[reportId] = updated;
    _updateReporterReputation(report.reporterId, 0.1);
    _reportController.add(updated);
  }

  void _updateReporterReputation(String reporterId, double delta) {
    _reporterReputation[reporterId] ??= 0.5;
    _reporterReputation[reporterId] =
        (_reporterReputation[reporterId]! + delta).clamp(0.0, 1.0);
  }

  void processExpiredReports() {
    final expired = _reports.entries.where((e) => e.value.isExpired).toList();

    for (final entry in expired) {
      _reports.remove(entry.key);
      _expiryController.add(entry.value);
    }
  }

  List<IntelReport> getReportsInRadius(
      double lat, double lng, double radiusMeters) {
    return _reports.values.where((r) {
      if (r.isExpired) return false;
      final distance = _calculateDistance(lat, lng, r.latitude, r.longitude);
      return distance <= radiusMeters;
    }).toList();
  }

  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * 3.14159265359 / 180;
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorCos(x);
  double _sqrt(double x) => x > 0 ? _newtonSqrt(x) : 0;
  double _atan2(double y, double x) => _simpleAtan2(y, x);

  double _taylorSin(double x) {
    x = x % (2 * 3.14159265359);
    if (x > 3.14159265359) x -= 2 * 3.14159265359;
    double result = x, term = x;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  double _taylorCos(double x) {
    x = x % (2 * 3.14159265359);
    double result = 1, term = 1;
    for (int i = 1; i < 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  double _newtonSqrt(double x) {
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  double _simpleAtan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265359;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265359;
    if (x == 0 && y > 0) return 3.14159265359 / 2;
    if (x == 0 && y < 0) return -3.14159265359 / 2;
    return 0;
  }

  double _atan(double x) {
    if (x.abs() > 1) {
      return (x > 0 ? 1 : -1) * 3.14159265359 / 2 - _atan(1 / x);
    }
    double result = x, term = x;
    for (int i = 1; i < 15; i++) {
      term *= -x * x;
      result += term / (2 * i + 1);
    }
    return result;
  }

  List<IntelReport> getReportsByType(IntelReportType type) {
    return _reports.values
        .where((r) => r.type == type && !r.isExpired)
        .toList();
  }

  IntelReport? getReport(String reportId) => _reports[reportId];

  Map<String, dynamic> getStatistics() {
    return {
      'totalReports': _reports.length,
      'byType': {
        for (final type in IntelReportType.values)
          type.name: _reports.values.where((r) => r.type == type).length,
      },
      'verifiedReports':
          _reports.values.where((r) => r.verifiedBy.length > 1).length,
      'activeReporters': _reporterReputation.length,
    };
  }

  void dispose() {
    _reportController.close();
    _expiryController.close();
  }
}
