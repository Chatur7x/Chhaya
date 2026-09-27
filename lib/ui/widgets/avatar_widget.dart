import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// AvatarWidget — Gradient avatar with optional status indicator
/// Uses aurora gradient ring, surface-0 inner, gradient fill
/// Sizes: 32, 36, 42, 48, 56, 72, 96, 110, 132
class AvatarWidget extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final Color? statusColor;
  final bool showGradientRing;
  final bool showShadow;

  const AvatarWidget({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.statusColor,
    this.showGradientRing = false,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fontSize = size * 0.40;

    // Flat hacker avatar: dark panel, 1.5px accent hairline, mono initial.
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ChhayaColors.cardSurfaceElevated,
        border: Border.all(
          color: ChhayaColors.accent.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            color: ChhayaColors.accent,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );

    if (showGradientRing) {
      final ringSize = size + 7;
      avatar = Container(
        width: ringSize,
        height: ringSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ChhayaColors.accent.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(2.2),
        child: avatar,
      );
    }

    if (statusColor != null) {
      final dotSize = size * 0.28;
      final offset = showGradientRing ? 1.0 : 0.0;
      final reduceMotion = MediaQuery.of(context).disableAnimations;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: offset,
            bottom: offset,
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : ChhayaAnimation.fast,
              curve: ChhayaAnimation.springCurve,
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: ChhayaColors.primaryBackground,
                  width: 2.2,
                ),
                boxShadow: !reduceMotion
                    ? [BoxShadow(
                        color: statusColor!.withValues(alpha: 0.5),
                        blurRadius: 6,
                      )]
                    : null,
              ),
            ),
          ),
        ],
      );
    }

    return avatar;
  }
}

/// AvatarStack — Overlapping avatar group (max 3 shown)
/// 62% overlap, surface-0 border separator
class AvatarStack extends StatelessWidget {
  final List<String> names;
  final double size;

  const AvatarStack({
    super.key,
    required this.names,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    final overlap = size * 0.62;
    final width = size + (shown.length - 1) * overlap;

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: List.generate(shown.length, (i) {
          return Positioned(
            left: i * overlap,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ChhayaColors.primaryBackground,
                  width: 2,
                ),
              ),
              child: AvatarWidget(name: shown[i], size: size),
            ),
          );
        }),
      ),
    );
  }
}

/// AvatarWithBadge — Avatar with notification badge
class AvatarWithBadge extends StatelessWidget {
  final String name;
  final int count;
  final double size;
  final Color? badgeColor;

  const AvatarWithBadge({
    super.key,
    required this.name,
    required this.count,
    this.size = 44,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final showBadge = count > 0;

    final children = <Widget>[
      AvatarWidget(name: name, size: size),
    ];

    if (showBadge) {
      children.add(
        Positioned(
          right: -4,
          top: -4,
          child: AnimatedScale(
            scale: showBadge ? 1.0 : 0.0,
            duration: disableAnimations ? Duration.zero : ChhayaAnimation.fast,
            curve: ChhayaAnimation.bounceCurve,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ChhayaSpacing.space1,
                vertical: 1,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                gradient: badgeColor != null
                    ? LinearGradient(colors: [badgeColor!, badgeColor!])
                    : ChhayaColors.accentGradient,
                borderRadius: BorderRadius.circular(ChhayaRadius.pill),
                border: Border.all(color: ChhayaColors.primaryBackground, width: 2),
                boxShadow: !disableAnimations
                    ? [BoxShadow(
                        color: (badgeColor ?? ChhayaColors.accent).withValues(alpha: 0.4),
                        blurRadius: 6,
                      )]
                    : null,
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: const TextStyle(
                    color: ChhayaColors.onAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: children,
    );
  }
}