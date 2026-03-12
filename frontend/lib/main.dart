import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/presentation/login_screen.dart';
import 'core/notifications/push_notification_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Secure Notifications
  await PushNotificationManager().initialize();
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '#PROJ16',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E), // Deep Blue
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        // Premium Design Aesthetics
        fontFamily: 'Inter', 
      ),
      home: const LoginScreen(),
    );
  }
}
