import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../mission_planner.dart';

final missionPlannerProvider = Provider<MissionPlanner>((ref) {
  return MissionPlanner();
});

class MissionPlannerScreen extends ConsumerStatefulWidget {
  const MissionPlannerScreen({super.key});

  @override
  ConsumerState<MissionPlannerScreen> createState() =>
      _MissionPlannerScreenState();
}

class _MissionPlannerScreenState extends ConsumerState<MissionPlannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    final planner = ref.watch(missionPlannerProvider);
    final activeMissions = planner.getActiveMissions();
    final allMissions = planner.getUserMissions('me');
    final completedMissions =
        allMissions.where((m) => m.status == 'completed').toList();

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Mission Planner'),
        backgroundColor: ChaayaTheme.background,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChaayaTheme.accent,
          tabs: [
            Tab(text: 'Active (${activeMissions.length})'),
            Tab(text: 'Completed (${completedMissions.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMissionsList(activeMissions),
          _buildMissionsList(completedMissions),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateMissionDialog(planner),
        backgroundColor: ChaayaTheme.accent,
        icon: const Icon(Icons.add),
        label: const Text('New Mission'),
      ),
    );
  }

  Widget _buildMissionsList(List<Mission> missions) {
    if (missions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: ChaayaTheme.textMuted),
            SizedBox(height: 16),
            Text('No missions yet',
                style: TextStyle(color: ChaayaTheme.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: missions.length,
      itemBuilder: (context, index) {
        final mission = missions[index];
        return _buildMissionCard(mission);
      },
    );
  }

  Widget _buildMissionCard(Mission mission) {
    final completedTasks = mission.tasks.where((t) => t.isComplete).length;
    final progress =
        mission.tasks.isEmpty ? 0.0 : completedTasks / mission.tasks.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getStatusColor(mission.status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_getStatusIcon(mission.status),
                  color: _getStatusColor(mission.status)),
            ),
            title: Text(mission.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(mission.description,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(mission.status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(mission.status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(mission.status))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$completedTasks / ${mission.tasks.length} tasks',
                        style: const TextStyle(
                            fontSize: 12, color: ChaayaTheme.textMuted)),
                    Text('${(progress * 100).toInt()}%',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: ChaayaTheme.accent)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: ChaayaTheme.surface,
                      valueColor:
                          const AlwaysStoppedAnimation(ChaayaTheme.accent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showTasksSheet(mission),
                    icon: const Icon(Icons.checklist, size: 18),
                    label: const Text('Tasks'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _activateMission(mission),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: ChaayaTheme.safeGreen),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Activate'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateMissionDialog(MissionPlanner planner) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChaayaTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create New Mission', style: ChaayaTheme.heading2),
            const SizedBox(height: 24),
            TextField(
                controller: nameController,
                decoration: InputDecoration(
                    labelText: 'Mission Name',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 16),
            TextField(
                controller: descController,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      planner.createMission(
                          name: nameController.text,
                          description: descController.text,
                          leaderId: 'me',
                          members: []);
                      Navigator.pop(context);
                      setState(() {});
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: ChaayaTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Create Mission')),
            ),
          ],
        ),
      ),
    );
  }

  void _showTasksSheet(Mission mission) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ChaayaTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tasks - ${mission.name}', style: ChaayaTheme.heading3),
            const SizedBox(height: 16),
            if (mission.tasks.isEmpty)
              const Text('No tasks yet')
            else
              ...mission.tasks.map((task) => ListTile(
                    leading: Checkbox(
                        value: task.isComplete,
                        onChanged: (value) {
                          final planner = ref.read(missionPlannerProvider);
                          if (!task.isComplete)
                            planner.completeTask(mission.id, task.id);
                          setState(() {});
                        }),
                    title: Text(task.title),
                    subtitle: Text(task.status),
                  )),
          ],
        ),
      ),
    );
  }

  void _activateMission(Mission mission) {
    final planner = ref.read(missionPlannerProvider);
    planner.activateMission(mission.id);
    setState(() {});
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return ChaayaTheme.safeGreen;
      case 'active':
        return ChaayaTheme.accent;
      case 'planning':
        return ChaayaTheme.warningYellow;
      default:
        return ChaayaTheme.textMuted;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'active':
        return Icons.play_circle;
      case 'planning':
        return Icons.edit_note;
      default:
        return Icons.assignment;
    }
  }
}
