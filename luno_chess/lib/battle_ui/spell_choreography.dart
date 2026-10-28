import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../battle_v1/model.dart';

/// A finite secondary silhouette for each card. Receives presentation inputs
/// only: no board, deck, private knowledge, clocks or mutable gameplay state.
void paintBattleSpellChoreography(
  Canvas canvas,
  CardId card,
  double radius,
  double progress,
  Color color,
  double strength, {
  bool forwardUp = true,
}) {
  if (!radius.isFinite ||
      radius <= 0 ||
      !progress.isFinite ||
      progress <= 0 ||
      progress >= 1 ||
      !strength.isFinite ||
      strength <= 0 ||
      color.a <= 0) {
    return;
  }
  final r = radius;
  final t = progress;
  final opening = Curves.easeOutCubic.transform((t * 3).clamp(0.0, 1.0));
  final fade = math.sin(math.pi * t) * strength.clamp(0.0, 1.0) * color.a;
  final light = Color.lerp(color, Colors.white, .65)!;
  Paint line([double opacity = 1, double width = 1]) =>
      Paint()
        ..color = light.withValues(alpha: fade * opacity * .62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, r * .038 * width)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
  Offset polar(double angle, double length) =>
      Offset(math.cos(angle), math.sin(angle)) * r * length;
  void arc(double size, double angle, double sweep, [double opacity = 1]) =>
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * size),
        angle,
        sweep,
        false,
        line(opacity),
      );
  void glint(double angle, double distance, double size, [double opacity = 1]) {
    final center = polar(angle, distance);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle + t * .6);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * size)
        ..lineTo(r * size * .45, 0)
        ..lineTo(0, r * size)
        ..lineTo(-r * size * .45, 0)
        ..close(),
      Paint()..color = light.withValues(alpha: fade * opacity * .8),
    );
    canvas.restore();
  }

  void ticks(int count, double start, double distance, double length) {
    for (var i = 0; i < count; i++) {
      final a = start + i * math.pi * 2 / count;
      canvas.drawLine(
        polar(a, distance),
        polar(a, distance + length),
        line(.8),
      );
    }
  }

  void ribbon(double side, {bool curved = false}) {
    final sign = forwardUp ? -1.0 : 1.0;
    final path = Path()..moveTo(side * r * .42, sign * r * .38);
    if (curved) {
      path.quadraticBezierTo(
        side * r * 1.5,
        0,
        side * r * 1.05,
        sign * r * 1.32 * opening,
      );
    } else {
      path.lineTo(side * r * .42, sign * r * 1.4 * opening);
    }
    canvas.drawPath(path, line(.85, 1.5));
    for (var i = 0; i < 3; i++) {
      final u = (t * .7 + i / 3) % 1;
      glint(
        math.atan2(sign * (u * .9 + .4), side * .55),
        .6 + u * .75,
        .04,
        1 - u,
      );
    }
  }

  canvas.save();
  // Keep chess-piece centres readable, even when several accepted cues overlap.
  canvas.clipPath(
    Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromCircle(center: Offset.zero, radius: r * 1.75))
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: r * .34)),
  );
  switch (card) {
    case CardId.radar:
      for (var i = 0; i < 3; i++) {
        arc(.8 + i * .24, t * math.pi * 2 - i * .45, .95, 1 - i * .2);
        glint(t * math.pi * 2 + i * 2.1, 1.02 + i * .12, .08);
      }
    case CardId.prophecy:
      final points = [
        for (var i = 0; i < 5; i++)
          polar(
            -math.pi / 2 + i * math.pi * 2 / 5,
            1.12 + .12 * math.sin(t * 3 + i),
          ),
      ];
      for (var i = 0; i < points.length; i++) {
        canvas.drawLine(points[i], points[(i + 2) % points.length], line(.42));
        glint(-math.pi / 2 + i * math.pi * 2 / 5, 1.12, .07 + (i % 2) * .03);
      }
    case CardId.shelter:
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + .15;
        final b = (i + .82) * math.pi / 3 + .15;
        canvas.drawPath(
          Path()
            ..moveTo(polar(a, 1.16 * opening).dx, polar(a, 1.16 * opening).dy)
            ..lineTo(
              polar((a + b) / 2, 1.35 * opening).dx,
              polar((a + b) / 2, 1.35 * opening).dy,
            )
            ..lineTo(polar(b, 1.16 * opening).dx, polar(b, 1.16 * opening).dy),
          line(.75),
        );
      }
    case CardId.chain:
      for (var i = 0; i < 10; i++) {
        canvas.save();
        canvas.rotate(i * math.pi / 5 + t * .24);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, -r * (1.36 - opening * .3)),
            width: r * .32,
            height: r * (i.isEven ? .18 : .3),
          ),
          line(.9, 1.6),
        );
        canvas.restore();
      }
    case CardId.slow:
      ticks(12, -.1, 1.13, .12);
      arc(.95, -math.pi / 2, -t * math.pi * 1.4, .8);
      for (var i = 0; i < 4; i++) {
        glint(i * math.pi / 2 + t * .15, 1.4, .045);
      }
    case CardId.pawnDeviation:
      ribbon(-1, curved: true);
      ribbon(1, curved: true);
    case CardId.pawnAdvance:
      ribbon(-1);
      ribbon(1);
      ticks(3, -math.pi / 2, 1.5, .1);
    case CardId.lockedSquare:
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.rotate(i * math.pi / 2);
        final d = r * (1.45 - .25 * opening);
        canvas.drawPath(
          Path()
            ..moveTo(-d, -d * .45)
            ..lineTo(-d, -d)
            ..lineTo(-d * .45, -d),
          line(.9, 1.8),
        );
        canvas.restore();
      }
    case CardId.freeze:
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + .1;
        glint(a, 1.15 + t * .3, .15 * (1 - t * .5));
        final p = polar(a, 1.15);
        canvas.drawLine(p, p + polar(a + .65, .22), line(.65));
      }
    case CardId.purify:
      for (var i = 0; i < 8; i++) {
        final phase = (t + i / 8) % 1;
        glint(
          i * 2.4 - phase * .35,
          .7 + phase * .8,
          .05 + .05 * phase,
          math.sin(phase * math.pi),
        );
      }
      arc(1.08 + t * .3, -.8, 1.6, .45);
    case CardId.mine:
      // An accepted Mine cast arms a device; it must not imply a detonation.
      for (var i = 0; i < 8; i++) {
        arc(1.14, i * math.pi / 4, .35 * opening, i / 8 < t ? .95 : .2);
      }
      ticks(4, math.pi / 4, 1.35, .12);
    case CardId.breakSeal:
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.save();
        canvas.translate(
          polar(a, .85 + t * .65).dx,
          polar(a, .85 + t * .65).dy,
        );
        canvas.rotate(a + t * .6);
        canvas.drawPath(
          Path()
            ..moveTo(-r * .14, -r * .12)
            ..lineTo(r * .18, -r * .05)
            ..lineTo(r * .04, r * .14),
          line(.7),
        );
        canvas.restore();
      }
    case CardId.fog:
      for (var i = 0; i < 4; i++) {
        final y = r * (i.isEven ? -.6 : .6);
        final drift = math.sin(t * 4 + i) * r * .2;
        canvas.drawPath(
          Path()
            ..moveTo(-r * 1.35, y + drift)
            ..cubicTo(
              -r * .4,
              y - r * .7,
              r * .4,
              y + r * .7,
              r * 1.35,
              y - drift,
            ),
          line(.28 + i * .07, 1.8),
        );
      }
    case CardId.manaSabotage:
      for (var i = 0; i < 7; i++) {
        final life = (t + i / 7) % 1;
        glint(
          i * math.pi * 2 / 7 - t * .35,
          1.45 - life * .8,
          .1 * (1 - life * .5),
          math.sin(life * math.pi),
        );
      }
    case CardId.cardBlock:
      for (final sign in [-1, 1]) {
        final x = sign * r * (1.5 - .45 * opening);
        canvas.drawLine(Offset(x, -r * .9), Offset(x, r * .9), line(.8, 1.8));
        for (var i = -1; i <= 1; i++) {
          canvas.drawLine(
            Offset(x, i * r * .65),
            Offset(x - sign * r * .26, i * r * .65),
            line(.8),
          );
        }
      }
    case CardId.rookBend:
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.rotate(i * math.pi / 2);
        canvas.drawPath(
          Path()
            ..moveTo(-r * 1.25, -r * .45)
            ..lineTo(-r * 1.25, -r * 1.25 * opening)
            ..lineTo(-r * .45, -r * 1.25 * opening),
          line(.75),
        );
        canvas.restore();
      }
    case CardId.angryN:
      for (var i = 0; i < 4; i++) {
        glint(i * math.pi / 2 + math.pi / 4, .82 + t * .65, .18);
        arc(1.25, i * math.pi / 2 + t * .2, .4, .6);
      }
    case CardId.shadowPass:
      for (final sign in [-1, 1]) {
        canvas.save();
        canvas.translate(sign * r * 1.05, 0);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset.zero,
            width: r * .6,
            height: r * 1.8 * opening,
          ),
          sign * t * 3,
          math.pi * 1.65,
          false,
          line(.9, 1.5),
        );
        canvas.restore();
      }
    case CardId.huntVow:
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2;
        canvas.drawLine(
          polar(a, 1.6 - opening * .35),
          polar(a, .93),
          line(.9, 1.5),
        );
        glint(a + math.pi / 4, 1.1, .055);
      }
    case CardId.watchVow:
      for (var i = 0; i < 5; i++) {
        glint(i * math.pi * 2 / 5 + t * .35, 1.18, .06);
      }
      arc(1.4, -.65, 1.3, .65);
      arc(1.4, math.pi - .65, 1.3, .65);
    case CardId.echo:
      for (var i = 0; i < 4; i++) {
        final u = (t * .7 + i / 4) % 1;
        arc(.65 + u * .9, -.65, 1.3, (1 - u) * .8);
        arc(.65 + u * .9, math.pi - .65, 1.3, (1 - u) * .8);
      }
    case CardId.fateExchange:
      for (final sign in [-1, 1]) {
        arc(1.1, sign * t * 2 + (sign < 0 ? math.pi : 0), 1.7, .8);
        glint(sign * t * 2 + (sign < 0 ? math.pi : 0), 1.1, .12);
      }
    case CardId.shadowContract:
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + t * .2;
        final p = polar(a, 1.15);
        canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy)
            ..quadraticBezierTo(
              p.dx * .7,
              p.dy * .7,
              polar(a + .65, 1.15).dx,
              polar(a + .65, 1.15).dy,
            ),
          line(.7),
        );
      }
    case CardId.boardSeal:
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.rotate(i * math.pi / 2);
        final d = r * 1.28 * opening;
        canvas.drawPath(
          Path()
            ..moveTo(-d, -d * .3)
            ..lineTo(-d, -d)
            ..lineTo(-d * .3, -d),
          line(.75, 1.5),
        );
        glint(-math.pi / 4, 1.35, .07);
        canvas.restore();
      }
  }
  canvas.restore();
}
