import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/map_download_service.dart';

final mapDownloadServiceProvider = Provider((ref) => MapDownloadService());

final downloadTasksProvider = FutureProvider<List<DownloadTask>>((ref) async {
  final service = ref.watch(mapDownloadServiceProvider);
  return service.getAllDownloads();
});

final storageUsedProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(mapDownloadServiceProvider);
  return service.getStorageUsed();
});

class OfflineMapsScreen extends ConsumerWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tasksAsync = ref.watch(downloadTasksProvider);
    final storageAsync = ref.watch(storageUsedProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: Text(l10n.offlineMaps),
        backgroundColor: ChaayaTheme.background,
      ),
      body: Column(
        children: [
          storageAsync.when(
            data: (bytes) => _StorageInfo(bytes: bytes),
            loading: () => const _StorageInfo(bytes: 0),
            error: (_, __) => const _StorageInfo(bytes: 0),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showDownloadDialog(context, ref),
                icon: const Icon(Icons.download),
                label: Text(l10n.downloadRegion),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChaayaTheme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: tasksAsync.when(
              data: (tasks) => tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 64, color: ChaayaTheme.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            l10n.downloadMaps,
                            style: ChaayaTheme.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: tasks.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return _RegionCard(task: task, ref: ref);
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showDownloadDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    double minLat = -90, maxLat = 90, minLon = -180, maxLon = 180;
    int minZoom = 1, maxZoom = 15;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: ChaayaTheme.surface,
          title: Text(l10n.downloadRegion),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Region Name',
                    hintText: 'e.g., Mountain Area',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Zoom: $minZoom - $maxZoom', style: ChaayaTheme.bodySmall),
                RangeSlider(
                  values: RangeValues(minZoom.toDouble(), maxZoom.toDouble()),
                  min: 1,
                  max: 18,
                  divisions: 17,
                  onChanged: (v) {
                    setState(() {
                      minZoom = v.start.round();
                      maxZoom = v.end.round();
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  Navigator.pop(context);
                  final service = ref.read(mapDownloadServiceProvider);
                  await service.downloadRegion(
                    minLat: minLat,
                    maxLat: maxLat,
                    minLon: minLon,
                    maxLon: maxLon,
                    minZoom: minZoom,
                    maxZoom: maxZoom,
                    regionName: nameController.text,
                    onProgress: (p) {
                      ref.invalidate(downloadTasksProvider);
                      ref.invalidate(storageUsedProvider);
                    },
                  );
                  ref.invalidate(downloadTasksProvider);
                  ref.invalidate(storageUsedProvider);
                }
              },
              child: Text(l10n.downloadRegion),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageInfo extends StatelessWidget {
  final int bytes;

  const _StorageInfo({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final mb = bytes / (1024 * 1024);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: ChaayaTheme.glassDecoration(),
      child: Row(
        children: [
          const Icon(Icons.storage, color: ChaayaTheme.accent),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Storage Used', style: ChaayaTheme.bodyMedium),
              Text(
                mb > 1
                    ? '${mb.toStringAsFixed(1)} MB'
                    : '${(bytes / 1024).toStringAsFixed(1)} KB',
                style: ChaayaTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  final DownloadTask task;
  final WidgetRef ref;

  const _RegionCard({required this.task, required this.ref});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isCompleted = task.status == DownloadStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: ChaayaTheme.glassDecoration(),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Icon(
          isCompleted ? Icons.check_circle : Icons.downloading,
          color: isCompleted ? ChaayaTheme.safeGreen : ChaayaTheme.accent,
        ),
        title: Text(task.regionName, style: ChaayaTheme.bodyLarge),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Zoom ${task.minZoom} - ${task.maxZoom}',
              style: ChaayaTheme.bodySmall,
            ),
            if (!isCompleted) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: task.progress,
                backgroundColor: ChaayaTheme.surfaceLight,
                color: ChaayaTheme.accent,
              ),
              const SizedBox(height: 4),
              Text(
                '${(task.progress * 100).toStringAsFixed(0)}%',
                style: ChaayaTheme.bodySmall,
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: ChaayaTheme.sosRed),
          onPressed: () => _confirmDelete(context),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: Text(l10n.delete),
        content: Text('Delete ${task.regionName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final service = ref.read(mapDownloadServiceProvider);
              await service.deleteRegion(task.regionName);
              ref.invalidate(downloadTasksProvider);
              ref.invalidate(storageUsedProvider);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}

void debugPrint(String msg) => print(msg);
