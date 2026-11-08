import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/chhaya_router.dart';
import '../theme/chhaya_theme.dart';
import 'app_lock_gate.dart';

/// Keeps routes mounted while hiding them and requiring reauthentication after
/// backgrounding. It does not claim to erase all Dart/native memory copies.
class AppLifecycleGuard extends ConsumerStatefulWidget {
  const AppLifecycleGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<AppLifecycleGuard> createState() => _AppLifecycleGuardState();
}

class _AppLifecycleGuardState extends ConsumerState<AppLifecycleGuard>
    with WidgetsBindingObserver {
  bool _covered = false;
  bool _locked = false;
  bool _gateStarted = false;
  Route<void>? _gateRoute;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _covered = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    // A first frame while already backgrounded must not reveal signed-in content.
    if (ref.read(appLockedProvider)) {
      ref.read(appUnlockedProvider.notifier).state = false;
      _locked = true;
      _gateStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showGate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _covered = false;
        if (_locked) _gateStarted = true;
      });
      if (_locked) _showGate();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final backgrounded =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    // A signed-in session that was previously unlocked must re-enter the lock
    // gate on background. Clearing the unlock flag lets the derived
    // appLockedProvider report the gate as active.
    if (backgrounded &&
        ref.read(appUnlockedProvider) &&
        ref.read(currentUserProvider) != null &&
        safeBiometricLockEnabled(ref.read(localDatabaseProvider))) {
      ref.read(appUnlockedProvider.notifier).state = false;
    }
    final shouldLock = backgrounded && ref.read(appLockedProvider);
    setState(() {
      _covered = true;
      if (shouldLock) _locked = true;
    });
  }

  /// The gate is a route on the root navigator: its own [PopScope] and
  /// `didPopRoute` block system back before it can pop a hidden raw route.
  void _showGate() {
    if (!mounted || !_locked || !_gateStarted || _gateRoute != null) return;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/app-lock'),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => AppStartupGate(
        onUnlocked: _unlocked,
        onAccountErased: _accountErased,
      ),
    );
    setState(() => _gateRoute = route);
    navigator.push(route).whenComplete(() {
      if (!mounted || _gateRoute != route) return;
      setState(() {
        _gateRoute = null;
        _locked = false;
        _gateStarted = false;
      });
    });
  }

  void _removeGate() {
    final route = _gateRoute;
    _gateRoute = null;
    if (route != null && route.isActive) {
      widget.navigatorKey.currentState?.removeRoute(route);
    }
  }

  void _unlocked() {
    if (!mounted) return;
    _removeGate();
    setState(() {
      _locked = false;
      _gateStarted = false;
    });
  }

  void _accountErased() {
    if (!mounted) return;
    _gateRoute = null; // Removed together with the rest of the stack.
    setState(() {
      _locked = false;
      _gateStarted = false;
    });
    widget.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      ChhayaRouter.onboarding,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (previous, current) {
      if (current == null && _locked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _locked && ref.read(currentUserProvider) == null) {
            _unlocked();
          }
        });
      }
    });
    // Keep the gate route itself visible; opaque-route painting hides the stack
    // below it, while an unpushed gate still needs the cover.
    final hideContent = _covered || (_locked && _gateRoute == null);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: hideContent,
          child: TickerMode(
            enabled: !_covered && !_locked,
            child: ExcludeFocus(
              excluding: _covered || _locked,
              child: widget.child,
            ),
          ),
        ),
        if (hideContent)
          ColoredBox(color: ChhayaPalette.of(context).primaryBackground),
      ],
    );
  }
}
