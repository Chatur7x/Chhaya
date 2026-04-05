import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../gamification_engine.dart';

final gamificationEngineProvider = Provider<GamificationEngine>((ref) {
  return GamificationEngine();
});

class GamificationScreen extends ConsumerStatefulWidget {
  const GamificationScreen({super.key});

  @override
  ConsumerState<GamificationScreen> createState() => _GamificationScreenState();
}

class _GamificationScreenState extends ConsumerState<GamificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AchievementCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(gamificationEngineProvider);
    final achievements = engine.getAchievements('me');
    final scores = engine.getScore('me') ?? UserScore(odId: 'me');

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Achievements'),
        backgroundColor: ChaayaTheme.background,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChaayaTheme.accent,
          tabs: const [
            Tab(text: 'Achievements'),
            Tab(text: 'Leaderboard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events),
            onPressed: () => _showScoreDetails(scores),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAchievementsTab(achievements),
          _buildLeaderboardTab(engine),
        ],
      ),
    );
  }

  Widget _buildAchievementsTab(List<Achievement> achievements) {
    final filtered = _selectedCategory == null
        ? achievements
        : achievements.where((a) => a.category == _selectedCategory).toList();

    return Column(
      children: [
        _buildCategoryFilter(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final achievement = filtered[index];
              return _buildAchievementCard(achievement);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(null, 'All'),
          _buildFilterChip(AchievementCategory.relay, 'Relay'),
          _buildFilterChip(AchievementCategory.sos, 'SOS'),
          _buildFilterChip(AchievementCategory.exploration, 'Exploration'),
          _buildFilterChip(AchievementCategory.social, 'Social'),
          _buildFilterChip(AchievementCategory.knowledge, 'Knowledge'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(AchievementCategory? category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategory = selected ? category : null;
          });
        },
        selectedColor: ChaayaTheme.accent.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildAchievementCard(Achievement achievement) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: achievement.isUnlocked
                ? ChaayaTheme.accent.withValues(alpha: 0.2)
                : ChaayaTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getCategoryIcon(achievement.category),
            color: achievement.isUnlocked
                ? ChaayaTheme.accent
                : ChaayaTheme.textMuted,
            size: 28,
          ),
        ),
        title: Text(
          achievement.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: achievement.isUnlocked
                ? ChaayaTheme.textPrimary
                : ChaayaTheme.textMuted,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              achievement.description,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: achievement.progress,
                      backgroundColor: ChaayaTheme.surface,
                      valueColor: AlwaysStoppedAnimation(
                        achievement.isUnlocked
                            ? ChaayaTheme.safeGreen
                            : ChaayaTheme.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${achievement.points} pts',
                  style: TextStyle(
                    color: ChaayaTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: achievement.isUnlocked
            ? const Icon(Icons.check_circle, color: ChaayaTheme.safeGreen)
            : Text('${achievement.current}/${achievement.target}'),
      ),
    );
  }

  Widget _buildLeaderboardTab(GamificationEngine engine) {
    final stats = engine.getStatistics('me');
    final breakdown = stats['scoreBreakdown'] as Map<String, dynamic>;
    final unlocked = stats['achievementsUnlocked'] as int;
    final total = stats['totalAchievements'] as int;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: ChaayaTheme.glassDecoration(borderRadius: 16),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: ChaayaTheme.accent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events,
                    size: 40, color: ChaayaTheme.accent),
              ),
              const SizedBox(height: 16),
              Text(
                '${stats['totalScore']} pts',
                style: ChaayaTheme.heading1,
              ),
              const SizedBox(height: 8),
              Text(
                'Rank #${(stats['totalScore'] as int) ~/ 100 + 1}',
                style: const TextStyle(color: ChaayaTheme.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$unlocked / $total Achievements Unlocked',
                  style: ChaayaTheme.heading3),
              const SizedBox(height: 12),
              _buildScoreRow('Relay', breakdown['relay'] ?? 0),
              _buildScoreRow('SOS', breakdown['sos'] ?? 0),
              _buildScoreRow('Exploration', breakdown['exploration'] ?? 0),
              _buildScoreRow('Social', breakdown['social'] ?? 0),
              _buildScoreRow('Knowledge', breakdown['knowledge'] ?? 0),
            ],
          ),
        ),
      ],
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return Colors.amber;
      case 1:
        return Colors.grey;
      case 2:
        return Colors.brown;
      default:
        return ChaayaTheme.accent;
    }
  }

  void _showScoreDetails(UserScore score) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ChaayaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ChaayaTheme.accent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events,
                size: 40,
                color: ChaayaTheme.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Total Score: ${score.totalPoints}',
              style: ChaayaTheme.heading2,
            ),
            const SizedBox(height: 24),
            _buildScoreRow('Relay', score.relayScore),
            _buildScoreRow('SOS', score.sosScore),
            _buildScoreRow('Exploration', score.explorationScore),
            _buildScoreRow('Social', score.socialScore),
            _buildScoreRow('Knowledge', score.knowledgeScore),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$value pts',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(AchievementCategory category) {
    switch (category) {
      case AchievementCategory.relay:
        return Icons.cell_tower;
      case AchievementCategory.sos:
        return Icons.emergency;
      case AchievementCategory.exploration:
        return Icons.explore;
      case AchievementCategory.social:
        return Icons.people;
      case AchievementCategory.knowledge:
        return Icons.school;
    }
  }
}
