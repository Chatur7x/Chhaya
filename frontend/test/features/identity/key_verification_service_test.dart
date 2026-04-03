import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/features/identity/data/key_verification_service.dart';

void main() {
  group('KeyVerificationService', () {
    late KeyVerificationService service;

    setUp(() {
      service = KeyVerificationService();
    });

    test('generates consistent safety number regardless of key order', () {
      final num1 = service.generateSafetyNumber('key1', 'key2');
      final num2 = service.generateSafetyNumber('key2', 'key1');
      expect(num1.replaceAll(' ', ''), num2.replaceAll(' ', ''));
    });

    test('generates 60-digit safety number', () {
      final safetyNum = service.generateSafetyNumber('key1', 'key2');
      final digitsOnly = safetyNum.replaceAll(' ', '');
      expect(digitsOnly.length, 60);
    });

    test('verifies matching safety numbers', () {
      final safetyNum = service.generateSafetyNumber('key1', 'key2');
      final isMatch = service.verifySafetyNumber(safetyNum, safetyNum);
      expect(isMatch, true);
    });

    test('rejects non-matching safety numbers', () {
      final num1 = service.generateSafetyNumber('key1', 'key2');
      final num2 = service.generateSafetyNumber('key3', 'key4');
      final isMatch = service.verifySafetyNumber(num1, num2);
      expect(isMatch, false);
    });
  });
}
