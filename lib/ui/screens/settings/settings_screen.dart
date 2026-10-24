import 'package:flutter/material.dart';
import '../../theme/appearance_provider.dart';
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
  bool _typingIndicators = true;
  bool _disappearingMessages = false;
  final bool _meshRouting = false;

  String _shortId(String id, int max) => id.length > max ? '${id.substring(0, max)}…' : id;

  @override
  void initState() {
    super.initState();
    final db = ref.read(localDatabaseProvider);
    _biometricLock = db.getBiometricLockEnabled();
    _readReceipts = db.getReadReceiptsEnabled();
    _typingIndicators = db.getTypingIndicatorsEnabled();
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
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;

    return Scaffold(
      backgroundColor: ChhayaPalette.of(context).primaryBackground,
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
                    if (!largeText) ...[
                      AvatarWidget(name: displayName, size: 56, showGradientRing: true),
                      const SizedBox(width: ChhayaSpacing.space4),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: ChhayaType.of(context).title.copyWith(fontSize: 24)),
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
                                    style: ChhayaType.of(context).code.copyWith(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: ChhayaSpacing.space1),
                                Icon(Icons.copy_rounded, size: 12, color: ChhayaPalette.of(context).accent),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: ChhayaPalette.of(context).labelTertiary, size: 16),
                  ],
                ),
              ),
            ),

            _sectionHeader('CONNECTION'),
            _settingsCard([
              _settingsTile(Icons.dns_rounded, ChhayaPalette.of(context).info, 'Connect messaging server', onTap: _configureServer),
            ]),
            _sectionHeader('ACCOUNT'),
            _settingsCard([
              _settingsTile(Icons.description_rounded, ChhayaPalette.of(context).accent, 'Recovery Phrase', onTap: _showRecoveryPhrase),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.devices_rounded, ChhayaPalette.of(context).info, 'Linked Devices', onTap: _showLinkedDevices),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.cloud_download_rounded, ChhayaPalette.of(context).success, 'Backup', onTap: _showBackup),
            ]),

            _sectionHeader('PRIVACY'),
            _settingsCard([
              _settingsSwitch(Icons.timer_rounded, ChhayaPalette.of(context).warning, 'Disappearing Messages', _disappearingMessages, (v) async {
                if (v) {
                  _showDisappearingDuration();
                } else {
                  await ref.read(localDatabaseProvider).setGlobalDisappearingDuration(0);
                  setState(() => _disappearingMessages = false);
                }
              }),
              const Divider(height: 0, indent: 56),
              _settingsSwitch(Icons.visibility_rounded, ChhayaPalette.of(context).accent, 'Read Receipts', _readReceipts, (v) async {
                await ref.read(localDatabaseProvider).setReadReceiptsEnabled(v);
                setState(() => _readReceipts = v);
              }),
              const Divider(height: 0, indent: 56),
              _settingsSwitch(Icons.more_horiz_rounded, ChhayaPalette.of(context).info, 'Typing Indicators', _typingIndicators, (v) async {
                await ref.read(localDatabaseProvider).setTypingIndicatorsEnabled(v);
                setState(() => _typingIndicators = v);
              }),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.block_rounded, ChhayaPalette.of(context).error, 'Block List', onTap: _showBlockList, trailing: _blockedCountBadge()),
            ]),

            _sectionHeader('SECURITY'),
            _settingsCard([
              _settingsSwitch(Icons.security_rounded, ChhayaPalette.of(context).info, 'Biometric Lock', _biometricLock, (v) async {
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
              _settingsTile(Icons.warning_rounded, ChhayaPalette.of(context).error, 'Panic PIN', subtitle: 'Removes local account data on entry', onTap: _showPanicPinSetup),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.qr_code_rounded, ChhayaPalette.of(context).success, 'Verify Contact', onTap: () {
                Navigator.of(context).pushNamed(ChhayaRouter.verification);
              }),
            ]),

            _sectionHeader('NETWORK'),
            _settingsCard([
              _settingsSwitch(Icons.public_rounded, ChhayaPalette.of(context).accent, 'Onion routing (unavailable)', _onionRouting, null),
              const Divider(height:0,indent:56),
              _settingsTile(Icons.info_outline,ChhayaPalette.of(context).info,'Transport status',onTap:_showRelaySpeed),
              const Divider(height:0,indent:56),
              _settingsSwitch(Icons.wifi_tethering_rounded,ChhayaPalette.of(context).success,'Offline mesh (unavailable)',_meshRouting,null),
              _settingsTile(Icons.info_outline,ChhayaPalette.of(context).info,'Offline transport status',onTap:_showMeshPeers),
            ]),

            _sectionHeader('APPEARANCE'),
            _settingsCard([
              _settingsTile(Icons.contrast_rounded, ChhayaPalette.of(context).accent, 'Appearance',
                subtitle: ref.watch(appearanceProvider).name == 'system' ? 'Match device' : ref.watch(appearanceProvider).name == 'dark' ? 'Warm dark' : 'Warm light',
                onTap: () => ChhayaMotion.sheet<void>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final mode in ThemeMode.values) ListTile(
                    title: Text(mode == ThemeMode.system ? 'Match device' : mode == ThemeMode.dark ? 'Warm dark' : 'Warm light'),
                    trailing: ref.read(appearanceProvider) == mode ? const Icon(Icons.check_rounded) : null,
                    onTap: () { ref.read(appearanceProvider.notifier).select(mode); Navigator.pop(ctx); }),
                ]))),
            ]),

            _sectionHeader('ABOUT'),
            _settingsCard([
              _settingsTile(Icons.info_rounded, ChhayaPalette.of(context).labelSecondary, 'Version', subtitle: '14.0.0 test build', onTap: () {
                showDialog(context: context, builder: (_) => AlertDialog(
                  backgroundColor: ChhayaPalette.of(context).cardSurfaceElevated,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xxl)),
                  title: const Text('Chhaya'),
                  content: const Text('Version 14.0.0 test build • 2026\n\n© 2026 Chhaya Project'),
                  actions: [TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
                ));
              }),
              const Divider(height: 0, indent: 56),
              _settingsTile(Icons.description_outlined, ChhayaPalette.of(context).labelSecondary, 'Licenses', onTap: () {
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
                  foregroundColor: ChhayaPalette.of(context).error,
                  side: BorderSide(color: ChhayaPalette.of(context).error.withValues(alpha: 0.35)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.pill)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text('Log Out', style: ChhayaType.of(context).headlineMedium.copyWith(color: ChhayaPalette.of(context).error)),
                onPressed: _logout,
              ),
            ),

            const SizedBox(height: ChhayaSpacing.space4),
            Center(
              child: Text(
                'Chhaya · Version 14.0.0 test build',
                style: ChhayaType.of(context).labelSmall.copyWith(color: ChhayaPalette.of(context).labelQuaternary),
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
        style: ChhayaType.of(context).labelSmall.copyWith(
          letterSpacing: 0.2,
          color: ChhayaPalette.of(context).labelTertiary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) => Material(
    color:ChhayaPalette.of(context).cardSurface,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),
      side:BorderSide(color:ChhayaPalette.of(context).borderSoft)),
    clipBehavior:Clip.antiAlias,
    child:Column(children:children),
  );

  Widget _settingsTile(IconData icon, Color color, String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: ChhayaPalette.of(context).hoverCream,
          borderRadius: BorderRadius.circular(ChhayaRadius.xs),
        ),
        child: Icon(icon, color: ChhayaPalette.of(context).inkSoft, size: 20),
      ),
      title: Text(title, style: ChhayaType.of(context).bodyMedium),
      subtitle: subtitle != null ? Text(subtitle, style: ChhayaType.of(context).labelMedium.copyWith(color: ChhayaPalette.of(context).labelTertiary)) : null,
      trailing: trailing ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: ChhayaPalette.of(context).labelTertiary, size: 14) : null),
      onTap: onTap != null ? () { ChhayaHaptics.selection(); onTap(); } : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: 6),
    );
  }

  Widget _settingsSwitch(IconData icon, Color color, String title, bool value, ValueChanged<bool>? onChanged) {
    return SwitchListTile(
      secondary: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: ChhayaPalette.of(context).hoverCream,
          borderRadius: BorderRadius.circular(ChhayaRadius.xs),
        ),
        child: Icon(icon, color: ChhayaPalette.of(context).inkSoft, size: 20),
      ),
      title: Text(title, style: ChhayaType.of(context).bodyMedium),
      value: value,
      onChanged: onChanged == null ? null : (v) { ChhayaHaptics.selection(); onChanged(v); },
      activeTrackColor: ChhayaPalette.of(context).accent,
      activeThumbColor: ChhayaPalette.of(context).white,
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
        color: ChhayaPalette.of(context).error,
        borderRadius: BorderRadius.circular(ChhayaRadius.pill),
      ),
      child: Text('${blocked.length}', style: TextStyle(color: ChhayaPalette.of(context).onAccent, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  void _showRecoveryPhrase() async {
    final auth = ref.read(authServiceProvider);
    final phrase = await auth.getRecoveryPhrase() ?? ['anchor','brave','castle','diamond','eagle','frost','garden','harbor','ivory','jasmine','knight','lantern'];
    if(!mounted) { return; }
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaPalette.of(context).sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => _buildBottomSheet(
        title: 'Recovery Phrase',
        child: Wrap(
          spacing: ChhayaSpacing.space2, runSpacing: ChhayaSpacing.space2,
          children: List.generate(phrase.length, (i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space3, vertical: ChhayaSpacing.space2),
            decoration: BoxDecoration(
              color: ChhayaPalette.of(context).fillTertiary,
              borderRadius: BorderRadius.circular(ChhayaRadius.md),
              border: Border.all(color: ChhayaPalette.of(context).separator),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${i + 1}.', style: ChhayaType.of(context).labelSmall.copyWith(color: ChhayaPalette.of(context).accent, fontWeight: FontWeight.w700)),
                const SizedBox(width: ChhayaSpacing.space2),
                Text(phrase[i], style: ChhayaType.of(context).bodyMedium.copyWith(fontSize: 13, fontFamily: 'RobotoMono')),
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
      backgroundColor: ChhayaPalette.of(context).sheetBackground,
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
                  color: ChhayaPalette.of(context).fillTertiary,
                  borderRadius: BorderRadius.circular(ChhayaRadius.md),
                  border: Border.all(color: ChhayaPalette.of(context).separator),
                ),
                child: Row(children: [
                  Icon(Icons.devices_rounded, color: ChhayaPalette.of(context).info, size: 24),
                  const SizedBox(width: ChhayaSpacing.space3),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['name'] as String? ?? 'Device', style: ChhayaType.of(context).bodyMedium),
                    Text(d['id'] as String? ?? '', style: ChhayaType.of(context).code.copyWith(fontSize: 10, color: ChhayaPalette.of(context).labelTertiary)),
                  ])),
                  TextButton(
                    onPressed: () async {
                      await db.removeLinkedDevice(d['id'] as String);
                      setSt(() => devices = db.getLinkedDevices());
                      ChhayaHaptics.medium();
                    },
                    child: Text('Revoke', style: TextStyle(color: ChhayaPalette.of(context).error, fontSize: 14)),
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
      backgroundColor: ChhayaPalette.of(context).sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => _buildBottomSheet(
        title: 'Encrypted Backup',
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(ChhayaSpacing.space3),
            decoration: BoxDecoration(
              color: ChhayaPalette.of(context).primaryBackground,
              borderRadius: BorderRadius.circular(ChhayaRadius.md),
              border: Border.all(color: ChhayaPalette.of(context).separator),
            ),
            child: Text(
              backup.length > 120 ? '${backup.substring(0, 120)}…' : backup,
              style: ChhayaType.of(context).code.copyWith(fontSize: 11, color: ChhayaPalette.of(context).labelSecondary),
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
      backgroundColor: ChhayaPalette.of(context).sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => _buildBottomSheet(
        title: 'Set Duration',
        child: Column(
          children: options.entries.map((e) => ListTile(
            title: Text(e.key, style: ChhayaType.of(context).bodyMedium),
            trailing: Icon(Icons.chevron_right_rounded, size: 16, color: ChhayaPalette.of(context).labelTertiary),
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
      backgroundColor: ChhayaPalette.of(context).sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _buildBottomSheet(
          title: 'Block List (${blocked.length})',
          child: blocked.isEmpty
              ? Center(child: Text('No blocked contacts', style: ChhayaType.of(context).bodyMedium.copyWith(color: ChhayaPalette.of(context).labelTertiary)))
              : Column(
                  children: blocked.map((id) {
                    final contacts = ref.read(contactsProvider);
                    final contact = contacts.where((c) => c.id == id).toList();
                    final name = contact.isNotEmpty ? contact.first.displayName : id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: ChhayaSpacing.space2),
                      padding: const EdgeInsets.all(ChhayaSpacing.space3),
                      decoration: BoxDecoration(
                        color: ChhayaPalette.of(context).fillTertiary,
                        borderRadius: BorderRadius.circular(ChhayaRadius.md),
                        border: Border.all(color: ChhayaPalette.of(context).separator),
                      ),
                      child: Row(children: [
                        AvatarWidget(name: name, size: 36),
                        const SizedBox(width: ChhayaSpacing.space3),
                        Expanded(child: Text(name, style: ChhayaType.of(context).bodyMedium)),
                        TextButton(
                          onPressed: () async {
                            await db.unblockContact(id);
                            setSt(() => blocked = db.getBlockedContacts());
                            ChhayaHaptics.selection();
                          },
                          child: Text('Unblock', style: TextStyle(color: ChhayaPalette.of(context).accent, fontSize: 14)),
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
        backgroundColor: ChhayaPalette.of(context).cardSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xxl)),
        title: Row(children: [
          Icon(Icons.warning_rounded, color: ChhayaPalette.of(context).error, size: 22),
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
                style: ChhayaType.of(context).bodySmall.copyWith(color: ChhayaPalette.of(context).labelSecondary, height: 1.5),
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
            style: TextButton.styleFrom(foregroundColor: ChhayaPalette.of(context).error),
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
        Text(label, style: ChhayaType.of(context).bodyMedium.copyWith(color: ChhayaPalette.of(context).labelSecondary)),
        const Spacer(),
        Text(value, style: ChhayaType.of(context).headlineSmall.copyWith(color: ChhayaPalette.of(context).accent)),
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
        backgroundColor: ChhayaPalette.of(context).cardSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xxl)),
        title: const Text('Log Out'),
        content: const Text('All local data will be erased. Make sure you have your recovery phrase.'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ChhayaPalette.of(context).error),
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
            Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: ChhayaPalette.of(context).fillPrimary, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: ChhayaSpacing.space4),
            Text(title, style: ChhayaType.of(context).displaySmall.copyWith(fontSize: 20)),
            const SizedBox(height: ChhayaSpacing.space4),
            child,
          ],
        ),
      ),
    );
  }
}
