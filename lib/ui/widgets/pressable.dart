import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// PressableScale — Apple-style press feedback (apple-design §1, §3).
///
/// - Feedback fires on pointer-DOWN (instant), not on release.
/// - Press scales to 0.97 over 100ms; release springs back with a
///   critically-damped spring from the CURRENT on-screen value, so a
///   re-press mid-release never jumps (interruptible).
/// - Reduced motion: no scale, haptic only.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final bool haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.borderRadius,
    this.haptic = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ChhayaAnimation.instant,
    );
    _scale = Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pressDown() {
    if (_pressed) return;
    _pressed = true;
    if (widget.haptic && !MediaQuery.of(context).disableAnimations) {
      ChhayaHaptics.light();
    }
    // Animate from the live presentation value — interruptible (§3).
    _controller.stop();
    _controller.animateTo(
      1.0,
      duration: ChhayaAnimation.instant,
      curve: Curves.easeOut,
    );
  }

  void _release() {
    if (!_pressed) return;
    _pressed = false;
    // Spring back from wherever the press animation currently is.
    _controller.stop();
    _controller.animateBack(
      0.0,
      duration: ChhayaAnimation.normal,
      curve: ChhayaSprings.criticalCurve,
    );
  }

  double get _effectiveScale {
    if (MediaQuery.of(context).disableAnimations) return 1.0;
    return _scale.value;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pressDown(),
      onTapUp: (_) {
        _release();
        widget.onTap?.call();
      },
      onTapCancel: _release,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _effectiveScale,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// SpringBack — drives a value back to rest with a real spring simulation
/// (apple-design §4). Use for momentum-driven motion (flick, drag release).
class SpringBack {
  SpringBack._();

  static void animate(
    AnimationController controller, {
    double from = 0.0,
    double to = 1.0,
    bool momentum = false,
  }) {
    controller.animateWith(
      SpringSimulation(
        momentum ? ChhayaSprings.momentum : ChhayaSprings.standard,
        from,
        to,
        0.0, // initial velocity handed off by the caller (§5)
      ),
    );
  }

  /// Apple §6 momentum projection: where is this flick GOING?
  /// projected = current + (v/1000) * d / (1 - d), d ≈ 0.998.
  static double projectEndpoint(
    double current,
    double releaseVelocity, {
    double decelerationRate = 0.998,
  }) {
    return current +
        (releaseVelocity / 1000) *
            decelerationRate /
            (1 - decelerationRate);
  }
}
