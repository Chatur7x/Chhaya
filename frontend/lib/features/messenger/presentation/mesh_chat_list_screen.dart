import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/mesh_chat_service.dart';
import 'mesh_conversation_screen.dart';

/// Mesh Chat List — WhatsApp-style conversation list.
class MeshChatListScreen extends ConsumerWidget {
  const MeshChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.background,
        title: const Row(
          children: [
            Icon(Icons.cell_tower_rounded, color: ChaayaTheme.accent, size: 24),
            SizedBox(width: 10),
            Text('Chaaya'),
          ],
        ),
        actions: [
          // Channel status indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: ChaayaTheme.channelBadge('ble'),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                return _ConversationTile(
                  conversation: conversations[index],
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MeshConversationScreen(
                          contactId: conversations[index].contactId,
                          contactName: conversations[index].contactName,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ChaayaTheme.accent.withOpacity(0.15),
                  ChaayaTheme.bleColor.withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_outlined,
              size: 40,
              color: ChaayaTheme.accent,
            ),
          ),
          const SizedBox(height: 20),
          const Text('No conversations', style: ChaayaTheme.heading3),
          const SizedBox(height: 8),
          const Text(
            'Pair with a contact and start\nmessaging over the mesh',
            textAlign: TextAlign.center,
            style: ChaayaTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationPreview conversation;
  final VoidCallback onTap;
  
  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: ChaayaTheme.accent.withOpacity(0.2),
          child: Text(
            conversation.contactName.isNotEmpty 
                ? conversation.contactName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ChaayaTheme.accent,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                conversation.contactName,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: ChaayaTheme.textPrimary,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              conversation.timeText,
              style: TextStyle(
                fontSize: 12,
                color: conversation.unreadCount > 0
                    ? ChaayaTheme.accent
                    : ChaayaTheme.textMuted,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                conversation.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: conversation.unreadCount > 0
                      ? ChaayaTheme.textSecondary
                      : ChaayaTheme.textMuted,
                ),
              ),
            ),
            if (conversation.unreadCount > 0)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: ChaayaTheme.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

