import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/contact.dart';
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
  bool _savingProfile = false;

  Future<void> _editProfile() async {
    var editedName = ref.read(currentUserProvider)?.displayName ?? '';
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit profile'),
      content: TextFormField(initialValue: editedName, maxLength: 80,
        onChanged: (value) => editedName = value,
        decoration: const InputDecoration(labelText: 'Display name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, editedName), child: const Text('Save'))],
    ));
    if (name == null || !mounted) return;
    setState(() => _savingProfile = true);
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty || trimmed.length > 80) {
        throw ArgumentError('Invalid display name');
      }
      final api = ref.read(apiServiceProvider);
      if (api.isAuthenticated) await api.updateDisplayName(trimmed);
      final auth = ref.read(authServiceProvider);
      await auth.updateDisplayName(trimmed);
      ref.read(currentUserProvider.notifier).state = auth.currentUser;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save profile. Check the name and server connection, then try again.')));
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

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
    _blocked = db.getBlockedContacts().contains(widget.contactId)||(_contact?.isBlocked??false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = widget.contactId == null;
    final user = ref.watch(currentUserProvider);
    final displayName = _contact?.displayName ?? user?.displayName ?? 'Chhaya User';
    final chhayaIdText = _contact?.chhayaId.publicKey ?? user?.chhayaId.publicKey ?? '—';
    final verified = _contact?.isVerified == true;

    return Scaffold(
      backgroundColor: ChhayaPalette.of(context).primaryBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(pinned:true,title:Text(isOwnProfile?'Your profile':'Contact')),
          SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[
            AvatarWidget(name:displayName,size:80),
            const SizedBox(height:20),
            Text(displayName,textAlign:TextAlign.center,style:ChhayaType.of(context).title.copyWith(fontSize:24)),
            const SizedBox(height:8),
            if(!isOwnProfile) Text(verified ? 'Verified' : 'Unverified',
              style:ChhayaType.of(context).body.copyWith(color:verified
                ? ChhayaPalette.of(context).verifiedLevel3
                : ChhayaPalette.of(context).verifiedLevel1)),
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
                          Expanded(child: Text(_shortId(chhayaIdText, 16), style: ChhayaType.of(context).code.copyWith(color: ChhayaPalette.of(context).accent, fontSize: 13))),
                          ChhayaIconButton(icon: Icons.copy_rounded, tooltip: 'Copy Chhaya ID', onPressed: () {
                            Clipboard.setData(ClipboardData(text: chhayaIdText));
                            ChhayaHaptics.selection();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          }, size: 36, background: ChhayaPalette.of(context).cardSurface),
                        ],
                      ),
                    ),
                  if (isOwnProfile) ...[
                    TextButton.icon(onPressed: _savingProfile ? null : _editProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(_savingProfile ? 'Saving…' : 'Edit profile')),
                    _buildInfoCard(
                      title: 'Your Chhaya ID',
                      child: Row(
                        children: [
                          Expanded(child: Text(_shortId(chhayaIdText, 16), style: ChhayaType.of(context).code.copyWith(color: ChhayaPalette.of(context).accent, fontSize: 13))),
                          ChhayaIconButton(icon: Icons.copy_rounded, tooltip: 'Copy Chhaya ID', onPressed: () {
                            Clipboard.setData(ClipboardData(text: chhayaIdText));
                            ChhayaHaptics.selection();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          }, size: 36, background: ChhayaPalette.of(context).cardSurface),
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
                      _actionBtn(Icons.chat_bubble_rounded, 'Message', ChhayaPalette.of(context).accent, () {
                        _startChat();
                      }),
                      _actionBtn(Icons.call_rounded, 'Audio Call', ChhayaPalette.of(context).success, () {
                        Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'conversationId':ref.read(conversationsProvider).where((c)=>c.participants.any((p)=>p.id==_contact?.id)).firstOrNull?.id??'', 'contactName': displayName, 'isVideo': false});
                      }),
                      _actionBtn(Icons.videocam_rounded, 'Video Call', ChhayaPalette.of(context).info, () {
                        Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {'conversationId':ref.read(conversationsProvider).where((c)=>c.participants.any((p)=>p.id==_contact?.id)).firstOrNull?.id??'', 'contactName': displayName, 'isVideo': true});
                      }),
                      _actionBtn(Icons.qr_code_rounded, 'Verify', ChhayaPalette.of(context).warning, () {
                        Navigator.of(context).pushNamed(ChhayaRouter.verification);
                      }),
                    ]),
                    _buildInfoCard(
                      title: 'Security Details',
                      child: Column(
                        crossAxisAlignment:CrossAxisAlignment.start,
                        children: [
                          _detailRow('Identity', _contact?.isVerified==true?'Verified':'Verification required'),
                          _detailRow('Messages', 'Encrypted direct text'),
                        ],
                      ),
                    ),
                    _buildActionRow([
                      _actionBtn(_blocked ? Icons.check_circle_rounded : Icons.block_rounded, _blocked ? 'Unblock' : 'Block', _blocked ? ChhayaPalette.of(context).success : ChhayaPalette.of(context).error, () {
                        _toggleBlock();
                      }, bgColor: (_blocked ? ChhayaPalette.of(context).success : ChhayaPalette.of(context).error).withValues(alpha: 0.1), textColor: _blocked ? ChhayaPalette.of(context).success : ChhayaPalette.of(context).error),
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

  Future<void> _toggleBlock() async {
    final contact=_contact;
    if(contact==null) return;
    try {
      final db=ref.read(localDatabaseProvider);
      if(_blocked) { await db.unblockContact(contact.id); }
      else { await db.blockContact(contact.id); }
      final updated=contact.copyWith(isBlocked:!_blocked);
      await db.updateContact(updated);
      if(!mounted) return;
      ref.read(contactsProvider.notifier).updateContact(updated);
      setState(() { _blocked=!_blocked; _contact=updated; });
    } catch(_) {
      if(mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not save this change. Try again.'))); }
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
      backgroundColor: ChhayaPalette.of(context).sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ChhayaSpacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recovery Phrase', style: ChhayaType.of(context).displaySmall.copyWith(fontSize: 20)),
            const SizedBox(height: ChhayaSpacing.space3),
            Text('Write these down. They restore your account.', style: ChhayaType.of(context).bodySmall.copyWith(color: ChhayaPalette.of(context).labelTertiary)),
            const SizedBox(height: ChhayaSpacing.space4),
            Wrap(
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
          ],
        ),
      ),
    );
  }

  Future<void> _startChat() async {
    final contact=_contact;
    if(contact==null) return;
    try {
      var conversation=ref.read(conversationsProvider).where((c)=>!c.isGroup&&
        c.participants.any((p)=>p.id==contact.id)).firstOrNull;
      if(conversation==null) {
        conversation=(await ref.read(apiServiceProvider).createConversation(
          type:'direct',participantIds:[contact.id])).copyWith(participants:[contact]);
        await ref.read(localDatabaseProvider).addConversation(conversation);
        if(!mounted) return;
        ref.read(conversationsProvider.notifier).addConversation(conversation);
      }
      if(mounted) { Navigator.of(context).pushNamed(ChhayaRouter.chat,arguments:{
        'conversationId':conversation.id,'contactName':contact.displayName}); }
    } catch(_) {
      if(mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Could not open this chat. Check your server connection and try again.'))); }
    }
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: ChhayaSpacing.space3),
      padding: const EdgeInsets.all(ChhayaSpacing.space4),
      decoration: BoxDecoration(
        color: ChhayaPalette.of(context).cardSurface,
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        border: Border.all(color: ChhayaPalette.of(context).opaqueSeparator.withValues(alpha: 0.45), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ChhayaType.of(context).labelSmall.copyWith(letterSpacing: 0.2, color: ChhayaPalette.of(context).labelTertiary, fontWeight: FontWeight.w700)),
          const SizedBox(height: ChhayaSpacing.space3),
          child,
        ],
      ),
    );
  }

  Widget _buildActionRow(List<Widget> children) => Padding(
    padding:const EdgeInsets.only(bottom:16),
    child:Wrap(spacing:8,runSpacing:8,children:children),
  );

  Widget _actionBtn(IconData icon,String label,Color color,VoidCallback onTap,
      {Color? bgColor,Color? textColor}) => TextButton.icon(
    onPressed:onTap,icon:Icon(icon,size:20),label:Text(label),
    style:TextButton.styleFrom(foregroundColor:ChhayaPalette.of(context).accent,
      backgroundColor:ChhayaPalette.of(context).coralTint,minimumSize:const Size(48,48)),
  );

  Widget _detailRow(String label,String value) => Padding(
    padding:const EdgeInsets.symmetric(vertical:8),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:ChhayaType.of(context).caption),
        const SizedBox(height:4),
        Text(value,style:ChhayaType.of(context).bodyLarge),
      ],
    ),
  );
}
