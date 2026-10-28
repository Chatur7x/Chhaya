import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:chaaya/ui/screens/onboarding/onboarding_screen.dart';
import 'package:chaaya/ui/screens/chat/chat_screen.dart';
import 'package:chaaya/ui/screens/call/call_screen.dart';
import 'package:chaaya/ui/screens/settings/settings_screen.dart';
import 'package:chaaya/ui/screens/profile/profile_screen.dart';
import 'package:chaaya/ui/screens/verification/verification_screen.dart';
import 'package:chaaya/ui/screens/home/home_shell.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

class ChhayaRouter {
  ChhayaRouter._();

  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String chat = '/chat';
  static const String call = '/call';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String verification = '/verification';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case onboarding:
        return _buildMaterialRoute(
          const OnboardingScreen(),
          routeSettings,
        );
      case home:
        return _buildMaterialRoute(
          const HomeShell(),
          routeSettings,
        );
      case chat:
        final args = routeSettings.arguments as Map<String, dynamic>?;
        return _buildMaterialRoute(
          ChatScreen(
            conversationId: args?['conversationId'] as String? ?? '',
            contactName: args?['contactName'] as String? ?? 'Unknown',
          ),
          routeSettings,
        );
      case call:
        final args = routeSettings.arguments as Map<String, dynamic>?;
        return _buildMaterialRoute(
          CallScreen(
            contactName: args?['contactName'] as String? ?? 'Unknown',
            contactAvatar: args?['contactAvatar'] as String?,
            isVideo: args?['isVideo'] as bool? ?? false,
            conversationId: args?['conversationId'] as String? ?? '',
          ),
          routeSettings,
          fullscreenDialog: true,
        );
      case settings:
        return _buildMaterialRoute(
          const SettingsScreen(),
          routeSettings,
        );
      case profile:
        final args = routeSettings.arguments as Map<String, dynamic>?;
        return _buildMaterialRoute(
          ProfileScreen(
            contactId: args?['contactId'] as String?,
          ),
          routeSettings,
        );
      case verification:
        return _buildMaterialRoute(
          const VerificationScreen(),
          routeSettings,
          fullscreenDialog: true,
        );
      default:
        return _buildMaterialRoute(
          const OnboardingScreen(),
          routeSettings,
        );
    }
  }

  static PageRoute<T> _buildMaterialRoute<T>(
    Widget page,
    RouteSettings settings, {
    bool fullscreenDialog = false,
  }) {
    final entering = settings.name == home || settings.name == onboarding;
    Widget buildPage(BuildContext context) => entering
      ? ColoredBox(color: ChhayaPalette.of(context).primaryBackground,
          child: MessageEntrance(animate: true, child: page)) : page;
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return ChhayaCupertinoRoute<T>(builder: buildPage, settings: settings, fullscreenDialog: fullscreenDialog);
    }
    return MaterialPageRoute<T>(builder: buildPage, settings: settings, fullscreenDialog: fullscreenDialog);
  }
}
