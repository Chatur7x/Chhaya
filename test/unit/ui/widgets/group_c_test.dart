import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/ui/widgets/chhaya_app_bar.dart';
import 'package:chaaya/ui/widgets/chhaya_bottom_nav.dart';
import 'package:chaaya/ui/widgets/chhaya_input.dart';

const _navItems = [
  ChhayaNavItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  ChhayaNavItem(
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    label: 'Chats',
  ),
  ChhayaNavItem(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  ),
];

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('ChhayaInput pumps hint and accepts text entry', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(ChhayaInput(controller: controller, hint: 'Display name')),
    );

    expect(find.text('Display name'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Aarav');
    await tester.pump();
    expect(controller.text, 'Aarav');
  });

  testWidgets('ChhayaBottomNav tap fires with index', (tester) async {
    var tapped = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChhayaBottomNav(
            currentIndex: 0,
            onTap: (index) => tapped = index,
            items: _navItems,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Chats'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('ChhayaAppBar shows title and subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: ChhayaAppBar(title: 'Chhaya', subtitle: 'Online'),
        ),
      ),
    );

    expect(find.text('Chhaya'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('ChhayaBottomNav tappables are at least 44x44', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChhayaBottomNav(
            currentIndex: 0,
            onTap: (_) {},
            items: _navItems,
          ),
        ),
      ),
    );

    for (var i = 0; i < _navItems.length; i++) {
      final size = tester.getSize(find.byKey(ValueKey('chhaya-nav-item-$i')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });
}
