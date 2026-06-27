import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/sync/vector_clock.dart';
import 'package:hive/hive.dart';

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

  static const String _reportsBoxName = 'chaaya_intel_reports';
  static const String _reputationBoxName = 'chaaya_reporter_reputation';
  Box<String>? _reportsBox;
  Box<double>? _reputationBox;

  final _reportController = StreamController<IntelReport>.broadcast();
  Stream<IntelReport> get reportStream => _reportController.stream;

  final _expiryController = StreamController<IntelReport>.broadcast();
  Stream<IntelReport> get expiryStream => _expiryController.stream;

  Future<void> initialize() async {
    _reportsBox = await Hive.openBox<String>(_reportsBoxName);
    _reputationBox = await Hive.openBox<double>(_reputationBoxName);
    _loadFromHive();
  }

  void _loadFromHive() {
    if (_reportsBox != null) {
      for (final key in _reportsBox!.keys) {
        final json = _reportsBox!.get(key);
        if (json != null) {
          try {
            final report = IntelReport.fromJson(jsonDecode(json));
            if (!report.isExpired) {
              _reports[report.id] = report;
            } else {
              _reportsBox!.delete(key);
            }
          } catch (e) {
            debugPrint('[CrowdIntel] Error parsing report: $e');
          }
        }
      }
    }
    if (_reputationBox != null) {
      for (final key in _reputationBox!.keys) {
        _reporterReputation[key.toString()] = _reputationBox!.get(key) ?? 0.5;
      }
    }
  }

  void _saveReport(IntelReport report) {
    _reportsBox?.put(report.id, jsonEncode(report.toJson()));
  }

  void _saveReputation(String reporterId, double reputation) {
    _reputationBox?.put(reporterId, reputation);
  }

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
    _saveReport(report);
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
    _saveReport(updated);
    _updateReporterReputation(report.reporterId, 0.1);
    _reportController.add(updated);
  }

  void _updateReporterReputation(String reporterId, double delta) {
    _reporterReputation[reporterId] ??= 0.5;
    _reporterReputation[reporterId] =
        (_reporterReputation[reporterId]! + delta).clamp(0.0, 1.0);
    _saveReputation(reporterId, _reporterReputation[reporterId]!);
  }

  void processExpiredReports() {
    final expired = _reports.entries.where((e) => e.value.isExpired).toList();

    for (final entry in expired) {
      _reports.remove(entry.key);
      _reportsBox?.delete(entry.key);
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
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

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
