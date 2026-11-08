import 'dart:async';
import 'package:chaaya/core/database/local_database.dart';
import 'package:chaaya/core/models/chhaya_id.dart';
import 'package:chaaya/core/models/user_profile.dart';
import 'package:chaaya/core/models/conversation.dart';
import 'package:chaaya/core/providers/app_providers.dart';
import 'package:chaaya/core/router/chhaya_router.dart';
import 'package:chaaya/core/crypto/key_manager.dart';
import 'package:chaaya/core/crypto/storage/secure_storage_mock.dart';
import 'package:chaaya/services/api/api_service.dart';
import 'package:chaaya/services/auth/auth_service.dart';
import 'package:chaaya/services/call/call_service.dart';
import 'package:chaaya/services/messaging/messaging_service.dart';
import 'package:chaaya/ui/screens/chat/chat_screen.dart';
import 'package:chaaya/ui/screens/home/home_shell.dart';
import 'package:chaaya/ui/widgets/app_lifecycle_guard.dart';
import 'package:chaaya/ui/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class LockDatabase extends LocalDatabase {
  LockDatabase({this.enabled = true, this.authentication});
  final bool enabled;
  final Completer<bool>? authentication;
  @override
  bool getBiometricLockEnabled() => enabled;
  @override
  Future<bool> isBiometricAvailable() async => authentication != null;
  @override
  Future<bool> authenticateWithBiometrics({String reason = 'Unlock Chhaya'}) =>
      authentication?.future ?? Future.value(false);
  @override
  String? getAppPin() => '1234';
  @override
  String? getPanicPin() => '9999';
}

class ThrowingLockDatabase extends LocalDatabase {
  @override
  bool getBiometricLockEnabled() =>
      throw const FormatException('corrupt biometric_lock setting');
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> authenticateWithBiometrics({String reason = 'Unlock Chhaya'}) =>
      Future.value(false);
  @override
  String? getAppPin() => '1234';
}

class FakeLogout extends AuthService {
  int calls = 0;
  @override
  Future<void> logout() async {
    calls++;
  }
}

class FakeApiService extends ApiService {
  FakeApiService()
      : super.forTesting(storage: SecureStorageMock(), client: http.Client());

  @override
  bool get isAuthenticated => true;
}

class CountingMessagingService extends MessagingService {
  CountingMessagingService({
    required super.api,
    required super.database,
    required super.keys,
  });

  int syncCalls = 0;
  int retryCalls = 0;

  @override
  Future<List<Conversation>> sync() async {
    syncCalls++;
    return [];
  }

  @override
  Future<void> retryAllPending() async {
    retryCalls++;
  }
}

class FakeCallService extends CallService {
  FakeCallService()
      : super(
          api: ApiService.forTesting(
            storage: SecureStorageMock(),
            client: http.Client(),
          ),
          database: LocalDatabase(),
          keys: KeyManager(),
        );

  final StreamController<IncomingCall> _fakeIncoming =
      StreamController<IncomingCall>.broadcast();

  @override
  Stream<IncomingCall> get incoming => _fakeIncoming.stream;

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> checkPendingInvites() async {}

  @override
  void dispose() {
    _fakeIncoming.close();
    super.dispose();
  }
}

UserProfile fixtureProfile() => UserProfile(
  chhayaId: ChhayaId.fromPublicKey('05${'11' * 32}'),
  displayName: 'Synthetic',
  recoveryPhrase: const [],
  createdAt: DateTime(2026),
);

void background(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.inactive) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void foreground(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Widget _guardApp({
  required Widget home,
  required GlobalKey<NavigatorState> navigator,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      navigatorKey: navigator,
      builder: (_, child) =>
          AppLifecycleGuard(navigatorKey: navigator, child: child!),
      home: home,
    ),
  );
}

