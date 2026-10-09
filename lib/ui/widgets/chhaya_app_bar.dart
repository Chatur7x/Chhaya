import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// ChhayaAppBar — 56px top bar.
///
/// Translucent [ChhayaColors.cream] background (alpha ~0.9) with no
/// elevation. The title uses [ChhayaTypography.title] in
/// [ChhayaColors.ink]; the optional subtitle uses
/// [ChhayaTypography.caption] in [ChhayaColors.inkMuted].
class ChhayaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;

  const ChhayaAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: ChhayaColors.cream.withValues(alpha: 0.9),
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      leading: leading,
      actions: actions,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: ChhayaTypography.title.copyWith(
              color: ChhayaColors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: ChhayaTypography.caption.copyWith(
                color: ChhayaColors.inkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
