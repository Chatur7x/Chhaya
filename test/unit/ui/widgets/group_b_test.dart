import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/chhaya_avatar.dart';
import 'package:chaaya/ui/widgets/chhaya_chat_bubble.dart';
import 'package:chaaya/ui/widgets/chhaya_pressable.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

BoxDecoration _bubbleDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(find.byType(Container).first);
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('sent bubble shows message with coral fill', (tester) async {
    await tester.pumpWidget(_wrap(
      const ChhayaChatBubble(message: 'Hello there', isMine: true),
    ));
    expect(find.text('Hello there'), findsOneWidget);
    expect(_bubbleDecoration(tester).color, ChhayaColors.coral);
  });

  testWidgets('received bubble shows message with white fill', (tester) async {
    await tester.pumpWidget(_wrap(
      const ChhayaChatBubble(message: 'Hi back', isMine: false),
    ));
    expect(find.text('Hi back'), findsOneWidget);
    final decoration = _bubbleDecoration(tester);
    expect(decoration.color, ChhayaColors.white);
    expect(decoration.border, isNotNull);
  });

  testWidgets('bubble shows timestamp and verified badge', (tester) async {
    await tester.pumpWidget(_wrap(
      const ChhayaChatBubble(
        message: 'Verified msg',
        isMine: false,
        timestamp: '10:30',
        verified: true,
      ),
    ));
    expect(find.text('10:30'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('avatar shows initial letter', (tester) async {
    await tester.pumpWidget(_wrap(const ChhayaAvatar(name: 'Asha')));
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('avatar shows verified badge when enabled', (tester) async {
    await tester.pumpWidget(_wrap(
      const ChhayaAvatar(name: 'Asha', showVerifiedBadge: true),
    ));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('pressable tap fires callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(
      ChhayaPressable(
        onTap: () => tapped = true,
        child: const Text('Go'),
      ),
    ));
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('pressable meets 44x44 minimum tap target', (tester) async {
    await tester.pumpWidget(_wrap(
      const ChhayaPressable(child: Text('Go')),
    ));
    final size = tester.getSize(find.byType(ChhayaPressable));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
