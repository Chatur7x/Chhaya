import 'package:flutter/material.dart';
import 'ui/theme/appearance_provider.dart';
import 'package:flutter/foundation.dart';
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
        child: HeroMode(enabled: !ChhayaMotion.reduced(context), child: child!)),
      home: initAsync.when(
        data: (isLoggedIn) {
          if (isLoggedIn) {
            return const AppStartupGate();
          } else {
            return const _RouteLoader(route: ChhayaRouter.onboarding);
          }
        },
        loading: () => const _SplashScreen(),
        error: (e, stack) => _SplashScreen(errorMessage: 'Could not open your account. Try again.',
          onRetry:()=>ref.invalidate(appInitializationProvider)),
      ),
      onGenerateRoute: ChhayaRouter.generateRoute,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback? onRetry;
  const _SplashScreen({this.errorMessage,this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
    body:SafeArea(child:Center(child:SingleChildScrollView(
      padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(Icons.chat_bubble_outline_rounded,size:56,color:ChhayaPalette.of(context).accent),
        const SizedBox(height:24),
        Text('Chhaya',style:ChhayaType.of(context).displayLarge),
        const SizedBox(height:24),
        if(errorMessage!=null) ...[
          Text(errorMessage!,textAlign:TextAlign.center,style:ChhayaType.of(context).bodyLarge),
          if(onRetry!=null) Padding(padding:const EdgeInsets.only(top:16),
            child:FilledButton(onPressed:onRetry,child:const Text('Try again'))),
        ] else ...[
          const SizedBox(width:24,height:24,child:CircularProgressIndicator(strokeWidth:2)),
          const SizedBox(height:16),
          Text('Opening your account…',style:ChhayaType.of(context).body),
        ],
      ]),
    ))),
  );
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
  bool _authenticating = false;
  bool _validatingPin = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (_authenticating || _validatingPin || !mounted) return;
    _authenticating = true;
    try {
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

    if (mounted) setState(() => _showPinPad = true);
    } finally {
      _authenticating = false;
    }
  }

  void _unlock() {
    if (mounted) {
      ref.read(appUnlockedProvider.notifier).state = true;
      Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
    }
  }

  void _onPinDigit(String digit) {
    if (_authenticating || _validatingPin || _enteredPin.length >= 4) return;
    setState(() => _enteredPin += digit);

    if (_enteredPin.length == 4) {
      _validatePin();
    }
  }

  void _onPinDelete() {
    if (_authenticating || _validatingPin || _enteredPin.isEmpty) return;
    setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
  }

  Future<void> _validatePin() async {
    if (_validatingPin || !mounted) return;
    _validatingPin = true;
    try {
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
            backgroundColor: ChhayaPalette.of(context).cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChhayaRadius.xl)),
            title: const Text('Data Erased'),
            content: const Text('Local account data and keys have been removed. Remote copies and backups are not erased.'),
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

    if (!mounted) return;
    ChhayaHaptics.error();
    setState(() {
      _shakeError = true;
      _enteredPin = '';
    });
    // Throttle repeated attempts. An unset PIN never grants access.
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _shakeError = false);
    } finally {
      _validatingPin = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!_showPinPad) return const _SplashScreen();
    final hasPin=ref.read(localDatabaseProvider).getAppPin()!=null;
    return Scaffold(body:SafeArea(child:ListView(
      padding:const EdgeInsets.symmetric(horizontal:24,vertical:32),children:[
        Icon(Icons.lock_outline,size:48,color:ChhayaPalette.of(context).accent),
        const SizedBox(height:24),
        Text('Unlock Chhaya',textAlign:TextAlign.center,style:ChhayaType.of(context).headline),
        const SizedBox(height:12),
        Text(hasPin?'Use your app PIN or device authentication':'Use device authentication to unlock',
          textAlign:TextAlign.center,style:ChhayaType.of(context).bodyLarge.copyWith(color:ChhayaPalette.of(context).inkMuted)),
        const SizedBox(height:24),
        Semantics(label:'${_enteredPin.length} of 4 passcode digits entered',excludeSemantics:true,
          child:Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(4,(i)=>Container(
            margin:const EdgeInsets.symmetric(horizontal:8),width:14,height:14,
            decoration:BoxDecoration(shape:BoxShape.circle,
              color:_shakeError?ChhayaPalette.of(context).error:i<_enteredPin.length?ChhayaPalette.of(context).accent:ChhayaPalette.of(context).borderMed),
          )))),
        const SizedBox(height:24),
        for(final row in [['1','2','3'],['4','5','6'],['7','8','9'],['','0','delete']])
          Padding(padding:const EdgeInsets.only(bottom:12),child:Row(
            mainAxisAlignment:MainAxisAlignment.spaceEvenly,
            children:[for(final digit in row) SizedBox(width:64,height:64,
              child:digit.isEmpty?null:digit=='delete'?IconButton(
                tooltip:'Delete passcode digit',onPressed:_onPinDelete,icon:const Icon(Icons.backspace_outlined)):
                OutlinedButton(onPressed:()=>_onPinDigit(digit),
                  style:OutlinedButton.styleFrom(padding:EdgeInsets.zero,shape:const CircleBorder()),
                  child:Text(digit,style:ChhayaType.of(context).title)),
            )],
          )),
        const SizedBox(height:12),
        TextButton.icon(onPressed:_checkAuth,icon:const Icon(Icons.fingerprint),
          label:const Text('Use Device Authentication')),
      ],
    )));
  }
}
