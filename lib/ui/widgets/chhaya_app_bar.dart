import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// Pixel display heading with native navigation and scaling-aware content.
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
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: ChhayaPalette.of(context).cream,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      titleSpacing: 24,
      shape: Border(bottom: BorderSide(color: ChhayaPalette.of(context).borderSoft)),
      leading: leading,
      actions: actions,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: ChhayaType.of(context).headline.copyWith(
              color: ChhayaPalette.of(context).ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: ChhayaType.of(context).caption.copyWith(
                color: ChhayaPalette.of(context).inkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
