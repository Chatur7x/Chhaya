import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/providers/app_providers.dart';
import '../../theme/chhaya_theme.dart';
import '../../widgets/avatar_widget.dart';

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
      body:SafeArea(child:Padding(padding:const EdgeInsets.all(ChhayaSpacing.space4),
        child:widget.isVideo&&_error==null
          ? Column(children:[
              _status(context,call.status),
              Expanded(child:Stack(children:[
                Positioned.fill(child:RTCVideoView(call.remoteRenderer,objectFit:RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
                Align(alignment:Alignment.topRight,child:SizedBox(width:120,height:160,child:RTCVideoView(call.localRenderer,mirror:true))),
              ])),
              _controls(context),
            ])
          : LayoutBuilder(builder:(context,constraints)=>SingleChildScrollView(
              child:ConstrainedBox(constraints:BoxConstraints(minHeight:constraints.maxHeight),
                child:Column(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
                  _status(context,call.status),
                  Padding(padding:const EdgeInsets.symmetric(vertical:24),child:Column(children:[
                    AvatarWidget(name:widget.contactName,size:96),
                    const SizedBox(height:24),
                    Text(widget.contactName,textAlign:TextAlign.center,style:ChhayaType.of(context).title.copyWith(fontSize:24)),
                  ])),
                  _controls(context),
                ])),
            )),
      ))));
  }
  Widget _status(BuildContext context,String status)=>Semantics(liveRegion:true,
    child:Text(_error??status,textAlign:TextAlign.center,style:ChhayaType.of(context).bodyLarge));

  Widget _controls(BuildContext context) {
    final call=ref.watch(callServiceProvider);
    return Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Keep both apps open during your call.',textAlign:TextAlign.center),
      const SizedBox(height:16),
      Wrap(spacing:12,runSpacing:8,alignment:WrapAlignment.center,children:[
        TextButton.icon(onPressed:call.toggleMute,icon:Icon(call.muted?Icons.mic_off:Icons.mic),label:Text(call.muted?'Unmute':'Mute')),
        if(widget.isVideo) IconButton(tooltip:'Toggle camera',onPressed:call.toggleVideo,icon:Icon(call.videoEnabled?Icons.videocam:Icons.videocam_off)),
        FilledButton.icon(onPressed:() async { await call.end(); if(context.mounted) Navigator.of(context).pop(); },icon:const Icon(Icons.call_end),label:const Text('End call')),
      ]),
    ]);
  }
}