void main() {
  for (final enabled in [false, true]) {
    testWidgets('background cover preserves draft; lock enabled: $enabled', (
      tester,
    ) async {
      foreground(tester);
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(
            LockDatabase(enabled: enabled),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = fixtureProfile();
      container.read(appUnlockedProvider.notifier).state = true;
      final controller = TextEditingController(text: 'preserved draft');
      addTearDown(controller.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (_, child) =>
                AppLifecycleGuard(navigatorKey: navigator, child: child!),
            home: Scaffold(body: TextField(controller: controller)),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('preserved draft'), findsNothing);
      background(tester);
      await tester.pump();
      expect(container.read(appUnlockedProvider), !enabled);
      foreground(tester);
      await tester.pumpAndSettle();
      if (enabled) {
        expect(find.text('Unlock Chhaya'), findsOneWidget);
        expect(find.text('preserved draft'), findsNothing);
        await enterPin(tester, '12');
        background(tester);
        await tester.pump();
        foreground(tester);
        await tester.pumpAndSettle();
        await enterPin(tester, '34');
        expect(
          container.read(appUnlockedProvider),
          isFalse,
          reason: 'A partial PIN must not survive backgrounding',
        );
        await tester.tap(find.byTooltip('Delete passcode digit'));
        await tester.pump();
        await tester.tap(find.byTooltip('Delete passcode digit'));
        await tester.pump();
        await enterPin(tester, '1234');
      } else {
        expect(find.text('Unlock Chhaya'), findsNothing);
      }
      expect(container.read(appUnlockedProvider), isTrue);
      expect(find.text('preserved draft'), findsOneWidget);
      expect(controller.text, 'preserved draft');
    });
  }

  test('appLockedProvider fails closed when the lock getter throws', () {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(ThrowingLockDatabase()),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = false;
    expect(container.read(appLockedProvider), isTrue);
  });

  testWidgets('backgrounding with an unreadable lock store still arms the cover', (
    tester,
  ) async {
    foreground(tester);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(ThrowingLockDatabase()),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = true;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) =>
              AppLifecycleGuard(navigatorKey: navigator, child: child!),
          home: const Scaffold(body: Text('Protected fixture')),
        ),
      ),
    );
    background(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Protected fixture'), findsNothing);
    expect(container.read(appUnlockedProvider), isFalse);
    expect(container.read(appLockedProvider), isTrue);
  });

  testWidgets('startup without a lock unlocks after the first frame', (
    tester,
  ) async {
    foreground(tester);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: false)),
      ],
    );
    addTearDown(container.dispose);
    var unlocked = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppStartupGate(onUnlocked: () => unlocked = true),
        ),
      ),
    );
    await tester.pump();
    expect(unlocked, isTrue);
    expect(container.read(appUnlockedProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native authentication inactivity alone does not reject success',
    (tester) async {
      foreground(tester);
      final pending = Completer<bool>();
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(
            LockDatabase(authentication: pending),
          ),
        ],
      );
      addTearDown(container.dispose);
      var unlocked = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStartupGate(onUnlocked: () => unlocked = true),
          ),
        ),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      pending.complete(true);
      await tester.pump();
      foreground(tester);
      await tester.pump();
      expect(unlocked, isTrue);
      expect(container.read(appUnlockedProvider), isTrue);
    },
  );

  for (final afterResume in [false, true]) {
    testWidgets(
      'stale biometric result cannot unlock after background: $afterResume',
      (tester) async {
        foreground(tester);
        final pending = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            localDatabaseProvider.overrideWithValue(
              LockDatabase(authentication: pending),
            ),
          ],
        );
        addTearDown(container.dispose);
        var unlocked = false;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: AppStartupGate(onUnlocked: () => unlocked = true),
            ),
          ),
        );
        await tester.pump();
        background(tester);
        await tester.pump();
        if (afterResume) foreground(tester);
        pending.complete(true);
        await tester.pump();
        if (!afterResume) foreground(tester);
        await tester.pumpAndSettle();
        expect(unlocked, isFalse);
        expect(container.read(appUnlockedProvider), isFalse);
        expect(find.text('Unlock Chhaya'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'panic callback clears the protected route stack using a fake account',
    (tester) async {
      foreground(tester);
      final auth = FakeLogout();
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(LockDatabase()),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = fixtureProfile();
      container.read(appUnlockedProvider.notifier).state = true;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigator,
            routes: {
              ChhayaRouter.onboarding: (_) =>
                  const Scaffold(body: Text('Signed out fixture')),
            },
            builder: (_, child) =>
                AppLifecycleGuard(navigatorKey: navigator, child: child!),
            home: const Scaffold(body: Text('Protected fixture')),
          ),
        ),
      );
      background(tester);
      await tester.pump();
      foreground(tester);
      await tester.pumpAndSettle();
      await enterPin(tester, '9999');
      expect(auth.calls, 1);
      expect(container.read(currentUserProvider), isNull);
      expect(find.text('Signed out fixture'), findsOneWidget);
      expect(find.text('Protected fixture', skipOffstage: false), findsNothing);
    },
  );

  testWidgets('no signed-in user never requires unlock', (tester) async {
    foreground(tester);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: true)),
      ],
    );
    addTearDown(container.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _guardApp(
        home: const Scaffold(body: Text('Onboarding content')),
        navigator: navigator,
        container: container,
      ),
    );
    background(tester);
    await tester.pump();
    foreground(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AppStartupGate), findsNothing);
    expect(find.text('Onboarding content'), findsOneWidget);
    expect(container.read(appUnlockedProvider), isFalse);
  });

  testWidgets('system back does not pop a hidden raw route while locked', (
    tester,
  ) async {
    foreground(tester);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: true)),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = false;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _guardApp(
        home: const Scaffold(body: Text('Root content')),
        navigator: navigator,
        container: container,
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Hidden fixture')),
      ),
    );
    await tester.pumpAndSettle();
    background(tester);
    await tester.pump();
    foreground(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unlock Chhaya'), findsOneWidget);
    tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Hidden fixture', skipOffstage: false), findsOneWidget);
    expect(find.text('Unlock Chhaya'), findsOneWidget);
    expect(container.read(appUnlockedProvider), isFalse);
  });

  testWidgets('first frame while backgrounded is covered', (tester) async {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: true)),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = false;
    expect(container.read(appLockedProvider), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _guardApp(
        home: const Scaffold(body: Text('Root content')),
        navigator: navigator,
        container: container,
      ),
    );
    await tester.pump();
    expect(find.text('Root content'), findsNothing);
    foreground(tester);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppStartupGate), findsOneWidget);
  });

  testWidgets('inactive without pause does not lock', (tester) async {
    foreground(tester);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: true)),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = true;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _guardApp(
        home: const Scaffold(body: Text('Root content')),
        navigator: navigator,
        container: container,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Root content'), findsNothing);
    expect(container.read(appUnlockedProvider), isTrue);
    expect(find.byType(AppStartupGate), findsNothing);
    foreground(tester);
    await tester.pumpAndSettle();
    expect(find.text('Root content'), findsOneWidget);
    expect(find.byType(AppStartupGate), findsNothing);
  });

  testWidgets('back on the gate does not dismiss it', (tester) async {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(
          LockDatabase(enabled: true, authentication: null),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(appUnlockedProvider.notifier).state = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppStartupGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppStartupGate), findsOneWidget);
    expect(find.text('Unlock Chhaya'), findsOneWidget);
    tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AppStartupGate), findsOneWidget);
    expect(container.read(appUnlockedProvider), isFalse);
  });

  testWidgets('router PopScope blocks back only while locked', (tester) async {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: true)),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = false;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          onGenerateRoute: ChhayaRouter.generateRoute,
          home: const Scaffold(body: Text('Root content')),
        ),
      ),
    );
    navigator.currentState!.push(
      ChhayaRouter.generateRoute(
        const RouteSettings(
          name: ChhayaRouter.chat,
          arguments: {'conversationId': 'design-chat', 'contactName': 'Maya'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    // Back must stay blocked while the lock gate is shown.
    tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);
    container.read(appUnlockedProvider.notifier).state = true;
    await tester.pumpAndSettle();
    tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('sync is suppressed while locked and restarts after unlock', (
    tester,
  ) async {
    final messaging = CountingMessagingService(
      api: ApiService.forTesting(
        storage: SecureStorageMock(),
        client: http.Client(),
      ),
      database: LocalDatabase(),
      keys: KeyManager(),
    );
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase(enabled: true)),
        messagingServiceProvider.overrideWithValue(messaging),
        apiServiceProvider.overrideWithValue(FakeApiService()),
        callServiceProvider.overrideWith(
          (ref) => FakeCallService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
    expect(messaging.syncCalls, 0);
    expect(messaging.retryCalls, 0);
    container.read(appUnlockedProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(messaging.syncCalls, greaterThanOrEqualTo(1));
    expect(messaging.retryCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('logout resets the lock and returns to onboarding', (tester) async {
    final auth = FakeLogout();
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(LockDatabase()),
        authServiceProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = fixtureProfile();
    container.read(appUnlockedProvider.notifier).state = true;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          routes: {
            ChhayaRouter.onboarding: (_) =>
                const Scaffold(body: Text('Signed out fixture')),
          },
          builder: (_, child) =>
              AppLifecycleGuard(navigatorKey: navigator, child: child!),
          home: const Scaffold(body: Text('Protected fixture')),
        ),
      ),
    );
    background(tester);
    await tester.pump();
    foreground(tester);
    await tester.pumpAndSettle();
    await enterPin(tester, '9999');
    expect(auth.calls, 1);
    expect(container.read(currentUserProvider), isNull);
    expect(container.read(appUnlockedProvider), isFalse);
    expect(find.text('Signed out fixture'), findsOneWidget);
  });
}
