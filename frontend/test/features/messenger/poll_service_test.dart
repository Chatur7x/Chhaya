import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:chaaya/features/messenger/data/poll_service.dart';
import 'package:chaaya/features/messenger/domain/models/poll.dart';

void main() {
  group('PollService', () {
    late PollService service;

    setUp(() async {
      Hive.init('test_poll');
      Hive.registerAdapter(PollAdapter());
      Hive.registerAdapter(PollOptionAdapter());
      service = PollService();
      await service.initialize();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
    });

    test('creates poll with options', () async {
      final poll = await service.createPoll(
        question: 'Best color?',
        optionTexts: ['Red', 'Blue', 'Green'],
        creatorId: 'user1',
      );
      expect(poll.options.length, 3);
      expect(poll.totalVotes, 0);
    });

    test('allows voting on poll', () async {
      final poll = await service.createPoll(
        question: 'Best food?',
        optionTexts: ['Pizza', 'Burger'],
        creatorId: 'user1',
      );
      await service.vote(poll.id, poll.options.first.id, 'user2');
      final updatedPoll = service.getPoll(poll.id);
      expect(updatedPoll?.totalVotes, 1);
    });

    test('calculates percentage correctly', () async {
      final poll = await service.createPoll(
        question: 'Vote',
        optionTexts: ['A', 'B'],
        creatorId: 'user1',
      );
      await service.vote(poll.id, poll.options[0].id, 'user2');
      await service.vote(poll.id, poll.options[0].id, 'user3');
      await service.vote(poll.id, poll.options[1].id, 'user4');

      final updatedPoll = service.getPoll(poll.id);
      expect(updatedPoll?.totalVotes, 3);
    });
  });
}
