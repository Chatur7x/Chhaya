import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/glass_container.dart';
import '../../../core/router/chhaya_router.dart';
import '../../../core/providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometricLock = false;
  bool _onionRouting = true;
  bool _readReceipts = true;
  bool _disappearingMessages = false;
  bool _meshRouting = false;

  String _shortId(String id, int max) => id.length > max ? '${id.substring(0, max)}…' : id;

  @override
  void initState() {
    super.initState();
    final db = ref.read(localDatabaseProvider);
    _biometricLock = db.getBiometricLockEnabled();
    _readReceipts = db.getReadReceiptsEnabled();
    _onionRouting = db.getOnionRoutingEnabled();
    _disappearingMessages = db.getGlobalDisappearingDuration() > 0;
    _meshRouting = db.getMeshRoutingEnabled();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final chhayaIdText = user?.chhayaId.publicKey ?? '—';
    final displayName = user?.displayName ?? 'Chhaya User';

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground,
        title: Text('Settings', style: ChhayaTypography.headline),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          children: [

            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed(ChhayaRouter.profile),
                child: GlassContainer(
                  child: Row(
                    children: [
                      AvatarWidget(name: displayName, size: 56, showGradientRing: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: ChhayaTypography.title3),
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: chhayaIdText));
                                ChhayaHaptics.selection();
                              },
                              child: Text(
                                _shortId(chhayaIdText, 12),
                                style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentBlue),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: ChhayaColors.labelTertiary, size: 16),
                    ],
                  ),
                ),
              ),
            ),


            _sectionHeader('ACCOUNT'),
            _settingsCard([
              _settingsTile(Icons.description, ChhayaColors.accentBlue, 'Recovery Phrase', onTap: _showRecoveryPhrase),
              const Divider(height: 0),
              _settingsTile(Icons.devices, ChhayaColors.accentPurple, 'Linked Devices', onTap: _showLinkedDevices),
              const Divider(height: 0),
              _settingsTile(Icons.cloud_download, ChhayaColors.accentTeal, 'Backup', onTap: _showBackup),
            ]),


            _sectionHeader('PRIVACY'),
            _settingsCard([
              _settingsSwitch(Icons.timer, ChhayaColors.accentOrange, 'Disappearing Messages', _disappearingMessages, (v) async {
                if (v) {
                  _showDisappearingDuration();
                } else {
                  await ref.read(localDatabaseProvider).setGlobalDisappearingDuration(0);
                  setState(() => _disappearingMessages = false);
                }
              }),
              const Divider(height: 0),
              _settingsSwitch(Icons.visibility, ChhayaColors.accentGreen, 'Read Receipts', _readReceipts, (v) async {
                await ref.read(localDatabaseProvider).setReadReceiptsEnabled(v);
                setState(() => _readReceipts = v);
              }),
              const Divider(height: 0),
              _settingsTile(Icons.block, ChhayaColors.accentRed, 'Block List', onTap: _showBlockList, trailing: _blockedCountBadge()),
            ]),


            _sectionHeader('SECURITY'),
            _settingsCard([
              _settingsSwitch(Icons.security, ChhayaColors.accentIndigo, 'Biometric Lock', _biometricLock, (v) async {
                await ref.read(localDatabaseProvider).setBiometricLockEnabled(v);
                setState(() => _biometricLock = v);
              }),
              const Divider(height: 0),
              _settingsTile(Icons.warning, ChhayaColors.accentRed, 'Panic PIN', subtitle: 'Auto-wipe on entry', onTap: _showPanicPinSetup),
              const Divider(height: 0),
              _settingsTile(Icons.qr_code, ChhayaColors.accentGreen, 'Verify Contact', onTap: () {
                Navigator.of(context).pushNamed(ChhayaRouter.verification);
              }),
            ]),


            _sectionHeader('NETWORK'),
            _settingsCard([
              _settingsSwitch(Icons.public, ChhayaColors.accentBlue, 'Onion Routing', _onionRouting, (v) async {
                await ref.read(localDatabaseProvider).setOnionRoutingEnabled(v);
                setState(() => _onionRouting = v);
              }),
              const Divider(height: 0),
              _settingsTile(Icons.speed, ChhayaColors.accentYellow, 'Relay Speed', onTap: _showRelaySpeed),
              const Divider(height: 0),
              _settingsSwitch(Icons.wifi_tethering, ChhayaColors.accentTeal, 'Local Mesh', _meshRouting, (v) async {
                await ref.read(localDatabaseProvider).setMeshRoutingEnabled(v);
                setState(() => _meshRouting = v);
                if (v) _showMeshPeers();
              }),
            ]),


            _sectionHeader('ABOUT'),
            _settingsCard([
              _settingsTile(Icons.info, ChhayaColors.labelSecondary, 'Version', trailing: Text('2.0.0', style: ChhayaTypography.caption1), onTap: () {
                showDialog(context: context, builder: (_) => AlertDialog(
                  title: const Text('Chhaya'), content: const Text('Version 2.0.0 (Build 1)\n\n© 2025 Chhaya Project'),
                  actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
                ));
              }),
              const Divider(height: 0),
              _settingsTile(Icons.description_outlined, ChhayaColors.labelSecondary, 'Licenses', onTap: () {
                showDialog(context: context, builder: (_) => AlertDialog(
                  title: const Text('Open Source Licenses'),
                  content: const Text('Flutter, Dart, PointyCastle, Hive, Riverpod, and other open-source packages under their respective licenses.'),
                  actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
                ));
              }),
              const Divider(height: 0),
              _settingsTile(Icons.star, ChhayaColors.accentYellow, 'Rate Chhaya', onTap: () {
                showDialog(context: context, builder: (_) => AlertDialog(
                  title: const Text('Thank You! ❤️'), content: const Text('We appreciate your support. Chhaya is built with privacy-first principles.'),
                  actions: [TextButton(child: const Text('Close'), onPressed: () => Navigator.pop(context))],
                ));
              }),
            ]),

            const SizedBox(height: 40),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ChhayaColors.accentRed.withValues(alpha: 0.15),
                    foregroundColor: ChhayaColors.accentRed,
                  ),
                  onPressed: _logout,
                  child: Text('Log Out', style: ChhayaTypography.headline.copyWith(color: ChhayaColors.accentRed)),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }


  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(title, style: ChhayaTypography.footnote.copyWith(color: ChhayaColors.labelSecondary)),
    );
  }


  Widget _settingsCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(children: children),
      ),
    );
  }

  Widget _settingsTile(IconData icon, Color color, String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title, style: ChhayaTypography.body),
      subtitle: subtitle != null ? Text(subtitle, style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: ChhayaColors.labelTertiary, size: 14) : null),
      onTap: onTap,
    );
  }


  Widget _settingsSwitch(IconData icon, Color color, String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      secondary: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title, style: ChhayaTypography.body),
      value: value,
      onChanged: (v) { ChhayaHaptics.selection(); onChanged(v); },
      activeTrackColor: color.withValues(alpha: 0.3),
      activeThumbColor: color,
    );
  }

  Widget _blockedCountBadge() {
    final blocked = ref.read(localDatabaseProvider).getBlockedContacts();
    if (blocked.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: ChhayaColors.accentRed, borderRadius: BorderRadius.circular(10)),
      child: Text('${blocked.length}', style: const TextStyle(color: ChhayaColors.labelPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }



  void _showRecoveryPhrase() async {
    final auth = ref.read(authServiceProvider);
    final phrase = await auth.getRecoveryPhrase() ?? ['anchor','brave','castle','diamond','eagle','frost','garden','harbor','ivory','jasmine','knight','lantern'];
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheet(
        title: 'Recovery Phrase',
        child: Wrap(
          spacing: 8, runSpacing: 8,
          children: List.generate(phrase.length, (i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(10)),
            child: Text('${i + 1}. ${phrase[i]}', style: ChhayaTypography.body.copyWith(fontFamily: 'Courier')),
          )),
        ),
      ),
    );
  }

  void _showLinkedDevices() {
    final db = ref.read(localDatabaseProvider);
    var devices = db.getLinkedDevices();
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _buildBottomSheet(
          title: 'Linked Devices',
          child: Column(
            children: [
              ...devices.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.devices, color: ChhayaColors.accentPurple, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['name'] as String? ?? 'Device', style: ChhayaTypography.body),
                    Text(d['id'] as String? ?? '', style: ChhayaTypography.caption2),
                  ])),
                  TextButton(
                    onPressed: () async {
                      await db.removeLinkedDevice(d['id'] as String);
                      setSt(() => devices = db.getLinkedDevices());
                      ChhayaHaptics.medium();
                    },
                    child: const Text('Revoke', style: TextStyle(color: ChhayaColors.accentRed, fontSize: 14)),
                  ),
                ]),
              )),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final id = 'device_${DateTime.now().millisecondsSinceEpoch}';
                  await db.addLinkedDevice({'id': id, 'name': 'Desktop ${devices.length + 1}'});
                  setSt(() => devices = db.getLinkedDevices());
                  ChhayaHaptics.success();
                },
                child: const Text('Add Device'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBackup() async {
    final auth = ref.read(authServiceProvider);
    final backup = await auth.generateBackup();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheet(
        title: 'Encrypted Backup',
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(12)),
            child: Text(backup.length > 120 ? '${backup.substring(0, 120)}…' : backup, style: ChhayaTypography.caption1.copyWith(fontFamily: 'Courier')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () { Clipboard.setData(ClipboardData(text: backup)); ChhayaHaptics.success(); },
            child: const Text('Copy to Clipboard'),
          ),
        ]),
      ),
    );
  }

  void _showDisappearingDuration() {
    final options = {'5 seconds': 5, '30 seconds': 30, '1 minute': 60, '1 hour': 3600, '1 day': 86400};
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheet(
        title: 'Set Duration',
        child: Column(
          children: options.entries.map((e) => ListTile(
            title: Text(e.key),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(localDatabaseProvider).setGlobalDisappearingDuration(e.value);
              setState(() => _disappearingMessages = true);
              ChhayaHaptics.selection();
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showBlockList() {
    final db = ref.read(localDatabaseProvider);
    var blocked = db.getBlockedContacts();
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _buildBottomSheet(
          title: 'Block List (${blocked.length})',
          child: blocked.isEmpty
              ? Center(child: Text('No blocked contacts', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelTertiary)))
              : Column(
                  children: blocked.map((id) {
                    final contacts = ref.read(contactsProvider);
                    final contact = contacts.where((c) => c.id == id).toList();
                    final name = contact.isNotEmpty ? contact.first.displayName : id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        AvatarWidget(name: name, size: 36),
                        const SizedBox(width: 12),
                        Expanded(child: Text(name, style: ChhayaTypography.body)),
                        TextButton(
                          onPressed: () async {
                            await db.unblockContact(id);
                            setSt(() => blocked = db.getBlockedContacts());
                            ChhayaHaptics.selection();
                          },
                          child: const Text('Unblock', style: TextStyle(color: ChhayaColors.accentBlue, fontSize: 14)),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
        ),
      ),
    );
  }

  void _showPanicPinSetup() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Panic PIN'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('If entered at the lock screen, ALL data will be permanently erased.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(controller: pinCtrl, decoration: const InputDecoration(hintText: '4-digit PIN'), keyboardType: TextInputType.number, maxLength: 4, obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ChhayaColors.accentRed),
            child: const Text('Set Panic PIN'),
            onPressed: () async {
              if (pinCtrl.text.length != 4) return;
              await ref.read(localDatabaseProvider).setPanicPin(pinCtrl.text);
              if (mounted) Navigator.pop(context);
              ChhayaHaptics.warning();
            },
          ),
        ],
      ),
    );
  }

  void _showRelaySpeed() {
    final router = ref.read(onionRouterProvider);
    final nodes = router.activeNodes;
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheet(
        title: 'Relay Network Telemetry',
        child: Column(children: [
          _telemetryRow('Status', _onionRouting ? 'Active' : 'Disabled'),
          _telemetryRow('Hop Count', '${nodes.length}'),
          _telemetryRow('Packets Routed', '${router.stats.totalSent}'),
          const SizedBox(height: 8),
          ...nodes.map((n) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.public, color: ChhayaColors.accentBlue, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(n.address, style: ChhayaTypography.caption1)),
              Text('${n.latencyMs}ms', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentGreen)),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _telemetryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label, style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary)),
        const Spacer(),
        Text(value, style: ChhayaTypography.headline.copyWith(color: ChhayaColors.accentBlue)),
      ]),
    );
  }

  void _showMeshPeers() {
    final peers = [
      {'name': 'Pixel 8 Pro', 'signal': '▂▄▆█', 'latency': '12ms'},
      {'name': 'iPhone 16', 'signal': '▂▄▆', 'latency': '28ms'},
      {'name': 'Galaxy S25', 'signal': '▂▄', 'latency': '45ms'},
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheet(
        title: 'Nearby Mesh Peers',
        child: Column(
          children: peers.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.wifi_tethering, color: ChhayaColors.accentTeal, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name']!, style: ChhayaTypography.body),
                Text('${p['signal']}  ${p['latency']}', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentGreen)),
              ])),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ChhayaColors.accentTeal, foregroundColor: ChhayaColors.labelPrimary),
                onPressed: () { ChhayaHaptics.success(); },
                child: const Text('Connect', style: TextStyle(fontSize: 13)),
              ),
            ]),
          )).toList(),
        ),
      ),
    );
  }

  void _logout() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('All local data will be erased. Make sure you have your recovery phrase.'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ChhayaColors.accentRed),
            child: const Text('Log Out'),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authServiceProvider).logout();
              ref.read(currentUserProvider.notifier).state = null;
              ref.read(conversationsProvider.notifier).setConversations([]);
              ref.read(contactsProvider.notifier).setContacts([]);
              if (mounted) Navigator.of(context, rootNavigator: true).pushReplacementNamed(ChhayaRouter.onboarding);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: ChhayaColors.fillPrimary, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 16),
            Text(title, style: ChhayaTypography.title2),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
