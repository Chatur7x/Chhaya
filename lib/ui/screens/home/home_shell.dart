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
  bool _syncing=false;
  String? _syncError;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _startSync(); }
  void _startSync() {
    _syncTimer?.cancel(); _sync();
    _syncTimer=Timer.periodic(const Duration(seconds:5),(_)=>_sync());
  }
  Future<void> _sync() async {
    if(_syncing) { return; }
    _syncing=true;
    try {
      final conversations=await ref.read(messagingServiceProvider).sync();
      final contacts=await ref.read(localDatabaseProvider).getAllContacts();
      if(!mounted) { return; }
      ref.read(conversationsProvider.notifier).setConversations(conversations);
      ref.read(contactsProvider.notifier).setContacts(contacts);
      setState(()=>_syncError=null);
    } catch (_) { if(mounted) setState(()=>_syncError='Sync unavailable. Check your server connection.'); }
    finally { _syncing=false; }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.resumed) { _startSync(); }
    else { _syncTimer?.cancel(); }
  }
  @override
  void dispose() { _syncTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }


  final _pages = const [
    ChatListScreen(),
    CallsTab(),
    ContactsTab(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Column(children:[
        if(_syncError!=null) SafeArea(bottom:false,child:MaterialBanner(
          content:Text(_syncError!),actions:[TextButton(onPressed:_sync,child:const Text('Retry'))])),
        Expanded(child:IndexedStack(index:_selectedIndex,children:_pages)),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: ChhayaColors.secondaryBackground.withValues(alpha: 0.92),
          border: Border(top: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12), width: 0.6)),
        ),
        child: SafeArea(
          child: NavigationBar(
            backgroundColor: ChhayaColors.transparent,
            elevation: 0,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              ChhayaHaptics.selection();
              setState(() => _selectedIndex = index);
            },
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call_rounded),
                label: 'Calls',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Contacts',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}