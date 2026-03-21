import 'package:flutter/material.dart';
import '../../core/theme/chaaya_theme.dart';
import '../../features/messenger/presentation/mesh_chat_list_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/radio/presentation/walkie_talkie_screen.dart';
import '../../features/safety/presentation/safety_map_screen.dart';
import '../../features/storage/presentation/file_vault_screen.dart';
import '../../features/photos/presentation/media_vault_screen.dart';
import '../../features/ai/presentation/ai_assistant_screen.dart';
import '../../features/settings/presentation/chaaya_settings_screen.dart';

/// Main Screen — Bottom navigation hub for Chaaya.
/// 5 tabs: Messenger, Contacts, Radio (PTT), Map, More
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const MeshChatListScreen(),
    const ContactsScreen(),
    const WalkieTalkieScreen(),    // PTT Radio — Phase 2 ✅
    const SafetyMapScreen(),       // Map — Phase 3 ✅
    const _MoreScreen(),          // Hub for File Vault, Media, Settings, etc.
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: ChaayaTheme.surface,
          border: Border(
            top: BorderSide(color: ChaayaTheme.glassBorder, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: ChaayaTheme.surface,
          selectedItemColor: ChaayaTheme.accent,
          unselectedItemColor: ChaayaTheme.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Messenger',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Contacts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radio_outlined),
              activeIcon: Icon(Icons.radio),
              label: 'Radio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for Radio/PTT (Phase 2)
class _RadioPlaceholder extends StatelessWidget {
  const _RadioPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Walkie-Talkie'),
        backgroundColor: ChaayaTheme.background,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ChaayaTheme.warningYellow.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radio, size: 40, color: ChaayaTheme.warningYellow),
            ),
            const SizedBox(height: 16),
            const Text('Push-to-Talk Radio', style: ChaayaTheme.heading3),
            const SizedBox(height: 8),
            const Text(
              'Coming in Phase 2',
              style: ChaayaTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for Map (Phase 3)
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Mesh Map'),
        backgroundColor: ChaayaTheme.background,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ChaayaTheme.safeGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.map, size: 40, color: ChaayaTheme.safeGreen),
            ),
            const SizedBox(height: 16),
            const Text('Offline Map & GPS', style: ChaayaTheme.heading3),
            const SizedBox(height: 8),
            const Text(
              'Coming in Phase 3',
              style: ChaayaTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// More screen — hub for File Vault, Media, Safety, Health, AI, Settings
class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('More'),
        backgroundColor: ChaayaTheme.background,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MoreTile(
            icon: Icons.folder_outlined,
            title: 'File Vault',
            subtitle: 'Encrypted file storage & sharing',
            color: ChaayaTheme.bleColor,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FileVaultScreen())),
          ),
          _MoreTile(
            icon: Icons.photo_library_outlined,
            title: 'Media Vault',
            subtitle: 'Photos, videos & field reports',
            color: ChaayaTheme.accent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaVaultScreen())),
          ),
          _MoreTile(
            icon: Icons.shield_outlined,
            title: 'Safety & SOS',
            subtitle: 'Location sharing, crash detection',
            color: ChaayaTheme.sosRed,
            onTap: () {},
          ),
          _MoreTile(
            icon: Icons.local_hospital_outlined,
            title: 'Health & Medical',
            subtitle: 'First aid, triage, medication',
            color: ChaayaTheme.safeGreen,
            onTap: () {},
          ),
          _MoreTile(
            icon: Icons.smart_toy_outlined,
            title: 'AI Assistant',
            subtitle: 'Offline survival intelligence',
            color: ChaayaTheme.warningYellow,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIAssistantScreen())),
          ),
          _MoreTile(
            icon: Icons.warning_amber_outlined,
            title: 'Emergency Broadcast',
            subtitle: 'Send alerts to all mesh devices',
            color: ChaayaTheme.sosRed,
            onTap: () {},
          ),
          _MoreTile(
            icon: Icons.groups_outlined,
            title: 'Coordination',
            subtitle: 'Tasks, voting, headcount',
            color: ChaayaTheme.bleColor,
            onTap: () {},
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Identity, security, mesh config',
            color: ChaayaTheme.textSecondary,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChaayaSettingsScreen())),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: ChaayaTheme.textPrimary,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: ChaayaTheme.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right, color: ChaayaTheme.textMuted, size: 20),
      ),
    );
  }
}

