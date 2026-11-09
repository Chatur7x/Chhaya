import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/ui/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class CorruptLockDatabase extends LocalDatabase {
  @override
  bool getBiometricLockEnabled() =>
      throw const FormatException('corrupt biometric_lock setting');
}

void main() {
  testWidgets('settings screen fails closed when the lock blob is corrupt', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(CorruptLockDatabase())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Biometric Lock'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Biometric Lock')).value,
      isTrue,
    );
  });
}
