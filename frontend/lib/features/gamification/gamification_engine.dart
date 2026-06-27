import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

enum AchievementCategory { relay, sos, exploration, social, knowledge }

class Achievement {
  final String id;
  final String title;
  final String description;
  final int target;
  int current;
  final String icon;
  final AchievementCategory category;
  DateTime? unlockedAt;
  final int points;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.current,
    required this.icon,
    required this.category,
    this.unlockedAt,
    required this.points,
  });

  bool get isUnlocked => unlockedAt != null;
  double get progress => (current / target).clamp(0.0, 1.0);

  Achievement copyWith({int? current, DateTime? unlockedAt}) {
    return Achievement(
      id: id,
      title: title,
      description: description,
      target: target,
      current: current ?? this.current,
      icon: icon,
      category: category,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      points: points,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'target': target,
        'current': current,
        'icon': icon,
        'category': category.name,
        'unlockedAt': unlockedAt?.toIso8601String(),
        'points': points,
      };

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        target: json['target'] ?? 0,
        current: json['current'] ?? 0,
        icon: json['icon'] ?? '',
        category: AchievementCategory.values.firstWhere(
            (e) => e.name == json['category'],
            orElse: () => AchievementCategory.relay),
        unlockedAt: json['unlockedAt'] != null
            ? DateTime.parse(json['unlockedAt'])
            : null,
        points: json['points'] ?? 0,
      );
}

class UserScore {
  final String odId;
  int relayScore;
  int sosScore;
  int explorationScore;
  int socialScore;
  int knowledgeScore;
  int totalPoints;
  final DateTime updatedAt;

