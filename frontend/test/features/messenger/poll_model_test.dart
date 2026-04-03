import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/features/messenger/domain/models/poll.dart';

void main() {
  group('Poll', () {
    test('creates poll correctly', () {
      final poll = Poll(
        id: 'test-id',
        question: 'Test question?',
        options: [PollOption(id: 'opt1', text: 'Yes')],
        creatorId: 'user1',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      expect(poll.totalVotes, 0);
      expect(poll.isExpired, false);
    });

    test('detects expiration', () {
      final poll = Poll(
        id: 'test-id',
        question: 'Expired?',
        options: [],
        creatorId: 'user1',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(poll.isExpired, true);
    });
  });
}
