import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

class ContactsTab extends ConsumerWidget {
  const ContactsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ChhayaColors.primaryBackground,
        title: Text('Contacts', style: ChhayaTypography.headline),
        actions: [
          IconButton(
            onPressed: () => _showAddContact(context, ref),
            icon: const Icon(Icons.person_add, color: ChhayaColors.accentBlue, size: 22),
          ),
        ],
      ),
      body: SafeArea(
        child: contacts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_outline, size: 48, color: ChhayaColors.labelTertiary),
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

    return InkWell(
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
            IconButton(
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
              icon: const Icon(Icons.chat_bubble, color: ChhayaColors.accentBlue, size: 20),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: ChhayaColors.labelTertiary, size: 16),
          ],
        ),
      ),
    );
  }

  void _showAddContact(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'Display Name'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 8),
              TextField(controller: keyCtrl, decoration: const InputDecoration(hintText: 'Chhaya ID (optional)'), maxLength: 66),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
          TextButton(
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
                chhayaId: ChhayaId.fromPublicKey(pk),
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
