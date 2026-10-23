import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/providers/app_providers.dart';
import '../../theme/chhaya_theme.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String contactName;
  final String? contactAvatar;
  final bool isVideo;
  final String conversationId;
  final bool incoming;
  const CallScreen({super.key,required this.contactName,this.contactAvatar,
      required this.isVideo,this.conversationId='',this.incoming=false});
  @override
  ConsumerState<CallScreen> createState()=>_CallScreenState();
}
class _CallScreenState extends ConsumerState<CallScreen> {
  String? _error;
  @override
  void initState(){ super.initState(); if(!widget.incoming) _start(); }
  Future<void> _start() async {
    try { await ref.read(callServiceProvider).call(widget.conversationId,widget.isVideo); }
    catch(error) {
      await ref.read(callServiceProvider).end(notifyPeer:false);
      if(mounted) setState(()=>_error='$error');
    }
  }
  @override
  Widget build(BuildContext context){
    final call=ref.watch(callServiceProvider);
    return PopScope(canPop:false,onPopInvokedWithResult:(didPop,result) async {
      if(didPop) { return; }
      await call.end();
      if(context.mounted) Navigator.of(context).pop();
    },child:Scaffold(appBar:AppBar(title:Text(widget.contactName),automaticallyImplyLeading:false),
      body:SafeArea(child:Padding(padding:const EdgeInsets.all(ChhayaSpacing.space4),child:Column(children:[
        Text(_error??call.status,semanticsLabel:_error??call.status),
        if(widget.isVideo&&_error==null) Expanded(child:Stack(children:[
          Positioned.fill(child:RTCVideoView(call.remoteRenderer,objectFit:RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
          Align(alignment:Alignment.topRight,child:SizedBox(width:120,height:160,child:RTCVideoView(call.localRenderer,mirror:true))),
        ])) else const Spacer(),
        const Text('Calls require both apps to be open. Restricted networks may require your own TURN server.'),
        Wrap(spacing:12,children:[
          IconButton(tooltip:call.muted?'Unmute':'Mute',onPressed:call.toggleMute,icon:Icon(call.muted?Icons.mic_off:Icons.mic)),
          if(widget.isVideo) IconButton(tooltip:'Toggle camera',onPressed:call.toggleVideo,icon:Icon(call.videoEnabled?Icons.videocam:Icons.videocam_off)),
          FilledButton.icon(onPressed:() async { await call.end(); if(context.mounted) Navigator.of(context).pop(); },icon:const Icon(Icons.call_end),label:const Text('End call')),
        ]),
      ])))));
  }
}
