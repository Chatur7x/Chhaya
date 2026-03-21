import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/chaaya_theme.dart';
import 'core/identity/identity_service.dart';
import 'core/mesh/message_queue.dart';
import 'core/providers/app_providers.dart';
import 'features/identity/presentation/identity_screen.dart';
import 'core/presentation/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUIOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: ChaayaTheme.surface,
  ));

  // Initialize Hive
  await Hive.initFlutter();

  runApp(const ProviderScope(child: ChaayaApp()));
}

class ChaayaApp extends ConsumerStatefulWidget {
  const ChaayaApp({super.key});

  @override
  ConsumerState<ChaayaApp> createState() => _ChaayaAppState();
}

class _ChaayaAppState extends ConsumerState<ChaayaApp> {
  bool _loading = true;
  bool _hasIdentity = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize identity service
      final identityService = ref.read(identityServiceProvider);
      final exists = await identityService.initialize();

      // Initialize message queue
      final queue = ref.read(messageQueueProvider);
      await queue.initialize();

      // Initialize contact service
      final contactService = ref.read(contactServiceProvider);
      await contactService.initialize();

      // Initialize chat service
      final chatService = ref.read(meshChatServiceProvider);
      await chatService.initialize();

      if (exists && identityService.currentIdentity != null) {
        ref.read(currentIdentityProvider.notifier).state =
            identityService.currentIdentity;
        ref.read(identityReadyProvider.notifier).state = true;
        ref.read(contactListProvider.notifier).state = contactService.getAll();
        ref.read(conversationListProvider.notifier).state =
            chatService.getConversations();
        _hasIdentity = true;
      }
    } catch (e) {
      debugPrint('[Chaaya] Init error: $e');
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final identityReady = ref.watch(identityReadyProvider);

    return MaterialApp(
      title: 'Chaaya',
      debugShowCheckedModeBanner: false,
      theme: ChaayaTheme.darkTheme,
      home: _loading
          ? const _SplashScreen()
          : (identityReady || _hasIdentity)
              ? const MainScreen()
              : const IdentityScreen(),
    );
  }
}

/// Splash screen shown while services initialize
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [ChaayaTheme.accent, ChaayaTheme.bleColor],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: ChaayaTheme.accent.withOpacity(0.3),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: const Icon(Icons.cell_tower_rounded, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chaaya',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: ChaayaTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ChaayaTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

