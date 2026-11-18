import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/router/chhaya_router.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/chhaya_app_bar.dart';

class CallsTab extends ConsumerWidget {
  const CallsTab({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref) {
    final conversations=ref.watch(conversationsProvider)
      .where((c)=>!c.isGroup&&c.participants.length==1).toList();
    return Scaffold(
      appBar:const ChhayaAppBar(title:'Calls'),
      body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(24),children:[
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(
          color:ChhayaPalette.of(context).coralTint,borderRadius:BorderRadius.circular(16)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Icon(Icons.call_outlined,color:ChhayaPalette.of(context).accent,size:28),
            const SizedBox(height:16),
            Text('Start a call',style:ChhayaType.of(context).title),
            const SizedBox(height:8),
            Text('Voice and video calls with verified contacts. Keep both apps open and connected to the same server.',
              style:ChhayaType.of(context).body),
          ]),
        ),
        const SizedBox(height:24),
        if(conversations.isEmpty) Padding(padding:const EdgeInsets.symmetric(vertical:32),
          child:Text('Add and verify a contact to make your first call.',
            textAlign:TextAlign.center,style:ChhayaType.of(context).bodyLarge.copyWith(color:ChhayaPalette.of(context).inkMuted))),
        for(final conversation in conversations) Padding(
          padding:const EdgeInsets.symmetric(vertical:8),
          child:Column(children:[
            Row(children:[
              AvatarWidget(name:conversation.displayName,size:48),
              const SizedBox(width:16),
              Expanded(child:Text(conversation.displayName,style:ChhayaType.of(context).title)),
            ]),
            const SizedBox(height:8),
            Align(alignment:AlignmentDirectional.centerEnd,child:Wrap(spacing:8,children:[
              TextButton.icon(icon:const Icon(Icons.call_outlined),label:const Text('Voice'),
                onPressed:()=>Navigator.of(context).pushNamed(ChhayaRouter.call,arguments:{
                  'conversationId':conversation.id,'contactName':conversation.displayName,'isVideo':false})),
              TextButton.icon(icon:const Icon(Icons.videocam_outlined),label:const Text('Video'),
                onPressed:()=>Navigator.of(context).pushNamed(ChhayaRouter.call,arguments:{
                  'conversationId':conversation.id,'contactName':conversation.displayName,'isVideo':true})),
            ])),
            const Divider(),
          ]),
        ),
      ])),
    );
  }
}
