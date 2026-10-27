import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import '../engine/piece.dart';
import 'spell_vfx.dart';
import 'tokens.dart';

class BattleTargetArrival extends StatefulWidget {
  final Set<int> squares;
  final PieceColor viewer;
  const BattleTargetArrival({
    super.key,
    required this.squares,
    required this.viewer,
  });
  @override
  State<BattleTargetArrival> createState() => _BattleTargetArrivalState();
}

class _BattleTargetArrivalState extends State<BattleTargetArrival>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  bool get _enabled =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  void _finish() {
    _motion.stop();
    _motion.value = 1;
  }

  @override
  void didUpdateWidget(BattleTargetArrival old) {
    super.didUpdateWidget(old);
    if (!_enabled) {
      _finish();
    } else if (old.viewer != widget.viewer ||
        !setEquals(old.squares, widget.squares)) {
      _motion.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled) {
      _finish();
    } else if (_motion.value == 0) {
      _motion.forward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          builder:
              (_, _) => CustomPaint(
                key: const ValueKey('battle-target-arrival'),
                painter: BattleTargetPainter(
                  widget.squares,
                  widget.viewer,
                  _motion.value,
                ),
              ),
        ),
      ),
    ),
  );
}

class BattleTargetPainter extends CustomPainter {
  final Set<int> squares;
  final PieceColor viewer;
  final double progress;
  const BattleTargetPainter(this.squares, this.viewer, this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    if (!progress.isFinite || progress < 0 || progress >= 1 || size.isEmpty) {
      return;
    }
    final cell = size.shortestSide / 8;
    final t = Curves.easeOutCubic.transform(progress);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = BattleTokens.mana.withValues(
            alpha: .9 * (progress < .65 ? 1 : (1 - progress) / .35),
          );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final square in squares.where((s) => s >= 0 && s < 64).take(64)) {
      final center = battleSquareCenter(square, viewer, cell);
      final r = cell * (.47 - .1 * t), line = cell * .17;
      for (final x in [-1.0, 1.0]) {
        for (final y in [-1.0, 1.0]) {
          final corner = center + Offset(x * r, y * r);
          canvas.drawPath(
            Path()
              ..moveTo(corner.dx - x * line, corner.dy)
              ..lineTo(corner.dx, corner.dy)
              ..lineTo(corner.dx, corner.dy - y * line),
            paint,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BattleTargetPainter old) =>
      old.progress != progress ||
      old.viewer != viewer ||
      old.squares != squares;
}
