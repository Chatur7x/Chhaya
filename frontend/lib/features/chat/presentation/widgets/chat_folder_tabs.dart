import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/chat_folder_service.dart';

class ChatFolderTabs extends ConsumerWidget {
  const ChatFolderTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFolder = ref.watch(currentFolderProvider);

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: ChatFolder.values.map((folder) {
          final isSelected = currentFolder == folder;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ChatFolderService.getFolderIcon(folder),
                    size: 16,
                    color: isSelected
                        ? ChaayaTheme.textPrimary
                        : ChatFolderService.getFolderColor(folder),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ChatFolderService.getFolderName(folder),
                    style: TextStyle(
                      color: isSelected
                          ? ChaayaTheme.textPrimary
                          : ChaayaTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              backgroundColor: ChaayaTheme.surface,
              selectedColor:
                  ChatFolderService.getFolderColor(folder).withOpacity(0.3),
              checkmarkColor: ChaayaTheme.textPrimary,
              side: BorderSide(
                color: isSelected
                    ? ChatFolderService.getFolderColor(folder)
                    : ChaayaTheme.glassBorder,
              ),
              onSelected: (_) {
                ref.read(currentFolderProvider.notifier).state = folder;
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
