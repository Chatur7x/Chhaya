import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import '../../widgets/chhaya_app_bar.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/ui/widgets/glass_container.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final contacts=ref.watch(contactsProvider);
    final query=_query.toLowerCase();
    final filtered=contacts.where((c)=>c.displayName.toLowerCase().contains(query)||
      c.chhayaId.publicKey.toLowerCase().contains(query)).toList()
      ..sort((a,b)=>a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return Scaffold(
      appBar:ChhayaAppBar(title:'Contacts',actions:[
        IconButton(tooltip:'Add contact',icon:const Icon(Icons.person_add_outlined),
          onPressed:()=>_showAddContact(context,ref)),
        const SizedBox(width:16),
      ]),
      body:SafeArea(top:false,child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(24,8,24,16),child:TextField(
          decoration:const InputDecoration(hintText:'Search by name or ID',prefixIcon:Icon(Icons.search)),
          onChanged:(value)=>setState(()=>_query=value),
        )),
        Padding(padding:const EdgeInsets.symmetric(horizontal:24),child:Row(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Icon(Icons.verified_user_outlined,size:20,color:ChhayaPalette.of(context).accent),
            const SizedBox(width:12),
            Expanded(child:Text('Verify each contact’s identity before messaging.',
              style:ChhayaType.of(context).body.copyWith(color:ChhayaPalette.of(context).inkMuted))),
          ],
        )),
        const SizedBox(height:16),
        Expanded(child:filtered.isEmpty?SingleChildScrollView(child:Padding(
          padding:const EdgeInsets.fromLTRB(32,48,32,32),child:Column(children:[
            Icon(Icons.people_outline,size:48,color:ChhayaPalette.of(context).accent),
            const SizedBox(height:24),
            Text(contacts.isEmpty?'Keep your people close':'No contacts found',
              style:ChhayaType.of(context).headline,textAlign:TextAlign.center),
            const SizedBox(height:12),
            Text(contacts.isEmpty?'Add someone using their Chhaya ID. No phone number or email is needed.'
              :'Try another name or Chhaya ID.',textAlign:TextAlign.center,style:ChhayaType.of(context).bodyLarge),
            if(contacts.isEmpty) ...[const SizedBox(height:24),
              ChhayaPrimaryButton(label:'Add a contact',expanded:false,
                onPressed:()=>_showAddContact(context,ref))],
          ]),
        )):ListView.separated(
          padding:const EdgeInsets.fromLTRB(16,0,16,24),itemCount:filtered.length,
          separatorBuilder:(_,index)=>const Divider(height:1,indent:80),
          itemBuilder:(_,index)=>_buildContactCard(context,ref,filtered[index]),
        )),
      ])),
    );
  }

  Widget _buildContactCard(BuildContext context,WidgetRef ref,Contact contact) => ListTile(
    contentPadding:const EdgeInsets.symmetric(horizontal:8,vertical:12),
    leading:AvatarWidget(name:contact.displayName,size:48),
    title:Text(contact.displayName,style:ChhayaType.of(context).bodyLarge.copyWith(fontWeight:FontWeight.w600)),
    subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Text(
      contact.isVerified?'Verified identity':'Identity not verified',
      style:ChhayaType.of(context).caption,
    )),
    onTap:()=>Navigator.of(context).pushNamed(ChhayaRouter.profile,arguments:{'contactId':contact.id}),
    trailing:IconButton(tooltip:'Message ${contact.displayName}',
      icon:Icon(Icons.chat_bubble_outline,color:ChhayaPalette.of(context).accent),
      onPressed:()=>_startChat(contact)),
  );

  Future<void> _startChat(Contact contact) async {
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

  void _showAddContact(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChhayaPalette.of(context).cardSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
        title: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: ChhayaPalette.of(context).accent, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.person_add_rounded, size: 18, color: ChhayaPalette.of(context).onAccent)), const SizedBox(width: 10), Text('Add Contact', style: ChhayaType.of(context).displaySmall.copyWith(fontSize: 18))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ChhayaInput(controller: nameCtrl, hint: 'Display name', label: 'Display name', prefixIcon: Icons.person_outline_rounded, textCapitalization: TextCapitalization.words, autofocus: true),
          const SizedBox(height: ChhayaSpacing.space3),
          ChhayaInput(controller: keyCtrl, hint: '05…', label: 'Full Chhaya ID', prefixIcon: Icons.fingerprint_rounded, maxLength: 66, style: ChhayaType.of(context).code.copyWith(color: ChhayaPalette.of(context).labelPrimary, fontSize: 11)),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Ask your contact for their full Chhaya ID', style: ChhayaType.of(context).labelSmall.copyWith(color: ChhayaPalette.of(context).labelQuaternary)),
        ]),
        actions: [TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)), ChhayaPrimaryButton(label: 'Add', onPressed: () async {
          final name = nameCtrl.text.trim();
          if(name.isEmpty) { return; }
          final pk=keyCtrl.text.trim().toLowerCase();
          if(!RegExp(r'^05[0-9a-f]{64}$').hasMatch(pk)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid full Chhaya ID')));
            return;
          }
          try {
            final api=ref.read(apiServiceProvider);
            final contact=await api.addContact(chhayaId:pk,displayName:name);
            await ref.read(localDatabaseProvider).addContact(contact);
            final conversations=await ref.read(messagingServiceProvider).sync();
            final contacts=await ref.read(localDatabaseProvider).getAllContacts();
            ref.read(contactsProvider.notifier).setContacts(contacts);
            ref.read(conversationsProvider.notifier).setConversations(conversations);
            if(ctx.mounted) Navigator.pop(ctx);
            ChhayaHaptics.success();
          } catch(error) {
            if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not add contact: $error')));
          }
        })],
      ),
    );
  }
}