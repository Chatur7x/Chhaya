import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';
import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/ui/widgets/glass_container.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/router/chhaya_router.dart';

class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final filtered = contacts.where((c) => c.displayName.toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppBar(
          backgroundColor: ChhayaColors.primaryBackground,
          elevation: 0,
          title: Text('Contacts', style: ChhayaTypography.displayMedium.copyWith(fontSize: 20)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ChhayaPrimaryButton(label: 'Add', icon: Icons.person_add_rounded, onPressed: () => _showAddContact(context, ref), height: 38, expanded: false),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space4, ChhayaSpacing.space3, ChhayaSpacing.space4, ChhayaSpacing.space3),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by name or ID…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: ChhayaColors.labelTertiary),
                  filled: true, fillColor: ChhayaColors.inputSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ChhayaRadius.lg), borderSide: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12))),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ChhayaSpacing.space4),
              child: GlassContainer(
                padding: const EdgeInsets.all(ChhayaSpacing.space4),
                child: Row(
                  children: [
                    AvatarStack(names: contacts.map((c) => c.displayName).toList()),
                    const SizedBox(width: ChhayaSpacing.space3),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${contacts.length} contacts', style: ChhayaTypography.headlineMedium.copyWith(fontSize: 13)),
                      Text('Verified • Encrypted', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.online, fontWeight: FontWeight.w600, fontSize: 11)),
                    ]),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: ChhayaColors.accentDim, borderRadius: BorderRadius.circular(ChhayaRadius.pill), border: Border.all(color: ChhayaColors.accent.withValues(alpha: 0.2))), child: Text('All synced', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w700, fontSize: 10))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ChhayaSpacing.space3),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(width: 88, height: 88, decoration: BoxDecoration(color: ChhayaColors.cardSurface, borderRadius: BorderRadius.circular(ChhayaRadius.xxl)), child: const Icon(Icons.people_outline_rounded, size: 40, color: ChhayaColors.labelTertiary)),
                        const SizedBox(height: ChhayaSpacing.space5),
                        Text('No contacts', style: ChhayaTypography.headlineMedium.copyWith(fontSize: 16)),
                        const SizedBox(height: ChhayaSpacing.space1),
                        Text('Add your first secure contact', style: ChhayaTypography.bodySmall.copyWith(color: ChhayaColors.labelTertiary)),
                      ]),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(ChhayaSpacing.space3, ChhayaSpacing.space2, ChhayaSpacing.space3, ChhayaSpacing.space12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: ChhayaSpacing.space2),
                      itemBuilder: (ctx, i) => _buildContactCard(ctx, ref, filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(BuildContext context, WidgetRef ref, Contact contact) {
    final levelColor = contact.verificationLevel == 3 ? ChhayaColors.verifiedLevel3 : contact.verificationLevel == 2 ? ChhayaColors.verifiedLevel2 : ChhayaColors.verifiedLevel1;
    final levelText = contact.verificationLevel == 3 ? 'Verified' : contact.verificationLevel == 2 ? 'Matched' : 'Unverified';
    return Container(
      decoration: BoxDecoration(color: ChhayaColors.cardSurface, borderRadius: BorderRadius.circular(ChhayaRadius.lg), border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.10))),
      child: InkWell(
        onTap: () {
          ChhayaHaptics.selection();
          Navigator.of(context).pushNamed(ChhayaRouter.profile, arguments: {'contactId': contact.id});
        },
        borderRadius: BorderRadius.circular(ChhayaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(ChhayaSpacing.space3),
          child: Row(
            children: [
              AvatarWidget(name: contact.displayName, size: 48, statusColor: contact.isOnline ? ChhayaColors.online : null),
              const SizedBox(width: ChhayaSpacing.space3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(contact.displayName, style: ChhayaTypography.headlineMedium.copyWith(fontSize: 14)),
                  const SizedBox(height: ChhayaSpacing.space1),
                  Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: levelColor.withValues(alpha: 0.5), blurRadius: 6)])),
                    const SizedBox(width: ChhayaSpacing.space2),
                    Text(levelText, style: ChhayaTypography.labelSmall.copyWith(color: levelColor, fontWeight: FontWeight.w700, fontSize: 11)),
                    const SizedBox(width: ChhayaSpacing.space2),
                    Text('• ${contact.chhayaId.publicKey.substring(0, 8)}…', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelTertiary, fontSize: 10)),
                  ]),
                ]),
              ),
              ChhayaIconButton(
                icon: Icons.chat_bubble_rounded,
                onPressed: () {
                  ChhayaHaptics.light();
                  final convos = ref.read(conversationsProvider);
                  final existing = convos.where((c) => c.participants.any((p) => p.id == contact.id)).toList();
                  if (existing.isNotEmpty) {
                    Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {'conversationId': existing.first.id, 'contactName': contact.displayName});
                  } else {
                    final convoId = 'convo_${contact.id}';
                    final newConvo = Conversation(id: convoId, participants: [contact], createdAt: DateTime.now());
                    ref.read(localDatabaseProvider).addConversation(newConvo);
                    ref.read(conversationsProvider.notifier).addConversation(newConvo);
                    Navigator.of(context).pushNamed(ChhayaRouter.chat, arguments: {'conversationId': convoId, 'contactName': contact.displayName});
                  }
                },
                size: 40,
                background: ChhayaColors.accent,
                color: ChhayaColors.onAccent,
              ),
              const Icon(Icons.chevron_right_rounded, size: 16, color: ChhayaColors.labelQuaternary),
            ],
          ),
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
        backgroundColor: ChhayaColors.cardSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
        title: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: ChhayaColors.accent, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.person_add_rounded, size: 18, color: ChhayaColors.onAccent)), const SizedBox(width: 10), Text('Add Contact', style: ChhayaTypography.displaySmall.copyWith(fontSize: 18))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ChhayaInput(controller: nameCtrl, hint: 'Display Name', prefixIcon: Icons.person_outline_rounded, textCapitalization: TextCapitalization.words, autofocus: true),
          const SizedBox(height: ChhayaSpacing.space3),
          ChhayaInput(controller: keyCtrl, hint: 'Chhaya ID (66 chars, optional)', prefixIcon: Icons.fingerprint_rounded, maxLength: 66, style: ChhayaTypography.code.copyWith(color: ChhayaColors.labelPrimary, fontSize: 11)),
          const SizedBox(height: ChhayaSpacing.space2),
          Text('Leave empty to generate a demo ID', style: ChhayaTypography.labelSmall.copyWith(color: ChhayaColors.labelQuaternary)),
        ]),
        actions: [TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)), ChhayaPrimaryButton(label: 'Add', onPressed: () async {
          final name = nameCtrl.text.trim();
          if (name.isEmpty) return;
          var pk = keyCtrl.text.trim().toLowerCase();
          if (pk.isEmpty || pk.length != 66) pk = List.generate(66, (_) => '0123456789abcdef'[DateTime.now().microsecond % 16]).join();
          final contactId = 'contact_${const Uuid().v4().substring(0, 8)}';
          final newContact = Contact(id: contactId, chhayaId: ChhayaId.fromPublicKey(pk), displayName: name, verificationLevel: 1, isOnline: true);
          final db = ref.read(localDatabaseProvider);
          await db.addContact(newContact);
          ref.read(contactsProvider.notifier).addContact(newContact);
          final convoId = 'convo_$contactId';
          final newConvo = Conversation(id: convoId, participants: [newContact], createdAt: DateTime.now());
          await db.addConversation(newConvo);
          ref.read(conversationsProvider.notifier).addConversation(newConvo);
          if (ctx.mounted) Navigator.pop(ctx);
          ChhayaHaptics.success();
        })],
      ),
    );
  }
}