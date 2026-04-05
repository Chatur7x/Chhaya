import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/sync/vector_clock.dart';

enum MissingPersonStatus { active, found, expired }

class MissingPersonReport {
  final String id;
  final String reporterId;
  final String name;
  final String? photoPath;
  final DateTime lastKnownLocationTime;
  final double? lastLatitude;
  final double? lastLongitude;
  final String? lastKnownAddress;
  final List<String> knownDestinations;
  final List<String> knownContacts;
  final String? medicalInfo;
  final String? additionalNotes;
  final MissingPersonStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final VectorClock vectorClock;

  MissingPersonReport({
    required this.id,
    required this.reporterId,
    required this.name,
    this.photoPath,
    required this.lastKnownLocationTime,
    this.lastLatitude,
    this.lastLongitude,
    this.lastKnownAddress,
    this.knownDestinations = const [],
    this.knownContacts = const [],
    this.medicalInfo,
    this.additionalNotes,
    this.status = MissingPersonStatus.active,
    required this.createdAt,
    required this.updatedAt,
    required this.vectorClock,
  });

  MissingPersonReport copyWith({
    String? id,
    String? reporterId,
    String? name,
    String? photoPath,
    DateTime? lastKnownLocationTime,
    double? lastLatitude,
    double? lastLongitude,
    String? lastKnownAddress,
    List<String>? knownDestinations,
    List<String>? knownContacts,
    String? medicalInfo,
    String? additionalNotes,
    MissingPersonStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    VectorClock? vectorClock,
  }) {
    return MissingPersonReport(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      name: name ?? this.name,
      photoPath: photoPath ?? this.photoPath,
      lastKnownLocationTime:
          lastKnownLocationTime ?? this.lastKnownLocationTime,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastKnownAddress: lastKnownAddress ?? this.lastKnownAddress,
      knownDestinations: knownDestinations ?? this.knownDestinations,
      knownContacts: knownContacts ?? this.knownContacts,
      medicalInfo: medicalInfo ?? this.medicalInfo,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      vectorClock: vectorClock ?? this.vectorClock,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'reporterId': reporterId,
        'name': name,
        'photoPath': photoPath,
        'lastKnownLocationTime': lastKnownLocationTime.toIso8601String(),
        'lastLatitude': lastLatitude,
        'lastLongitude': lastLongitude,
        'lastKnownAddress': lastKnownAddress,
        'knownDestinations': knownDestinations,
        'knownContacts': knownContacts,
        'medicalInfo': medicalInfo,
        'additionalNotes': additionalNotes,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'vectorClock': vectorClock.toJson(),
      };

  factory MissingPersonReport.fromJson(Map<String, dynamic> json) {
    return MissingPersonReport(
      id: json['id'],
      reporterId: json['reporterId'],
      name: json['name'],
      photoPath: json['photoPath'],
      lastKnownLocationTime: DateTime.parse(json['lastKnownLocationTime']),
      lastLatitude: json['lastLatitude']?.toDouble(),
      lastLongitude: json['lastLongitude']?.toDouble(),
      lastKnownAddress: json['lastKnownAddress'],
      knownDestinations: List<String>.from(json['knownDestinations'] ?? []),
      knownContacts: List<String>.from(json['knownContacts'] ?? []),
      medicalInfo: json['medicalInfo'],
      additionalNotes: json['additionalNotes'],
      status: MissingPersonStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MissingPersonStatus.active,
      ),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      vectorClock: VectorClock.fromJson(json['vectorClock']),
    );
  }
}

class LocationUpdate {
  final String reportId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final DateTime timestamp;
  final String sourceNodeId;
  final VectorClock vectorClock;

