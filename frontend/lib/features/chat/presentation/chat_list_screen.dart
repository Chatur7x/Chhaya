import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../contacts/domain/models/contact.dart';
import '../../../core/theme/chaaya_theme.dart';
import 'conversation_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactServiceProvider).getAll();
    final presence = ref.watch(presenceServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text('#PROJ16 Chat',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: contacts.isEmpty
          ? const Center(
              child: Text('No contacts paired yet.',
                  style: TextStyle(color: Colors.white54)))
          : ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (context, index) =>
                  Divider(color: Colors.white.withOpacity(0.1), height: 1),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                final isOnline = presence.isUserOnline(contact.deviceId);
                final isTyping = presence.isTyping(contact.deviceId);

                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Text(contact.name[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: ChaayaTheme.nearbyGreen,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Text(contact.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      if (isTyping) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ChaayaTheme.accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('•',
                                  style: TextStyle(
                                      color: ChaayaTheme.accent, fontSize: 8)),
                              Text('typing',
                                  style: TextStyle(
                                      color: ChaayaTheme.accent,
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    isOnline
                        ? 'Online'
                        : 'ID: ${contact.deviceId.substring(0, 8)}...',
                    style: TextStyle(
                      color:
                          isOnline ? ChaayaTheme.nearbyGreen : Colors.white54,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (contact.status == ContactStatus.nearby)
                        ChaayaTheme.channelBadge('ble')
                      else if (contact.status == ContactStatus.viaRelay)
                        ChaayaTheme.channelBadge('wifi')
                      else
                        Text(contact.status.name,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ConversationScreen(contact: contact),
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
