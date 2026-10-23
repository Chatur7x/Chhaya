import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/contact.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/models/message.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'polling does not publish unchanged contact or conversation snapshots',
    () {
      final peer = Contact(
        id: 'peer-1',
        chhayaId: ChhayaId.fromPublicKey('peer-public-key'),
        displayName: 'Sam',
        isVerified: true,
      );
      final sentAt = DateTime.utc(2026, 1, 1);
      final conversation = Conversation(
        id: 'conversation-1',
        participants: [peer],
        lastMessage: Message(
          id: 'message-1',
          conversationId: 'conversation-1',
          senderId: 'peer-1',
          content: 'Hello',
          timestamp: sentAt,
        ),
        createdAt: sentAt,
      );

      final contacts = ContactsNotifier();
      final conversations = ConversationsNotifier();
      addTearDown(contacts.dispose);
      addTearDown(conversations.dispose);
      var contactNotifications = 0;
      var conversationNotifications = 0;
      contacts.addListener(
        (_) => contactNotifications++,
        fireImmediately: false,
      );
      conversations.addListener(
        (_) => conversationNotifications++,
        fireImmediately: false,
      );

      contacts.setContacts([peer]);
      conversations.setConversations([conversation]);
      final contactSnapshot = contacts.state;
      final conversationSnapshot = conversations.state;

      // Sync decodes new objects on every response; equal visible data should
      // retain the original list reference and avoid another UI rebuild.
      contacts.setContacts([peer.copyWith()]);
      conversations.setConversations([
        conversation.copyWith(participants: [peer.copyWith()]),
      ]);
      expect(identical(contacts.state, contactSnapshot), isTrue);
      expect(identical(conversations.state, conversationSnapshot), isTrue);
      expect(contactNotifications, 1);
      expect(conversationNotifications, 1);

      conversations.setConversations([
        conversation.copyWith(
          lastMessage: conversation.lastMessage!.copyWith(content: 'Updated'),
        ),
      ]);
      expect(conversationNotifications, 2);
      expect(conversations.state.single.lastMessage!.content, 'Updated');
    },
  );
}
