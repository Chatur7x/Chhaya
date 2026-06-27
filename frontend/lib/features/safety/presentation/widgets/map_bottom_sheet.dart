import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../../core/theme/chaaya_theme.dart';
import '../../data/location_safety_service.dart';

/// Apple Maps-style draggable bottom sheet with frosted glass
class MapBottomSheet extends StatelessWidget {
  final bool sharingLocation;
  final bool privateMode;
  final bool isDriving;
  final int battery;
  final List<CheckIn> recentCheckIns;
  final VoidCallback onToggleSharing;
  final VoidCallback onTogglePrivate;
  final VoidCallback onCheckIn;
  final VoidCallback onHistory;
  final VoidCallback onPlaces;
  final VoidCallback onCircles;
  final VoidCallback onSOS;

  const MapBottomSheet({
    super.key,
    required this.sharingLocation,
    required this.privateMode,
    required this.isDriving,
    required this.battery,
    required this.recentCheckIns,
    required this.onToggleSharing,
    required this.onTogglePrivate,
    required this.onCheckIn,
    required this.onHistory,
    required this.onPlaces,
    required this.onCircles,
    required this.onSOS,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.15,
      minChildSize: 0.10,
      maxChildSize: 0.65,
      snap: true,
      snapSizes: const [0.15, 0.4, 0.65],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: ChaayaTheme.surface.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: const Border(
                  top: BorderSide(color: ChaayaTheme.glassBorder, width: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 30,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ChaayaTheme.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Quick actions row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _QuickAction(
                          icon: sharingLocation ? Icons.location_on : Icons.location_off,
                          label: 'Share',
                          isActive: sharingLocation,
                          onTap: onToggleSharing,
                        ),
                        _QuickAction(
                          icon: Icons.visibility_off,
                          label: 'Private',
                          isActive: privateMode,
                          onTap: onTogglePrivate,
                        ),
                        _QuickAction(
                          icon: Icons.add_location_alt,
                          label: 'Check In',
                          isActive: false,
                          onTap: onCheckIn,
                        ),
                        _QuickAction(
                          icon: Icons.groups_2,
                          label: 'Circles',
                          isActive: false,
                          onTap: onCircles,
                        ),
                        _QuickAction(
                          icon: Icons.place,
                          label: 'Places',
                          isActive: false,
                          onTap: onPlaces,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // SOS Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: onSOS,
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ChaayaTheme.sosRed.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sos, color: Colors.white, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'SOS — Send to Circle',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Section: Recent Check-ins
                  if (recentCheckIns.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('RECENT CHECK-INS', style: TextStyle(
                        color: ChaayaTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      )),
                    ),
                    const SizedBox(height: 8),
                    ...recentCheckIns.take(5).map((c) => _CheckInTile(checkIn: c)),
                  ],
                  // Section: History link
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: GestureDetector(
                      onTap: onHistory,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
                        child: const Row(children: [
                          Icon(Icons.history, color: ChaayaTheme.textMuted, size: 20),
                          SizedBox(width: 12),
                          Text('Location History', style: ChaayaTheme.bodyMedium),
                          Spacer(),
                          Icon(Icons.chevron_right, color: ChaayaTheme.textMuted, size: 20),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive
                ? ChaayaTheme.accent.withValues(alpha: 0.15)
                : ChaayaTheme.surfaceLight,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive
                  ? ChaayaTheme.accent.withValues(alpha: 0.5)
                  : ChaayaTheme.glassBorder,
            ),
            boxShadow: isActive
                ? [BoxShadow(
                    color: ChaayaTheme.accent.withValues(alpha: 0.2),
                    blurRadius: 12,
                  )]
                : null,
          ),
          child: Icon(icon,
              size: 22,
              color: isActive ? ChaayaTheme.accent : ChaayaTheme.textMuted),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isActive ? ChaayaTheme.accent : ChaayaTheme.textMuted)),
      ]),
    );
  }
}

class _CheckInTile extends StatelessWidget {
  final CheckIn checkIn;
  const _CheckInTile({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().difference(checkIn.timestamp);
    final timeStr = ago.inMinutes < 60
        ? '${ago.inMinutes}m ago'
        : '${ago.inHours}h ago';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: ChaayaTheme.safeGreen.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: ChaayaTheme.safeGreen, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(checkIn.username,
                  style: const TextStyle(
                      color: ChaayaTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 14)),
              if (checkIn.statusMessage.isNotEmpty)
                Text(checkIn.statusMessage,
                    style: ChaayaTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Text(timeStr, style: ChaayaTheme.bodySmall),
      ]),
    );
  }
}
