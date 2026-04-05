import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/wallpaper_service.dart';

class WallpaperPickerSheet extends ConsumerWidget {
  final String chatId;
  final Function(WallpaperPreset) onSelect;

  const WallpaperPickerSheet({
    super.key,
    required this.chatId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaperService = ref.watch(wallpaperServiceProvider);

    return Container(
      decoration: BoxDecoration(
        color: ChaayaTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Chat Wallpaper',
              style: TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: WallpaperService.presets.length,
              itemBuilder: (context, index) {
                final wallpaper = WallpaperService.presets[index];
                final isSelected =
                    wallpaperService.getWallpaper(chatId) == wallpaper.id;

                return GestureDetector(
                  onTap: () {
                    onSelect(wallpaper);
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? ChaayaTheme.accent
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration:
                            wallpaperService.getWallpaperDecoration(wallpaper),
                        child: isSelected
                            ? const Center(
                                child: Icon(Icons.check, color: Colors.white))
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              wallpaperService.clearWallpaper(chatId);
              Navigator.pop(context);
            },
            child: const Text(
              'Reset to Default',
              style: TextStyle(color: ChaayaTheme.textMuted),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
