import 'package:flutter/material.dart';
import '../../../../core/theme/chaaya_theme.dart';

class TypingIndicator extends StatefulWidget {
  final String contactName;

  const TypingIndicator({
    super.key,
    required this.contactName,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1Animation;
  late Animation<double> _dot2Animation;
  late Animation<double> _dot3Animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();

    _dot1Animation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.4, curve: Curves.easeInOut)),
    );

    _dot2Animation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.2, 0.6, curve: Curves.easeInOut)),
    );

    _dot3Animation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.4, 0.8, curve: Curves.easeInOut)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: ChaayaTheme.glassDecoration(
              borderRadius: 16,
              color: ChaayaTheme.surfaceLight.withOpacity(0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _dot1Animation.value),
                      child: _buildDot(),
                    );
                  },
                ),
                const SizedBox(width: 4),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _dot2Animation.value),
                      child: _buildDot(),
                    );
                  },
                ),
                const SizedBox(width: 4),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _dot3Animation.value),
                      child: _buildDot(),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.contactName} is typing',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ChaayaTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: ChaayaTheme.textMuted,
        shape: BoxShape.circle,
      ),
    );
  }
}
