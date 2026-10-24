import '../../../services/call/call_service.dart';
import '../call/call_screen.dart';
import '../../widgets/chhaya_brand_mark.dart';
import '../../widgets/chhaya_navigation.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/screens/chat_list/chat_list_screen.dart';
import 'package:chaaya/ui/screens/calls/calls_tab.dart';
import 'package:chaaya/ui/screens/contacts/contacts_tab.dart';
import 'package:chaaya/ui/screens/settings/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _selectedIndex=0;
  Timer? _syncTimer;
  StreamSubscription<IncomingCall>? _incomingCalls;
  bool _showingCall=false;
  bool _syncing=false;
  bool _foreground=true;
  int _syncFailures=0;
  String? _syncError;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this);
    _incomingCalls=ref.read(callServiceProvider).incoming.listen(_receiveCall);
    _startSync(); }
  void _startSync() {
    _syncTimer?.cancel();
    unawaited(_sync().whenComplete(_scheduleNextSync));
  }
  void _scheduleNextSync() {
    if(!mounted||!_foreground) { return; }
    final authenticated=ref.read(apiServiceProvider).isAuthenticated;
    // Local-only accounts need no remote poll. Back off on network failures.
    final delay=!authenticated
      ? const Duration(seconds:30)
      : _syncFailures==0?const Duration(seconds:15)
      : _syncFailures==1?const Duration(seconds:30)
      : const Duration(seconds:60);
    _syncTimer?.cancel();
    _syncTimer=Timer(delay,_startSync);
  }
  Future<void> _sync() async {
    if(_syncing) { return; }
    _syncing=true;
    try {
      if(!ref.read(apiServiceProvider).isAuthenticated) {
        _syncFailures=0;
        if(mounted&&_syncError!=null) setState(()=>_syncError=null);
        return;
      }
      try { await ref.read(callServiceProvider).ensureConnected(); } catch (_) { /* Messaging can still use REST. */ }
      await ref.read(messagingServiceProvider).retryAllPending();
      final conversations=await ref.read(messagingServiceProvider).sync();
      await ref.read(callServiceProvider).checkPendingInvites();
      final contacts=await ref.read(localDatabaseProvider).getAllContacts();
      if(!mounted) { return; }
      ref.read(conversationsProvider.notifier).setConversations(conversations);
      ref.read(contactsProvider.notifier).setContacts(contacts);
      _syncFailures=0;
      setState(()=>_syncError=null);
    } catch (_) {
      _syncFailures++;
      if(mounted) { setState(()=>_syncError='Sync unavailable. Check your server connection.'); }
    } finally { _syncing=false; }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.resumed) { _foreground=true; _startSync(); }
    else { _foreground=false; _syncTimer?.cancel(); }
  }
  @override
  void dispose() { _incomingCalls?.cancel(); _syncTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }


  Future<void> _receiveCall(IncomingCall incoming) async {
    if(!mounted||_showingCall) { return; }
    _showingCall=true;
    final contact=ref.read(contactsProvider).where((c)=>c.id==incoming.senderId).firstOrNull;
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('Incoming call from ${contact?.displayName??'verified contact'}'),
      content:Text(incoming.video?'Video call':'Voice call'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Decline')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Accept'))]));
    try {
      if(accepted==true&&mounted) {
        await ref.read(callServiceProvider).accept(incoming);
        if(mounted) { await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>CallScreen(
          contactName:contact?.displayName??'Contact',isVideo:incoming.video,incoming:true,conversationId:incoming.conversationId))); }
      } else { await ref.read(callServiceProvider).reject(incoming); }
    } catch(error) {
      await ref.read(callServiceProvider).end(notifyPeer:false);
      if(mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Call failed: $error'))); }
    } finally { _showingCall=false; }
  }

  final _pages = const [
    ChatListScreen(),
    CallsTab(),
    ContactsTab(),
    SettingsScreen(),
  ];

  void _select(int index) {
    ChhayaHaptics.selection();
    setState(()=>_selectedIndex=index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder:(context,constraints) {
    final wide=constraints.maxWidth>=720;
    const icons=[Icons.chat_bubble_outline_rounded,Icons.call_outlined,
      Icons.people_outline_rounded,Icons.settings_outlined];
    const selectedIcons=[Icons.chat_bubble_rounded,Icons.call_rounded,
      Icons.people_rounded,Icons.settings_rounded];
    const labels=['Chats','Calls','Contacts','Settings'];
    return Scaffold(
      body:Row(children:[
        if(wide) NavigationRail(
          leading: const Padding(padding: EdgeInsets.symmetric(vertical:24),child:ChhayaBrandMark(size:32)),
          selectedIndex:_selectedIndex,onDestinationSelected:_select,
          labelType:NavigationRailLabelType.all,groupAlignment:-0.7,
          backgroundColor:ChhayaPalette.of(context).surface,
          destinations:[for(var i=0;i<labels.length;i++) NavigationRailDestination(
            icon:Icon(icons[i]),selectedIcon:Icon(selectedIcons[i]),label:Text(labels[i]))],
        ),
        Expanded(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:880),
          child:Column(children:[
            if(_syncError!=null) SafeArea(bottom:false,child:MaterialBanner(
              content:Text(_syncError!),actions:[TextButton(onPressed:_startSync,child:const Text('Retry'))])),
            Expanded(child:IndexedStack(index:_selectedIndex,children:_pages)),
          ]),
        ))),
      ]),
      bottomNavigationBar:wide?null:DecoratedBox(
        decoration:BoxDecoration(border:Border(top:BorderSide(color:ChhayaPalette.of(context).borderSoft))),
        child:ChhayaNavigation(
        index:_selectedIndex,onSelect:_select,
        destinations:[for(var i=0;i<labels.length;i++) NavigationDestination(
          icon:Icon(icons[i]),selectedIcon:Icon(selectedIcons[i]),label:labels[i])],
      )),
    );
  });
}
