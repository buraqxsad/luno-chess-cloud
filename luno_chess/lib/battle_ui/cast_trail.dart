import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import 'card_motion.dart';
import 'effect_timing.dart';

/// Shares the real card's measured path; never invents a second projectile.
class BattleCastTrailPainter extends CustomPainter {
  final CardId card;
  final Offset from, to;
  final double progress;
  final Color color;
  const BattleCastTrailPainter({
    required this.card,
    required this.from,
    required this.to,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!progress.isFinite ||
        progress <= 0 ||
        progress >= battleCastCardFadeEndFraction ||
        !from.dx.isFinite ||
        !from.dy.isFinite ||
        !to.dx.isFinite ||
        !to.dy.isFinite ||
        size.isEmpty) {
      return;
    }
    final t = battleTravelProgress(progress);
    final fade =
        progress <= battleCastArrivalFraction
            ? math.min(1.0, progress / .045)
            : 1 -
                (progress - battleCastArrivalFraction) /
                    (battleCastCardFadeEndFraction - battleCastArrivalFraction);
    final light = Color.lerp(color, Colors.white, .8)!;
    Offset point(double step) => battleCardFlightPoint(card, from, to, step);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 11; i >= 0; i--) {
      final end = (t - i * .018).clamp(0.0, 1.0);
      final start = (end - .022).clamp(0.0, 1.0);
      if (end == start) continue;
      final tail = 1 - i / 12;
      final path =
          Path()
            ..moveTo(point(start).dx, point(start).dy)
            ..lineTo(point(end).dx, point(end).dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .15 * tail * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13 * tail + 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .8 * tail * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * tail + 1
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = light.withValues(alpha: .9 * tail * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 * tail
          ..strokeCap = StrokeCap.round,
      );
    }
    final originFade = (1 - progress / .24).clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(center: from, width: 52 + t * 16, height: 16 + t * 5),
      Paint()
        ..color = color.withValues(alpha: .65 * originFade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final head = point(t);
    for (var i = 0; i < 6; i++) {
      final step = (t - .04 - i * .026).clamp(0.0, 1.0);
      if (step == 0) continue;
      final angle = i * 2.4 + card.index * .2;
      final center =
          point(step) +
          Offset(math.cos(angle), math.sin(angle)) * (5 + i * 1.4);
      canvas.drawCircle(
        center,
        1.8 - i * .18,
        Paint()..color = light.withValues(alpha: (.8 - i * .1) * fade),
      );
    }
    if (progress >= battleCastArrivalFraction) {
      final impact =
          (progress - battleCastArrivalFraction) /
          (battleCastCardFadeEndFraction - battleCastArrivalFraction);
      canvas.drawOval(
        Rect.fromCenter(
          center: head,
          width: 18 + impact * 38,
          height: 8 + impact * 18,
        ),
        Paint()
          ..color = light.withValues(alpha: .8 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * fade,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BattleCastTrailPainter old) =>
      old.card != card ||
      old.from != from ||
      old.to != to ||
      old.progress != progress ||
      old.color != color;
}
