import 'package:flutter/cupertino.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final Color? statusColor;
  final bool showGradientRing;

  const AvatarWidget({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.statusColor,
    this.showGradientRing = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [ChhayaColors.accentBlue, ChhayaColors.accentIndigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: ChhayaColors.labelPrimary,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    if (showGradientRing) {
      avatar = Container(
        width: size + 6,
        height: size + 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: ChhayaColors.accentGradient,
        ),
        padding: const EdgeInsets.all(2.5),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ChhayaColors.primaryBackground,
          ),
          padding: const EdgeInsets.all(1.5),
          child: avatar,
        ),
      );
    }

    if (statusColor != null) {
      return Stack(
        children: [
          avatar,
          Positioned(
            right: showGradientRing ? 2 : 0,
            bottom: showGradientRing ? 2 : 0,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: ChhayaColors.primaryBackground, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    return avatar;
  }
}
