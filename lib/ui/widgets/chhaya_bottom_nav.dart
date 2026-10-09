import 'package:flutter/material.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';

/// ChhayaNavItem — One destination in [ChhayaBottomNav].
class ChhayaNavItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const ChhayaNavItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
  });
}

/// ChhayaBottomNav — 72px bottom destination bar.
///
/// Translucent [ChhayaColors.cream] background with a hairline
/// [ChhayaColors.borderMed] top border. The selected destination uses
/// [ChhayaColors.coralDeep] for icon and label; unselected destinations
/// use [ChhayaColors.inkMuted]. Every tappable is at least 44x44 and
/// fires [ChhayaHaptics.selection] on tap.
class ChhayaBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ChhayaNavItem> items;

  const ChhayaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: ChhayaColors.cream.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: ChhayaColors.borderMed, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('chhaya-nav-item-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  ChhayaHaptics.selection();
                  onTap(i);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        i == currentIndex
                            ? items[i].selectedIcon ?? items[i].icon
                            : items[i].icon,
                        size: 24,
                        color: i == currentIndex
                            ? ChhayaColors.coralDeep
                            : ChhayaColors.inkMuted,
                      ),
                      const SizedBox(height: ChhayaSpacing.space1),
                      Text(
                        items[i].label,
                        style: ChhayaTypography.labelSmall.copyWith(
                          color: i == currentIndex
                              ? ChhayaColors.coralDeep
                              : ChhayaColors.inkMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
