import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/backup/encrypted_backup_service.dart';
import '../../../l10n/app_localizations.dart';

final encryptedBackupServiceProvider =
    Provider((ref) => EncryptedBackupService());

final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  final service = ref.watch(encryptedBackupServiceProvider);
  final files = await service.listBackups();
  final backups = <BackupInfo>[];

  for (final file in files) {
    final size = await service.getBackupSize(file.path);
    final date = await service.getBackupDate(file.path);
    backups.add(BackupInfo(
      path: file.path,
      fileName: file.path.split('/').last,
      size: size,
      date: date ?? DateTime.now(),
    ));
  }

  return backups;
});

class BackupInfo {
  final String path;
  final String fileName;
  final int size;
  final DateTime date;

  BackupInfo({
    required this.path,
    required this.fileName,
    required this.size,
    required this.date,
  });

  String get formattedSize {
    final mb = size / (1024 * 1024);
    return mb > 1
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(size / 1024).toStringAsFixed(1)} KB';
  }

  String get formattedDate {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isLoading = false;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _checkPassword();
  }

  Future<void> _checkPassword() async {
    final service = ref.read(encryptedBackupServiceProvider);
    final hasPassword = await service.hasBackupPassword();
    setState(() => _hasPassword = hasPassword);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final backupsAsync = ref.watch(backupListProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: Text(l10n.backup),
        backgroundColor: ChaayaTheme.background,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              title: l10n.createBackup,
              description: l10n.backupDescription,
              icon: Icons.backup,
              actionLabel: l10n.createBackup,
              onAction: _hasPassword ? _createBackup : _setupPassword,
              isLoading: _isLoading,
            ),
            const SizedBox(height: 24),
            Text(l10n.restoreBackup, style: ChaayaTheme.heading3),
            const SizedBox(height: 12),
            backupsAsync.when(
              data: (backups) => backups.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(24),
                      decoration: ChaayaTheme.glassDecoration(),
                      child: Center(
                        child: Text(
                          'No backups available',
                          style: ChaayaTheme.bodyMedium,
                        ),
                      ),
                    )
                  : Column(
                      children: backups
                          .map((b) => _BackupCard(
                                backup: b,
                                onRestore: () => _confirmRestore(b),
                                onDelete: () => _confirmDelete(b),
                              ))
                          .toList(),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e', style: ChaayaTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setupPassword() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: Text('Set Backup Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.enterPassword,
                hintText: 'Enter a strong password',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                hintText: 'Re-enter password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final service = ref.read(encryptedBackupServiceProvider);
      await service.setBackupPassword(result);
      setState(() => _hasPassword = true);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(encryptedBackupServiceProvider);
      final path = await service
          .createBackup(boxNames: ['contacts', 'messages', 'settings']);
      ref.invalidate(backupListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup created: ${path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _confirmRestore(BackupInfo backup) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: Text(l10n.restoreBackup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Restore ${backup.fileName}?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.enterPassword),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _restoreBackup(backup.path, controller.text);
            },
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup(String path, String password) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(encryptedBackupServiceProvider);
      await service.restoreBackup(filePath: path, password: password);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _confirmDelete(BackupInfo backup) {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: Text(l10n.delete),
        content: Text('Delete ${backup.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final service = ref.read(encryptedBackupServiceProvider);
              await service.deleteBackup(backup.path);
              ref.invalidate(backupListProvider);
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isLoading;

  const _SectionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ChaayaTheme.glassDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ChaayaTheme.accent),
              const SizedBox(width: 12),
              Text(title, style: ChaayaTheme.heading3),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: ChaayaTheme.bodyMedium),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isLoading ? null : onAction,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  final BackupInfo backup;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _BackupCard({
    required this.backup,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: ChaayaTheme.glassDecoration(),
      child: Row(
        children: [
          const Icon(Icons.file_copy, color: ChaayaTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(backup.fileName, style: ChaayaTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  '${backup.formattedSize} - ${backup.formattedDate}',
                  style: ChaayaTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restore, color: ChaayaTheme.safeGreen),
            onPressed: onRestore,
            tooltip: l10n.restore,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: ChaayaTheme.sosRed),
            onPressed: onDelete,
            tooltip: l10n.delete,
          ),
        ],
      ),
    );
  }
}
