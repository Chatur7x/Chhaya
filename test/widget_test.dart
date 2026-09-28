import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chaaya/main.dart';

void main() {
  testWidgets('Onboarding screen smoke test', (WidgetTester tester) async {

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appInitializationProvider.overrideWith((ref) => false),
        ],
        child: const ChhayaApp(),
      ),
    );


    // NOTE: pumpAndSettle() can never complete here — the onboarding
    // screen has a terminal block cursor that blinks forever via
    // AnimationController.repeat() (correct behavior on-device; it
    // already goes static under reduced motion). Pump explicit frames
    // instead: long enough for the 800ms hero entrance to finish.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // Welcome page assertions (match current onboarding copy).
    expect(find.text('CHHAYA'), findsOneWidget);
    expect(
      find.text('Privacy Redefined. Speed Perfected.'),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsOneWidget);
  });
}
