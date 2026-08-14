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


    await tester.pumpAndSettle();


    expect(find.text('Welcome to Chhaya'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
