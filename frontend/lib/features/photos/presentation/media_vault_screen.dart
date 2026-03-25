import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../storage/data/secure_storage_manager.dart';

/// Media Vault Screen — encrypted photo/video gallery with field reports.
class MediaVaultScreen extends ConsumerStatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  ConsumerState<MediaVaultScreen> createState() => _MediaVaultScreenState();
}

class _MediaVaultScreenState extends ConsumerState<MediaVaultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MediaItem> _media = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() => _loading = true);
    final storage = ref.read(secureStorageProvider);
    await storage.initialize(); // Production = user PIN
    
    final media = storage.getMedia();
    if (mounted) {
      setState(() {
        _media = media;
        _loading = false;
      });
    }
  }

  Future<void> _addRealPhoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) return;
    
    setState(() => _loading = true);
    try {
      final storage = ref.read(secureStorageProvider);
      final bytes = await image.readAsBytes();
      
      await storage.saveMedia(
        name: image.name,
        type: MediaType.photo,
        sizeBytes: bytes.length,
        localPath: image.path, 
        latitude: null, 
        longitude: null,
      );
    } catch (e) {
      debugPrint('[MediaVault] Failed to save photo: $e');
    } finally {
      if (mounted) _loadMedia();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.photo_library, color: ChaayaTheme.accent, size: 22),
            SizedBox(width: 10),
            Text('Media Vault'),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ChaayaTheme.accent,
          labelColor: ChaayaTheme.accent,
          unselectedLabelColor: ChaayaTheme.textMuted,
          tabs: const [
            Tab(text: 'Photos'),
            Tab(text: 'Videos'),
            Tab(text: 'Reports'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: ChaayaTheme.textSecondary),
            onPressed: () => _loadMedia(),
          ),
        ],
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator(color: ChaayaTheme.accent))
        : TabBarView(
        controller: _tabController,
        children: [
          _buildPhotoGrid(),
          _buildVideoList(),
          _buildReportList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRealPhoto,
        backgroundColor: ChaayaTheme.accent,
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
    );
  }

  Widget _buildPhotoGrid() {
    final photos = _media.where((m) => m.type == MediaType.photo).toList();
    if (photos.isEmpty) {
      return const Center(child: Text('No photos securely saved.', style: TextStyle(color: ChaayaTheme.textMuted)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        final colors = [
          ChaayaTheme.accent.withOpacity(0.2),
          ChaayaTheme.bleColor.withOpacity(0.2),
          ChaayaTheme.safeGreen.withOpacity(0.2),
          ChaayaTheme.warningYellow.withOpacity(0.2),
        ];
        return GestureDetector(
          onLongPress: () => _deleteMedia(photo.id),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors[index % 4],
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colors[index % 4], colors[(index + 1) % 4]],
                  ),
                ),
                child: Icon(Icons.image, color: Colors.white.withOpacity(0.3), size: 32),
              ),
              // Encrypted badge
              Positioned(
                bottom: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.lock, size: 10, color: ChaayaTheme.safeGreen),
                ),
              ),
              // GPS tagged
              if (photo.latitude != null)
                Positioned(
                  top: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.location_on, size: 10, color: ChaayaTheme.bleColor),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoList() {
    final videos = _media.where((m) => m.type == MediaType.video).toList();
    if (videos.isEmpty) {
      return const Center(child: Text('No videos in vault.', style: TextStyle(color: ChaayaTheme.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: videos.length,
      itemBuilder: (context, i) {
        final video = videos[i];
        return GestureDetector(
          onLongPress: () => _deleteMedia(video.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
            child: ListTile(
              leading: Container(
                width: 60, height: 45,
                decoration: BoxDecoration(
                  color: ChaayaTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.play_circle_fill, color: ChaayaTheme.accent, size: 28),
                  ],
                ),
              ),
              title: const Text('Encrypted Video', style: TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
              subtitle: Row(
                children: [
                  const Icon(Icons.lock, size: 10, color: ChaayaTheme.safeGreen),
                  const SizedBox(width: 4),
                  Text('${(video.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB • ${video.createdAt.month}/${video.createdAt.day}', 
                    style: const TextStyle(fontSize: 11, color: ChaayaTheme.textMuted)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportList() {
    return const Center(
      child: Text('No field reports generated yet.', style: TextStyle(color: ChaayaTheme.textMuted)),
    );
  }

  void _deleteMedia(String id) async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteMedia(id);
    _loadMedia();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Securely deleted media item.')));
    }
  }
}

