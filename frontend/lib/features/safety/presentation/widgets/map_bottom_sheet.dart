import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../../../core/theme/chaaya_theme.dart';
import '../../data/location_safety_service.dart';

/// Apple Maps-style draggable bottom sheet with deep frosted glass
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
            child: Container(
              decoration: BoxDecoration(
                color: ChaayaTheme.surface.withValues(alpha: 0.88),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, -15),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Premium drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 16),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
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
                          icon: sharingLocation ? Icons.location_on_rounded : Icons.location_off_rounded,
                          label: 'Share',
                          isActive: sharingLocation,
                          activeColor: ChaayaTheme.safeGreen,
                          onTap: onToggleSharing,
                        ),
                        _QuickAction(
                          icon: Icons.visibility_off_rounded,
                          label: 'Private',
                          isActive: privateMode,
                          activeColor: ChaayaTheme.warningYellow,
                          onTap: onTogglePrivate,
                        ),
                        _QuickAction(
                          icon: Icons.add_location_alt_rounded,
                          label: 'Check In',
                          isActive: false,
                          onTap: onCheckIn,
                        ),
                        _QuickAction(
                          icon: Icons.groups_2_rounded,
                          label: 'Circles',
                          isActive: false,
                          onTap: onCircles,
                        ),
                        _QuickAction(
                          icon: Icons.place_rounded,
                          label: 'Places',
                          isActive: false,
                          onTap: onPlaces,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // SOS Button — premium 3D gradient
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        onSOS();
                      },
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          boxShadow: [
                            BoxShadow(
                              color: ChaayaTheme.sosRed.withValues(alpha: 0.45),
                              blurRadius: 25,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sos_rounded, color: Colors.white, size: 26),
                            SizedBox(width: 10),
                            Text(
                              'SOS — Send to Circle',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Section: Recent Check-ins
                  if (recentCheckIns.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text('RECENT CHECK-INS', style: TextStyle(
                        color: ChaayaTheme.textMuted.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      )),
                    ),
                    const SizedBox(height: 10),
                    ...recentCheckIns.take(5).map((c) => _CheckInTile(checkIn: c)),
                  ],
                  // History link
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: GestureDetector(
                      onTap: onHistory,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: ChaayaTheme.surfaceLight.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: const Row(children: [
                          Icon(Icons.history_rounded, color: ChaayaTheme.textMuted, size: 22),
                          SizedBox(width: 14),
                          Text('Location History', style: TextStyle(color: ChaayaTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w500)),
                          Spacer(),
                          Icon(Icons.chevron_right_rounded, color: ChaayaTheme.textMuted, size: 22),
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

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.isActive,
    this.activeColor,
    required this.onTap,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ?? ChaayaTheme.accent;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); HapticFeedback.lightImpact(); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.identity()..scale(_pressed ? 0.9 : 1.0),
        transformAlignment: Alignment.center,
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: widget.isActive ? color.withValues(alpha: 0.15) : ChaayaTheme.surfaceLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isActive ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
                width: widget.isActive ? 1.5 : 0.5,
              ),
              boxShadow: widget.isActive
                  ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 14)]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Icon(widget.icon, size: 24, color: widget.isActive ? color : ChaayaTheme.textMuted),
          ),
          const SizedBox(height: 7),
          Text(widget.label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isActive ? color : ChaayaTheme.textMuted)),
        ]),
      ),
    );
  }
}

class _CheckInTile extends StatelessWidget {
  final CheckIn checkIn;
  const _CheckInTile({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().difference(checkIn.timestamp);
    final timeStr = ago.inMinutes < 60 ? '${ago.inMinutes}m ago' : '${ago.inHours}h ago';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChaayaTheme.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ChaayaTheme.safeGreen.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: ChaayaTheme.safeGreen.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.check_rounded, color: ChaayaTheme.safeGreen, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(checkIn.username,
                  style: const TextStyle(color: ChaayaTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
              if (checkIn.statusMessage.isNotEmpty)
                Text(checkIn.statusMessage,
                    style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Text(timeStr, style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
