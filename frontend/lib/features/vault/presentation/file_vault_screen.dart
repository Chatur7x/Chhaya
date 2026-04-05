import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart' hide FileType;
import '../../../core/theme/chaaya_theme.dart';
import '../data/file_vault_service.dart';

final fileVaultProvider = FutureProvider<FileVaultService>((ref) async {
  return await FileVaultService.getInstance();
});

final currentFolderProvider = StateProvider<String?>((ref) => null);

class FileVaultScreen extends ConsumerStatefulWidget {
  const FileVaultScreen({super.key});

  @override
  ConsumerState<FileVaultScreen> createState() => _FileVaultScreenState();
}

class _FileVaultScreenState extends ConsumerState<FileVaultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSelectionMode = false;
  Set<String> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      final service = await ref.read(fileVaultProvider.future);
      final currentFolder = ref.read(currentFolderProvider);

      for (final file in result.files) {
        if (file.path != null) {
          await service.saveFile(
            sourcePath: file.path!,
            folderId: currentFolder ?? 'root',
            ownerId: 'local',
          );
        }
      }
      setState(() {});
    }
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: ChaayaTheme.surface,
          title: const Text('New Folder',
              style: TextStyle(color: ChaayaTheme.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: ChaayaTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Folder name',
              hintStyle: TextStyle(color: ChaayaTheme.textMuted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      final service = await ref.read(fileVaultProvider.future);
      await service.createFolder(
        name: name,
        parentId: ref.read(currentFolderProvider),
        ownerId: 'local',
      );
      setState(() {});
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedFiles.clear();
      }
    });
  }

  void _toggleSelection(String fileId) {
    setState(() {
      if (_selectedFiles.contains(fileId)) {
        _selectedFiles.remove(fileId);
      } else {
        _selectedFiles.add(fileId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vaultAsync = ref.watch(fileVaultProvider);
    final currentFolder = ref.watch(currentFolderProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.surface,
        title: _isSelectionMode
            ? Text('${_selectedFiles.length} selected',
                style: const TextStyle(color: ChaayaTheme.textPrimary))
            : const Text('File Vault',
                style: TextStyle(color: ChaayaTheme.textPrimary)),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.share, color: ChaayaTheme.accent),
              onPressed: _selectedFiles.isEmpty ? null : () => _shareSelected(),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: ChaayaTheme.sosRed),
              onPressed:
                  _selectedFiles.isEmpty ? null : () => _deleteSelected(),
            ),
          ],
          IconButton(
            icon: Icon(
              _isSelectionMode ? Icons.close : Icons.select_all,
              color: ChaayaTheme.textPrimary,
            ),
            onPressed: _toggleSelectionMode,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChaayaTheme.accent,
          labelColor: ChaayaTheme.accent,
          unselectedLabelColor: ChaayaTheme.textMuted,
          tabs: const [
            Tab(text: 'My Files', icon: Icon(Icons.folder)),
            Tab(text: 'Shared', icon: Icon(Icons.group)),
            Tab(text: 'Trash', icon: Icon(Icons.delete_outline)),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: ChaayaTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: const TextStyle(color: ChaayaTheme.textMuted),
                prefixIcon:
                    const Icon(Icons.search, color: ChaayaTheme.textMuted),
                filled: true,
                fillColor: ChaayaTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          if (currentFolder != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(currentFolderProvider.notifier).state = null,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back'),
                    style: TextButton.styleFrom(
                        foregroundColor: ChaayaTheme.accent),
                  ),
                ],
              ),
            ),
          Expanded(
            child: vaultAsync.when(
              data: (service) => TabBarView(
                controller: _tabController,
                children: [
                  _buildFilesList(service, currentFolder),
                  _buildSharedList(service),
                  _buildTrashList(service),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: ChaayaTheme.sosRed))),
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'folder',
                  backgroundColor: ChaayaTheme.accent,
                  onPressed: _createFolder,
                  child: const Icon(Icons.create_new_folder),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'file',
                  backgroundColor: ChaayaTheme.accent,
                  onPressed: _addFile,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
    );
  }

  Widget _buildFilesList(FileVaultService service, String? currentFolderId) {
    final folders = service.getFolders(parentId: currentFolderId);
    final files = service.getFiles(
      folderId: currentFolderId ?? 'root',
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
    );

    if (folders.isEmpty && files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open,
                size: 80, color: ChaayaTheme.textMuted.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No files yet' : 'No results found',
              style:
                  const TextStyle(color: ChaayaTheme.textMuted, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Tap + to add files'
                  : 'Try a different search',
              style: const TextStyle(color: ChaayaTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        ...folders.map((f) => _buildFolderTile(f, service)),
        ...files.map((f) => _buildFileTile(f, service)),
      ],
    );
  }

  Widget _buildFolderTile(VaultFolder folder, FileVaultService service) {
    final fileCount = service.getFiles(folderId: folder.id).length;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: ChaayaTheme.accent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.folder, color: ChaayaTheme.accent),
      ),
      title: Text(folder.name,
          style: const TextStyle(color: ChaayaTheme.textPrimary)),
      subtitle: Text('$fileCount files',
          style: const TextStyle(color: ChaayaTheme.textMuted)),
      trailing: PopupMenuButton(
        icon: const Icon(Icons.more_vert, color: ChaayaTheme.textMuted),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'share', child: Text('Share')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
        onSelected: (value) => _handleFolderAction(value, folder, service),
      ),
      onTap: () => ref.read(currentFolderProvider.notifier).state = folder.id,
    );
  }

  Widget _buildFileTile(VaultFile file, FileVaultService service) {
    final isSelected = _selectedFiles.contains(file.id);

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _getFileColor(file.type).withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_getFileIcon(file.type), color: _getFileColor(file.type)),
      ),
      title: Text(
        file.name,
        style: const TextStyle(color: ChaayaTheme.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${service.formatFileSize(file.size)} • ${_formatDate(file.modifiedAt)}',
        style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 12),
      ),
      trailing: _isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelection(file.id),
              activeColor: ChaayaTheme.accent,
            )
          : PopupMenuButton(
              icon: const Icon(Icons.more_vert, color: ChaayaTheme.textMuted),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'preview', child: Text('Preview')),
                const PopupMenuItem(value: 'share', child: Text('Share')),
                const PopupMenuItem(value: 'tag', child: Text('Add Tag')),
                const PopupMenuItem(
                    value: 'version', child: Text('Version History')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              onSelected: (value) => _handleFileAction(value, file, service),
            ),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(file.id);
        } else if (service.canPreview(file.name)) {
          _previewFile(file, service);
        }
      },
    );
  }

  Widget _buildSharedList(FileVaultService service) {
    final folders = service.getSharedFolders();

    if (folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group,
                size: 80, color: ChaayaTheme.textMuted.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'No shared folders',
              style: TextStyle(color: ChaayaTheme.textMuted, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a folder and share it',
              style: TextStyle(color: ChaayaTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: folders.map((f) => _buildSharedFolderTile(f, service)).toList(),
    );
  }

  Widget _buildSharedFolderTile(VaultFolder folder, FileVaultService service) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.folder_shared, color: Colors.green),
      ),
      title: Text(folder.name,
          style: const TextStyle(color: ChaayaTheme.textPrimary)),
      subtitle: Text(
        '${folder.sharedWithDeviceIds.length} members',
        style: const TextStyle(color: ChaayaTheme.textMuted),
      ),
      trailing: const Icon(Icons.sync, color: Colors.green, size: 20),
      onTap: () => ref.read(currentFolderProvider.notifier).state = folder.id,
    );
  }

  Widget _buildTrashList(FileVaultService service) {
    final deletedFiles = service.getDeletedFiles();

    if (deletedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline,
                size: 80, color: ChaayaTheme.textMuted.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'Trash is empty',
              style: TextStyle(color: ChaayaTheme.textMuted, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _emptyTrash(service),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Empty Trash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ChaayaTheme.sosRed,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: deletedFiles
                .map((f) => _buildTrashFileTile(f, service))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTrashFileTile(VaultFile file, FileVaultService service) {
    return ListTile(
      leading: Icon(_getFileIcon(file.type), color: ChaayaTheme.textMuted),
      title: Text(file.name,
          style: const TextStyle(color: ChaayaTheme.textPrimary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore, color: ChaayaTheme.accent),
            onPressed: () => service.restoreFile(file.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: ChaayaTheme.sosRed),
            onPressed: () => service.permanentlyDeleteFile(file.id),
          ),
        ],
      ),
    );
  }

  void _handleFolderAction(
      String action, VaultFolder folder, FileVaultService service) {
    switch (action) {
      case 'rename':
        _renameFolder(folder, service);
        break;
      case 'share':
        _shareFolder(folder);
        break;
      case 'delete':
        service.deleteFolder(folder.id);
        setState(() {});
        break;
    }
  }

  void _handleFileAction(
      String action, VaultFile file, FileVaultService service) {
    switch (action) {
      case 'preview':
        _previewFile(file, service);
        break;
      case 'share':
        _shareFile(file);
        break;
      case 'tag':
        _addTag(file, service);
        break;
      case 'version':
        _showVersionHistory(file, service);
        break;
      case 'rename':
        _renameFile(file, service);
        break;
      case 'delete':
        service.deleteFile(file.id);
        setState(() {});
        break;
    }
  }

  Future<void> _renameFolder(
      VaultFolder folder, FileVaultService service) async {
    final newName = await _showRenameDialog(folder.name);
    if (newName != null && newName.isNotEmpty) {
      await service.renameFolder(folder.id, newName);
      setState(() {});
    }
  }

  Future<void> _renameFile(VaultFile file, FileVaultService service) async {
    final newName = await _showRenameDialog(file.name);
    if (newName != null && newName.isNotEmpty) {
      await service.renameFile(file.id, newName);
      setState(() {});
    }
  }

  Future<String?> _showRenameDialog(String currentName) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: currentName);
        return AlertDialog(
          backgroundColor: ChaayaTheme.surface,
          title: const Text('Rename',
              style: TextStyle(color: ChaayaTheme.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: ChaayaTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  void _shareFolder(VaultFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: const Text('Share Folder',
            style: TextStyle(color: ChaayaTheme.textPrimary)),
        content: const Text(
          'This folder can be shared over the mesh network. Other devices in range will be able to access files in this folder.',
          style: TextStyle(color: ChaayaTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sharing over mesh network...')),
              );
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _shareFile(VaultFile file) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sharing ${file.name} over mesh...')),
    );
  }

  Future<void> _addTag(VaultFile file, FileVaultService service) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: ChaayaTheme.surface,
          title: const Text('Add Tag',
              style: TextStyle(color: ChaayaTheme.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: ChaayaTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Enter tag',
              hintStyle: TextStyle(color: ChaayaTheme.textMuted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (tag != null && tag.isNotEmpty) {
      await service.addTag(file.id, tag);
      setState(() {});
    }
  }

  void _showVersionHistory(VaultFile file, FileVaultService service) {
    final versions = service.getVersions(file.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: ChaayaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Version History',
              style: TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (versions.isEmpty)
              const Text(
                'No previous versions',
                style: TextStyle(color: ChaayaTheme.textMuted),
              )
            else
              ...versions.take(5).map((v) => ListTile(
                    leading:
                        const Icon(Icons.history, color: ChaayaTheme.textMuted),
                    title: Text('Version ${v.versionNumber}',
                        style: const TextStyle(color: ChaayaTheme.textPrimary)),
                    subtitle: Text(_formatDate(v.createdAt),
                        style: const TextStyle(color: ChaayaTheme.textMuted)),
                    trailing: TextButton(
                      onPressed: () {
                        service.rollbackVersion(file.id, v.versionNumber);
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: const Text('Restore'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  void _previewFile(VaultFile file, FileVaultService service) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening ${file.name}...')),
    );
  }

  void _shareSelected() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Sharing ${_selectedFiles.length} files over mesh...')),
    );
    _selectedFiles.clear();
    _toggleSelectionMode();
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: const Text('Delete Files?',
            style: TextStyle(color: ChaayaTheme.textPrimary)),
        content: Text('${_selectedFiles.length} files will be moved to trash.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = await ref.read(fileVaultProvider.future);
      for (final id in _selectedFiles) {
        await service.deleteFile(id);
      }
      _selectedFiles.clear();
      _toggleSelectionMode();
      setState(() {});
    }
  }

  void _emptyTrash(FileVaultService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        title: const Text('Empty Trash?',
            style: TextStyle(color: ChaayaTheme.sosRed)),
        content: const Text('All files in trash will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            child: const Text('Empty'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await service.emptyBin();
      setState(() {});
    }
  }

  IconData _getFileIcon(FileType type) {
    switch (type) {
      case FileType.folder:
        return Icons.folder;
      case FileType.image:
        return Icons.image;
      case FileType.video:
        return Icons.video_file;
      case FileType.audio:
        return Icons.audio_file;
      case FileType.document:
        return Icons.description;
      case FileType.pdf:
        return Icons.picture_as_pdf;
      case FileType.spreadsheet:
        return Icons.table_chart;
      case FileType.archive:
        return Icons.folder_zip;
      case FileType.other:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(FileType type) {
    switch (type) {
      case FileType.image:
        return Colors.purple;
      case FileType.video:
        return Colors.red;
      case FileType.audio:
        return Colors.orange;
      case FileType.document:
        return Colors.blue;
      case FileType.pdf:
        return Colors.red;
      case FileType.spreadsheet:
        return Colors.green;
      case FileType.archive:
        return Colors.brown;
      case FileType.folder:
        return ChaayaTheme.accent;
      case FileType.other:
        return ChaayaTheme.textMuted;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}
