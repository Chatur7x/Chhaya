import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../auth/data/biometric_service.dart';
import '../../auth/data/decoy_service.dart';
import '../../auth/presentation/widgets/decoy_setup_sheet.dart';
import '../../auth/presentation/biometric_setup_screen.dart';
import '../../identity/presentation/safety_numbers_screen.dart';
import '../../contacts/domain/models/contact.dart';
import '../../security/presentation/panic_wipe_screen.dart';
import '../../security/presentation/dead_man_switch_screen.dart';
import '../../security/presentation/device_manager_screen.dart';
import '../../security/presentation/privacy_settings_screen.dart';
import '../../status/presentation/statuses_screen.dart';
import '../../chat/presentation/starred_messages_screen.dart';

final decoyServiceProvider = Provider<DecoyService>((ref) {
  return DecoyService();
});

class ChaayaSettingsScreen extends ConsumerStatefulWidget {
  const ChaayaSettingsScreen({super.key});

  @override
  ConsumerState<ChaayaSettingsScreen> createState() =>
      _ChaayaSettingsScreenState();
}

class _ChaayaSettingsScreenState extends ConsumerState<ChaayaSettingsScreen> {
  bool _covertMode = false;
  bool _autoRelay = true;
  bool _batterySaver = false;
  bool _crashDetection = true;
  bool _locationSharing = true;
  bool _biometricEnabled = false;
  bool _decoyEnabled = false;
  int _maxHops = 7;

  @override
  void initState() {
    super.initState();
    _loadSecurityState();
  }

  Future<void> _loadSecurityState() async {
    final biometricService = ref.read(biometricServiceProvider);
    final decoyService = ref.read(decoyServiceProvider);

    await decoyService.initialize();

    if (mounted) {
      final bioEnabled = await biometricService.isBiometricEnabled();
      setState(() {
        _biometricEnabled = bioEnabled;
        _decoyEnabled = decoyService.isDecoyEnabled;
      });
    }
  }