  UserScore({
    required this.odId,
    this.relayScore = 0,
    this.sosScore = 0,
    this.explorationScore = 0,
    this.socialScore = 0,
    this.knowledgeScore = 0,
    this.totalPoints = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  int get totalScore =>
      relayScore + sosScore + explorationScore + socialScore + knowledgeScore;

  Map<String, dynamic> toJson() => {
        'odId': odId,
        'relayScore': relayScore,
        'sosScore': sosScore,
        'explorationScore': explorationScore,
        'socialScore': socialScore,
        'knowledgeScore': knowledgeScore,
        'totalScore': totalScore,
        'totalPoints': totalPoints,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserScore.fromJson(Map<String, dynamic> json) => UserScore(
        odId: json['odId'] ?? '',
        relayScore: json['relayScore'] ?? 0,
        sosScore: json['sosScore'] ?? 0,
        explorationScore: json['explorationScore'] ?? 0,
        socialScore: json['socialScore'] ?? 0,
        knowledgeScore: json['knowledgeScore'] ?? 0,
        totalPoints: json['totalPoints'] ?? 0,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : null,
      );
}

class GamificationEngine {
  final Map<String, Achievement> _achievements = {};
  final Map<String, UserScore> _userScores = {};
  final Random _random = Random.secure();

  static const String _boxName = 'chaaya_gamification';
  Box<String>? _box;

  final _achievementController = StreamController<Achievement>.broadcast();
  Stream<Achievement> get achievementStream => _achievementController.stream;

  final _scoreController = StreamController<UserScore>.broadcast();
  Stream<UserScore> get scoreStream => _scoreController.stream;

  GamificationEngine() {
    _initializeAchievements();
  }

  Future<void> initialize() async {
    _box = await Hive.openBox<String>(_boxName);
    _loadFromHive();
  }

  void _loadFromHive() {
    if (_box == null) return;
    
    // Load achievements
    for (final key in _box!.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith('achievement_')) {
        final json = _box!.get(keyStr);
        if (json != null) {
          try {
            final ach = Achievement.fromJson(jsonDecode(json));
            if (_achievements.containsKey(ach.id)) {
              _achievements[ach.id]!.current = ach.current;
              _achievements[ach.id]!.unlockedAt = ach.unlockedAt;
            }
          } catch (e) {
            debugPrint('[Gamification] Error parsing achievement: $e');
          }
        }
      } else if (keyStr.startsWith('score_')) {
        final userId = keyStr.replaceFirst('score_', '');
        final json = _box!.get(keyStr);
        if (json != null) {
          try {
            _userScores[userId] = UserScore.fromJson(jsonDecode(json));
          } catch (e) {
            debugPrint('[Gamification] Error parsing score: $e');
          }
        }
      }
    }
  }

  void _saveAchievement(String userId, Achievement achievement) {
    _box?.put('achievement_${userId}_${achievement.id}', jsonEncode(achievement.toJson()));
  }

  void _saveScore(String userId, UserScore score) {
    _box?.put('score_$userId', jsonEncode(score.toJson()));
  }

  void _initializeAchievements() {
    final defaultAchievements = [
      Achievement(
          id: 'msg_hero',
          title: 'Message Hero',
          description: 'Relay 100 messages',
          target: 100,
          current: 0,
          icon: '!',
          category: AchievementCategory.relay,
          points: 100),
      Achievement(
          id: 'msg_soldier',
          title: 'Message Soldier',
          description: 'Relay 10 messages',
          target: 10,
          current: 0,
          icon: '!',
          category: AchievementCategory.relay,
          points: 20),
      Achievement(
          id: 'msg_commander',
          title: 'Message Commander',
          description: 'Relay 500 messages',
          target: 500,
          current: 0,
          icon: '!',
          category: AchievementCategory.relay,
          points: 250),
      Achievement(
          id: 'lifeline',
          title: 'Lifeline',
          description: 'Respond to an SOS',
          target: 1,
          current: 0,
          icon: '+',
          category: AchievementCategory.sos,
          points: 100),
      Achievement(
          id: 'guardian',
          title: 'Guardian Angel',
          description: 'Respond to 10 SOS',
          target: 10,
          current: 0,
          icon: '+',
          category: AchievementCategory.sos,
          points: 300),
      Achievement(
          id: 'explorer',
          title: 'Explorer',
          description: 'Cover 1km via mesh',
          target: 1000,
          current: 0,
          icon: '~',
          category: AchievementCategory.exploration,
          points: 50),
      Achievement(
          id: 'adventurer',
          title: 'Adventurer',
          description: 'Cover 10km via mesh',
          target: 10000,
          current: 0,
          icon: '~',
          category: AchievementCategory.exploration,
          points: 150),
      Achievement(
          id: 'network_builder',
          title: 'Network Builder',
          description: 'Have 10 contacts',
          target: 10,
          current: 0,
          icon: '@',
          category: AchievementCategory.social,
          points: 75),
      Achievement(
          id: 'knowledge_sharer',
          title: 'Knowledge Sharer',
          description: 'Share 5 guides',
          target: 5,
          current: 0,
          icon: '#',
          category: AchievementCategory.knowledge,
          points: 50),
      Achievement(
          id: 'scholar',
          title: 'Scholar',
          description: 'Share 20 guides',
          target: 20,
          current: 0,
          icon: '#',
          category: AchievementCategory.knowledge,
          points: 150),
    ];

    for (final achievement in defaultAchievements) {
      _achievements[achievement.id] = achievement;
    }
  }

  void addRelayScore(String userId, int messages) {
    _ensureUserExists(userId);
    _userScores[userId]!.relayScore += messages * 10;
    _incrementAchievement(userId, 'msg_hero', messages);
    _incrementAchievement(userId, 'msg_soldier', messages);
    _incrementAchievement(userId, 'msg_commander', messages);
    _emitScore(userId);
  }

  void addSOSResponse(String userId) {
    _ensureUserExists(userId);
    _userScores[userId]!.sosScore += 100;
    _unlockAchievement(userId, 'lifeline');
    _incrementAchievement(userId, 'guardian', 1);
    _emitScore(userId);
  }

  void addExplorationScore(String userId, int meters) {
    _ensureUserExists(userId);
    _userScores[userId]!.explorationScore += meters;
    _incrementAchievement(userId, 'explorer', meters);
    _incrementAchievement(userId, 'adventurer', meters);
    _emitScore(userId);
  }

  void addSocialScore(String userId, int contacts) {
    _ensureUserExists(userId);
    _userScores[userId]!.socialScore += contacts * 5;
    _incrementAchievement(userId, 'network_builder', contacts);
    _emitScore(userId);
  }

  void addKnowledgeScore(String userId, int guides) {
    _ensureUserExists(userId);
    _userScores[userId]!.knowledgeScore += guides * 50;
    _incrementAchievement(userId, 'knowledge_sharer', guides);
    _incrementAchievement(userId, 'scholar', guides);
    _emitScore(userId);
  }

  void _ensureUserExists(String userId) {
    if (!_userScores.containsKey(userId)) {
      _userScores[userId] = UserScore(odId: userId);
    }
  }

  void _incrementAchievement(String userId, String achievementId, int amount) {
    final achievement = _achievements[achievementId];
    if (achievement == null || achievement.isUnlocked) return;

    achievement.current += amount;
    _saveAchievement(userId, achievement);
    if (achievement.current >= achievement.target) {
      _unlockAchievement(userId, achievementId);
    }
  }

  void _unlockAchievement(String userId, String achievementId) {
    final achievement = _achievements[achievementId];
    if (achievement == null || achievement.isUnlocked) return;

    achievement.current = achievement.target;
    achievement.unlockedAt = DateTime.now();

    _ensureUserExists(userId);
    _userScores[userId]!.totalPoints += achievement.points;

    _saveAchievement(userId, achievement);
    _saveScore(userId, _userScores[userId]!);

    _achievementController.add(achievement);
    debugPrint('Achievement unlocked: ${achievement.title}');
  }

  void _emitScore(String userId) {
    final score = _userScores[userId];
    if (score != null) {
      _saveScore(userId, score);
      _scoreController.add(score);
    }
  }

  List<Achievement> getAchievements(String userId) {
    return _achievements.values.toList()
      ..sort((a, b) {
        if (a.isUnlocked && !b.isUnlocked) return -1;
        if (!a.isUnlocked && b.isUnlocked) return 1;
        return b.points.compareTo(a.points);
      });
  }

  List<Achievement> getUnlockedAchievements(String userId) {
    return _achievements.values.where((a) => a.isUnlocked).toList();
  }

  UserScore? getScore(String userId) => _userScores[userId];

  Map<String, dynamic> getStatistics(String userId) {
    final score = _userScores[userId];
    final unlockedCount = getUnlockedAchievements(userId).length;

    return {
      'totalScore': score?.totalScore ?? 0,
      'achievementsUnlocked': unlockedCount,
      'totalAchievements': _achievements.length,
      'scoreBreakdown': {
        'relay': score?.relayScore ?? 0,
        'sos': score?.sosScore ?? 0,
        'exploration': score?.explorationScore ?? 0,
        'social': score?.socialScore ?? 0,
        'knowledge': score?.knowledgeScore ?? 0,
      },
    };
  }

  void dispose() {
    _achievementController.close();
    _scoreController.close();
  }
}
