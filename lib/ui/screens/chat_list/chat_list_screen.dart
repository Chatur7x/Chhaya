import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/router/chhaya_router.dart';
import 'package:chaaya/ui/screens/contacts/contacts_tab.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);

    final filtered = _searchQuery.isEmpty
        ? conversations
        : conversations.where((c) {
            final name = c.participants.isNotEmpty ? c.participants.first.displayName : '';
            return name.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

    filtered.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      final aTime = a.lastMessage?.timestamp ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground,
        title: Text('Chats', style: ChhayaTypography.headline),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: Icon(Icons.search),
                ),
                style: ChhayaTypography.body,
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shield, size: 48, color: ChhayaColors.labelTertiary),
                          const SizedBox(height: ChhayaSpacing.md),
                          Text('No conversations yet', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelTertiary)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 0, indent: 80),
                      itemBuilder: (ctx, i) => _buildConvoItem(ctx, filtered[i]),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ChhayaHaptics.selection();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ContactsTab()),
          );
        },
        child: const Icon(Icons.chat_bubble),
      ),
    );
  }

  Widget _buildConvoItem(BuildContext context, Conversation convo) {
    final name = convo.participants.isNotEmpty ? convo.participants.first.displayName : 'Unknown';
    final lastMsg = convo.lastMessage?.content ?? 'Tap to start chatting';
    final time = convo.lastMessage?.timestamp ?? convo.createdAt;
    final timeStr = _formatTime(time);
    final isOnline = convo.participants.isNotEmpty && convo.participants.first.isOnline;

    return Dismissible(
      key: ValueKey(convo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: ChhayaColors.accentRed,
        child: const Icon(Icons.delete, color: ChhayaColors.labelPrimary),
      ),
      onDismissed: (_) async {
        final db = ref.read(localDatabaseProvider);
        await db.deleteConversation(convo.id);
        ref.read(conversationsProvider.notifier).removeConversation(convo.id);
        ChhayaHaptics.medium();
      },
      child: ListTile(
        leading: AvatarWidget(
          name: name,
          size: 52,
          statusColor: isOnline ? ChhayaColors.online : null,
        ),
        title: Row(
          children: [
            if (convo.isPinned)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.push_pin, size: 12, color: ChhayaColors.accentBlue),
              ),
            Expanded(
              child: Text(name, style: ChhayaTypography.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(timeStr, style: ChhayaTypography.caption1),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                lastMsg.length > 40 ? '${lastMsg.substring(0, 40)}...' : lastMsg,
                style: ChhayaTypography.subheadline.copyWith(color: ChhayaColors.labelSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (convo.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: const BoxDecoration(
                  color: ChhayaColors.accentBlue,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Text(
                  '${convo.unreadCount}',
                  style: const TextStyle(color: ChhayaColors.labelPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        onTap: () {
          ChhayaHaptics.selection();
          Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {
            'conversationId': convo.id,
            'contactName': name,
          });
        },
        onLongPress: () {
          ChhayaHaptics.medium();
          ref.read(conversationsProvider.notifier).pinConversation(convo.id);
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 2) return 'Yesterday';
    return '${time.month}/${time.day}';
  }
}
