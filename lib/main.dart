import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/chhaya_router.dart';
import 'ui/theme/chhaya_theme.dart';
import 'core/providers/app_providers.dart';

final appInitializationProvider = FutureProvider<bool>((ref) async {
  final authService = ref.read(authServiceProvider);
  final db = ref.read(localDatabaseProvider);
  final apiService = ref.read(apiServiceProvider);

  // Part 2: wipe in-memory session keys when the app backgrounds.
  ref.read(keyManagerProvider).startObserving();

  await apiService.init();
  await authService.init();
  await ref.read(notificationServiceProvider).init();

  final currentUser = authService.currentUser;
  ref.read(currentUserProvider.notifier).state = currentUser;

  if (currentUser != null) {
    final convos = await db.getAllConversations();
    final contacts = await db.getAllContacts();
    ref.read(conversationsProvider.notifier).setConversations(convos);
    ref.read(contactsProvider.notifier).setContacts(contacts);

    // Sync with backend if online
    try {
      final backendConvos = await apiService.getConversations();
      final backendContacts = await apiService.getContacts();
      
      // Merge with local (backend wins for conflicts)
      for (final c in backendConvos) {
        await db.addConversation(c);
      }
      for (final c in backendContacts) {
        await db.addContact(c);
      }
      
      ref.read(conversationsProvider.notifier).setConversations(
        [...backendConvos, ...(convos.where((c) => !backendConvos.any((bc) => bc.id == c.id)))]
      );
      ref.read(contactsProvider.notifier).setContacts(
        [...backendContacts, ...(contacts.where((c) => !backendContacts.any((bc) => bc.id == c.id)))]
      );
    } catch (e) {
      // Offline mode - use local data
      // ignore: avoid_print
      print('Backend sync failed, using local data: $e');
    }
  }

  return currentUser != null;
});

final appUnlockedProvider = StateProvider<bool>((ref) => false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: ChhayaColors.primaryBackground,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: ChhayaColors.primaryBackground,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: ChhayaApp()));
}

class ChhayaApp extends ConsumerWidget {
  const ChhayaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initAsync = ref.watch(appInitializationProvider);

    return MaterialApp(
      title: 'Chhaya',
      debugShowCheckedModeBanner: false,
      theme: ChhayaTheme.materialLight,
      darkTheme: ChhayaTheme.materialDark,
      themeMode: ThemeMode.system,
      home: initAsync.when(
        data: (isLoggedIn) {
          if (isLoggedIn) {
            return const AppStartupGate();
          } else {
            return const _RouteLoader(route: ChhayaRouter.onboarding);
          }
        },
        loading: () => const _SplashScreen(),
        error: (e, stack) => _SplashScreen(errorMessage: 'Error: $e'),
      ),
      onGenerateRoute: ChhayaRouter.generateRoute,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String? errorMessage;
  const _SplashScreen({this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Stack(
        children: [
          Positioned(
            top: -80, left: -60, right: -60, height: 420,
            child: Container(decoration: const BoxDecoration(gradient: ChhayaColors.glowGradient)),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ChhayaRadius.xl),
                    color: ChhayaColors.cardSurface,
                    border: Border.all(
                      color: ChhayaColors.accent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 48, color: ChhayaColors.accent),
                ),
                const SizedBox(height: ChhayaSpacing.space5),
                Text(
                  'CHHAYA',
                  style: ChhayaTypography.displayHero.copyWith(
                    color: ChhayaColors.accent,
                    fontFamily: 'JetBrains Mono',
                    fontSize: 40,
                    letterSpacing: 6.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'PRIVACY • SPEED • TRUST',
                  style: ChhayaTypography.labelSmall.copyWith(
                    letterSpacing: 2.0,
                    color: ChhayaColors.labelTertiary,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: ChhayaSpacing.space12),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.error),
                    ),
                  )
                else
                  Column(children: [
                    SizedBox(
                      width: 28, height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        color: ChhayaColors.accent,
                        valueColor: disableAnimations
                            ? const AlwaysStoppedAnimation<Color>(ChhayaColors.accent)
                            : null,
                      ),
                    ),
                    const SizedBox(height: ChhayaSpacing.space3),
                    Text('Securing tunnel…', style: ChhayaTypography.code.copyWith(color: ChhayaColors.labelTertiary, fontSize: 12)),
                  ]),
              ],
            ),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => const _SplashScreen();
}

class AppStartupGate extends ConsumerStatefulWidget {
  const AppStartupGate({super.key});

