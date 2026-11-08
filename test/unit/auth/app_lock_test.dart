import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/ui/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class UnsetPinDatabase extends LocalDatabase {
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

class PinDatabase extends LocalDatabase {
  PinDatabase({this.appPin = '1234', this.panicPin = '9999'});
  final String? appPin;
  final String? panicPin;
  @override
  bool getBiometricLockEnabled() => true;
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  String? getAppPin() => appPin;
  @override
  String? getPanicPin() => panicPin;
}

class ThrowingLockDatabase extends LocalDatabase {
  @override
  bool getBiometricLockEnabled() => true;
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  String? getAppPin() => throw StateError('lock store unavailable');
  @override
  String? getPanicPin() => throw StateError('lock store unavailable');
}

void main() {
  testWidgets('failed device authentication and an unset PIN never unlock', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: [
      localDatabaseProvider.overrideWithValue(UnsetPinDatabase()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppStartupGate()),
    ));
    await tester.pump();
    await tester.pump();
    // No app PIN is configured, so the 4-digit keypad must not render; only
    // the bounded device-authentication action is offered.
    expect(find.text('Use Device Authentication'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(container.read(appUnlockedProvider), isFalse);
    await tester.ensureVisible(find.text('Use Device Authentication'));
    await tester.tap(find.text('Use Device Authentication'));
    await tester.pump();
    expect(container.read(appUnlockedProvider), isFalse);
    expect(find.byType(AppStartupGate), findsOneWidget);
  });

  testWidgets('wrong PIN then correct PIN unlocks through the app PIN', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: [
      localDatabaseProvider.overrideWithValue(PinDatabase()),
    ]);
    addTearDown(container.dispose);
    var unlockedCount = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppStartupGate(onUnlocked: () => unlockedCount++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlock Chhaya'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    for (final digit in '0000'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 3));
    expect(container.read(appUnlockedProvider), isFalse);
    expect(unlockedCount, 0);

    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(container.read(appUnlockedProvider), isTrue);
    expect(unlockedCount, 1);
  });

  testWidgets('unlock fails closed when the local lock store throws', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: [
      localDatabaseProvider.overrideWithValue(ThrowingLockDatabase()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppStartupGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AppStartupGate), findsOneWidget);
    expect(container.read(appUnlockedProvider), isFalse);
    await tester.ensureVisible(find.text('Use Device Authentication'));
    await tester.tap(find.text('Use Device Authentication'));
    await tester.pump();
    await tester.pump();
    expect(container.read(appUnlockedProvider), isFalse);
    expect(find.byType(AppStartupGate), findsOneWidget);
  });
}
