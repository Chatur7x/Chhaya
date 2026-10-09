import 'package:flutter/material.dart';
import 'package:chaaya/ui/widgets/pressable.dart';

/// ChhayaPressable — Wraps [PressableScale], which already provides
/// scale-down press feedback plus [ChhayaHaptics.light] on pointer-down.
///
/// This wrapper only forwards the contract and guarantees a minimum
/// 44x44 tap target. [ChhayaIconButton] is intentionally not redefined
/// here — it already lives in `chhaya_button.dart`.
class ChhayaPressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool haptic;
  final double pressedScale;

  const ChhayaPressable({
    super.key,
    required this.child,
    this.onTap,
    this.haptic = true,
    this.pressedScale = 0.97,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: PressableScale(
        onTap: onTap,
        haptic: haptic,
        pressedScale: pressedScale,
        child: child,
      ),
    );
  }
}
