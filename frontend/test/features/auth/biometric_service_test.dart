import 'package:flutter_test/flutter_test.dart';
import 'package:catus_chat/features/auth/data/biometric_service.dart';

void main() {
  group('BiometricService', () {
    late BiometricService service;

    setUp(() {
      service = BiometricService();
    });

    test('isBiometricAvailable returns bool', () async {
      final available = await service.isBiometricAvailable();
      expect(available, isA<bool>());
    });

    test('stores biometric enabled state', () async {
      await service.setBiometricEnabled(true);
      final enabled = await service.isBiometricEnabled();
      expect(enabled, true);
    });

    test('enrollment tracking', () async {
      await service.enrollBiometric();
      final enrolled = await service.isEnrolled();
      expect(enrolled, true);
    });
  });
}
