import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/theme/theme_service.dart';

class ThemeSelectorSheet extends ConsumerWidget {
  const ThemeSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(currentThemeProvider);

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
              'App Theme',
              style: TextStyle(
                color: ChaayaTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...ThemeService.getAllThemes().map((theme) {
            final isSelected = currentTheme.name == theme.id;
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.primary, theme.accent],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              title: Text(
                theme.name,
                style: TextStyle(
                  color:
                      isSelected ? ChaayaTheme.accent : ChaayaTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: ChaayaTheme.accent)
                  : null,
              onTap: () {
                final mode = AppThemeMode.values.firstWhere(
                  (m) => m.name == theme.id,
                  orElse: () => AppThemeMode.chaaya,
                );
                ref.read(currentThemeProvider.notifier).state = mode;
                Navigator.pop(context);
              },
            );
          }),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
