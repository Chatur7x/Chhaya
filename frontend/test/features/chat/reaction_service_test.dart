import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:catus_chat/features/chat/data/reaction_service.dart';
import 'package:catus_chat/features/chat/domain/models/message_metadata.dart';

void main() {
  group('ReactionService', () {
    late ReactionService service;

    setUp(() async {
      Hive.init('test_reaction');
      Hive.registerAdapter(MessageMetadataAdapter());
      Hive.registerAdapter(MessageReactionAdapter());
      service = ReactionService();
      await service.initialize();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
    });

    test('adds reaction to message', () async {
      await service.addReaction('msg1', '👍', 'user1');
      final metadata = service.getMetadata('msg1');
      expect(metadata?.reactions.length, 1);
      expect(metadata?.reactions.first.emoji, '👍');
    });

    test('removes existing reaction from user', () async {
      await service.addReaction('msg1', '👍', 'user1');
      await service.removeReaction('msg1', 'user1');
      final metadata = service.getMetadata('msg1');
      expect(
          metadata?.reactions.where((r) => r.userId == 'user1').isEmpty, true);
    });

    test('user can only have one reaction per message', () async {
      await service.addReaction('msg1', '👍', 'user1');
      await service.addReaction('msg1', '❤️', 'user1');
      final metadata = service.getMetadata('msg1');
      expect(metadata?.reactions.length, 1);
      expect(metadata?.reactions.first.emoji, '❤️');
    });
  });
}
