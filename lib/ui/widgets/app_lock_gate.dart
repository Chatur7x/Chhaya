import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/chhaya_router.dart';
import '../theme/chhaya_theme.dart';
import 'chhaya_brand_mark.dart';

/// Whole-screen lock shown on startup and after re-locking a backgrounded app.
/// While mounted it consumes system back so hidden routes are never popped.
class AppStartupGate extends ConsumerStatefulWidget {
  const AppStartupGate({super.key, this.onUnlocked, this.onAccountErased});
  final VoidCallback? onUnlocked;
  final VoidCallback? onAccountErased;

  @override
  ConsumerState<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends ConsumerState<AppStartupGate>
    with WidgetsBindingObserver {
  static const int _maxDeviceAttempts = 3;

  int _authEpoch = 0;
  bool _foreground = true;
  bool _showPinPad = false;
  bool _pinAvailable = false;
  int _deviceAttempts = 0;
  String _enteredPin = '';
  bool _shakeError = false;
  bool _authenticating = false;
  bool _validatingPin = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAuth();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _authEpoch++;
      _enteredPin = '';
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (mounted) {
        setState(() {
          _showPinPad = true;
          _pinAvailable = _readPinAvailability();
        });
      }
    }
  }

  bool _readPinAvailability() {
    try {
      return ref.read(localDatabaseProvider).getAppPin() != null;
    } catch (_) {
      return false; // Fail closed when the lock settings cannot be read.
    }
  }

  Future<void> _checkAuth({bool countDeviceFailure = false}) async {
    if (_authenticating || _validatingPin || !mounted || !_foreground) return;
    final epoch = _authEpoch;
    _authenticating = true;
    var unlocked = false;
    try {
      final db = ref.read(localDatabaseProvider);
      var biometricEnabled = true;
      var pinAvailable = false;
      try {
        biometricEnabled = db.getBiometricLockEnabled();
        pinAvailable = db.getAppPin() != null;
      } catch (_) {
        // Fail closed: an unreadable lock store must not unlock the app.
      }
      if (mounted) setState(() => _pinAvailable = pinAvailable);

      if (!biometricEnabled) {
        _unlock(epoch);
        unlocked = true;
        return;
      }

      final isBioAvailable = await db.isBiometricAvailable();
      if (!_foreground || epoch != _authEpoch || !mounted) return;
      if (isBioAvailable) {
        final success = await db.authenticateWithBiometrics(
          reason: 'Unlock Chhaya',
        );
        if (success) {
          _unlock(epoch);
          unlocked = true;
          return;
        }
      }

      if (mounted) setState(() => _showPinPad = true);
    } catch (_) {
      if (mounted) setState(() => _showPinPad = true);
    } finally {
      _authenticating = false;
      if (countDeviceFailure && !unlocked && mounted) {
        setState(() => _deviceAttempts++);
      }
    }
  }

  Future<void> _useDeviceAuthentication() async {
    if (_authenticating || _deviceAttempts >= _maxDeviceAttempts) return;
    await _checkAuth(countDeviceFailure: true);
  }

  void _unlock(int epoch) {
    if (mounted && _foreground && epoch == _authEpoch) {
      ref.read(appUnlockedProvider.notifier).state = true;
      if (widget.onUnlocked != null) {
        widget.onUnlocked!();
      } else {
        Navigator.of(context).pushReplacementNamed(ChhayaRouter.home);
      }
    }
  }

  void _onPinDigit(String digit) {
    if (!_foreground ||
        _authenticating ||
        _validatingPin ||
        _enteredPin.length >= 4) {
      return;
    }
    setState(() => _enteredPin += digit);

    if (_enteredPin.length == 4) {
      _validatePin();
    }
  }

  void _onPinDelete() {
    if (!_foreground ||
        _authenticating ||
        _validatingPin ||
        _enteredPin.isEmpty) {
      return;
    }
    setState(
      () => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1),
    );
  }

  Future<void> _validatePin() async {
    if (_validatingPin || !mounted) return;
    _validatingPin = true;
    final epoch = _authEpoch;
    try {
      final db = ref.read(localDatabaseProvider);
      String? panicPin;
      String? appPin;
      try {
        panicPin = db.getPanicPin();
        appPin = db.getAppPin();
      } catch (_) {
        // Fail closed: unreadable PINs never grant access.
      }

      if (panicPin != null && _enteredPin == panicPin) {
        ChhayaHaptics.error();
        final authService = ref.read(authServiceProvider);
        await authService.logout();
        if (!mounted) return;
        ref.read(appUnlockedProvider.notifier).state = false;
        ref.read(currentUserProvider.notifier).state = null;
        ref.read(conversationsProvider.notifier).setConversations([]);
        ref.read(contactsProvider.notifier).setContacts([]);
        if (widget.onAccountErased != null) {
          // Shown before the gate is torn down; the messenger outlives it so
          // the notice stays visible on the onboarding route.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 8),
              content: Text(
                'Data Erased: local account data and keys have been removed. '
                'Remote copies and backups are not erased.',
              ),
            ),
          );
          widget.onAccountErased!();
          return;
        }
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: ChhayaPalette.of(context).cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ChhayaRadius.xl),
              ),
              title: const Text('Data Erased'),
              content: const Text(
                'Local account data and keys have been removed. Remote copies and backups are not erased.',
              ),
              actions: [
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      ChhayaRouter.onboarding,
                      (_) => false,
                    );
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
        _unlock(epoch);
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
    if (!_showPinPad) {
      return const PopScope(canPop: false, child: ChhayaSplashScreen());
    }
    final palette = ChhayaPalette.of(context);
    final deviceExhausted = _deviceAttempts >= _maxDeviceAttempts;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            children: [
              Icon(Icons.lock_outline, size: 48, color: palette.accent),
              const SizedBox(height: 24),
              Text(
                'Unlock Chhaya',
                textAlign: TextAlign.center,
                style: ChhayaType.of(context).headline,
              ),
              const SizedBox(height: 12),
              Text(
                _pinAvailable
                    ? 'Use your app PIN or device authentication'
                    : 'Use device authentication to unlock',
                textAlign: TextAlign.center,
                style: ChhayaType.of(
                  context,
                ).bodyLarge.copyWith(color: palette.inkMuted),
              ),
              if (_pinAvailable) ...[
                const SizedBox(height: 24),
                Semantics(
                  label: '${_enteredPin.length} of 4 passcode digits entered',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      4,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _shakeError
                              ? palette.error
                              : i < _enteredPin.length
                              ? palette.accent
                              : palette.borderMed,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                for (final row in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', 'delete'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final digit in row)
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: digit.isEmpty
                                ? null
                                : digit == 'delete'
                                ? IconButton(
                                    tooltip: 'Delete passcode digit',
                                    onPressed: _onPinDelete,
                                    icon: const Icon(Icons.backspace_outlined),
                                  )
                                : OutlinedButton(
                                    onPressed: () => _onPinDigit(digit),
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      shape: const CircleBorder(),
                                    ),
                                    child: Text(
                                      digit,
                                      style: ChhayaType.of(context).title,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _checkAuth,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use Device Authentication'),
                ),
              ] else ...[
                if (_deviceAttempts > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    deviceExhausted
                        ? 'Too many failed attempts. Restart the app to try again.'
                        : 'Device authentication failed. Try again.',
                    textAlign: TextAlign.center,
                    style: ChhayaType.of(
                      context,
                    ).body.copyWith(color: palette.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: deviceExhausted ? null : _useDeviceAuthentication,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use Device Authentication'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded startup visual shared by the app shell and the lock gate.
class ChhayaSplashScreen extends StatelessWidget {
  const ChhayaSplashScreen({
    super.key,
    this.errorMessage,
    this.errorDetails,
    this.onRetry,
  });

  final String? errorMessage;
  final String? errorDetails;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChhayaBrandMark(size: 64),
              const SizedBox(height: 24),
              Text('Chhaya', style: ChhayaType.of(context).displayLarge),
              const SizedBox(height: 24),
              if (errorMessage != null) ...[
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: ChhayaType.of(context).bodyLarge,
                ),
                if (errorDetails != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      errorDetails!,
                      textAlign: TextAlign.center,
                      style: ChhayaType.of(context).labelSmall.copyWith(
                        color: ChhayaPalette.of(context).inkMuted,
                      ),
                    ),
                  ),
                if (onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ),
              ] else ...[
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 16),
                Text(
                  'Opening your account…',
                  style: ChhayaType.of(context).body,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
