import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/sync/vector_clock.dart';
import '../crowd_intelligence.dart';

final crowdIntelProvider = Provider<CrowdIntelligence>((ref) {
  return CrowdIntelligence();
});

class CrowdIntelligenceScreen extends ConsumerStatefulWidget {
  const CrowdIntelligenceScreen({super.key});

  @override
  ConsumerState<CrowdIntelligenceScreen> createState() =>
      _CrowdIntelligenceScreenState();
}

class _CrowdIntelligenceScreenState
    extends ConsumerState<CrowdIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  IntelReportType? _selectedFilter;

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
    final intel = ref.watch(crowdIntelProvider);
    final reports =
        intel.getReportsByType(_selectedFilter ?? IntelReportType.danger);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Crowd Intelligence'),
        backgroundColor: ChaayaTheme.background,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChaayaTheme.accent,
          tabs: const [
            Tab(text: 'Active Reports'),
            Tab(text: 'Map View'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReportsList(reports),
          _buildMapView(reports),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReportDialog(intel),
        backgroundColor: ChaayaTheme.accent,
        icon: const Icon(Icons.add_alert),
        label: const Text('Report'),
      ),
    );
  }

  Widget _buildReportsList(List<IntelReport> reports) {
    final filtered = _selectedFilter == null
        ? reports
        : reports.where((r) => r.type == _selectedFilter).toList();

    return Column(
      children: [
        _buildFilterChips(),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('No reports',
                      style: TextStyle(color: ChaayaTheme.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildReportCard(filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(null, 'All'),
          _chip(IntelReportType.danger, 'Danger'),
          _chip(IntelReportType.safe, 'Safe'),
          _chip(IntelReportType.resource, 'Resource'),
          _chip(IntelReportType.infrastructure, 'Infra'),
        ],
      ),
    );
  }

  Widget _chip(IntelReportType? type, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _selectedFilter == type,
        onSelected: (s) => setState(() => _selectedFilter = s ? type : null),
      ),
    );
  }

  Widget _buildReportCard(IntelReport report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getTypeColor(report.type).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_getTypeIcon(report.type),
              color: _getTypeColor(report.type)),
        ),
        title: Text(report.type.name.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _getTypeColor(report.type))),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (report.description != null)
              Text(report.description!, maxLines: 2),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.timer, size: 12, color: ChaayaTheme.textMuted),
                const SizedBox(width: 4),
                Text('${report.ttlRemaining.inMinutes}m left',
                    style: const TextStyle(
                        fontSize: 12, color: ChaayaTheme.textMuted)),
                const SizedBox(width: 12),
                Icon(Icons.verified, size: 12, color: ChaayaTheme.textMuted),
                const SizedBox(width: 4),
                Text('${report.verifiedBy.length} verified',
                    style: const TextStyle(
                        fontSize: 12, color: ChaayaTheme.textMuted)),
              ],
            ),
          ],
        ),
        trailing: _buildConfidenceBadge(report.confidence),
      ),
    );
  }

  Widget _buildConfidenceBadge(int confidence) {
    Color color;
    if (confidence >= 80)
      color = ChaayaTheme.safeGreen;
    else if (confidence >= 50)
      color = ChaayaTheme.warningYellow;
    else
      color = ChaayaTheme.sosRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$confidence%',
          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildMapView(List<IntelReport> reports) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map, size: 64, color: ChaayaTheme.textMuted),
          const SizedBox(height: 16),
          const Text('Map View', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${reports.length} active reports',
              style: const TextStyle(color: ChaayaTheme.textMuted)),
        ],
      ),
    );
  }

  void _showReportDialog(CrowdIntelligence intel) {
    IntelReportType selectedType = IntelReportType.danger;
    final descController = TextEditingController();
    int confidence = 70;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChaayaTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report Intel', style: ChaayaTheme.heading2),
              const SizedBox(height: 24),
              DropdownButtonFormField<IntelReportType>(
                value: selectedType,
                decoration: InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
                items: IntelReportType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (v) => setModalState(() => selectedType = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 16),
              Text('Confidence: $confidence%'),
              Slider(
                  value: confidence.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 10,
                  onChanged: (v) =>
                      setModalState(() => confidence = v.toInt())),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    intel.createReport(
                      type: selectedType,
                      latitude: 0,
                      longitude: 0,
                      radius: 100,
                      reporterId: 'me',
                      description: descController.text,
                    );
                    Navigator.pop(context);
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: ChaayaTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(IntelReportType type) {
    switch (type) {
      case IntelReportType.danger:
        return ChaayaTheme.sosRed;
      case IntelReportType.safe:
        return ChaayaTheme.safeGreen;
      case IntelReportType.resource:
        return ChaayaTheme.accent;
      case IntelReportType.infrastructure:
        return ChaayaTheme.warningYellow;
    }
  }

  IconData _getTypeIcon(IntelReportType type) {
    switch (type) {
      case IntelReportType.danger:
        return Icons.warning;
      case IntelReportType.safe:
        return Icons.check_circle;
      case IntelReportType.resource:
        return Icons.inventory;
      case IntelReportType.infrastructure:
        return Icons.business;
    }
  }
}