  @override
  ConsumerState<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends ConsumerState<AppStartupGate> {
  bool _showPinPad = false;
  String _enteredPin = '';
  bool _shakeError = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final db = ref.read(localDatabaseProvider);
    final biometricEnabled = db.getBiometricLockEnabled();

    if (!biometricEnabled) {
      _unlock();
      return;
    }

    final isBioAvailable = await db.isBiometricAvailable();
    if (isBioAvailable) {
      final success = await db.authenticateWithBiometrics(
        reason: 'Unlock Chhaya',
      );
      if (success) {
        _unlock();
        return;
      }
    }

    setState(() => _showPinPad = true);
  }

  void _unlock() {
    ref.read(appUnlockedProvider.notifier).state = true;
    if (mounted) {
      Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
    }
  }

  void _onPinDigit(String digit) {
    if (_enteredPin.length >= 4) return;
    setState(() => _enteredPin += digit);

    if (_enteredPin.length == 4) {
      _validatePin();
    }
  }

  void _onPinDelete() {
    if (_enteredPin.isEmpty) return;
    setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
  }

  Future<void> _validatePin() async {
    final db = ref.read(localDatabaseProvider);
    final panicPin = db.getPanicPin();
    final appPin = db.getAppPin();

    if (panicPin != null && _enteredPin == panicPin) {
      ChhayaHaptics.error();
      final authService = ref.read(authServiceProvider);
      await authService.logout();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: ChhayaColors.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
            title: const Text('Data Erased'),
            content: const Text('All data has been permanently destroyed.'),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacementNamed(ChhayaRouter.onboarding);
                },
              ),
            ],
          ),
        );
      }
      return;
    }

    if (appPin != null && _enteredPin == appPin) {
      ChhayaHaptics.success();
      _unlock();
      return;
    }

    if (appPin == null) {
      ChhayaHaptics.success();
      _unlock();
      return;
    }

    ChhayaHaptics.error();
    setState(() {
      _shakeError = true;
      _enteredPin = '';
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _shakeError = false);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    if (!_showPinPad) {
      return const _SplashScreen();
    }

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Stack(
        children: [
          Positioned(
            top: -80, left: -80, right: -80, height: 320,
            child: Container(decoration: const BoxDecoration(gradient: ChhayaColors.glowGradient)),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ChhayaRadius.lg),
                    color: ChhayaColors.cardSurface,
                    border: Border.all(
                      color: ChhayaColors.accent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.lock_person_outlined, size: 34, color: ChhayaColors.accent),
                ),
                const SizedBox(height: ChhayaSpacing.space4),
                Text('Enter Passcode', style: ChhayaTypography.displaySmall.copyWith(fontSize: 22)),
                const SizedBox(height: ChhayaSpacing.space1),
                Text('Biometric failed • Use PIN', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.labelTertiary)),
                const SizedBox(height: ChhayaSpacing.space5),
                AnimatedContainer(
                  duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 100),
                  transform: _shakeError
                      ? Matrix4.translationValues(10.0, 0.0, 0.0)
                      : Matrix4.identity(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < _enteredPin.length;
                      return AnimatedContainer(
                        duration: disableAnimations ? Duration.zero : ChhayaAnimation.fast,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 16, height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? ChhayaColors.accent : ChhayaColors.cardSurface,
                          border: Border.all(
                            color: filled ? ChhayaColors.accent : ChhayaColors.opaqueSeparator,
                            width: 1.5,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const Spacer(flex: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(
                    children: [
                      for (final row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: row.map((digit) {
                              if (digit.isEmpty) return const SizedBox(width: 76, height: 76);
                              if (digit == '⌫') {
                                return SizedBox(
                                  width: 76, height: 76,
                                  child: IconButton(
                                    style: IconButton.styleFrom(
                                      backgroundColor: ChhayaColors.cardSurface,
                                      shape: const CircleBorder(),
                                      side: BorderSide(color: ChhayaColors.glassBorder.withValues(alpha: 0.12)),
                                    ),
                                    onPressed: _onPinDelete,
                                    icon: const Icon(Icons.backspace_outlined, color: ChhayaColors.labelPrimary, size: 22),
                                  ),
                                );
                              }
                              return InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  if (!disableAnimations) ChhayaHaptics.light();
                                  _onPinDigit(digit);
                                },
                                child: Container(
                                  width: 76, height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ChhayaColors.cardSurface,
                                    border: Border.all(color: ChhayaColors.glassBorder.withValues(alpha: 0.14)),
                                    boxShadow: disableAnimations ? null : ChhayaShadows.subtle,
                                  ),
                                  child: Center(child: Text(digit, style: ChhayaTypography.displaySmall.copyWith(fontWeight: FontWeight.w300, fontSize: 26))),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: ChhayaSpacing.space4),
                TextButton.icon(
                  onPressed: _checkAuth,
                  icon: const Icon(Icons.fingerprint_rounded, size: 18, color: ChhayaColors.accent),
                  label: Text('Try Biometrics Again', style: ChhayaTypography.labelMedium.copyWith(color: ChhayaColors.accent, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}