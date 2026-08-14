import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

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

    return CupertinoPageScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        border: null,
        middle: Text('Chats', style: ChhayaTypography.headline),
      ),
      child: SafeArea(
        child: Column(
          children: [

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: CupertinoSearchTextField(
                placeholder: 'Search conversations',
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
                          const Icon(CupertinoIcons.shield_lefthalf_fill, size: 48, color: ChhayaColors.labelTertiary),
                          const SizedBox(height: ChhayaSpacing.md),
                          Text('No conversations yet', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelTertiary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _buildConvoItem(ctx, filtered[i]),
                    ),
            ),
          ],
        ),
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
        child: const Icon(CupertinoIcons.delete, color: ChhayaColors.labelPrimary),
      ),
      onDismissed: (_) async {
        final db = ref.read(localDatabaseProvider);
        await db.deleteConversation(convo.id);
        ref.read(conversationsProvider.notifier).removeConversation(convo.id);
        ChhayaHaptics.medium();
      },
      child: GestureDetector(
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.lg, vertical: ChhayaSpacing.md),
          decoration: BoxDecoration(
            color: convo.isPinned ? ChhayaColors.fillTertiary.withValues(alpha: 0.15) : ChhayaColors.primaryBackground,
            border: Border(bottom: BorderSide(color: ChhayaColors.separator, width: 0.33)),
          ),
          child: Row(
            children: [
              AvatarWidget(
                name: name,
                size: 52,
                statusColor: isOnline ? ChhayaColors.online : null,
              ),
              const SizedBox(width: ChhayaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (convo.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(CupertinoIcons.pin_fill, size: 12, color: ChhayaColors.accentBlue),
                          ),
                        Expanded(
                          child: Text(name, style: ChhayaTypography.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Text(timeStr, style: ChhayaTypography.caption1),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
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
                  ],
                ),
              ),
            ],
          ),
        ),
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
