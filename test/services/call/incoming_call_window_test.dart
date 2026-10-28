import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/services/call/incoming_call_window.dart';

void main() {
  group('IncomingCallWindow', () {
    test('suppresses the same offer during its ring window', () {
      final window = IncomingCallWindow();
      final now = DateTime.utc(2026, 1, 1);

      expect(window.shouldPresent('call-1', now), isTrue);
      expect(
        window.shouldPresent('call-1', now.add(const Duration(seconds: 1))),
        isFalse,
      );
      expect(window.shouldPresent('call-2', now), isTrue);
    });

    test('allows an offer again after its ring window expires', () {
      final window = IncomingCallWindow(ttl: const Duration(seconds: 60));
      final now = DateTime.utc(2026, 1, 1);

      expect(window.shouldPresent('call-1', now), isTrue);
      expect(
        window.shouldPresent('call-1', now.add(const Duration(seconds: 60))),
        isTrue,
      );
    });

    test('bounds retained offer IDs and evicts the earliest expiry', () {
      final window = IncomingCallWindow(
        ttl: const Duration(seconds: 60),
        maxEntries: 2,
      );
      final now = DateTime.utc(2026, 1, 1);

      expect(window.shouldPresent('call-1', now), isTrue);
      expect(
        window.shouldPresent('call-2', now.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        window.shouldPresent('call-3', now.add(const Duration(seconds: 2))),
        isTrue,
      );
      expect(
        window.shouldPresent('call-1', now.add(const Duration(seconds: 3))),
        isTrue,
      );
      expect(
        window.shouldPresent('call-3', now.add(const Duration(seconds: 3))),
        isFalse,
      );
    });
  });
}
