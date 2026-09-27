import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
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
  String _filter = 'All';

  bool get disableAnimations => MediaQuery.of(context).disableAnimations;

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);

    final filtered = conversations.where((c) {
      final name = c.participants.isNotEmpty ? c.participants.first.displayName : '';
      final matchesSearch = _searchQuery.isEmpty || name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter = _filter == 'All' ||
          (_filter == 'Unread' && c.unreadCount > 0) ||
          (_filter == 'Pinned' && c.isPinned);
      return matchesSearch && matchesFilter;
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: AppBar(
          backgroundColor: ChhayaColors.primaryBackground,
          elevation: 0,
          titleSpacing: ChhayaSpacing.space4,
          title: Row(
            children: [
              Text('Chhaya', style: ChhayaTypography.displayMedium.copyWith(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              const SizedBox(width: ChhayaSpacing.space2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space2, vertical: ChhayaSpacing.space1),
                decoration: BoxDecoration(
                  color: ChhayaColors.accentDim,
                  borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                  border: Border.all(color: ChhayaColors.accent.withValues(alpha: 0.2)),
                ),
                child: Text('PRIVATE', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 10)),
              ),
            ],
          ),
          actions: [
            ChhayaIconButton(
              icon: Icons.search_rounded,
              onPressed: _showSearchSheet,
              size: 38,
              background: ChhayaColors.cardSurface,
            ),
            const SizedBox(width: ChhayaSpacing.space2),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search + filters
            Padding(
              padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space4, ChhayaSpacing.space1, ChhayaSpacing.space4, ChhayaSpacing.space3),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search conversations',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: ChhayaColors.labelTertiary),
                      filled: true,
                      fillColor: ChhayaColors.inputSurface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4, vertical: ChhayaSpacing.space3),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
                    ),
                    style: ChhayaTypography.bodyMedium.copyWith(fontSize: 14),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: ChhayaSpacing.space3),
                  Row(
                    children: [
                      for (final f in ['All', 'Unread', 'Pinned'])
                        Padding(
                          padding: const EdgeInsets.only(right: ChhayaSpacing.space2),
                          child: ChhayaChip(
                            label: f,
                            selected: _filter == f,
                            onSelected: () => setState(() => _filter = f),
                          ),
                        ),
                      const Spacer(),
                      Text('${filtered.length} chats', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelQuaternary)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space3, ChhayaSpacing.space1, ChhayaSpacing.space3, ChhayaSpacing.space12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: ChhayaSpacing.space2),
                      itemBuilder: (ctx, i) => _buildConvoCard(ctx, filtered[i]),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: ChhayaFAB(
        label: 'New Chat',
        icon: Icons.edit_rounded,
        onPressed: () {
          ChhayaHaptics.medium();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactsTab()));
        },
        extended: true,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ChhayaSpacing.space8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: ChhayaColors.cardSurface,
                borderRadius: BorderRadius.circular(ChhayaRadius.xxl),
                border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.12)),
              ),
              child: Icon(Icons.shield_outlined, size: 42, color: ChhayaColors.labelTertiary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: ChhayaSpacing.space5),
            Text('No conversations yet', style: ChhayaTypography.displaySmall.copyWith(fontSize: 16)),
            const SizedBox(height: ChhayaSpacing.space1),
            Text('Start a secure chat. Onion-routed, E2E encrypted.\nTap New Chat to begin.', textAlign: TextAlign.center, style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelTertiary, height: 1.5)),
            const SizedBox(height: ChhayaSpacing.space5),
            ChhayaSecondaryButton(
              label: 'Add Contact',
              icon: Icons.person_add_rounded,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactsTab())),
              expanded: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvoCard(BuildContext context, Conversation convo) {
    final name = convo.participants.isNotEmpty ? convo.participants.first.displayName : 'Unknown';
    final lastMsg = convo.lastMessage?.content ?? 'Tap to start secure chat →';
    final time = convo.lastMessage?.timestamp ?? convo.createdAt;
    final timeStr = _formatTime(time);
    final isOnline = convo.participants.isNotEmpty && convo.participants.first.isOnline;
    final isUnread = convo.unreadCount > 0;

    return Dismissible(
      key: ValueKey(convo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ChhayaSpacing.space5),
        decoration: BoxDecoration(color: ChhayaColors.error, borderRadius: BorderRadius.circular(ChhayaRadius.lg)),
        child: const Icon(Icons.delete_rounded, color: ChhayaColors.onAccent),
      ),
      onDismissed: (_) async {
        final db = ref.read(localDatabaseProvider);
        await db.deleteConversation(convo.id);
        ref.read(conversationsProvider.notifier).removeConversation(convo.id);
        ChhayaHaptics.medium();
      },
      child: InkWell(
        onTap: () {
          ChhayaHaptics.selection();
          Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {'conversationId': convo.id, 'contactName': name});
        },
        onLongPress: () {
          ChhayaHaptics.medium();
          ref.read(conversationsProvider.notifier).pinConversation(convo.id);
        },
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        child: AnimatedContainer(
          duration: disableAnimations ? Duration.zero : ChhayaAnimation.fast,
          padding: const EdgeInsets.all(ChhayaSpacing.space3),
          decoration: BoxDecoration(
            color: isUnread ? ChhayaColors.cardSurfaceElevated : ChhayaColors.cardSurface,
            borderRadius: BorderRadius.circular(ChhayaRadius.lg),
            border: Border.all(color: isUnread ? ChhayaColors.accent.withValues(alpha: 0.18) : ChhayaColors.glassBorder.withValues(alpha: 0.10), width: 0.8),
            boxShadow: isUnread ? ChhayaShadows.glowBlue : ChhayaShadows.subtle,
          ),
          child: Row(
            children: [
              AvatarWidget(name: name, size: 48, statusColor: isOnline ? ChhayaColors.online : null),
              const SizedBox(width: ChhayaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (convo.isPinned) Padding(padding: const EdgeInsets.only(right: ChhayaSpacing.space1), child: Icon(Icons.push_pin_rounded, size: 14, color: ChhayaColors.accent)),
                        Expanded(child: Text(name, style: ChhayaTypography.headlineMedium.copyWith(fontSize: 14, fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(timeStr, style: ChhayaTypography.labelSmall.copyWith(color: isUnread ? ChhayaColors.accent : ChhayaColors.labelTertiary, fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: ChhayaSpacing.space1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMsg.length > 38 ? '${lastMsg.substring(0, 38)}…' : lastMsg,
                            style: ChhayaTypography.bodySmall.copyWith(color: isUnread ? ChhayaColors.labelPrimary : ChhayaColors.labelSecondary, fontSize: 13, fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: ChhayaSpacing.space2),
                        if (convo.unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space2, vertical: ChhayaSpacing.space1),
                            decoration: BoxDecoration(
                              color: ChhayaColors.accent,
                              borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                            ),
                            child: Text('${convo.unreadCount}', style: const TextStyle(color: ChhayaColors.onAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                          )
                        else
                          const Icon(Icons.chevron_right_rounded, size: 14, color: ChhayaColors.labelQuaternary),
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

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChhayaColors.sheetBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ChhayaRadius.xxl))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(ChhayaSpacing.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Search Chats', style: ChhayaTypography.displaySmall),
              const SizedBox(height: ChhayaSpacing.space3),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Type contact or message...', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: ChhayaSpacing.space4),
              SizedBox(width: double.infinity, child: ChhayaPrimaryButton(label: 'Done', onPressed: () => Navigator.pop(context))),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 2) return 'Yesterday';
    return '${time.day}/${time.month}';
  }
}