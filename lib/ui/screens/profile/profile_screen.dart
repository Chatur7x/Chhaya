import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String? contactId;

  const ProfileScreen({super.key, this.contactId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Contact? _contact;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    if (widget.contactId != null) {
      _loadContact();
    }
  }

  Future<void> _loadContact() async {
    final db = ref.read(localDatabaseProvider);
    _contact = await db.getContact(widget.contactId!);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = widget.contactId == null;
    final user = ref.watch(currentUserProvider);
    final displayName = _contact?.displayName ?? user?.displayName ?? 'Chhaya User';
    final chhayaIdText = _contact?.chhayaId.publicKey ?? user?.chhayaId.publicKey ?? '—';
    final verificationLevel = _contact?.verificationLevel ?? 3;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(pinned:true,title:Text(isOwnProfile?'Your profile':'Contact')),
          SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[
            AvatarWidget(name:displayName,size:80),
            const SizedBox(height:20),
            Text(displayName,textAlign:TextAlign.center,style:ChhayaTypography.headline),
            const SizedBox(height:8),
            if(!isOwnProfile) Text(_verificationLabel(verificationLevel),
              style:ChhayaTypography.body.copyWith(color:_verificationColor(verificationLevel))),
          ]))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(ChhayaSpacing.space4),
              child: Column(
                children: [
                  // Chhaya ID
                  if (!isOwnProfile)
                    _buildInfoCard(
                      title: 'Chhaya ID',
                      child: Row(
                        children: [
                          Expanded(child: Text(_shortId(chhayaIdText, 16), style: ChhayaTypography.code.copyWith(color: ChhayaColors.accent, fontSize: 13))),
                          ChhayaIconButton(icon: Icons.copy_rounded, tooltip: 'Copy Chhaya ID', onPressed: () {
                            Clipboard.setData(ClipboardData(text: chhayaIdText));
                            ChhayaHaptics.selection();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          }, size: 36, background: ChhayaColors.cardSurface),
                        ],
                      ),
                    ),
                  if (isOwnProfile) ...[
                    _buildInfoCard(
                      title: 'Your Chhaya ID',
                      child: Row(
                        children: [
                          Expanded(child: Text(_shortId(chhayaIdText, 16), style: ChhayaTypography.code.copyWith(color: ChhayaColors.accent, fontSize: 13))),
                          ChhayaIconButton(icon: Icons.copy_rounded, tooltip: 'Copy Chhaya ID', onPressed: () {
                            Clipboard.setData(ClipboardData(text: chhayaIdText));
                            ChhayaHaptics.selection();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          }, size: 36, background: ChhayaColors.cardSurface),
                        ],
                      ),
                    ),
                    _buildInfoCard(
                      title: 'Recovery Phrase',
                      child: ChhayaPrimaryButton(label: 'View Phrase', icon: Icons.key_rounded, onPressed: _showRecoveryPhrase),
                    ),
                  ],
                  if (!isOwnProfile) ...[
                    _buildActionRow([
                      _actionBtn(Icons.chat_bubble_rounded, 'Message', ChhayaColors.accent, () {
                        _startChat();
                      }),
                      _actionBtn(Icons.call_rounded, 'Audio Call', ChhayaColors.success, () {
                        Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'conversationId':ref.read(conversationsProvider).where((c)=>c.participants.any((p)=>p.id==_contact?.id)).firstOrNull?.id??'', 'contactName': displayName, 'isVideo': false});
                      }),
                      _actionBtn(Icons.videocam_rounded, 'Video Call', ChhayaColors.info, () {
                        Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'conversationId':ref.read(conversationsProvider).where((c)=>c.participants.any((p)=>p.id==_contact?.id)).firstOrNull?.id??'', 'contactName': displayName, 'isVideo': true});
                      }),
                      _actionBtn(Icons.qr_code_rounded, 'Verify', ChhayaColors.warning, () {
                        Navigator.of(context).pushNamed(ChhayaRouter.verification);
                      }),
                    ]),
                    _buildInfoCard(
                      title: 'Security Details',
                      child: Column(
                        children: [
                          _detailRow('Identity', _contact?.isVerified==true?'Verified':'Verification required'),
                          _detailRow('Messages', 'Encrypted direct text'),
                        ],
                      ),
                    ),
                    _buildActionRow([
                      _actionBtn(_blocked ? Icons.check_circle_rounded : Icons.block_rounded, _blocked ? 'Unblock' : 'Block', _blocked ? ChhayaColors.success : ChhayaColors.error, () {
                        setState(() => _blocked = !_blocked);
                        ChhayaHaptics.warning();
                      }, bgColor: (_blocked ? ChhayaColors.success : ChhayaColors.error).withValues(alpha: 0.1), textColor: _blocked ? ChhayaColors.success : ChhayaColors.error),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _verificationColor(int level) {
    switch (level) {
      case 3: return ChhayaColors.verifiedLevel3;
      case 2: return ChhayaColors.verifiedLevel2;
      default: return ChhayaColors.verifiedLevel1;
    }
  }

  String _verificationLabel(int level) {
    switch (level) {
      case 3: return 'Verified';
      case 2: return 'Matched';
      default: return 'Unverified';
    }
  }

  String _shortId(String id, int max) => id.length > max ? '${id.substring(0, max)}\u2026' : id;

  void _showRecoveryPhrase() async {
    final auth = ref.read(authServiceProvider);
    final phrase = await auth.getRecoveryPhrase();
    if (!mounted) return;
    if(phrase==null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Recovery phrase is unavailable. Unlock your account and try again.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ChhayaSpacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recovery Phrase', style: ChhayaTypography.displaySmall.copyWith(fontSize: 20)),
            const SizedBox(height: ChhayaSpacing.space3),
            Text('Write these down. They restore your account.', style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelTertiary)),
            const SizedBox(height: ChhayaSpacing.space4),
            Wrap(
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
                    Text(phrase[i], style: ChhayaTypography.bodyMedium.copyWith(fontSize: 13, fontFamily: 'JetBrains Mono')),
                  ],
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }

  void _startChat() {
    if (_contact == null) return;
    final convoId = 'convo_${_contact!.id}';
    final newConvo = Conversation(id: convoId, participants: [_contact!], createdAt: DateTime.now());
    ref.read(localDatabaseProvider).addConversation(newConvo);
    ref.read(conversationsProvider.notifier).addConversation(newConvo);
    Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {'conversationId': convoId, 'contactName': _contact!.displayName});
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: ChhayaSpacing.space3),
      padding: const EdgeInsets.all(ChhayaSpacing.space4),
      decoration: BoxDecoration(
        color: ChhayaColors.cardSurface,
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        border: Border.all(color: ChhayaColors.opaqueSeparator.withValues(alpha: 0.45), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ChhayaTypography.labelSmall.copyWith(letterSpacing: 0.2, color: ChhayaColors.labelTertiary, fontWeight: FontWeight.w700)),
          const SizedBox(height: ChhayaSpacing.space3),
          child,
        ],
      ),
    );
  }

  Widget _buildActionRow(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: ChhayaSpacing.space3),
      child: Row(
        children: children.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space1), child: c))).toList(),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap, {Color? bgColor, Color? textColor}) {
    return ChhayaIconButton(
      icon: icon,
      onPressed: onTap,
      size: 48,
      background: bgColor ?? color.withValues(alpha: 0.12),
      color: textColor ?? color,
      tooltip: label,
    );
  }

  Widget _detailRow(String label,String value) => Padding(
    padding:const EdgeInsets.symmetric(vertical:8),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:ChhayaTypography.caption),
        const SizedBox(height:4),
        Text(value,style:ChhayaTypography.bodyLarge),
      ],
    ),
  );
}
