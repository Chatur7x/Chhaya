import 'package:flutter/material.dart';
import 'ui/theme/appearance_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/chhaya_router.dart';
import 'ui/theme/chhaya_theme.dart';
import 'core/providers/app_providers.dart';
import 'core/log.dart';
import 'services/messaging/voice_temporary_files.dart';
import 'ui/widgets/app_lock_gate.dart';
import 'ui/widgets/app_lifecycle_guard.dart';

/// Identifies which local startup stage failed without exposing exception
/// messages that could contain paths or other device-specific details.
class AppInitializationFailure implements Exception {
  AppInitializationFailure({required this.stage, required Object cause})
      : causeType = cause.runtimeType.toString(),
        safeSummary = _safeInitializationError(cause);

  final String stage;
  final String causeType;
  final String safeSummary;

  @override
  String toString() => 'AppInitializationFailure($stage, $causeType)';
}

/// Produces useful diagnostics without displaying SQL statements, database
/// paths, passwords, message contents, or other potentially sensitive values.
String _safeInitializationError(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('no implementation found') ||
      lower.contains('notimplementederror')) {
    return 'A required secure storage plugin is unavailable. Restart the app; '
        'your local account data has been left untouched.';
  }
  if (lower.contains('not a database') ||
      lower.contains('file is encrypted') ||
      lower.contains('wrong key')) {
    return 'The encrypted local database could not be unlocked. Your account '
        'data was left untouched.';
  }
  if (lower.contains('unable to open database') ||
      lower.contains('cantopen') ||
      lower.contains('cannot open')) {
    return 'The app could not open the local database. Check free storage '
        'space and try again.';
  }
  if (lower.contains('no such table') || lower.contains('no such column') ||
      lower.contains('syntax error') || lower.contains('migration')) {
    return 'The local database schema could not be initialized. The error '
        'has been recorded for diagnosis.';
  }
  if (error is StateError || error is ArgumentError) {
    return 'A required local account setting could not be loaded. Try again.';
  }
  return 'The app could not initialize local storage. The error has been '
      'recorded for diagnosis.';
}

/// Notifications are useful after account setup, but must never prevent the
/// user from opening local chats or onboarding when Android notification setup
/// is unavailable or denied.
Future<void> initializeNotificationsBestEffort(
  Future<void> Function() initialize,
) async {
  try {
    await initialize();
  } catch (error) {
    ChhayaLog.w(
      'Notification setup failed; continuing app startup',
      name: 'Startup',
      error: error,
    );
  }
}

final appInitializationProvider = FutureProvider<bool>((ref) async {
  var stage = 'secure device storage';
  try {
    final authService = ref.read(authServiceProvider);
    final db = ref.read(localDatabaseProvider);
    final apiService = ref.read(apiServiceProvider);

    // Part 2: wipe in-memory session keys when the app backgrounds.
    ref.read(keyManagerProvider).startObserving();

    stage = 'server settings';
    await apiService.init();
    stage = 'encrypted local database';
    await authService.init();

    final currentUser = authService.currentUser;
    ref.read(currentUserProvider.notifier).state = currentUser;

    if (currentUser != null) {
      stage = 'saved conversations';
      final convos = await db.getAllConversations();
      final contacts = await db.getAllContacts();
      ref.read(conversationsProvider.notifier).setConversations(convos);
      ref.read(contactsProvider.notifier).setContacts(contacts);
    }

    // Notification setup is optional and cannot gate account access. Keep
    // existing permission/registration behavior while degrading gracefully.
    await initializeNotificationsBestEffort(
      () => ref.read(notificationServiceProvider).init(),
    );

    return currentUser != null;
  } catch (error, stackTrace) {
    ChhayaLog.e(
      'App startup failed during $stage',
      name: 'Startup',
      error: error,
      stackTrace: stackTrace,
    );
    throw AppInitializationFailure(stage: stage, cause: error);
  }
});


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await VoiceTemporaryFiles.cleanup();
  } catch (_) {
    // An unavailable temporary directory must not prevent access to the app.
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: ChhayaColors.primaryBackground,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: ChhayaColors.primaryBackground,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'],await rootBundle.loadString('assets/fonts/OFL-Inter.txt'));
    yield LicenseEntryWithLineBreaks(['Departure Mono'],await rootBundle.loadString('assets/fonts/OFL-DepartureMono.txt'));
    yield LicenseEntryWithLineBreaks(['Roboto Mono'],await rootBundle.loadString('assets/fonts/OFL-RobotoMono.txt'));
  });
  runApp(const ProviderScope(child: ChhayaApp()));
}

class ChhayaApp extends ConsumerStatefulWidget {
  const ChhayaApp({super.key});

  @override
  ConsumerState<ChhayaApp> createState() => _ChhayaAppState();
}

class _ChhayaAppState extends ConsumerState<ChhayaApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(appInitializationProvider);

    return MaterialApp(
      title: 'Chhaya',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ChhayaTheme.materialLight,
      darkTheme: ChhayaTheme.materialDark,
      themeMode: ref.watch(appearanceProvider),
      themeAnimationDuration: ChhayaMotion.duration(context, 300),
      themeAnimationCurve: Curves.easeInOutCubic,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Theme.of(context).colorScheme.surface,
          statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: Theme.of(context).brightness,
          systemNavigationBarColor: Theme.of(context).colorScheme.surface,
          systemNavigationBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark),
        child: AppLifecycleGuard(navigatorKey: _navigatorKey,
          child: HeroMode(enabled: !ChhayaMotion.reduced(context), child: child!))),
      home: initAsync.when(
        data: (isLoggedIn) {
          if (isLoggedIn) {
            return const AppStartupGate();
          } else {
            return const _RouteLoader(route: ChhayaRouter.onboarding);
          }
        },
        loading: () => const ChhayaSplashScreen(),
        error: (e, stack) => ChhayaSplashScreen(
          errorMessage: 'Could not open your account. Try again.',
          errorDetails: e is AppInitializationFailure
              ? 'Setup step: ${e.stage} (${e.causeType})\n${e.safeSummary}'
              : null,
          onRetry: () => ref.invalidate(appInitializationProvider),
        ),
      ),
      onGenerateRoute: ChhayaRouter.generateRoute,
    );
  }
}

class _RouteLoader extends StatefulWidget {
  final String route;
  const _RouteLoader({required this.route});

  @override
  State<_RouteLoader> createState() => _RouteLoaderState();
}

class _RouteLoaderState extends State<_RouteLoader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed(widget.route);
    });
  }

  @override
  Widget build(BuildContext context) => const ChhayaSplashScreen();
}

