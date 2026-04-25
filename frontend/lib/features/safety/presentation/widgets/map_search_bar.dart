import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../../core/theme/chaaya_theme.dart';

/// Apple Maps-style floating search bar with frosted glass
class MapSearchBar extends StatelessWidget {
  final int batteryLevel;
  final String channelType;
  final TextEditingController? controller;
  final VoidCallback? onTap;

  const MapSearchBar({
    super.key,
    required this.batteryLevel,
    this.channelType = 'ble',
    this.controller,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: ChaayaTheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ChaayaTheme.glassBorder, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            const Icon(Icons.search, color: ChaayaTheme.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onTap: onTap,
                style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search places, contacts...',
                  hintStyle: TextStyle(color: ChaayaTheme.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            ChaayaTheme.channelBadge(channelType),
            const SizedBox(width: 8),
            _BatteryPill(level: batteryLevel),
          ]),
        ),
      ),
    );
  }
}

class _BatteryPill extends StatelessWidget {
  final int level;
  const _BatteryPill({required this.level});

  @override
  Widget build(BuildContext context) {
    final isLow = level <= 20;
    final color = isLow ? ChaayaTheme.sosRed : ChaayaTheme.safeGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isLow ? Icons.battery_alert : Icons.battery_full,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text('$level%',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
