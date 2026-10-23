import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/chhaya_theme.dart';

/// Cupertino preview lifting when motion is allowed; a static action sheet
/// remains available when the person requests reduced motion/navigation.
class ChhayaContextMenu extends StatelessWidget {
  const ChhayaContextMenu({super.key, required this.actions, required this.onStaticMenu, required this.child});
  final List<Widget> actions;
  final VoidCallback onStaticMenu;
  final Widget child;
  @override
  Widget build(BuildContext context) => ChhayaMotion.reduced(context)
    ? GestureDetector(onLongPress: onStaticMenu, child: child)
    : CupertinoContextMenu(enableHapticFeedback: true, actions: actions, child: child);
}
