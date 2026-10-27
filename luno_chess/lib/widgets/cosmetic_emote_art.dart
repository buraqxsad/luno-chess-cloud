import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/luno_assets.dart';

typedef CosmeticEmotePose = ({double x, double y, double angle, double scale});

Duration cosmeticEmoteDuration(String id) => Duration(
  milliseconds: switch (id) {
    'smile' => 540,
    'heart' => 700,
    'laugh' => 620,
    'cry' => 720,
    'angry' => 500,
    'think' => 760,
    'fire' => 740,
    'star' => 780,
    'thunder' => 520,
    'bomb' => 660,
    'strat' => 800,
    'trophy' => 900,
    'crown' => 980,
    'rainbow' => 1100,
    _ => 0,
  },
);

/// Translation is a fraction of the fixed square, never a board coordinate.
CosmeticEmotePose cosmeticEmotePose(String id, double progress) {
  final t = progress.clamp(0.0, 1.0);
  if (t == 1 || cosmeticEmoteDuration(id) == Duration.zero) {
    return (x: 0, y: 0, angle: 0, scale: 1);
  }
  final arc = math.sin(math.pi * t);
  final settle = Curves.easeOutCubic.transform(t);
  final fade = (1 - t) * (1 - t);
  final base = .84 + .16 * settle;
  return switch (id) {
    'smile' => (
      x: 0,
      y: -.045 * math.sin(2 * math.pi * t) * (1 - t),
      angle: .045 * arc,
      scale: base,
    ),
    'heart' => (
      x: 0,
      y: -.018 * arc,
      angle: 0,
      scale: base + .055 * math.sin(3 * math.pi * t) * arc,
    ),
    'laugh' => (
      x: .014 * math.sin(4 * math.pi * t) * arc,
      y: -.03 * math.sin(4 * math.pi * t) * arc,
      angle: .09 * math.sin(4 * math.pi * t) * arc,
      scale: base,
    ),
    'cry' => (
      x: .025 * math.sin(2 * math.pi * t) * arc,
      y: .035 * arc,
      angle: -.075 * arc,
      scale: base - .025 * arc,
    ),
    'angry' => (
      x: .035 * math.sin(8 * math.pi * t) * fade,
      y: 0,
      angle: -.05 * math.sin(6 * math.pi * t) * fade,
      scale: base + .03 * arc,
    ),
    'think' => (
      x: -.018 * arc,
      y: -.014 * arc,
      angle: -.12 * math.sin(math.pi * math.sqrt(t)),
      scale: base,
    ),
    'fire' => (
      x: .012 * math.sin(10 * math.pi * t) * arc,
      y: -.055 * arc,
      angle: .055 * math.sin(6 * math.pi * t) * arc,
      scale: base + .025 * arc,
    ),
    'star' => (
      x: .025 * math.sin(2 * math.pi * t) * arc,
      y: -.035 * arc,
      angle: .16 * math.sin(2 * math.pi * t) * arc,
      scale: base + .035 * arc,
    ),
    'thunder' => (
      x: .045 * math.sin(6 * math.pi * t) * fade,
      y: -.02 * math.sin(4 * math.pi * t) * fade,
      angle: -.09 * math.sin(6 * math.pi * t) * fade,
      scale: base,
    ),
    'bomb' => (
      x: .025 * math.sin(4 * math.pi * t) * arc,
      y: .045 * math.sin(2 * math.pi * t) * arc,
      angle: .12 * math.sin(2 * math.pi * t) * arc,
      scale: base - .035 * arc,
    ),
    'strat' => (
      x: .035 * math.sin(2 * math.pi * t) * arc,
      y: -.02 * math.sin(3 * math.pi * t) * arc,
      angle: 0,
      scale: base,
    ),
    'trophy' => (
      x: 0,
      y: -.06 * math.sin(math.pi * math.sqrt(t)),
      angle: .035 * math.sin(2 * math.pi * t) * arc,
      scale: base + .045 * arc,
    ),
    'crown' => (
      x: 0,
      y: -.04 * arc,
      angle: -.1 * math.sin(2 * math.pi * t) * fade,
      scale: base + .025 * math.sin(3 * math.pi * t) * arc,
    ),
    'rainbow' => (
      x: .04 * math.sin(2 * math.pi * t) * arc,
      y: -.05 * arc,
      angle: -.08 * math.sin(2 * math.pi * t) * arc,
      scale: base + .04 * arc,
    ),
    _ => (x: 0, y: 0, angle: 0, scale: 1),
  };
}

/// One expression entrance. Replaying requires a new presentation key.
/// Art is silent: accepted-event/reward owners explicitly request audio.
class CosmeticEmoteArt extends StatefulWidget {
  const CosmeticEmoteArt({super.key, required this.id, this.size = 144})
    : assert(size > 0 && size < double.infinity);
  final String id;
  final double size;
  @override
  State<CosmeticEmoteArt> createState() => _CosmeticEmoteArtState();
}

class _CosmeticEmoteArtState extends State<CosmeticEmoteArt>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _started = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: cosmeticEmoteDuration(widget.id),
    );
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  void _syncMotion() {
    final staticMotion =
        !_foreground ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        _controller.duration == Duration.zero;
    if (staticMotion) {
      _controller.stop();
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant CosmeticEmoteArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _controller.duration = cosmeticEmoteDuration(widget.id);
      _started = false;
      _syncMotion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _controller.stop();
      _controller.value = 1;
      _started = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        child: Center(
          child: LunoArt(
            LunoAssets.emoji(widget.id),
            width: widget.size * .84,
            height: widget.size * .84,
          ),
        ),
        builder: (_, child) {
          final pose = cosmeticEmotePose(widget.id, _controller.value);
          return Transform.translate(
            offset: Offset(pose.x * widget.size, pose.y * widget.size),
            child: Transform.rotate(
              angle: pose.angle,
              child: Transform.scale(scale: pose.scale, child: child),
            ),
          );
        },
      ),
    ),
  );
}
