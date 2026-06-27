import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
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
import '../../features/survival/presentation/survival_toolkit_screen.dart';
import '../../features/security/presentation/panic_wipe_screen.dart';
import '../../features/security/presentation/dead_man_switch_screen.dart';
import '../../features/security/presentation/device_manager_screen.dart';
import '../../features/security/presentation/privacy_settings_screen.dart';
import '../../features/status/presentation/statuses_screen.dart';
import '../../features/chat/presentation/starred_messages_screen.dart';

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
                _Card3D(icon: Icons.emergency_rounded, title: 'Survival Kit', subtitle: 'Grid-Down Tools', color: ChaayaTheme.sosRed,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SurvivalToolkitScreen()))),
                _Card3D(icon: Icons.circle, title: 'Status', subtitle: '24-Hour Stories', color: ChaayaTheme.gradientCool,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusesScreen()))),
                _Card3D(icon: Icons.devices, title: 'Devices', subtitle: 'Linked Devices', color: ChaayaTheme.bleColor,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceManagerScreen()))),
                _Card3D(icon: Icons.timer, title: 'DMS', subtitle: 'Dead Man\'s Switch', color: ChaayaTheme.warningYellow,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeadManSwitchScreen()))),
                _Card3D(icon: Icons.visibility, title: 'Privacy', subtitle: 'Privacy Controls', color: ChaayaTheme.accent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()))),
                _Card3D(icon: Icons.star, title: 'Starred', subtitle: 'Bookmarked Messages', color: ChaayaTheme.warningYellow,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StarredMessagesScreen()))),
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
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  @override
  void initState() {
    super.initState();
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      if (mounted) {
        setState(() {
          // Subtle tilt based on device movement
          _tiltX = (event.y * 0.05).clamp(-0.15, 0.15);
          _tiltY = (event.x * 0.05).clamp(-0.15, 0.15);
        });
      }
    });
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Advanced 3D matrix transformation
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.002) // Perspective depth
      ..rotateX(_pressed ? 0 : _tiltX)
      ..rotateY(_pressed ? 0 : _tiltY)
      ..scale(_pressed ? 0.92 : 1.0);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutQuart,
        transform: matrix,
        transformAlignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ChaayaTheme.surfaceLight.withValues(alpha: 0.9),
                ChaayaTheme.surfaceLight.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: widget.color.withValues(alpha: _pressed ? 0.4 : 0.15), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: _pressed ? 10 : 25,
                offset: Offset(0, _pressed ? 4 : 12),
              ),
              BoxShadow(
                color: widget.color.withValues(alpha: _pressed ? 0.05 : 0.1),
                blurRadius: 30,
                offset: const Offset(0, 0),
              ),
              // Inner light reflection (simulated glassmorphism)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.03),
                blurRadius: 0,
                spreadRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Background glow
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.1),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 26),
                  ),
                  const Spacer(),
                  Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, color: ChaayaTheme.textPrimary, fontSize: 16, letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: ChaayaTheme.textMuted, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
