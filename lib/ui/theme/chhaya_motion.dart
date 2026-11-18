import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'chhaya_theme.dart';

/// Shared native-motion policy: every custom transition has a static alternative.
class ChhayaMotion {
  static bool reduced(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final features = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (media?.disableAnimations ?? features.disableAnimations) ||
      (media?.accessibleNavigation ?? features.accessibleNavigation);
  }
  static Duration duration(BuildContext context, [int milliseconds = 300]) =>
    reduced(context) ? Duration.zero : Duration(milliseconds: milliseconds);

  static Future<T?> sheet<T>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) =>
    showModalBottomSheet<T>(context: context, useSafeArea: true, isScrollControlled: true,
      isDismissible: dismissible, enableDrag: dismissible, showDragHandle: dismissible,
      constraints: const BoxConstraints(maxWidth: 640),
      sheetAnimationStyle: AnimationStyle(duration: duration(context, 360),
        reverseDuration: duration(context, 250)),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86),
        child: SingleChildScrollView(child: builder(ctx))),
    );
}

/// Keeps the iOS interactive back gesture and platform-specific route semantics.
class ChhayaCupertinoRoute<T> extends CupertinoPageRoute<T> {
  ChhayaCupertinoRoute({required super.builder, super.settings, super.fullscreenDialog});
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) => ChhayaMotion.reduced(context)
    ? child : super.buildTransitions(context, animation, secondaryAnimation, child);
}

/// Appears once when newly sent/received content joins a conversation.
class MessageEntrance extends StatefulWidget {
  const MessageEntrance({super.key, required this.animate, required this.child});
  final bool animate;
  final Widget child;
  @override
  State<MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<MessageEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 360), value: 1);
  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.animate && !ChhayaMotion.reduced(context)) _controller.forward(from: 0);
    }
    if (ChhayaMotion.reduced(context)) _controller.value = 1;
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _controller,
    child: widget.child, builder: (_, child) {
      final t = Curves.easeOutBack.transform(_controller.value);
      return Opacity(opacity: _controller.value.clamp(0.0, 1.0), child: Transform.translate(
        offset: Offset(0, (1-t)*10), child: Transform.scale(scale: 0.96 + t*0.04, child: child)));
    });
}

/// A thresholded reply gesture follows the finger, then settles using a spring.
class SwipeReply extends StatefulWidget {
  const SwipeReply({super.key, required this.onReply, required this.child});
  final VoidCallback onReply;
  final Widget child;
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(vsync: this);
  double _drag = 0;
  bool _armed = false;
  double get _direction => Directionality.of(context) == TextDirection.rtl ? -1 : 1;
  void _reset() {
    if (ChhayaMotion.reduced(context)) { _offset.value = 0; return; }
    _offset.animateWith(SpringSimulation(ChhayaSprings.standard, _offset.value, 0, 0));
  }
  @override
  void dispose() { _offset.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: (_) { _offset.stop(); _drag=0; _armed=false; },
    onHorizontalDragUpdate: (details) {
      _drag = (_drag + details.delta.dx * _direction).clamp(0.0, 180.0);
      _offset.value = _direction * (_drag <= 64 ? _drag : 64 + (_drag-64)*0.25);
      if (_drag >= 64 && !_armed) { _armed=true; ChhayaHaptics.selection(); }
      if (_drag < 64) _armed=false;
    },
    onHorizontalDragCancel: _reset,
    onHorizontalDragEnd: (_) { if (_armed) widget.onReply(); _reset(); },
    child: AnimatedBuilder(animation: _offset, child: widget.child,
      builder: (_, child) => Transform.translate(offset: Offset(ChhayaMotion.reduced(context) ? 0 : _offset.value, 0), child: child)),
  );
}
