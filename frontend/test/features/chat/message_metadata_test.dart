import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/features/chat/domain/models/message_metadata.dart';

void main() {
  group('MessageMetadata', () {
    test('creates empty metadata', () {
      final metadata = MessageMetadata();
      expect(metadata.reactions, isEmpty);
      expect(metadata.edited, false);
    });

    test('adds reaction', () {
      final metadata = MessageMetadata();
      metadata.reactions.add(MessageReaction(emoji: '👍', userId: 'user1'));
      expect(metadata.reactions.length, 1);
      expect(metadata.reactions.first.emoji, '👍');
    });

    test('removes reaction', () {
      final metadata = MessageMetadata();
      metadata.reactions.add(MessageReaction(emoji: '👍', userId: 'user1'));
      metadata.reactions.removeWhere((r) => r.userId == 'user1');
      expect(metadata.reactions.isEmpty, true);
    });
  });
}
