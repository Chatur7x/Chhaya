import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class LockedDatabase extends LocalDatabase {
  @override
  bool getBiometricLockEnabled() => true;
  @override
  Future<bool> isBiometricAvailable() async => true;
  @override
  Future<bool> authenticateWithBiometrics({String reason = 'Unlock Chhaya'}) async => false;
  @override
  String? getAppPin() => null;
  @override
  String? getPanicPin() => null;
}

void main() {
  testWidgets('failed device authentication and an unset PIN never unlock', (tester) async {
    final container = ProviderContainer(overrides: [
      localDatabaseProvider.overrideWithValue(LockedDatabase()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppStartupGate()),
    ));
    await tester.pump();
    await tester.pump();
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 3));
    expect(container.read(appUnlockedProvider), isFalse);
    expect(find.byType(AppStartupGate), findsOneWidget);
    expect(find.text('Use Device Authentication'), findsOneWidget);
    await tester.ensureVisible(find.text('Use Device Authentication'));
    await tester.tap(find.text('Use Device Authentication'));
    await tester.pump();
    expect(container.read(appUnlockedProvider), isFalse);
  });
}
