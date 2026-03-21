import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Emergency Broadcast Service — alert all mesh devices.
/// Also handles: coordination (tasks, headcount, voting), health module.
class EmergencyBroadcastService {
  static const String _alertBox = 'chaaya_alerts';
  Box<String>? _box;
  final _alertStream = StreamController<EmergencyAlert>.broadcast();

  Stream<EmergencyAlert> get alerts => _alertStream.stream;

  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_alertBox);
  }

  /// Send emergency broadcast to ALL on the mesh
  Future<EmergencyAlert> broadcast({
    required String senderId,
    required String senderName,
    required AlertType type,
    required String message,
    double? latitude,
    double? longitude,
  }) async {
    final alert = EmergencyAlert(
      id: const Uuid().v4(),
      senderId: senderId,
      senderName: senderName,
      type: type,
      message: message,
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
    );

    await _box?.put(alert.id, jsonEncode(alert.toJson()));
    _alertStream.add(alert);
    debugPrint('[BROADCAST] 🚨 ${type.name}: $message from $senderName');
    return alert;
  }

  /// Get alert history
  List<EmergencyAlert> getHistory() {
    return _box?.values
        .map((j) => EmergencyAlert.fromJson(jsonDecode(j)))
        .toList()
      ?..sort((a, b) => b.timestamp.compareTo(a.timestamp)) ?? [];
  }

  Future<void> dispose() async {
    await _alertStream.close();
  }
}

/// Coordination Service — tasks, headcount, voting.
class CoordinationService {
  static const String _taskBox = 'chaaya_tasks';
  static const String _voteBox = 'chaaya_votes';
  Box<String>? _tasks;
  Box<String>? _votes;

  Future<void> initialize() async {
    _tasks = await Hive.openBox<String>(_taskBox);
    _votes = await Hive.openBox<String>(_voteBox);
  }

  /// Create a task assignment
  Future<TeamTask> createTask({
    required String title,
    required String assignedTo,
    required String createdBy,
    String? description,
    DateTime? deadline,
  }) async {
    final task = TeamTask(
      id: const Uuid().v4(),
      title: title,
      description: description,
      assignedTo: assignedTo,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      deadline: deadline,
    );
    await _tasks?.put(task.id, jsonEncode(task.toJson()));
    return task;
  }

  /// Get all tasks
  List<TeamTask> getTasks() {
    return _tasks?.values
        .map((j) => TeamTask.fromJson(jsonDecode(j)))
        .toList() ?? [];
  }

  /// Mark task complete
  Future<void> completeTask(String taskId) async {
    final j = _tasks?.get(taskId);
    if (j == null) return;
    final task = TeamTask.fromJson(jsonDecode(j));
    final updated = task.copyWith(isCompleted: true);
    await _tasks?.put(taskId, jsonEncode(updated.toJson()));
  }

  /// Create a vote
  Future<TeamVote> createVote({
    required String question,
    required List<String> options,
    required String createdBy,
  }) async {
    final vote = TeamVote(
      id: const Uuid().v4(),
      question: question,
      options: options,
      votes: {},
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    await _votes?.put(vote.id, jsonEncode(vote.toJson()));
    return vote;
  }

  /// Cast a vote
  Future<void> castVote(String voteId, String option, String voterId) async {
    final j = _votes?.get(voteId);
    if (j == null) return;
    final vote = TeamVote.fromJson(jsonDecode(j));
    vote.votes[voterId] = option;
    await _votes?.put(voteId, jsonEncode(vote.toJson()));
  }

  List<TeamVote> getVotes() {
    return _votes?.values
        .map((j) => TeamVote.fromJson(jsonDecode(j)))
        .toList() ?? [];
  }
}

/// Health & Medical Service
class HealthService {
  static const String _healthBox = 'chaaya_health';
  Box<String>? _box;

  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_healthBox);
  }

  /// Save medical profile
  Future<void> saveMedicalProfile(MedicalProfile profile) async {
    await _box?.put('profile', jsonEncode(profile.toJson()));
  }

  /// Get medical profile
  MedicalProfile? getMedicalProfile() {
    final j = _box?.get('profile');
    return j != null ? MedicalProfile.fromJson(jsonDecode(j)) : null;
  }

  /// Log medication taken
  Future<void> logMedication(String name, DateTime time) async {
    final key = 'med_${time.millisecondsSinceEpoch}';
    await _box?.put(key, jsonEncode({'name': name, 'time': time.toIso8601String()}));
  }

  /// Get medication log
  List<Map<String, String>> getMedicationLog() {
    return _box?.toMap().entries
        .where((e) => (e.key as String).startsWith('med_'))
        .map((e) => Map<String, String>.from(jsonDecode(e.value)))
        .toList() ?? [];
  }
}

