import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/chhaya_button.dart';
import '../../widgets/chhaya_app_bar.dart';
import '../../widgets/chhaya_search.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/models/conversation.dart';
import '../../../core/router/chhaya_router.dart';
import '../contacts/contacts_tab.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});
  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  String _filter = 'All';

  void _newChat() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ContactsTab()),
  );

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(conversationsProvider);
    final visible = all.where((c) {
      final matches = c.displayName.toLowerCase().contains(_query.toLowerCase());
      return matches && (_filter == 'All' ||
        (_filter == 'Unread' && c.unreadCount > 0) ||
        (_filter == 'Pinned' && c.isPinned));
    }).toList()..sort((a,b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return (b.lastMessage?.timestamp ?? b.createdAt)
        .compareTo(a.lastMessage?.timestamp ?? a.createdAt);
    });
    return Scaffold(
      appBar: const ChhayaAppBar(title: 'Chats'),
      floatingActionButton: ChhayaFAB(label: 'New chat', icon: Icons.edit_outlined, onPressed: _newChat),
      body: SafeArea(top: false, child: Column(children: [
        Padding(padding: const EdgeInsets.only(top:8,bottom:12),child:ChhayaSearch(
          controller:_searchController,hint:'Search conversations',
          onChanged:(value)=>setState(()=>_query=value))),
        Padding(padding: const EdgeInsets.symmetric(horizontal:24), child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(spacing:8, runSpacing:4, children: [
            for (final label in ['All','Unread','Pinned']) ChoiceChip(
              label: Text(label), selected: _filter==label,
              showCheckmark:false,
              onSelected: (_) => setState(() => _filter=label),
            ),
          ]),
        )),
        const SizedBox(height:12),
        Expanded(child: visible.isEmpty ? _empty(all.isEmpty) : ListView.separated(
          padding: const EdgeInsets.fromLTRB(16,0,16,104),
          itemCount: visible.length,
          separatorBuilder: (_,index) => const Divider(height:1,indent:76,endIndent:12),
          itemBuilder: (_,index) => _conversation(visible[index]),
        )),
      ])),
    );
  }

  Widget _empty(bool noChats) => LayoutBuilder(builder:(context,constraints) =>
    SingleChildScrollView(child: ConstrainedBox(
      constraints:BoxConstraints(minHeight:constraints.maxHeight),
      child: Padding(padding:const EdgeInsets.all(32),child:Column(
        mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(Icons.chat_bubble_outline_rounded,size:48,color:ChhayaPalette.of(context).accent),
          const SizedBox(height:24),
          Text(noChats?'Your conversations start here':'No matching conversations',
            textAlign:TextAlign.center,style:ChhayaType.of(context).headline),
          const SizedBox(height:12),
          Text(noChats?'Connect a server in Settings, then add and verify a contact to start chatting.'
            :'Try another name or choose a different filter.',
            textAlign:TextAlign.center,style:ChhayaType.of(context).bodyLarge.copyWith(color:ChhayaPalette.of(context).inkMuted)),
          if(noChats) ...[
            const SizedBox(height:24),
            ChhayaSecondaryButton(label:'Add a contact',icon:Icons.person_add_outlined,onPressed:_newChat,expanded:false),
          ],
        ],
      )),
    )),
  );

  Widget _conversation(Conversation conversation) {
    final unread=conversation.unreadCount>0;
    final largeText=MediaQuery.textScalerOf(context).scale(16)>22;
    final last=conversation.lastMessage;
    final preview=last==null?'Start a conversation':last.isExpired?'Message expired':
      !conversation.participants.every((p)=>p.isVerified)?'Verify identity to read messages':last.content;
    final time=conversation.lastMessage?.timestamp??conversation.createdAt;
    final age=DateTime.now().difference(time);
    final stamp=age.inDays>0?'${time.day}/${time.month}':'${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}';
    return InkWell(
      borderRadius:BorderRadius.circular(16),
      onTap:()=>Navigator.of(context).pushNamed(ChhayaRouter.chat,arguments:{
        'conversationId':conversation.id,'contactName':conversation.displayName}),
      onLongPress:()=>_options(conversation),
      child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:16),child:Row(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Hero(tag:'conversation-avatar-${conversation.id}',child:AvatarWidget(name:conversation.displayName,size:52)),
          const SizedBox(width:16),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Expanded(child:Text(conversation.displayName,maxLines:largeText?2:1,overflow:TextOverflow.ellipsis,
                style:ChhayaType.of(context).bodyLarge.copyWith(fontWeight:unread?FontWeight.w700:FontWeight.w600))),
              const SizedBox(width:8),
              if(!largeText) Text(stamp,style:ChhayaType.of(context).monoCode.copyWith(fontSize:13,color:ChhayaPalette.of(context).inkMuted)),
            ]),
            if(largeText) Padding(padding:const EdgeInsets.only(top:6),
              child:Text(stamp,style:ChhayaType.of(context).monoCode.copyWith(fontSize:13,color:ChhayaPalette.of(context).inkMuted))),
            const SizedBox(height:6),
            Row(children:[
              if(conversation.isPinned) Padding(padding:EdgeInsetsDirectional.only(end:4),
                child:Icon(Icons.push_pin_outlined,size:16,color:ChhayaPalette.of(context).inkMuted)),
              Expanded(child:Text(preview,
                maxLines:2,overflow:TextOverflow.ellipsis,
                style:ChhayaType.of(context).body.copyWith(color:ChhayaPalette.of(context).inkMuted))),
              if(unread) Padding(padding:const EdgeInsetsDirectional.only(start:8),child:Badge(
                backgroundColor:ChhayaPalette.of(context).accent,textColor:ChhayaPalette.of(context).white,
                label:Text('${conversation.unreadCount}'),)),
            ]),
          ])),
          PopupMenuButton<String>(
            tooltip:'Conversation options',
            onSelected:(value)=>_action(conversation,value),
            itemBuilder:(_)=>[
              PopupMenuItem(value:'pin',child:Text(conversation.isPinned?'Unpin':'Pin')),
              const PopupMenuItem(value:'delete',child:Text('Delete local conversation')),
            ],
          ),
        ],
      )),
    );
  }

  Future<void> _options(Conversation c) async {
    final action=await showModalBottomSheet<String>(context:context,builder:(ctx)=>SafeArea(
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(title:Text(c.isPinned?'Unpin conversation':'Pin conversation'),
          leading:const Icon(Icons.push_pin_outlined),onTap:()=>Navigator.pop(ctx,'pin')),
        ListTile(title:const Text('Delete local conversation'),leading:const Icon(Icons.delete_outline),
          onTap:()=>Navigator.pop(ctx,'delete')),
      ]),
    ));
    if(action!=null&&mounted) await _action(c,action);
  }

  Future<void> _action(Conversation c,String action) async {
    if(action=='pin') {
      ref.read(conversationsProvider.notifier).pinConversation(c.id);
      await ref.read(localDatabaseProvider).addConversation(c.copyWith(isPinned:!c.isPinned));
      return;
    }
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Delete this local conversation?'),
      content:const Text('This removes local history. Copies on the server or other devices remain and may sync again.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))],
    ));
    if(confirmed!=true||!mounted) return;
    await ref.read(localDatabaseProvider).deleteConversation(c.id);
    if(mounted) ref.read(conversationsProvider.notifier).removeConversation(c.id);
  }
}
