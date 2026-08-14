import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/ui/screens/chat_list/chat_list_screen.dart';
import 'package:chaaya/ui/screens/settings/settings_screen.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      tabBar: CupertinoTabBar(
        backgroundColor: ChhayaColors.secondaryBackground.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: ChhayaColors.separator.withValues(alpha: 0.3), width: 0.33),
        ),
        activeColor: ChhayaColors.accentBlue,
        inactiveColor: ChhayaColors.labelTertiary,
        iconSize: 24,
        height: 49,
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chat_bubble_2_fill), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.phone_fill), label: 'Calls'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.person_2_fill), label: 'Contacts'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.gear_alt_fill), label: 'Settings'),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            switch (index) {
              case 0: return const ChatListScreen();
              case 1: return const _CallsTab();
              case 2: return const _ContactsTab();
              case 3: return const SettingsScreen();
              default: return const ChatListScreen();
            }
          },
        );
      },
    );
  }
}



class _CallsTab extends StatelessWidget {
  const _CallsTab();

  static final _calls = [
    _CallData('Priya Sharma', 'Incoming', '15 min', false, false),
    _CallData('Arjun Mehta', 'Outgoing', '2 min', true, false),
    _CallData('Dev Team', 'Missed', '', false, true),
    _CallData('Neha Gupta', 'Outgoing', '8 min', true, true),
    _CallData('Rahul Kapoor', 'Incoming', '45 min', false, false),
    _CallData('Ananya Reddy', 'Missed', '', true, false),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        border: null,
        middle: Text('Calls', style: ChhayaTypography.headline),
      ),
      child: SafeArea(
        child: ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: _calls.length,
          itemBuilder: (ctx, i) => _buildCallItem(ctx, _calls[i]),
        ),
      ),
    );
  }

  Widget _buildCallItem(BuildContext context, _CallData call) {
    final missed = call.type == 'Missed';
    final color = missed ? ChhayaColors.accentRed : ChhayaColors.labelSecondary;
    final icon = call.type == 'Incoming'
        ? CupertinoIcons.phone_arrow_down_left
        : call.type == 'Outgoing'
            ? CupertinoIcons.phone_arrow_up_right
            : CupertinoIcons.phone_down_fill;

    return GestureDetector(
      onTap: () {
        ChhayaHaptics.selection();
        Navigator.of(context).pushNamed(ChhayaRouter.call, arguments: {
          'contactName': call.name,
          'isVideo': call.isVideo,
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.lg, vertical: ChhayaSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ChhayaColors.separator, width: 0.33)),
        ),
        child: Row(
          children: [
            AvatarWidget(name: call.name, size: 44),
            const SizedBox(width: ChhayaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.name, style: ChhayaTypography.body.copyWith(
                    color: missed ? ChhayaColors.accentRed : ChhayaColors.labelPrimary,
                  )),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(
                      call.duration.isEmpty ? call.type : '${call.type} · ${call.duration}',
                      style: ChhayaTypography.caption1.copyWith(color: color),
                    ),
                  ]),
                ],
              ),
            ),
            Icon(
              call.isVideo ? CupertinoIcons.videocam_fill : CupertinoIcons.phone_fill,
              color: ChhayaColors.accentBlue,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallData {
  final String name, type, duration;
  final bool isVideo, missed;
  const _CallData(this.name, this.type, this.duration, this.isVideo, this.missed);
}



class _ContactsTab extends ConsumerWidget {
  const _ContactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);

    return CupertinoPageScaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: ChhayaColors.primaryBackground.withValues(alpha: 0.92),
        border: null,
        middle: Text('Contacts', style: ChhayaTypography.headline),
        trailing: GestureDetector(
          onTap: () => _showAddContact(context, ref),
          child: const Icon(CupertinoIcons.person_badge_plus_fill, color: ChhayaColors.accentBlue, size: 22),
        ),
      ),
      child: SafeArea(
        child: contacts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.person_2, size: 48, color: ChhayaColors.labelTertiary),
                    const SizedBox(height: ChhayaSpacing.md),
                    Text('No contacts yet', style: ChhayaTypography.body.copyWith(color: ChhayaColors.labelTertiary)),
                  ],
                ),
              )
            : ListView.builder(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                itemCount: contacts.length,
                itemBuilder: (ctx, i) => _buildContactItem(ctx, ref, contacts[i]),
              ),
      ),
    );
  }

  Widget _buildContactItem(BuildContext context, WidgetRef ref, Contact contact) {
    final levelColor = contact.verificationLevel == 3
        ? ChhayaColors.verifiedLevel3
        : contact.verificationLevel == 2
            ? ChhayaColors.verifiedLevel2
            : ChhayaColors.verifiedLevel1;
    final levelText = contact.verificationLevel == 3 ? 'Verified' : contact.verificationLevel == 2 ? 'Matched' : 'Unverified';

    return GestureDetector(
      onTap: () {
        ChhayaHaptics.selection();
        Navigator.of(context).pushNamed(ChhayaRouter.profile, arguments: {'contactId': contact.id});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.lg, vertical: ChhayaSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ChhayaColors.separator, width: 0.33)),
        ),
        child: Row(
          children: [
            AvatarWidget(
              name: contact.displayName,
              size: 44,
              statusColor: contact.isOnline ? ChhayaColors.online : null,
            ),
            const SizedBox(width: ChhayaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.displayName, style: ChhayaTypography.body),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(levelText, style: ChhayaTypography.caption1.copyWith(color: levelColor)),
                  ]),
                ],
              ),
            ),

            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () {
                ChhayaHaptics.light();

                final convos = ref.read(conversationsProvider);
                final existing = convos.where((c) => c.participants.any((p) => p.id == contact.id)).toList();
                if (existing.isNotEmpty) {
                  Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {
                    'conversationId': existing.first.id,
                    'contactName': contact.displayName,
                  });
                } else {

                  final convoId = 'convo_${contact.id}';
                  final newConvo = Conversation(
                    id: convoId,
                    participants: [contact],
                    createdAt: DateTime.now(),
                  );
                  final db = ref.read(localDatabaseProvider);
                  db.addConversation(newConvo);
                  ref.read(conversationsProvider.notifier).addConversation(newConvo);
                  Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {
                    'conversationId': convoId,
                    'contactName': contact.displayName,
                  });
                }
              },
              child: const Icon(CupertinoIcons.chat_bubble_fill, color: ChhayaColors.accentBlue, size: 20),
            ),
            const SizedBox(width: 8),
            const Icon(CupertinoIcons.chevron_right, color: ChhayaColors.labelTertiary, size: 16),
          ],
        ),
      ),
    );
  }

  void _showAddContact(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Add Contact'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(children: [
            CupertinoTextField(controller: nameCtrl, placeholder: 'Display Name', textCapitalization: TextCapitalization.words),
            const SizedBox(height: 8),
            CupertinoTextField(controller: keyCtrl, placeholder: 'Chhaya ID (optional)', maxLength: 66),
          ]),
        ),
        actions: [
          CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(
            child: const Text('Add'),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              var pk = keyCtrl.text.trim().toLowerCase();
              if (pk.isEmpty || pk.length != 66) {
                pk = List.generate(66, (_) => '0123456789abcdef'[DateTime.now().microsecond % 16]).join();
              }

              final contactId = 'contact_${const Uuid().v4().substring(0, 8)}';
              final newContact = Contact(
                id: contactId,
                ChhayaId: ChhayaId.fromPublicKey(pk),
                displayName: name,
                verificationLevel: 1,
                isOnline: true,
              );

              final db = ref.read(localDatabaseProvider);
              await db.addContact(newContact);
              ref.read(contactsProvider.notifier).addContact(newContact);

              final convoId = 'convo_$contactId';
              final newConvo = Conversation(id: convoId, participants: [newContact], createdAt: DateTime.now());
              await db.addConversation(newConvo);
              ref.read(conversationsProvider.notifier).addConversation(newConvo);

              if (ctx.mounted) Navigator.pop(ctx);
              ChhayaHaptics.success();
            },
          ),
        ],
      ),
    );
  }
}
