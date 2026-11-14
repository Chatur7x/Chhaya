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

class CorruptPrivacyDatabase extends LocalDatabase {
  @override
  bool getReadReceiptsEnabled() =>
      throw const FormatException('corrupt read_receipts setting');

  @override
  bool getTypingIndicatorsEnabled() =>
      throw const FormatException('corrupt typing_indicators setting');

  @override
  int getGlobalDisappearingDuration() =>
      throw const FormatException('corrupt global_disappearing_duration setting');
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

  testWidgets(
    'settings screen falls back to fresh-install defaults when privacy settings are corrupt',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(CorruptPrivacyDatabase()),
        ],
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
      for (final entry in const [
        ('Disappearing Messages', false),
        ('Read Receipts', true),
        ('Typing Indicators', true),
      ]) {
        await tester.scrollUntilVisible(
          find.text(entry.$1),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, entry.$1),
              )
              .value,
          entry.$2,
        );
      }
    },
  );
}
