import 'package:chaaya/ui/widgets/chhaya_button.dart';
import 'package:chaaya/ui/widgets/chhaya_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Group A widgets', () {
    testWidgets('primary button shows label and fires on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChhayaPrimaryButton(
              label: 'Continue',
              expanded: false,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.byType(ChhayaPrimaryButton));
      await tester.pump();
      expect(tapped, isTrue);

      final size = tester.getSize(find.byType(ChhayaPrimaryButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('secondary button pumps with label', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChhayaSecondaryButton(
              label: 'Cancel',
              expanded: false,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.byType(ChhayaSecondaryButton));
      await tester.pump();
      expect(tapped, isTrue);

      final size = tester.getSize(find.byType(ChhayaSecondaryButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('pill button shows icon and label, fires on tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChhayaPillButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      await tester.tap(find.byType(ChhayaPillButton));
      await tester.pump();
      expect(tapped, isTrue);

      final size = tester.getSize(find.byType(ChhayaPillButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('card pumps child and fires on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChhayaCard(
              onTap: () => tapped = true,
              child: const SizedBox(
                width: 120,
                height: 60,
                child: Text('Card body'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Card body'), findsOneWidget);
      await tester.tap(find.byType(ChhayaCard));
      await tester.pump();
      expect(tapped, isTrue);

      final size = tester.getSize(find.byType(ChhayaCard));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('section card shows title row and child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChhayaSectionCard(
              title: 'Details',
              child: Text('Section body'),
            ),
          ),
        ),
      );

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Section body'), findsOneWidget);

      final size = tester.getSize(find.byType(ChhayaSectionCard));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
