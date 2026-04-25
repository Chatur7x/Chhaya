import 'package:flutter/material.dart';
import 'dart:ui';
import '../../core/theme/chaaya_theme.dart';
import '../../features/messenger/presentation/mesh_chat_list_screen.dart';
import '../../features/contacts/presentation/qr_pairing_screen.dart';
import '../../features/radio/presentation/walkie_talkie_screen.dart';
import '../../features/safety/presentation/safety_map_screen.dart';
import '../../features/ai/presentation/ai_assistant_screen.dart';
import '../../features/settings/presentation/chaaya_settings_screen.dart';
import '../../features/gamification/presentation/gamification_screen.dart';
import '../../features/mission/presentation/mission_planner_screen.dart';
import '../../features/intelligence/presentation/crowd_intelligence_screen.dart';
import '../../features/navigation/presentation/multi_hop_navigator_screen.dart';
import '../../features/emergency/presentation/emergency_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const MeshChatListScreen(),
    const QrPairingScreen(),
    const WalkieTalkieScreen(),
    const SafetyMapScreen(),
    const _MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            decoration: BoxDecoration(
              color: ChaayaTheme.surface.withValues(alpha: 0.85),
              border: const Border(top: BorderSide(color: ChaayaTheme.glassBorder, width: 0.5)),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              selectedItemColor: ChaayaTheme.accent,
              unselectedItemColor: ChaayaTheme.textMuted,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              elevation: 0,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble), label: 'Messenger'),
                BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Contacts'),
                BottomNavigationBarItem(icon: Icon(Icons.radio_outlined), activeIcon: Icon(Icons.radio), label: 'Radio'),
                BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Map'),
                BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view), label: 'More'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            backgroundColor: ChaayaTheme.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: const Text('More', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              delegate: SliverChildListDelegate([
                _Card3D(icon: Icons.warning_amber_rounded, title: 'Emergency', subtitle: 'SOS Alerts', color: ChaayaTheme.sosRed,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyScreen()))),
                _Card3D(icon: Icons.smart_toy_outlined, title: 'AI Assistant', subtitle: 'Offline Intel', color: ChaayaTheme.warningYellow,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIAssistantScreen()))),
                _Card3D(icon: Icons.emoji_events, title: 'Achievements', subtitle: 'Rewards', color: ChaayaTheme.warningYellow,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GamificationScreen()))),
                _Card3D(icon: Icons.assignment, title: 'Missions', subtitle: 'Team Tasks', color: ChaayaTheme.accent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MissionPlannerScreen()))),
                _Card3D(icon: Icons.psychology, title: 'Crowd Intel', subtitle: 'Shared Reports', color: ChaayaTheme.safeGreen,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CrowdIntelligenceScreen()))),
                _Card3D(icon: Icons.navigation, title: 'Navigator', subtitle: 'Multi-Hop', color: ChaayaTheme.bleColor,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiHopNavigatorScreen()))),
                _Card3D(icon: Icons.folder_outlined, title: 'File Vault', subtitle: 'Encrypted Storage', color: ChaayaTheme.bleColor, onTap: () {}),
                _Card3D(icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Security & Mesh', color: ChaayaTheme.textSecondary,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChaayaSettingsScreen()))),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _Card3D extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Card3D({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  @override
  State<_Card3D> createState() => _Card3DState();
}

class _Card3DState extends State<_Card3D> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_pressed ? 0.95 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ChaayaTheme.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.color.withValues(alpha: _pressed ? 0.3 : 0.1)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: _pressed ? 0.15 : 0.35), blurRadius: _pressed ? 8 : 20, offset: Offset(0, _pressed ? 3 : 10)),
            BoxShadow(color: widget.color.withValues(alpha: _pressed ? 0.02 : 0.06), blurRadius: 30, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.icon, color: widget.color, size: 24),
            ),
            const Spacer(),
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, color: ChaayaTheme.textPrimary, fontSize: 15)),
            const SizedBox(height: 2),
            Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: ChaayaTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
