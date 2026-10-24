import 'package:flutter/material.dart';
import '../theme/chhaya_theme.dart';

/// Preserve standard destination semantics while one shared indicator moves
/// continuously between destinations. Content has no translucent decoration.
class ChhayaNavigation extends StatelessWidget {
  const ChhayaNavigation({super.key, required this.index, required this.onSelect,
    required this.destinations});
  final int index;
  final ValueChanged<int> onSelect;
  final List<NavigationDestination> destinations;
  @override
  Widget build(BuildContext context) => ColoredBox(color: ChhayaPalette.of(context).surface,
    child: LayoutBuilder(builder: (context, constraints) {
      final cell = constraints.maxWidth / destinations.length;
      final visualIndex = Directionality.of(context) == TextDirection.rtl ? destinations.length-1-index : index;
      return Stack(children: [
        AnimatedPositioned(duration: ChhayaMotion.duration(context, 320), curve: Curves.easeOutCubic,
          left: visualIndex*cell+(cell-64)/2, top: 12, width: 64, height: 32,
          child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
            color: ChhayaPalette.of(context).coralTint, borderRadius: BorderRadius.circular(18))))),
        NavigationBar(height: 80, backgroundColor: ChhayaPalette.of(context).transparent,
          indicatorColor: ChhayaPalette.of(context).transparent,
          animationDuration: ChhayaMotion.duration(context, 300),
          selectedIndex: index, onDestinationSelected: onSelect, destinations: destinations),
      ]);
    }),
  );
}
