import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';

/// ChhayaAvatar — Wraps [AvatarWidget] with an optional verified badge.
///
/// When [showVerifiedBadge] is true, a small [ChhayaColors.coralDeep]
/// circle with a white check overlays the bottom-right corner.
/// Note: if [statusColor] is also set, the inner status dot sits at the
/// same corner, so prefer one indicator at a time.
class ChhayaAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? statusColor;
  final bool showVerifiedBadge;

  const ChhayaAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.statusColor,
    this.showVerifiedBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarWidget(
      name: name,
      size: size,
      statusColor: statusColor,
    );
    if (!showVerifiedBadge) return avatar;

    final badgeSize = size * 0.36;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: ChhayaColors.coralDeep,
              shape: BoxShape.circle,
              border: Border.all(color: ChhayaColors.white, width: 2),
            ),
            child: Icon(
              Icons.check,
              size: badgeSize * 0.55,
              color: ChhayaColors.white,
            ),
          ),
        ),
      ],
    );
  }
}