  LocationUpdate({
    required this.reportId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude,
    this.speed,
    required this.timestamp,
    required this.sourceNodeId,
    required this.vectorClock,
  });

  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'timestamp': timestamp.toIso8601String(),
        'sourceNodeId': sourceNodeId,
        'vectorClock': vectorClock.toJson(),
      };

  factory LocationUpdate.fromJson(Map<String, dynamic> json) {
    return LocationUpdate(
      reportId: json['reportId'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      accuracy: json['accuracy'].toDouble(),
      altitude: json['altitude']?.toDouble(),
      speed: json['speed']?.toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      sourceNodeId: json['sourceNodeId'],
      vectorClock: VectorClock.fromJson(json['vectorClock']),
    );
  }
}

class MissingPersonService {
  final Map<String, MissingPersonReport> _reports = {};
  final Map<String, List<LocationUpdate>> _locationHistory = {};
  final Map<String, Timer> _expirationTimers = {};
  final VectorClock _vectorClock;

  static const Duration _defaultExpirationDuration = Duration(hours: 48);
  static const int _maxLocationHistory = 100;

  final _reportController = StreamController<MissingPersonReport>.broadcast();
  Stream<MissingPersonReport> get reportUpdates => _reportController.stream;

  final _locationUpdateController =
      StreamController<LocationUpdate>.broadcast();
  Stream<LocationUpdate> get locationUpdates =>
      _locationUpdateController.stream;

  final _foundController = StreamController<MissingPersonReport>.broadcast();
  Stream<MissingPersonReport> get foundReports => _foundController.stream;

  MissingPersonService({VectorClock? vectorClock, String? deviceId})
      : _vectorClock =
            vectorClock ?? VectorClock(deviceId ?? 'missing_person_service');

  String createReport({
    required String reporterId,
    required String name,
    String? photoPath,
    required double latitude,
    required double longitude,
    String? lastKnownAddress,
    List<String>? knownDestinations,
    List<String>? knownContacts,
    String? medicalInfo,
    String? additionalNotes,
  }) {
    final id = 'MP_${DateTime.now().millisecondsSinceEpoch}';
    _vectorClock.increment();

    final report = MissingPersonReport(
      id: id,
      reporterId: reporterId,
      name: name,
      photoPath: photoPath,
      lastKnownLocationTime: DateTime.now(),
      lastLatitude: latitude,
      lastLongitude: longitude,
      lastKnownAddress: lastKnownAddress,
      knownDestinations: knownDestinations ?? [],
      knownContacts: knownContacts ?? [],
      medicalInfo: medicalInfo,
      additionalNotes: additionalNotes,
      status: MissingPersonStatus.active,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      vectorClock: _vectorClock.copy(),
    );

    _reports[id] = report;
    _locationHistory[id] = [];
    _startExpirationTimer(id);
    _reportController.add(report);

    debugPrint('Missing person report created: $id for $name');
    return id;
  }

  void _startExpirationTimer(String reportId) {
    _expirationTimers[reportId]?.cancel();
    _expirationTimers[reportId] = Timer(_defaultExpirationDuration, () {
      expireReport(reportId);
    });
  }

  void reportFound(String reportId, {String? foundBy, String? foundLocation}) {
    final report = _reports[reportId];
    if (report == null) return;

    _vectorClock.increment();

    final updated = report.copyWith(
      status: MissingPersonStatus.found,
      additionalNotes: foundLocation != null
          ? '${report.additionalNotes ?? ''}\nFound at: $foundLocation'
          : report.additionalNotes,
      updatedAt: DateTime.now(),
      vectorClock: _vectorClock.copy(),
    );

    _reports[reportId] = updated;
    _expirationTimers[reportId]?.cancel();
    _foundController.add(updated);
    _reportController.add(updated);

    debugPrint('Missing person found: $reportId');
  }

  void expireReport(String reportId) {
    final report = _reports[reportId];
    if (report == null) return;

    _vectorClock.increment();

    final updated = report.copyWith(
      status: MissingPersonStatus.expired,
      updatedAt: DateTime.now(),
      vectorClock: _vectorClock.copy(),
    );

    _reports[reportId] = updated;
    _reportController.add(updated);

    debugPrint('Missing person report expired: $reportId');
  }