// ─── Models ───

class EmergencyAlert {
  final String id, senderId, senderName, message;
  final AlertType type;
  final DateTime timestamp;
  final double? latitude, longitude;

  EmergencyAlert({required this.id, required this.senderId, required this.senderName,
    required this.type, required this.message, required this.timestamp,
    this.latitude, this.longitude});

  factory EmergencyAlert.fromJson(Map<String, dynamic> j) => EmergencyAlert(
    id: j['id'], senderId: j['senderId'], senderName: j['senderName'],
    type: AlertType.values.firstWhere((e) => e.name == j['type']),
    message: j['message'], timestamp: DateTime.parse(j['timestamp']),
    latitude: j['latitude'], longitude: j['longitude'],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'senderId': senderId, 'senderName': senderName,
    'type': type.name, 'message': message,
    'timestamp': timestamp.toIso8601String(),
    'latitude': latitude, 'longitude': longitude,
  };
}

enum AlertType { emergency, weather, security, medical, evacuation, custom }

class TeamTask {
  final String id, title, assignedTo, createdBy;
  final String? description;
  final DateTime createdAt;
  final DateTime? deadline;
  final bool isCompleted;

  TeamTask({required this.id, required this.title, required this.assignedTo,
    required this.createdBy, this.description, required this.createdAt,
    this.deadline, this.isCompleted = false});

  factory TeamTask.fromJson(Map<String, dynamic> j) => TeamTask(
    id: j['id'], title: j['title'], assignedTo: j['assignedTo'],
    createdBy: j['createdBy'], description: j['description'],
    createdAt: DateTime.parse(j['createdAt']),
    deadline: j['deadline'] != null ? DateTime.parse(j['deadline']) : null,
    isCompleted: j['isCompleted'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'assignedTo': assignedTo,
    'createdBy': createdBy, 'description': description,
    'createdAt': createdAt.toIso8601String(),
    'deadline': deadline?.toIso8601String(), 'isCompleted': isCompleted,
  };

  TeamTask copyWith({bool? isCompleted}) => TeamTask(
    id: id, title: title, assignedTo: assignedTo, createdBy: createdBy,
    description: description, createdAt: createdAt, deadline: deadline,
    isCompleted: isCompleted ?? this.isCompleted,
  );
}

class TeamVote {
  final String id, question, createdBy;
  final List<String> options;
  final Map<String, String> votes;
  final DateTime createdAt;

  TeamVote({required this.id, required this.question, required this.options,
    required this.votes, required this.createdBy, required this.createdAt});

  factory TeamVote.fromJson(Map<String, dynamic> j) => TeamVote(
    id: j['id'], question: j['question'], options: List<String>.from(j['options']),
    votes: Map<String, String>.from(j['votes'] ?? {}),
    createdBy: j['createdBy'], createdAt: DateTime.parse(j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'question': question, 'options': options,
    'votes': votes, 'createdBy': createdBy,
    'createdAt': createdAt.toIso8601String(),
  };

  Map<String, int> get results {
    final counts = <String, int>{};
    for (final opt in options) counts[opt] = 0;
    for (final v in votes.values) counts[v] = (counts[v] ?? 0) + 1;
    return counts;
  }
}

class MedicalProfile {
  final String bloodType;
  final List<String> allergies;
  final List<String> medications;
  final List<String> conditions;
  final String? emergencyContact;

  MedicalProfile({required this.bloodType, required this.allergies,
    required this.medications, required this.conditions, this.emergencyContact});

  factory MedicalProfile.fromJson(Map<String, dynamic> j) => MedicalProfile(
    bloodType: j['bloodType'], allergies: List<String>.from(j['allergies'] ?? []),
    medications: List<String>.from(j['medications'] ?? []),
    conditions: List<String>.from(j['conditions'] ?? []),
    emergencyContact: j['emergencyContact'],
  );

  Map<String, dynamic> toJson() => {
    'bloodType': bloodType, 'allergies': allergies,
    'medications': medications, 'conditions': conditions,
    'emergencyContact': emergencyContact,
  };
}

