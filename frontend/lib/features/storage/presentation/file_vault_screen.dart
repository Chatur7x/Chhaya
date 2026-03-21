import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/secure_storage_manager.dart';

/// File Vault Screen — encrypted file storage with folders.
class FileVaultScreen extends ConsumerStatefulWidget {
  const FileVaultScreen({super.key});

  @override
  ConsumerState<FileVaultScreen> createState() => _FileVaultScreenState();
}

class _FileVaultScreenState extends ConsumerState<FileVaultScreen> {
  List<VaultFile> _files = [];
  bool _loading = true;
  StorageStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final storage = ref.read(secureStorageProvider);
    await storage.initialize('vault_master_key_temp_123'); // In production, derive from user pin
    
    final files = storage.getAllFiles();
    final stats = await storage.getStorageStats();
    
    if (mounted) {
      setState(() {
        _files = files;
        _stats = stats;
        _loading = false;
      });
    }
  }

  Future<void> _addMockFile() async {
    final storage = ref.read(secureStorageProvider);
    final dir = await getTemporaryDirectory();
    final tempFile = File('${dir.path}/mock_survival_guide.txt');
    await tempFile.writeAsString('Water purification: boil for 1 minute.');
    
    await storage.saveFile(
      tempFile.path, 
      'Survival Guide.txt', 
      folder: 'Documents',
    );
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.folder_special, color: ChaayaTheme.bleColor, size: 22),
            SizedBox(width: 10),
            Text('File Vault'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: ChaayaTheme.textSecondary),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.sort, color: ChaayaTheme.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator(color: ChaayaTheme.accent))
        : Column(
        children: [
          // Storage info bar
          if (_stats != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: ChaayaTheme.bleColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storage, color: ChaayaTheme.bleColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${(_stats!.totalVaultBytes / 1024 / 1024).toStringAsFixed(1)} MB used',
                            style: const TextStyle(color: ChaayaTheme.textPrimary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('${_stats!.totalFiles} files • All encrypted (AES-256)',
                            style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock, size: 16, color: ChaayaTheme.safeGreen),
                ],
              ),
            ),

          // Folders row (Dynamic calculation)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _folderTile('Documents', _files.where((f) => f.folder == 'Documents').length, ChaayaTheme.bleColor),
                _folderTile('Maps', _files.where((f) => f.folder == 'Maps').length, ChaayaTheme.safeGreen),
                _folderTile('Shared', _files.where((f) => f.folder == 'Shared').length, ChaayaTheme.warningYellow),
                _folderTile('Emergency', _files.where((f) => f.folder == 'Emergency').length, ChaayaTheme.sosRed),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Files
          Expanded(
            child: _files.isEmpty 
              ? const Center(
                  child: Text('Vault is empty. Add encrypted files.', 
                    style: TextStyle(color: ChaayaTheme.textMuted)))
              : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _files.length,
              itemBuilder: (context, i) => _fileTile(_files[i]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMockFile,
        backgroundColor: ChaayaTheme.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _folderTile(String name, int count, Color color) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder, color: color, size: 28),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontSize: 11, color: ChaayaTheme.textPrimary),
              overflow: TextOverflow.ellipsis),
          Text('$count items', style: const TextStyle(fontSize: 9, color: ChaayaTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _fileTile(VaultFile file) {
    IconData icon = Icons.insert_drive_file;
    if (file.mimeType.contains('pdf')) icon = Icons.picture_as_pdf;
    if (file.mimeType.contains('image')) icon = Icons.image;
    if (file.mimeType.contains('text')) icon = Icons.description;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: ChaayaTheme.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: ChaayaTheme.accent, size: 20),
        ),
        title: Text(file.fileName, style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w400)),
        subtitle: Row(
          children: [
            const Icon(Icons.lock, size: 10, color: ChaayaTheme.safeGreen),
            const SizedBox(width: 4),
            Text('${(file.size / 1024).toStringAsFixed(1)} KB • Encrypted', style: const TextStyle(fontSize: 11, color: ChaayaTheme.textMuted)),
          ],
        ),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert, color: ChaayaTheme.textMuted, size: 18),
          color: ChaayaTheme.surface,
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'share', child: Text('Share via Mesh', style: TextStyle(color: ChaayaTheme.textPrimary, fontSize: 13))),
            const PopupMenuItem(value: 'export', child: Text('Export', style: TextStyle(color: ChaayaTheme.textPrimary, fontSize: 13))),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: ChaayaTheme.sosRed, fontSize: 13))),
          ],
          onSelected: (value) async {
            if (value == 'delete') {
              final storage = ref.read(secureStorageProvider);
              await storage.deleteFile(file.id);
              _loadFiles();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deleted ${file.fileName}')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}

