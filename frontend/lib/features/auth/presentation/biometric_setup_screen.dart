import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/biometric_service.dart';

class BiometricSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;
  final bool isInitialSetup;

  const BiometricSetupScreen({
    super.key,
    this.onComplete,
    this.isInitialSetup = false,
  });

  @override
  ConsumerState<BiometricSetupScreen> createState() =>
      _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends ConsumerState<BiometricSetupScreen> {
  bool _isEnrolling = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final biometricService = ref.read(biometricServiceProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 140,
                height: 140,
                decoration: ChaayaTheme.glassDecoration(
                  borderRadius: 70,
                  color: ChaayaTheme.accent.withOpacity(0.1),
                ),
                child: const Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: ChaayaTheme.accent,
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Enable Biometric Unlock',
                style: ChaayaTheme.heading1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Secure your messages with fingerprint or face authentication. '
                'Quick access while keeping your data protected.',
                style: ChaayaTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ChaayaTheme.sosRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: ChaayaTheme.sosRed.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: ChaayaTheme.sosRed, size: 18),
                      const SizedBox(width: 8),
                      Text(_error!,
                          style: const TextStyle(
                              color: ChaayaTheme.sosRed, fontSize: 13)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isEnrolling ? null : _handleEnroll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ChaayaTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isEnrolling
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Enable Biometrics',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _handleSkip,
                child: Text(
                  'Skip for now',
                  style: TextStyle(color: ChaayaTheme.textMuted),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleEnroll() async {
    setState(() {
      _isEnrolling = true;
      _error = null;
    });

    try {
      final biometricService = ref.read(biometricServiceProvider);
      final isAvailable = await biometricService.isBiometricAvailable();

      if (!isAvailable) {
        setState(() {
          _error = 'Biometric authentication not available on this device';
        });
        return;
      }

      await biometricService.enrollBiometric();
      final isEnabled = await biometricService.isBiometricEnabled();

      if (isEnabled) {
        widget.onComplete?.call();
      } else {
        setState(() {
          _error = 'Enrollment failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'An error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEnrolling = false;
        });
      }
    }
  }

  void _handleSkip() {
    widget.onComplete?.call();
  }
}
