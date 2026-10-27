import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../theme/luno_theme.dart';
import '../theme/luno_visual_assets.dart';

DecorationImage lunoFace(
  String asset, {
  bool button = false,
  double opacity = 1,
  Rect? centerSlice,
}) => DecorationImage(
  image: AssetImage(asset),
  centerSlice:
      centerSlice ??
      (button ? LunoVisualAssets.buttonSlice : LunoVisualAssets.panelSlice),
  fit: BoxFit.fill,
  opacity: opacity,
  filterQuality: FilterQuality.medium,
);

/// A one-shot entrance; it never owns a repeating ticker or changes layout size.
class LunoEntrance extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const LunoEntrance({
    super.key,
    required this.child,
    this.duration = LunoMotion.panelEnter,
  });
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: LunoMotion.screenCurve,
      child: child,
      builder:
          (_, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - value)),
              child: child,
            ),
          ),
    );
  }
}

/// Visual press feedback only. Native controls continue to own activation.
class LunoPressFeedback extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;
  const LunoPressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = .985,
  });
  @override
  State<LunoPressFeedback> createState() => _LunoPressFeedbackState();
}

class _LunoPressFeedbackState extends State<LunoPressFeedback>
    with WidgetsBindingObserver {
  bool pressed = false;
  bool _foreground = true, _dragged = false;
  int? _pointer;
  Offset? _origin;

  bool get _enabled =>
      widget.enabled && _foreground && TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
  }

  void update(bool value) {
    final next = value && _enabled;
    if (mounted && next != pressed) setState(() => pressed = next);
  }

  void _reset() {
    _pointer = null;
    _origin = null;
    _dragged = false;
    pressed = false;
  }

  void _down(PointerDownEvent event) {
    if (!_enabled ||
        _pointer != null ||
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _pointer = event.pointer;
    _origin = event.position;
    _dragged = false;
    update(true);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _dragged || _origin == null) return;
    if ((event.position - _origin!).distance > kTouchSlop) {
      _dragged = true;
      update(false);
    }
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _origin = null;
    _dragged = false;
    update(false);
  }

  @override
  void didUpdateWidget(LunoPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled || MediaQuery.disableAnimationsOf(context)) _reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_reset);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: AnimatedScale(
      scale:
          pressed && !MediaQuery.disableAnimationsOf(context)
              ? widget.pressedScale
              : 1,
      duration: LunoMotion.adaptive(
        context,
        pressed ? LunoMotion.pressDown : LunoMotion.press,
      ),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class LunoRewardArt extends StatelessWidget {
  final Widget child;
  final double size;
  const LunoRewardArt({super.key, required this.child, this.size = 144});
  @override
  Widget build(BuildContext context) {
    final artwork = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            child: IgnorePointer(
              child: Image.asset(
                LunoVisualAssets.reward,
                width: size,
                height: size,
                cacheWidth: 256,
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: .78,
            heightFactor: .78,
            child: child,
          ),
        ],
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return artwork;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: LunoMotion.reward,
      curve: LunoMotion.screenCurve,
      child: artwork,
      builder:
          (_, value, child) => Opacity(
            opacity: .4 + .6 * value,
            child: Transform.scale(scale: .94 + .06 * value, child: child),
          ),
    );
  }
}
