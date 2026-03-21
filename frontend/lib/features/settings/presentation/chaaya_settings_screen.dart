import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/chaaya_theme.dart';

/// Chaaya Settings Screen — identity, security, mesh config.
class ChaayaSettingsScreen extends StatefulWidget {
  const ChaayaSettingsScreen({super.key});

  @override
  State<ChaayaSettingsScreen> createState() => _ChaayaSettingsScreenState();
}

class _ChaayaSettingsScreenState extends State<ChaayaSettingsScreen> {
  bool _covertMode = false;
  bool _autoRelay = true;
  bool _batterySaver = false;
  bool _crashDetection = true;
  bool _locationSharing = true;
  int _maxHops = 7;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.settings, color: ChaayaTheme.textSecondary, size: 22),
            SizedBox(width: 10),
            Text('Settings'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Identity card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: ChaayaTheme.glassDecoration(borderRadius: 16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: ChaayaTheme.accent.withOpacity(0.2),
                  child: const Icon(Icons.person, size: 36, color: ChaayaTheme.accent),
                ),
                const SizedBox(height: 12),
                const Text('ALPHA-1', style: ChaayaTheme.heading2),
                const SizedBox(height: 4),
                Text('Device: mesh-abc-1234',
                    style: TextStyle(fontSize: 12, color: ChaayaTheme.textMuted, fontFamily: 'JetBrains Mono')),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ChaayaTheme.safeGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.key, size: 12, color: ChaayaTheme.safeGreen),
                      const SizedBox(width: 4),
                      Text('Ed25519 • Verified', style: TextStyle(fontSize: 11, color: ChaayaTheme.safeGreen)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section: Mesh Network
          _sectionTitle('Mesh Network'),
          _switchTile(Icons.repeat, 'Auto-relay messages', 'Forward messages for other devices', _autoRelay,
              (v) => setState(() => _autoRelay = v)),
          _sliderTile(Icons.device_hub, 'Max relay hops', _maxHops,
              (v) => setState(() => _maxHops = v.round())),
          _switchTile(Icons.battery_saver, 'Battery saver mode', 'Reduce BLE scan frequency', _batterySaver,
              (v) => setState(() => _batterySaver = v)),
          const SizedBox(height: 16),

          // Section: Safety
          _sectionTitle('Safety'),
          _switchTile(Icons.location_on, 'Location sharing', 'Share GPS with your circle', _locationSharing,
              (v) => setState(() => _locationSharing = v)),
          _switchTile(Icons.car_crash, 'Crash detection', 'Auto-SOS on impact', _crashDetection,
              (v) => setState(() => _crashDetection = v)),
          const SizedBox(height: 16),

          // Section: Security
          _sectionTitle('Security'),
          _switchTile(Icons.visibility_off, 'Covert mode', 'Hide app, disguise as calculator', _covertMode,
              (v) => setState(() => _covertMode = v), color: ChaayaTheme.warningYellow),
          _actionTile(Icons.security, 'Safety numbers', 'Verify contact key fingerprints', () {}),
          const SizedBox(height: 16),

          // Danger zone
          _sectionTitle('Danger Zone', color: ChaayaTheme.sosRed),
          _dangerTile(Icons.delete_forever, 'Panic Wipe', 'Destroy ALL data instantly', () {
            _showPanicDialog(context);
          }),
          _dangerTile(Icons.logout, 'Reset Identity', 'Delete keypair and start fresh', () {}),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {Color color = ChaayaTheme.textSecondary}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title.toUpperCase(), style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.5,
      )),
    );
  }

  Widget _switchTile(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged, {Color color = ChaayaTheme.accent}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: SwitchListTile(
        secondary: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(title, style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11)),
        value: value,
        activeColor: ChaayaTheme.accent,
        onChanged: onChanged,
      ),
    );
  }

  Widget _sliderTile(IconData icon, String title, int value, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: ChaayaTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: ChaayaTheme.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
              const Spacer(),
              Text('$value hops', style: const TextStyle(color: ChaayaTheme.accent, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            activeColor: ChaayaTheme.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: ChaayaTheme.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: ChaayaTheme.accent, size: 18),
        ),
        title: Text(title, style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, color: ChaayaTheme.textMuted, size: 18),
        onTap: onTap,
      ),
    );
  }

  Widget _dangerTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: ChaayaTheme.sosRed.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChaayaTheme.sosRed.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: ChaayaTheme.sosRed.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: ChaayaTheme.sosRed, size: 18),
        ),
        title: Text(title, style: const TextStyle(color: ChaayaTheme.sosRed, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11)),
        onTap: onTap,
      ),
    );
  }

  void _showPanicDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: ChaayaTheme.sosRed),
            SizedBox(width: 8),
            Text('PANIC WIPE', style: TextStyle(color: ChaayaTheme.sosRed, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'This will PERMANENTLY DELETE:\n'
          '• All messages\n'
          '• All contacts\n'
          '• Your identity keypair\n'
          '• All files and media\n'
          '• Location history\n\n'
          'This action CANNOT be undone.',
          style: ChaayaTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ChaayaTheme.sosRed),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🗑️ All data wiped. App reset.'),
                  backgroundColor: ChaayaTheme.sosRed,
                ),
              );
            },
            child: const Text('WIPE EVERYTHING'),
          ),
        ],
      ),
    );
  }
}

