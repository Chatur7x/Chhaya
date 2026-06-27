import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

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
}

class GamificationEngine {
  final Map<String, Achievement> _achievements = {};
  final Map<String, UserScore> _userScores = {};
  final Random _random = Random.secure();

  final _achievementController = StreamController<Achievement>.broadcast();
  Stream<Achievement> get achievementStream => _achievementController.stream;

  final _scoreController = StreamController<UserScore>.broadcast();
  Stream<UserScore> get scoreStream => _scoreController.stream;

  GamificationEngine() {
    _initializeAchievements();
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

    _achievementController.add(achievement);
    debugPrint('Achievement unlocked: ${achievement.title}');
  }

  void _emitScore(String userId) {
    final score = _userScores[userId];
    if (score != null) {
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