  void updateLocation({
    required String reportId,
    required double latitude,
    required double longitude,
    required double accuracy,
    double? altitude,
    double? speed,
    required String sourceNodeId,
  }) {
    final report = _reports[reportId];
    if (report == null) return;

    _vectorClock.increment();

    final update = LocationUpdate(
      reportId: reportId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      timestamp: DateTime.now(),
      sourceNodeId: sourceNodeId,
      vectorClock: _vectorClock.copy(),
    );

    _locationHistory[reportId] ??= [];
    _locationHistory[reportId]!.add(update);

    if (_locationHistory[reportId]!.length > _maxLocationHistory) {
      _locationHistory[reportId]!.removeAt(0);
    }

    final updatedReport = report.copyWith(
      lastLatitude: latitude,
      lastLongitude: longitude,
      lastKnownLocationTime: DateTime.now(),
      updatedAt: DateTime.now(),
      vectorClock: _vectorClock.copy(),
    );

    _reports[reportId] = updatedReport;
    _locationUpdateController.add(update);
    _reportController.add(updatedReport);

    debugPrint('Location updated for report: $reportId');
  }

  void mergeReport(MissingPersonReport remoteReport) {
    final local = _reports[remoteReport.id];

    if (local == null) {
      _reports[remoteReport.id] = remoteReport;
      _locationHistory[remoteReport.id] = [];
      _startExpirationTimer(remoteReport.id);
      _reportController.add(remoteReport);
      return;
    }

    final shouldMerge =
        remoteReport.vectorClock.happensBefore(local.vectorClock);

    if (shouldMerge) {
      _reports[remoteReport.id] = remoteReport;
      _reportController.add(remoteReport);
    }
  }

  void mergeLocationUpdate(LocationUpdate update) {
    final history = _locationHistory[update.reportId];
    if (history == null) {
      _locationHistory[update.reportId] = [update];
      return;
    }

    final existing = history.indexWhere(
      (u) =>
          u.timestamp == update.timestamp &&
          u.sourceNodeId == update.sourceNodeId,
    );

    if (existing >= 0) {
      if (update.vectorClock.happensBefore(history[existing].vectorClock)) {
        history[existing] = update;
        _locationUpdateController.add(update);
      }
    } else {
      history.add(update);
      history.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _locationUpdateController.add(update);
    }
  }

  MissingPersonReport? getReport(String reportId) => _reports[reportId];

  List<MissingPersonReport> getActiveReports() {
    return _reports.values
        .where((r) => r.status == MissingPersonStatus.active)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<MissingPersonReport> getReportsByReporter(String reporterId) {
    return _reports.values.where((r) => r.reporterId == reporterId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<LocationUpdate> getLocationHistory(String reportId) {
    return List.from(_locationHistory[reportId] ?? []);
  }

  LocationUpdate? getLastLocation(String reportId) {
    final history = _locationHistory[reportId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  Map<String, MissingPersonReport> getAllReports() =>
      Map.unmodifiable(_reports);

  List<MissingPersonReport> searchReports(String query) {
    final lowerQuery = query.toLowerCase();
    return _reports.values.where((r) {
      return r.name.toLowerCase().contains(lowerQuery) ||
          (r.lastKnownAddress?.toLowerCase().contains(lowerQuery) ?? false) ||
          (r.additionalNotes?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  int getActiveReportCount() {
    return _reports.values
        .where((r) => r.status == MissingPersonStatus.active)
        .length;
  }

  void cancelReport(String reportId) {
    _expirationTimers[reportId]?.cancel();
    _expirationTimers.remove(reportId);
    _reports.remove(reportId);
    _locationHistory.remove(reportId);
  }

  void dispose() {
    for (final timer in _expirationTimers.values) {
      timer.cancel();
    }
    _expirationTimers.clear();
    _reportController.close();
    _locationUpdateController.close();
    _foundController.close();
  }
}
