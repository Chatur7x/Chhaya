import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../contacts/data/contact_service.dart';
import 'conversation_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactServiceProvider).getAll();

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text('#PROJ16 Chat', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: contacts.isEmpty 
        ? const Center(child: Text('No contacts paired yet.', style: TextStyle(color: Colors.white54)))
        : ListView.separated(
        itemCount: contacts.length,
        separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1), height: 1),
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: Text(contact.username[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
            ),
            title: Text(contact.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('ID: ${contact.deviceId.substring(0, 8)}...', style: const TextStyle(color: Colors.white54)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(contact.lastSeenText, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ConversationScreen(contact: contact),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}
