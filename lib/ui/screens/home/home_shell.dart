import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/screens/chat_list/chat_list_screen.dart';
import 'package:chaaya/ui/screens/calls/calls_tab.dart';
import 'package:chaaya/ui/screens/contacts/contacts_tab.dart';
import 'package:chaaya/ui/screens/settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

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
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: ChhayaColors.secondaryBackground,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.phone), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