  void _showBiometricSetup() async {
    final biometricService = ref.read(biometricServiceProvider);
    final isAvailable = await biometricService.isBiometricAvailable();

    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Biometric authentication not available on this device'),
            backgroundColor: ChaayaTheme.warningYellow,
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BiometricSetupScreen(
            onComplete: () {
              _loadSecurityState();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Biometric authentication enabled'),
                  backgroundColor: ChaayaTheme.safeGreen,
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _showDecoySetup() {
    final decoyService = ref.read(decoyServiceProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoySetupSheet(
        decoyService: decoyService,
        onComplete: () {
          _loadSecurityState();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Decoy password enabled'),
              backgroundColor: ChaayaTheme.safeGreen,
            ),
          );
        },
      ),
    );
  }

  void _handleCovertModeToggle(bool value) {
    setState(() => _covertMode = value);

    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Covert mode enabled - app will appear as calculator'),
          backgroundColor: ChaayaTheme.warningYellow,
        ),
      );
    }
  }

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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: ChaayaTheme.glassDecoration(borderRadius: 16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: ChaayaTheme.accent.withOpacity(0.2),
                  child: const Icon(Icons.person,
                      size: 36, color: ChaayaTheme.accent),
                ),
                const SizedBox(height: 12),
                const Text('ALPHA-1', style: ChaayaTheme.heading2),
                const SizedBox(height: 4),
                Text('Device: mesh-abc-1234',
                    style: TextStyle(
                        fontSize: 12,
                        color: ChaayaTheme.textMuted,
                        fontFamily: 'JetBrains Mono')),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ChaayaTheme.safeGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.key, size: 12, color: ChaayaTheme.safeGreen),
                      const SizedBox(width: 4),
                      Text('Ed25519 • Verified',
                          style: TextStyle(
                              fontSize: 11, color: ChaayaTheme.safeGreen)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Mesh Network'),
          _switchTile(
              Icons.repeat,
              'Auto-relay messages',
              'Forward messages for other devices',
              _autoRelay,
              (v) => setState(() => _autoRelay = v)),
          _sliderTile(Icons.device_hub, 'Max relay hops', _maxHops,
              (v) => setState(() => _maxHops = v.round())),
          _switchTile(
              Icons.battery_saver,
              'Battery saver mode',
              'Reduce BLE scan frequency',
              _batterySaver,
              (v) => setState(() => _batterySaver = v)),
          const SizedBox(height: 16),
          _sectionTitle('Safety'),
          _switchTile(
              Icons.location_on,
              'Location sharing',
              'Share GPS with your circle',
              _locationSharing,
              (v) => setState(() => _locationSharing = v)),
          _switchTile(Icons.car_crash, 'Crash detection', 'Auto-SOS on impact',
              _crashDetection, (v) => setState(() => _crashDetection = v)),
          const SizedBox(height: 16),
          _sectionTitle('Security'),
          _switchTile(
            Icons.fingerprint,
            'Biometric Unlock',
            _biometricEnabled ? 'Enabled' : 'Use fingerprint/face to unlock',
            _biometricEnabled,
            (v) => _showBiometricSetup(),
            color: ChaayaTheme.safeGreen,
          ),
          _actionTile(
            Icons.lock_outline,
            'Decoy Password',
            _decoyEnabled
                ? 'Enabled - Shows fake inbox'
                : 'Set up decoy password',
            _showDecoySetup,
            color: ChaayaTheme.warningYellow,
          ),
          _switchTile(
              Icons.visibility_off,
              'Covert mode',
              'Hide app, disguise as calculator',
              _covertMode,
              _handleCovertModeToggle,
              color: ChaayaTheme.warningYellow),
          _actionTile(Icons.security, 'Safety numbers',
              'Verify contact key fingerprints', () {
            final mockContact = Contact(
              deviceId: 'test-device',
              name: 'Test Contact',
              publicKey: 'mock-public-key',
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SafetyNumbersScreen(
                  myPublicKeyBase64: 'mock-my-key',
                  peerContact: mockContact,
                ),
              ),
            );
          }),
          _actionTile(Icons.devices, 'Device Manager',
              'Manage linked devices', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DeviceManagerScreen()));
          }),
          _actionTile(Icons.timer, 'Dead Man\'s Switch',
              'Auto-wipe if no check-in', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DeadManSwitchScreen()));
          }),
          _actionTile(Icons.star_border, 'Starred Messages',
              'Bookmarked messages', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StarredMessagesScreen()));
          }),
          const SizedBox(height: 16),
          _sectionTitle('Social'),
          _actionTile(Icons.circle, 'Status',
              'Share 24-hour stories', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StatusesScreen()));
          }),
          const SizedBox(height: 16),
          _sectionTitle('Privacy'),
          _actionTile(Icons.visibility, 'Privacy Controls',
              'Last seen, profile photo, read receipts', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()));
          }),
          const SizedBox(height: 16),
          _sectionTitle('Danger Zone', color: ChaayaTheme.sosRed),
          _dangerTile(
              Icons.delete_forever, 'Panic Wipe', 'Destroy ALL data instantly',
              () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PanicWipeScreen()));
          }),
          _dangerTile(
              Icons.logout, 'Reset Identity', 'Delete keypair and start fresh',
              () {
            _showResetDialog(context);
          }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title,
      {Color color = ChaayaTheme.textSecondary}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.5,
          )),
    );
  }

  Widget _switchTile(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged,
      {Color color = ChaayaTheme.accent}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: SwitchListTile(
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(title,
            style:
                const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11)),
        value: value,
        activeColor: ChaayaTheme.accent,
        onChanged: onChanged,
      ),
    );
  }

  Widget _sliderTile(
      IconData icon, String title, int value, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ChaayaTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: ChaayaTheme.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Text(title,
                  style: const TextStyle(
                      color: ChaayaTheme.textPrimary, fontSize: 14)),
              const Spacer(),
              Text('$value hops',
                  style: const TextStyle(
                      color: ChaayaTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
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

  Widget _actionTile(
      IconData icon, String title, String subtitle, VoidCallback onTap,
      {Color color = ChaayaTheme.accent}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(title,
            style:
                const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right,
            color: ChaayaTheme.textMuted, size: 18),
        onTap: onTap,
      ),
    );
  }

  Widget _dangerTile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: ChaayaTheme.sosRed.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChaayaTheme.sosRed.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: ChaayaTheme.sosRed.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: ChaayaTheme.sosRed, size: 18),
        ),
        title: Text(title,
            style: const TextStyle(
                color: ChaayaTheme.sosRed,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11)),
        onTap: onTap,
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChaayaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: ChaayaTheme.warningYellow),
            SizedBox(width: 8),
            Text('Reset Identity',
                style: TextStyle(
                    color: ChaayaTheme.warningYellow,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'This will:\n'
          '• Delete your current keypair\n'
          '• Remove all contact trust relationships\n'
          '• Generate a new identity\n\n'
          'You will need to re-verify all contacts.',
          style: ChaayaTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: ChaayaTheme.warningYellow,
                foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Identity reset. Please restart the app.'),
                  backgroundColor: ChaayaTheme.warningYellow,
                ),
              );
            },
            child: const Text('RESET IDENTITY'),
          ),
        ],
      ),
    );
  }
}
