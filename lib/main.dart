import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/chhaya_router.dart';
import 'ui/theme/chhaya_theme.dart';
import 'core/providers/app_providers.dart';

final appInitializationProvider = FutureProvider<bool>((ref) async {
  final authService = ref.read(authServiceProvider);
  final db = ref.read(localDatabaseProvider);

  await authService.init();
  await ref.read(notificationServiceProvider).init();

  final currentUser = authService.currentUser;
  ref.read(currentUserProvider.notifier).state = currentUser;

  if (currentUser != null) {
    final convos = await db.getAllConversations();
    final contacts = await db.getAllContacts();
    ref.read(conversationsProvider.notifier).setConversations(convos);
    ref.read(contactsProvider.notifier).setContacts(contacts);
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
      theme: ChhayaTheme.materialDark,
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
    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ChhayaColors.accentGradient,
                boxShadow: [
                  BoxShadow(
                    color: ChhayaColors.accentBlue.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 48,
                color: ChhayaColors.labelPrimary,
              ),
            ),
            const SizedBox(height: ChhayaSpacing.xl),
            Text(
              'Chhaya',
              style: ChhayaTypography.largeTitle.copyWith(letterSpacing: 1.0),
            ),
            const SizedBox(height: ChhayaSpacing.md),
            if (errorMessage != null)
              Text(
                errorMessage!,
                style: ChhayaTypography.footnote.copyWith(
                  color: ChhayaColors.accentRed,
                ),
              )
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ChhayaColors.labelSecondary,
                ),
              ),
          ],
        ),
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
    if (!_showPinPad) {
      return const _SplashScreen();
    }

    return Scaffold(
      backgroundColor: ChhayaColors.primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const Icon(
              Icons.lock_person_rounded,
              size: 56,
              color: ChhayaColors.accentBlue,
            ),
            const SizedBox(height: ChhayaSpacing.lg),
            Text('Enter Passcode', style: ChhayaTypography.title2),
            const SizedBox(height: ChhayaSpacing.xxl),
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              transform: _shakeError
                  ? Matrix4.translationValues(10.0, 0.0, 0.0)
                  : Matrix4.identity(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _enteredPin.length;
                  return AnimatedContainer(
                    duration: ChhayaAnimation.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? ChhayaColors.accentBlue : ChhayaColors.fillTertiary,
                      border: Border.all(
                        color: filled ? ChhayaColors.accentBlue : ChhayaColors.labelTertiary,
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const Spacer(flex: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: Column(
                children: [
                  for (final row in [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['', '0', '⌫']
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: row.map((digit) {
                          if (digit.isEmpty) {
                            return const SizedBox(width: 72, height: 72);
                          }
                          if (digit == '⌫') {
                            return SizedBox(
                              width: 72,
                              height: 72,
                              child: IconButton(
                                onPressed: _onPinDelete,
                                icon: const Icon(
                                  Icons.backspace_outlined,
                                  color: ChhayaColors.labelPrimary,
                                  size: 24,
                                ),
                              ),
                            );
                          }
                          return InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              ChhayaHaptics.light();
                              _onPinDigit(digit);
                            },
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ChhayaColors.fillTertiary,
                              ),
                              child: Center(
                                child: Text(
                                  digit,
                                  style: ChhayaTypography.title1.copyWith(
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: ChhayaSpacing.lg),
            TextButton(
              onPressed: _checkAuth,
              child: Text(
                'Use Biometrics',
                style: ChhayaTypography.body.copyWith(
                  color: ChhayaColors.accentBlue,
                ),
              ),
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}
