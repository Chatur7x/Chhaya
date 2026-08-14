import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/glass_container.dart';
import '../../../core/router/chhaya_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/models/contact.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String? contactId;
  const ProfileScreen({super.key, this.contactId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {

  int _ratchetEpoch = 1;
  int _msgCount = 14;
  String _rootKey = '';
  String _sendChainKey = '';
  String _recvChainKey = '';
  String _dhEphemeral = '';


  bool _verifying = false;
  List<bool> _chunkStatus = List.filled(5, false);

  @override
  void initState() {
    super.initState();
    _generateRatchetKeys();
  }

  void _generateRatchetKeys() {
    final rng = Random();
    String hex(int len) => List.generate(len, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
    _rootKey = hex(16);
    _sendChainKey = hex(16);
    _recvChainKey = hex(16);
    _dhEphemeral = hex(32);
  }

  Contact? _getContact() {
    if (widget.contactId == null) return null;
    final contacts = ref.read(contactsProvider);
    final matches = contacts.where((c) => c.id == widget.contactId).toList();
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final contact = _getContact();
    final user = ref.watch(currentUserProvider);
    final isSelf = contact == null;

    final name = isSelf ? (user?.displayName ?? 'Chhaya User') : contact.displayName;
    final ChhayaId = isSelf ? (user?.ChhayaId.publicKey ?? '') : contact.ChhayaId.publicKey;
    final verLevel = isSelf ? 3 : contact.verificationLevel;
    final verColor = verLevel == 3 ? ChhayaColors.verifiedLevel3 : verLevel == 2 ? ChhayaColors.verifiedLevel2 : ChhayaColors.verifiedLevel1;
    final verLabel = verLevel == 3 ? 'Verified' : verLevel == 2 ? 'Matched' : 'Unverified';

    return CupertinoPageScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        border: null,
        middle: Text(isSelf ? 'My Profile' : 'Contact', style: ChhayaTypography.headline),
      ),
      child: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 16),


            Center(child: AvatarWidget(name: name, size: 100, showGradientRing: true)),
            const SizedBox(height: 16),
            Center(child: Text(name, style: ChhayaTypography.title1)),
            const SizedBox(height: 4),


            Center(
              child: GestureDetector(
                onTap: () { Clipboard.setData(ClipboardData(text: ChhayaId)); ChhayaHaptics.selection(); },
                child: Text('${ChhayaId.substring(0, 16)}…', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.accentBlue)),
              ),
            ),
            const SizedBox(height: 8),


            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: verColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: verColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(verLabel, style: ChhayaTypography.caption1.copyWith(color: verColor)),
                ]),
              ),
            ),

            const SizedBox(height: 24),

            if (contact != null) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _actionBtn(CupertinoIcons.chat_bubble_fill, 'Message', ChhayaColors.accentBlue, () {
                  final convos = ref.read(conversationsProvider);
                  final existing = convos.where((c) => c.participants.any((p) => p.id == contact.id)).toList();
                  if (existing.isNotEmpty) {
                    Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {'conversationId': existing.first.id, 'contactName': contact.displayName});
                  }
                }),
                _actionBtn(CupertinoIcons.phone_fill, 'Audio', ChhayaColors.accentGreen, () {
                  Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': contact.displayName, 'isVideo': false});
                }),
                _actionBtn(CupertinoIcons.videocam_fill, 'Video', ChhayaColors.accentPurple, () {
                  Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'contactName': contact.displayName, 'isVideo': true});
                }),
                _actionBtn(CupertinoIcons.qrcode, 'Verify', ChhayaColors.accentOrange, () {
                  Navigator.of(context).pushNamed(ChhayaRouter.verification, arguments: {'contactId': contact.id});
                }),
              ]),
              const SizedBox(height: 24),
            ],


            GestureDetector(
              onTap: _showRatchetVisualizer,
              child: GlassContainer(
                child: Row(children: [
                  const Icon(CupertinoIcons.lock_shield_fill, color: ChhayaColors.accentGreen, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('End-to-End Encrypted', style: ChhayaTypography.headline),
                    Text('Tap to view key rotation', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)),
                  ])),
                  const Icon(CupertinoIcons.chevron_right, color: ChhayaColors.labelTertiary, size: 14),
                ]),
              ),
            ),

            const SizedBox(height: 24),


            Text('Shared Media', style: ChhayaTypography.headline),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                itemBuilder: (_, i) {
                  final colors = [ChhayaColors.accentBlue, ChhayaColors.accentPurple, ChhayaColors.accentIndigo, ChhayaColors.accentTeal, ChhayaColors.accentOrange];
                  return GestureDetector(
                    onTap: () => _showSwarmChunks('file_${i + 1}.enc'),
                    child: Container(
                      width: 80, height: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: colors[i].withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors[i].withValues(alpha: 0.3)),
                      ),
                      child: Icon(CupertinoIcons.doc_fill, color: colors[i], size: 28),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),


            GestureDetector(
              onTap: _showShamirKeys,
              child: GlassContainer(
                child: Row(children: [
                  const Icon(CupertinoIcons.person_3_fill, color: ChhayaColors.accentIndigo, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Group Key Shards', style: ChhayaTypography.headline),
                    Text('Shamir\'s Secret Sharing (3-of-5)', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)),
                  ])),
                  const Icon(CupertinoIcons.chevron_right, color: ChhayaColors.labelTertiary, size: 14),
                ]),
              ),
            ),

            const SizedBox(height: 24),


            if (contact != null) ...[
              _blockUnblockTile(contact),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { ChhayaHaptics.light(); onTap(); },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label, style: ChhayaTypography.caption1),
      ]),
    );
  }

  Widget _blockUnblockTile(Contact contact) {
    final db = ref.read(localDatabaseProvider);
    final blocked = db.getBlockedContacts().contains(contact.id);
    return GestureDetector(
      onTap: () async {
        if (blocked) {
          await db.unblockContact(contact.id);
        } else {
          await db.blockContact(contact.id);
        }
        setState(() {});
        ChhayaHaptics.medium();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: ChhayaColors.accentRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(blocked ? CupertinoIcons.checkmark_circle : CupertinoIcons.nosign, color: blocked ? ChhayaColors.accentGreen : ChhayaColors.accentRed, size: 20),
          const SizedBox(width: 8),
          Text(blocked ? 'Unblock Contact' : 'Block Contact', style: ChhayaTypography.headline.copyWith(color: blocked ? ChhayaColors.accentGreen : ChhayaColors.accentRed)),
        ]),
      ),
    );
  }


  void _showRatchetVisualizer() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _bottomSheet(
          title: '🔑 Double Ratchet Visualizer',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _keyRow('DH Ephemeral', _dhEphemeral),
              _keyRow('Root Key', _rootKey),
              _keyRow('Sending Chain', _sendChainKey),
              _keyRow('Receiving Chain', _recvChainKey),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Epoch: $_ratchetEpoch', style: ChhayaTypography.body.copyWith(color: ChhayaColors.accentBlue)),
                Text('Messages: $_msgCount', style: ChhayaTypography.body.copyWith(color: ChhayaColors.accentGreen)),
              ]),
              const SizedBox(height: 16),
              CupertinoButton(
                color: ChhayaColors.accentBlue,
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  _ratchetEpoch++;
                  _msgCount = 0;
                  _generateRatchetKeys();
                  setSt(() {});
                  setState(() {});
                  ChhayaHaptics.success();
                },
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(CupertinoIcons.arrow_2_circlepath, size: 18),
                  const SizedBox(width: 8),
                  const Text('Simulate Key Exchange'),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyRow(String label, String hex) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)),
        const SizedBox(height: 2),
        Text('0x${hex.substring(0, min(hex.length, 24))}…', style: ChhayaTypography.body.copyWith(fontFamily: 'Courier', color: ChhayaColors.accentGreen, fontSize: 14)),
      ]),
    );
  }


  void _showSwarmChunks(String fileName) {
    _chunkStatus = List.filled(5, false);
    _verifying = false;
    final rng = Random();
    String sha() => List.generate(16, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
    final chunks = List.generate(5, (i) => {
      'index': i,
      'node': ['US-East', 'EU-West', 'ASIA-South', 'US-West', 'EU-North'][i],
      'hash': sha(),
    });

    showCupertinoModalPopup(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _bottomSheet(
          title: '📦 Swarm Chunk Manager',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $fileName', style: ChhayaTypography.headline),
              Text('Size: 2.4 MB  |  5 chunks', style: ChhayaTypography.caption1.copyWith(color: ChhayaColors.labelTertiary)),
              const SizedBox(height: 12),
              ...chunks.map((c) {
                final i = c['index'] as int;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: ChhayaColors.fillTertiary, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(
                      _chunkStatus[i] ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                      color: _chunkStatus[i] ? ChhayaColors.accentGreen : ChhayaColors.labelTertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('Chunk ${i + 1}', style: ChhayaTypography.body),
                    const Spacer(),
                    Text(c['node'] as String, style: ChhayaTypography.caption2.copyWith(color: ChhayaColors.accentBlue)),
                    const SizedBox(width: 8),
                    Text('${(c['hash'] as String).substring(0, 8)}…', style: ChhayaTypography.caption2.copyWith(fontFamily: 'Courier')),
                  ]),
                );
              }),
              const SizedBox(height: 12),
              CupertinoButton(
                color: _verifying ? ChhayaColors.fillTertiary : ChhayaColors.accentGreen,
                borderRadius: BorderRadius.circular(12),
                onPressed: _verifying ? null : () async {
                  setSt(() => _verifying = true);
                  for (int i = 0; i < 5; i++) {
                    await Future.delayed(const Duration(milliseconds: 600));
                    _chunkStatus[i] = true;
                    setSt(() {});
                    ChhayaHaptics.light();
                  }
                  _verifying = false;
                  ChhayaHaptics.success();
                },
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_verifying ? CupertinoIcons.arrow_2_circlepath : CupertinoIcons.checkmark_shield, size: 18),
                  const SizedBox(width: 8),
                  Text(_verifying ? 'Verifying…' : 'Verify Integrity'),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _showShamirKeys() {
    final members = ['Priya', 'Arjun', 'Neha', 'Rahul', 'You'];
    final colors = [ChhayaColors.accentBlue, ChhayaColors.accentPurple, ChhayaColors.accentOrange, ChhayaColors.accentTeal, ChhayaColors.accentGreen];
    bool reconstructed = false;

    showCupertinoModalPopup(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => _bottomSheet(
          title: '🔐 Shamir\'s Secret Sharing',
          child: Column(children: [
            Text('Threshold: 3 of 5 shards required', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelSecondary)),
            const SizedBox(height: 16),

            ...List.generate(5, (i) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors[i].withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors[i].withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(members[i], style: ChhayaTypography.body),
                const Spacer(),
                Text('Shard ${i + 1}', style: ChhayaTypography.caption1.copyWith(color: colors[i])),
              ]),
            )),
            const SizedBox(height: 16),
            CupertinoButton(
              color: reconstructed ? ChhayaColors.accentGreen : ChhayaColors.accentIndigo,
              borderRadius: BorderRadius.circular(12),
              onPressed: () async {
                setSt(() => reconstructed = false);
                await Future.delayed(const Duration(milliseconds: 800));
                setSt(() => reconstructed = true);
                ChhayaHaptics.success();
              },
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(reconstructed ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.lock_open_fill, size: 18),
                const SizedBox(width: 8),
                Text(reconstructed ? 'Key Reconstructed ✅' : 'Reconstruct Key'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomSheet({required String title, required Widget child}) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ChhayaColors.secondaryBackground.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: ChhayaColors.fillPrimary, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 16),
            Text(title, style: ChhayaTypography.title2),
            const SizedBox(height: 16),
            child,
          ])),
        ),
      ),
    );
  }
}
