import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:chaaya/features/auth/data/decoy_service.dart';

void main() {
  group('DecoyService', () {
    late DecoyService service;

    setUp(() async {
      Hive.init('test_decoy');
      service = DecoyService();
      await service.initialize();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
    });

    test('sets and verifies decoy password', () async {
      await service.setDecoyPassword('decoy123');
      final isDecoy = service.isDecoyPassword('decoy123');
      expect(isDecoy, true);
    });

    test('sets and verifies real password', () async {
      await service.setRealPassword('real456');
      final isReal = service.isRealPassword('real456');
      expect(isReal, true);
    });

    test('authenticate returns correct result', () async {
      await service.setDecoyPassword('decoy123');
      await service.setRealPassword('real456');

      expect(await service.authenticate('decoy123'), AuthResult.decoy);
      expect(await service.authenticate('real456'), AuthResult.real);
      expect(await service.authenticate('wrong'), AuthResult.failed);
    });
  });
}
