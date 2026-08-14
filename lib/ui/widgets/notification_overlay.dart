import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/avatar_widget.dart';






class NotificationOverlay extends StatefulWidget {
  final String senderName;
  final String messagePreview;
  final String? avatarUrl;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const NotificationOverlay({
    super.key,
    required this.senderName,
    required this.messagePreview,
    this.avatarUrl,
    this.onTap,
    this.onDismiss,
  });


  static GlobalKey<_NotificationOverlayState>? _activeKey;


  static void show(
    BuildContext context, {
    required String senderName,
    required String messagePreview,
    String? avatarUrl,
    VoidCallback? onTap,
  }) {

    dismissActive();

    final key = GlobalKey<_NotificationOverlayState>();
    _activeKey = key;

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => NotificationOverlay(
        key: key,
        senderName: senderName,
        messagePreview: messagePreview,
        avatarUrl: avatarUrl,
        onTap: () {
          onTap?.call();
          key.currentState?._dismiss();
        },
        onDismiss: () {
          try {
            overlayEntry.remove();
          } catch (_) {

          }
          if (_activeKey == key) {
            _activeKey = null;
          }
        },
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }


  static void dismissActive() {
    if (_activeKey != null) {
      final state = _activeKey!.currentState;
      if (state != null) {
        state.widget.onDismiss?.call();
      }
      _activeKey = null;
    }
  }

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;
  double _dragOffsetY = 0.0;


  static const double _bannerHeight = 90.0;
  static const double _borderRadius = 38.0;
  static const double _blurSigma = ChhayaBlur.notification;
  static const double _swipeVelocityThreshold = 200.0;
  static const Duration _autoDismissDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: ChhayaAnimation.normal,
      reverseDuration: ChhayaAnimation.fast,
    );


    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: ChhayaAnimation.springCurve,
      reverseCurve: ChhayaAnimation.dismissCurve,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ));


    _controller.forward().then((_) {

      ChhayaHaptics.light();

      _autoDismissTimer = Timer(_autoDismissDuration, () {
        _dismiss();
      });
    });
  }


  void _dismiss() {
    _autoDismissTimer?.cancel();
    if (mounted) {
      _controller.reverse().then((_) {
        widget.onDismiss?.call();
      });
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;

    return Positioned(
      top: topPadding + ChhayaSpacing.sm,
      left: ChhayaSpacing.sm,
      right: ChhayaSpacing.sm,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          setState(() {

            _dragOffsetY += details.primaryDelta!;
            if (_dragOffsetY > 0.0) _dragOffsetY = 0.0;
          });
        },
        onVerticalDragEnd: (details) {

          if (_dragOffsetY < -20.0 ||
              details.primaryVelocity! < -_swipeVelocityThreshold) {
            _dismiss();
          } else {

            setState(() {
              _dragOffsetY = 0.0;
            });
          }
        },
        onTap: () {

          widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: _dragOffsetY == 0.0
              ? ChhayaAnimation.fast
              : Duration.zero,
          curve: ChhayaAnimation.springCurve,
          transform: Matrix4.translationValues(0, _dragOffsetY, 0),
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildBanner(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(BuildContext context) {
    return Container(
      height: _bannerHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_borderRadius),
        boxShadow: ChhayaShadows.notification,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ChhayaSpacing.lg,
              vertical: ChhayaSpacing.md,
            ),
            decoration: BoxDecoration(
              color: ChhayaColors.secondaryBackground.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(_borderRadius),
              border: Border.all(
                color: ChhayaColors.labelPrimary.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [

                AvatarWidget(
                  name: widget.senderName,
                  imageUrl: widget.avatarUrl,
                  size: 42,
                ),
                const SizedBox(width: ChhayaSpacing.md),

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.senderName,
                              style: ChhayaTypography.headline.copyWith(
                                color: ChhayaColors.labelPrimary,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: ChhayaSpacing.xs),
                          Text(
                            'now',
                            style: ChhayaTypography.caption1.copyWith(
                              color: ChhayaColors.labelTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ChhayaSpacing.xs),
                      Text(
                        widget.messagePreview,
                        style: ChhayaTypography.subheadline.copyWith(
                          color: ChhayaColors.labelSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
