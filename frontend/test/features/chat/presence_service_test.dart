import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:catus_chat/features/chat/data/presence_service.dart';

void main() {
  group('PresenceService', () {
    late PresenceService service;

    setUp(() async {
      Hive.init('test_presence');
      service = PresenceService();
      await service.initialize();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      service.dispose();
    });

    test('sends typing indicator', () {
      service.sendTyping('recipient1');
      expect(service.typingIndicatorsEnabled, true);
    });

    test('disables read receipts when setting is off', () {
      service.setReadReceiptsEnabled(false);
      expect(service.readReceiptsEnabled, false);
    });

    test('checks online status', () {
      final isOnline = service.isUserOnline('user1');
      expect(isOnline, false);
    });
  });
}
