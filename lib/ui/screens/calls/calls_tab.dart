import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/router/chhaya_router.dart';

class CallsTab extends ConsumerWidget {
  const CallsTab({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref){
    final conversations=ref.watch(conversationsProvider)
        .where((c)=>!c.isGroup&&c.participants.length==1).toList();
    return Scaffold(appBar:AppBar(title:const Text('Calls')),
      body:SafeArea(child:conversations.isEmpty?const Center(child:Text('Add and verify a contact to make a call.')):
        ListView(children:[
          const Padding(padding:EdgeInsets.all(16),child:Text('Both apps must be open and connected to the same server.')),
          for(final conversation in conversations) ListTile(
            title:Text(conversation.displayName),subtitle:const Text('Direct voice or video call'),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              IconButton(tooltip:'Voice call',icon:const Icon(Icons.call),onPressed:()=>Navigator.of(context).pushNamed(
                ChhayaRouter.call,arguments:{'conversationId':conversation.id,'contactName':conversation.displayName,'isVideo':false})),
              IconButton(tooltip:'Video call',icon:const Icon(Icons.videocam),onPressed:()=>Navigator.of(context).pushNamed(
                ChhayaRouter.call,arguments:{'conversationId':conversation.id,'contactName':conversation.displayName,'isVideo':true})),
            ])),
        ])));
  }
}
