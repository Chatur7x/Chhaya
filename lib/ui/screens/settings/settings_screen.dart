import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/chhaya_app_bar.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/chhaya_button.dart';
import '../../../core/router/chhaya_router.dart';
import '../../../core/providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometricLock = false;
  bool _changingLock = false;
  final bool _onionRouting = false;
  bool _readReceipts = true;
  bool _disappearingMessages = false;
  final bool _meshRouting = false;

  String _shortId(String id, int max) => id.length > max ? '${id.substring(0, max)}…' : id;

  @override
  void initState() {
    super.initState();
    final db = ref.read(localDatabaseProvider);
    _biometricLock = db.getBiometricLockEnabled();
    _readReceipts = db.getReadReceiptsEnabled();
    _disappearingMessages = db.getGlobalDisappearingDuration() > 0;
  }

  Future<void> _configureServer() async {
    final api=ref.read(apiServiceProvider);
    final controller=TextEditingController(text:api.baseUrl);
    final url=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Messaging server'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Both people must use the same deployed Chhaya server. Enter its HTTPS address.'),
        TextField(controller:controller,keyboardType:TextInputType.url,decoration:const InputDecoration(hintText:'https://chat.example.com')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('Connect'))]));
    controller.dispose();
    if(url==null||!mounted) { return; }
    try {
      final user=ref.read(currentUserProvider);
      if(user==null) { throw StateError('Create an account first'); }
      await api.connectAccount(url,user,ref.read(keyManagerProvider));
      final conversations=await ref.read(messagingServiceProvider).sync();
      ref.read(conversationsProvider.notifier).setConversations(conversations);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Connected to messaging server')));
    } catch(error) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Connection failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final chhayaIdText = user?.chhayaId.publicKey ?? '—';
    final displayName = user?.displayName ?? 'Chhaya User';

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: const ChhayaAppBar(title: 'Settings'),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(
            ChhayaSpacing.space4,
            ChhayaSpacing.space2,
            ChhayaSpacing.space4,
            ChhayaSpacing.space16,
          ),
          children: [
            // Profile card
            GestureDetector(
              onTap: () {
                ChhayaHaptics.selection();
                Navigator.of(context).pushNamed(ChhayaRouter.profile);
              },
              child: GlassContainer(
                padding: const EdgeInsets.all(ChhayaSpacing.space4),
                child: Row(
                  children: [
                    AvatarWidget(name: displayName, size: 56, showGradientRing: true),
                    const SizedBox(width: ChhayaSpacing.space4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: ChhayaTypography.headlineLarge),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: chhayaIdText));
                              ChhayaHaptics.selection();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Chhaya ID copied')),
                              );
                            },
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _shortId(chhayaIdText, 16),
                                    style: ChhayaTypography.code.copyWith(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: ChhayaSpacing.space1),
                                const Icon(Icons.copy_rounded, size: 12, color: ChhayaColors.accent),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: ChhayaColors.labelTertiary, size: 16),
                  ],
                ),
              ),
            ),

            _sectionHeader('CONNECTION'),
            _settingsCard([
              _settingsTile(Icons.dns_rounded, ChhayaColors.info, 'Connect messaging server', onTap: _configureServer),
            ]),
            _sectionHeader('ACCOUNT'),
            _settingsCard([
              _settingsTile(Icons.description_rounded, ChhayaColors.accent, 'Recovery Phrase', onTap: _showRecoveryPhrase),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.devices_rounded, ChhayaColors.info, 'Linked Devices', onTap: _showLinkedDevices),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.cloud_download_rounded, ChhayaColors.success, 'Backup', onTap: _showBackup),
            ]),

            _sectionHeader('PRIVACY'),
            _settingsCard([
              _settingsSwitch(Icons.timer_rounded, ChhayaColors.warning, 'Disappearing Messages', _disappearingMessages, (v) async {
                if (v) {
                  _showDisappearingDuration();
                } else {
                  await ref.read(localDatabaseProvider).setGlobalDisappearingDuration(0);
                  setState(() => _disappearingMessages = false);
                }
              }),
              const Divider(height: 0, indent: 56),
              _settingsSwitch(Icons.visibility_rounded, ChhayaColors.accent, 'Read Receipts', _readReceipts, (v) async {
                await ref.read(localDatabaseProvider).setReadReceiptsEnabled(v);
                setState(() => _readReceipts = v);
              }),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.block_rounded, ChhayaColors.error, 'Block List', onTap: _showBlockList, trailing: _blockedCountBadge()),
            ]),

            _sectionHeader('SECURITY'),
            _settingsCard([
              _settingsSwitch(Icons.security_rounded, ChhayaColors.info, 'Biometric Lock', _biometricLock, (v) async {
                if (_changingLock) return;
                _changingLock = true;
                try {
                  final db = ref.read(localDatabaseProvider);
                  final available = await db.isBiometricAvailable();
                  final authenticated = available && await db.authenticateWithBiometrics(
                    reason: v ? 'Enable Chhaya device lock' : 'Disable Chhaya device lock',
                  );
                  if (!context.mounted) return;
                  if (!authenticated) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Device authentication is required to change the lock. Set a device passcode first.'),
                    ));
                    return;
                  }
                  await db.setBiometricLockEnabled(v);
                  if (mounted) setState(() => _biometricLock = v);
                } finally {
                  _changingLock = false;
                }
              }),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.warning_rounded, ChhayaColors.error, 'Panic PIN', subtitle: 'Removes local account data on entry', onTap: _showPanicPinSetup),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.qr_code_rounded, ChhayaColors.success, 'Verify Contact', onTap: () {
                Navigator.of(context).pushNamed(ChhayaRouter.verification);
              }),
            ]),

            _sectionHeader('NETWORK'),
            _settingsCard([
              _settingsSwitch(Icons.public_rounded, ChhayaColors.accent, 'Onion routing (unavailable)', _onionRouting, null),
              const Divider(height:0,indent:56),
              _settingsTile(Icons.info_outline,ChhayaColors.info,'Transport status',onTap:_showRelaySpeed),
              const Divider(height:0,indent:56),
              _settingsSwitch(Icons.wifi_tethering_rounded,ChhayaColors.success,'Offline mesh (unavailable)',_meshRouting,null),
              _settingsTile(Icons.info_outline,ChhayaColors.info,'Offline transport status',onTap:_showMeshPeers),
            ]),

            _sectionHeader('ABOUT'),
            _settingsCard([
              _settingsTile(Icons.info_rounded, ChhayaColors.labelSecondary, 'Version', subtitle: '14.0.0 test build', onTap: () {
                showDialog(context: context, builder: (_) => AlertDialog(
                  backgroundColor: ChhayaColors.cardSurfaceElevated,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xxl)),
                  title: const Text('Chhaya'),
                  content: const Text('Version 14.0.0 test build • 2026\n\n© 2026 Chhaya Project'),
                  actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
                ));
              }),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.description_outlined, ChhayaColors.labelSecondary, 'Licenses', onTap: () {
                showLicensePage(context:context,applicationName:'Chhaya',applicationVersion:'14.0.0 test build');
              }),
              const Divider(height: 0, indent: 56),
            ]),

            const SizedBox(height: ChhayaSpacing.space8),

            // Logout
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ChhayaColors.error,
                  side: BorderSide(color: ChhayaColors.error.withValues(alpha: 0.35)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.pill)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text('Log Out', style: ChhayaTypography.headlineMedium.copyWith(color: ChhayaColors.error)),
                onPressed: _logout,
              ),
            ),

            const SizedBox(height: ChhayaSpacing.space4),
            Center(
              child: Text(
                'Chhaya · Version 14.0.0 test build',
                style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelQuaternary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space1, ChhayaSpacing.space6, ChhayaSpacing.space1, ChhayaSpacing.space2),
      child: Text(
        title,
        style: ChhayaTypography.labelSmall.copyWith(
          letterSpacing: 0.2,
          color: ChhayaColors.labelTertiary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) => Material(
    color:ChhayaColors.cardSurface,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),
      side:const BorderSide(color:ChhayaColors.borderSoft)),
    clipBehavior:Clip.antiAlias,
    child:Column(children:children),
  );

  Widget _settingsTile(IconData icon, Color color, String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: ChhayaColors.hoverCream,
          borderRadius: BorderRadius.circular(ChhayaRadius.xs),
        ),
        child: Icon(icon, color: ChhayaColors.inkSoft, size: 20),
      ),
      title: Text(title, style: ChhayaTypography.bodyMedium),
      subtitle: subtitle != null ? Text(subtitle, style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded, color: ChhayaColors.labelTertiary, size: 14) : null),
      onTap: onTap != null ? () { ChhayaHaptics.selection(); onTap(); } : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: 6),
    );
  }

  Widget _settingsSwitch(IconData icon, Color color, String title, bool value, ValueChanged<bool>? onChanged) {
    return SwitchListTile(
      secondary: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: ChhayaColors.hoverCream,
          borderRadius: BorderRadius.circular(ChhayaRadius.xs),
        ),
        child: Icon(icon, color: ChhayaColors.inkSoft, size: 20),
      ),
      title: Text(title, style: ChhayaTypography.bodyMedium),
      value: value,
      onChanged: onChanged == null ? null : (v) { ChhayaHaptics.selection(); onChanged(v); },
      activeTrackColor: ChhayaColors.accent,
      activeThumbColor: ChhayaColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: 6),
    );
  }

  Widget _blockedCountBadge() {
    final blocked = ref.read(localDatabaseProvider).getBlockedContacts();
    if(blocked.isEmpty) { return const SizedBox.shrink(); }
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space2, vertical: 6),
      decoration: BoxDecoration(
        color: ChhayaColors.error,
        borderRadius: BorderRadius.circular(ChhayaRadius.pill),
      ),
      child: Text('${blocked.length}', style: const TextStyle(color: ChhayaColors.onAccent, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  void _showRecoveryPhrase() async {
    final auth = ref.read(authServiceProvider);
    final phrase = await auth.getRecoveryPhrase() ?? ['anchor','brave','castle','diamond','eagle','frost','garden','harbor','ivory','jasmine','knight','lantern'];
    if(!mounted) { return; }
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => _buildBottomSheet(
        title: 'Recovery Phrase',
        child: Wrap(
          spacing: ChhayaSpacing.space2, runSpacing: ChhayaSpacing.space2,
          children: List.generate(phrase.length, (i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
            decoration: BoxDecoration(
              color: ChhayaColors.fillTertiary,
              borderRadius: BorderRadius.circular(ChhayaRadius.md),
              border: Border.all(color: ChhayaColors.separator),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${i + 1}.', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w700)),
                const SizedBox(width: ChhayaSpacing.space2),
                Text(phrase[i], style: ChhayaTypography.bodyMedium.copyWith(fontSize: 13, fontFamily: 'RobotoMono')),
              ],
            ),
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
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _buildBottomSheet(
          title: 'Linked Devices',
          child: Column(
            children: [
              ...devices.map((d) => Container(
                margin: const EdgeInsets.only(bottom: ChhayaSpacing.space2),
                padding: const EdgeInsets.all(ChhayaSpacing.space3),
                decoration: BoxDecoration(
                  color: ChhayaColors.fillTertiary,
                  borderRadius: BorderRadius.circular(ChhayaRadius.md),
                  border: Border.all(color: ChhayaColors.separator),
                ),
                child: Row(children: [
                  const Icon(Icons.devices_rounded, color: ChhayaColors.info, size: 24),
                  const SizedBox(width: ChhayaSpacing.space3),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['name'] as String? ?? 'Device', style: ChhayaTypography.bodyMedium),
                    Text(d['id'] as String? ?? '', style: ChhayaTypography.code.copyWith(fontSize: 10, color: ChhayaColors.labelTertiary)),
                  ])),
                  TextButton(
                    onPressed: () async {
                      await db.removeLinkedDevice(d['id'] as String);
                      setSt(() => devices = db.getLinkedDevices());
                      ChhayaHaptics.medium();
                    },
                    child: const Text('Revoke', style: TextStyle(color: ChhayaColors.error, fontSize: 14)),
                  ),
                ]),
              )),
              const SizedBox(height: ChhayaSpacing.space3),
              SizedBox(width: double.infinity, child: ChhayaPrimaryButton(label: 'Add Device', height: 48, onPressed: () async {
                final id = 'device_${DateTime.now().millisecondsSinceEpoch}';
                await db.addLinkedDevice({'id': id, 'name': 'Desktop ${devices.length + 1}'});
                setSt(() => devices = db.getLinkedDevices());
                ChhayaHaptics.success();
              })),
            ],
          ),
        ),
      ),
    );
  }

  void _showBackup() async {
    final auth = ref.read(authServiceProvider);
    final backup = await auth.generateBackup();
    if(!mounted) { return; }
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => _buildBottomSheet(
        title: 'Encrypted Backup',
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(ChhayaSpacing.space3),
            decoration: BoxDecoration(
              color: ChhayaColors.primaryBackground,
              borderRadius: BorderRadius.circular(ChhayaRadius.md),
              border: Border.all(color: ChhayaColors.separator),
            ),
            child: Text(
              backup.length > 120 ? '${backup.substring(0, 120)}…' : backup,
              style: ChhayaTypography.code.copyWith(fontSize: 11, color: ChhayaColors.labelSecondary),
            ),
          ),
          const SizedBox(height: ChhayaSpacing.space4),
          SizedBox(width: double.infinity, child: ChhayaPrimaryButton(label: 'Copy to Clipboard', icon: Icons.copy_rounded, height: 48, onPressed: () {
            Clipboard.setData(ClipboardData(text: backup));
            ChhayaHaptics.success();
          })),
        ]),
      ),
    );
  }

  void _showDisappearingDuration() {
    final options = {'5 seconds': 5, '30 seconds': 30, '1 minute': 60, '1 hour': 3600, '1 day': 86400};
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => _buildBottomSheet(
        title: 'Set Duration',
        child: Column(
          children: options.entries.map((e) => ListTile(
            title: Text(e.key, style: ChhayaTypography.bodyMedium),
            trailing: const Icon(Icons.chevron_right_rounded, size: 16, color: ChhayaColors.labelTertiary),
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
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _buildBottomSheet(
          title: 'Block List (${blocked.length})',
          child: blocked.isEmpty
              ? Center(child: Text('No blocked contacts', style: ChhayaTypography.bodyMedium.copyWith(color: ChhayaColors.labelTertiary)))
              : Column(
                  children: blocked.map((id) {
                    final contacts = ref.read(contactsProvider);
                    final contact = contacts.where((c) => c.id == id).toList();
                    final name = contact.isNotEmpty ? contact.first.displayName : id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: ChhayaSpacing.space2),
                      padding: const EdgeInsets.all(ChhayaSpacing.space3),
                      decoration: BoxDecoration(
                        color: ChhayaColors.fillTertiary,
                        borderRadius: BorderRadius.circular(ChhayaRadius.md),
                        border: Border.all(color: ChhayaColors.separator),
                      ),
                      child: Row(children: [
                        AvatarWidget(name: name, size: 36),
                        const SizedBox(width: ChhayaSpacing.space3),
                        Expanded(child: Text(name, style: ChhayaTypography.bodyMedium)),
                        TextButton(
                          onPressed: () async {
                            await db.unblockContact(id);
                            setSt(() => blocked = db.getBlockedContacts());
                            ChhayaHaptics.selection();
                          },
                          child: const Text('Unblock', style: TextStyle(color: ChhayaColors.accent, fontSize: 14)),
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
        backgroundColor: ChhayaColors.cardSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xxl)),
        title: Row(children: [
          const Icon(Icons.warning_rounded, color: ChhayaColors.error, size: 22),
          const SizedBox(width: ChhayaSpacing.space2),
          const Text('Set Panic PIN'),
        ]),
        content: Padding(
          padding: const EdgeInsets.only(top: ChhayaSpacing.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Entering this PIN at the lock screen removes this device’s account data and keys. Remote copies and backups remain.',
                style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelSecondary, height: 1.5),
              ),
              const SizedBox(height: ChhayaSpacing.space3),
              TextField(
                controller: pinCtrl,
                decoration: const InputDecoration(hintText: '4-digit PIN'),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ChhayaColors.error),
            child: const Text('Set Panic PIN'),
            onPressed: () async {
              if (!RegExp(r'^\d{4}$').hasMatch(pinCtrl.text)) { return; }
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
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Transport status'),
      content:_telemetryRow('Transport','HTTPS API; onion routing unavailable'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))]));
  }

  Widget _telemetryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ChhayaSpacing.space1),
      child: Row(children: [
        Text(label, style: ChhayaTypography.bodyMedium.copyWith(color: ChhayaColors.labelSecondary)),
        const Spacer(),
        Text(value, style: ChhayaTypography.headlineSmall.copyWith(color: ChhayaColors.accent)),
      ]),
    );
  }

  void _showMeshPeers() {
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Offline transport'),
      content:const Text('Offline mesh is not implemented in this build. Internet messaging requires a configured server.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))]));
  }

  void _logout() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ChhayaColors.cardSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xxl)),
        title: const Text('Log Out'),
        content: const Text('All local data will be erased. Make sure you have your recovery phrase.'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ChhayaColors.error),
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
      padding: EdgeInsets.only(
        left: ChhayaSpacing.space5,
        right: ChhayaSpacing.space5,
        top: ChhayaSpacing.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + ChhayaSpacing.space5,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: ChhayaColors.fillPrimary, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: ChhayaSpacing.space4),
            Text(title, style: ChhayaTypography.displaySmall.copyWith(fontSize: 20)),
            const SizedBox(height: ChhayaSpacing.space4),
            child,
          ],
        ),
      ),
    );
  }
}