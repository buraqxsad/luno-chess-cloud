import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';

/// Event-driven material layers beneath the readable spell outline.
void paintBattleSpellMaterial(
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
      progress < 0 ||
      progress > 1 ||
      !strength.isFinite ||
      strength <= 0) {
    return;
  }
  final t = progress;
  final r = radius;
  final alpha = strength.clamp(0.0, 1.0);
  final open = Curves.easeOutBack.transform((t * 3.2).clamp(0, 1));
  final settle = math.sin(t * math.pi);
  final bright = Color.lerp(color, Colors.white, .76)!;
  final dark = Color.lerp(color, const Color(0xff10212c), .68)!;
  final bounds = Rect.fromCircle(center: Offset.zero, radius: r * 1.45);

  Paint stroke(double opacity, double width) =>
      Paint()
        ..color = bright.withValues(alpha: opacity * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, r * width)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  void body(Path path, {double opacity = .46, double depth = .07}) {
    canvas.save();
    canvas.translate(r * depth, r * depth * 1.6);
    canvas.drawPath(path, Paint()..color = dark.withValues(alpha: .5 * alpha));
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bright.withValues(alpha: opacity * alpha),
            color.withValues(alpha: opacity * alpha),
            dark.withValues(alpha: opacity * alpha),
          ],
          stops: const [0, .42, 1],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.clipPath(path);
    final sheenX = r * (-1.9 + t * 3.8);
    final sheen = Rect.fromLTWH(sheenX - r * .25, -r * 1.5, r * .5, r * 3);
    canvas.drawRect(
      sheen,
      Paint()
        ..shader = LinearGradient(
          colors: [
            bright.withValues(alpha: 0),
            bright.withValues(alpha: .5 * alpha),
            bright.withValues(alpha: 0),
          ],
        ).createShader(sheen),
    );
    canvas.restore();
    canvas.drawPath(path, stroke(.72, .035));
  }

  void oval(Offset center, double w, double h, {double opacity = .4}) => body(
    Path()..addOval(Rect.fromCenter(center: center, width: w, height: h)),
    opacity: opacity,
  );
  void cardFace(double x, double angle) {
    canvas.save();
    canvas.translate(x, -r * .08 * settle);
    canvas.rotate(angle);
    body(
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: r * .65,
            height: r * 1.05,
          ),
          Radius.circular(r * .09),
        ),
      ),
    );
    canvas.drawLine(
      Offset(-r * .18, -r * .25),
      Offset(r * .18, r * .25),
      stroke(.8, .04),
    );
    canvas.restore();
  }

  void ribbon(Offset from, Offset to, double width) {
    final direction = to - from;
    final normal = Offset(-direction.dy, direction.dx) / direction.distance;
    final neck = to - direction * .25;
    body(
      Path()
        ..moveTo(
          (from + normal * width * .32).dx,
          (from + normal * width * .32).dy,
        )
        ..lineTo(
          (neck + normal * width * .32).dx,
          (neck + normal * width * .32).dy,
        )
        ..lineTo((neck + normal * width).dx, (neck + normal * width).dy)
        ..lineTo(to.dx, to.dy)
        ..lineTo((neck - normal * width).dx, (neck - normal * width).dy)
        ..lineTo(
          (neck - normal * width * .32).dx,
          (neck - normal * width * .32).dy,
        )
        ..lineTo(
          (from - normal * width * .32).dx,
          (from - normal * width * .32).dy,
        )
        ..close(),
      opacity: .36,
    );
  }

  canvas.save();
  canvas.scale(.78 + .22 * open);
  switch (card) {
    case CardId.radar:
      canvas.save();
      canvas.rotate(t * math.pi * 2);
      final sweep =
          Path()
            ..moveTo(0, 0)
            ..arcTo(
              Rect.fromCircle(center: Offset.zero, radius: r * 1.05),
              -.8,
              1.05,
              false,
            )
            ..close();
      canvas.drawPath(
        sweep,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: .38 * alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(bounds),
      );
      canvas.restore();
      for (var i = 0; i < 3; i++) {
        final angle = i * 2.1 + .4;
        oval(
          Offset(math.cos(angle), math.sin(angle)) * r * .73,
          r * .13,
          r * .13,
          opacity: .8,
        );
      }
    case CardId.prophecy:
      final diamond =
          Path()
            ..moveTo(0, -r * .94)
            ..lineTo(r * .48, 0)
            ..lineTo(0, r * .94)
            ..lineTo(-r * .48, 0)
            ..close();
      body(diamond, opacity: .5);
      canvas.drawPath(
        Path()
          ..moveTo(0, -r * .94)
          ..lineTo(-r * .12, 0)
          ..lineTo(0, r * .94)
          ..lineTo(r * .48, 0)
          ..close(),
        Paint()..color = bright.withValues(alpha: .24 * alpha),
      );
    case CardId.shelter:
      body(
        Path()
          ..moveTo(0, -r)
          ..lineTo(r * .76, -r * .63)
          ..quadraticBezierTo(r * .8, r * .45, 0, r)
          ..quadraticBezierTo(-r * .8, r * .45, -r * .76, -r * .63)
          ..close(),
        opacity: .39,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, -r * .78)
          ..lineTo(0, r * .63),
        stroke(.85, .06),
      );
    case CardId.chain:
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4 + t * .55;
        canvas.save();
        canvas.rotate(angle);
        final y = -r * (1.2 - open * .4);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, y), width: r * .5, height: r * .28),
          Paint()
            ..color = dark.withValues(alpha: .8 * alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .13,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(0, y - r * .025),
            width: r * .5,
            height: r * .28,
          ),
          math.pi,
          math.pi,
          false,
          stroke(.95, .06),
        );
        canvas.restore();
      }
    case CardId.slow:
      body(
        Path()
          ..moveTo(-r * .48, -r * .8)
          ..lineTo(r * .48, -r * .8)
          ..quadraticBezierTo(r * .46, -r * .3, r * .08, 0)
          ..quadraticBezierTo(r * .46, r * .3, r * .48, r * .8)
          ..lineTo(-r * .48, r * .8)
          ..quadraticBezierTo(-r * .46, r * .3, -r * .08, 0)
          ..quadraticBezierTo(-r * .46, -r * .3, -r * .48, -r * .8)
          ..close(),
        opacity: .25,
      );
      body(
        Path()
          ..moveTo(-r * .32, r * .66)
          ..lineTo(0, r * (.12 + .3 * t))
          ..lineTo(r * .32, r * .66)
          ..close(),
        opacity: .7,
        depth: 0,
      );
    case CardId.pawnDeviation:
      canvas.scale(1, forwardUp ? 1 : -1);
      ribbon(Offset(0, r * .65), Offset(-r * .8, -r * .65), r * .24);
      ribbon(Offset(0, r * .65), Offset(r * .8, -r * .65), r * .24);
    case CardId.pawnAdvance:
      canvas.scale(1, forwardUp ? 1 : -1);
      ribbon(Offset(0, r * .85), Offset(0, -r), r * .4);
    case CardId.lockedSquare:
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(0, -r * .35),
          width: r * .66,
          height: r * .8,
        ),
        math.pi,
        math.pi,
        false,
        stroke(.9, .13),
      );
      body(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(0, r * .2),
              width: r * 1.04,
              height: r * .83,
            ),
            Radius.circular(r * .12),
          ),
        ),
      );
    case CardId.freeze:
      for (var i = 0; i < 7; i++) {
        canvas.save();
        canvas.rotate(i * math.pi * 2 / 7 + .15);
        final length = r * (.72 + (i % 3) * .16) * open;
        body(
          Path()
            ..moveTo(0, -length)
            ..lineTo(r * .16, -r * .3)
            ..lineTo(0, -r * .15)
            ..lineTo(-r * .16, -r * .3)
            ..close(),
          opacity: .55,
          depth: .025,
        );
        canvas.drawLine(
          Offset(0, -length),
          Offset(0, -r * .2),
          stroke(.95, .025),
        );
        canvas.restore();
      }
    case CardId.purify:
      for (var i = 0; i < 5; i++) {
        final phase = (t + i / 5) % 1;
        final x = math.sin(i * 2.4) * r * .65;
        oval(
          Offset(x, r * (.8 - phase * 1.8)),
          r * .11,
          r * .2,
          opacity: .65 * math.sin(phase * math.pi),
        );
      }
    case CardId.mine:
      // Arming a mine is not a detonation: seated plate and a charging core.
      oval(Offset(0, r * .2), r * 1.45, r * .6, opacity: .65);
      oval(Offset(0, r * .02), r * .8, r * .65, opacity: .65);
      canvas.drawCircle(
        Offset(0, -r * .1),
        r * (.11 + .04 * settle),
        Paint()..color = bright.withValues(alpha: .9 * alpha),
      );
    case CardId.breakSeal:
      for (final sign in [-1, 1]) {
        canvas.save();
        canvas.translate(sign * r * t * .3, r * t * .15);
        canvas.rotate(sign * t * .2);
        body(
          Path()
            ..moveTo(sign * r * .75, -r * .75)
            ..lineTo(0, -r * .75)
            ..lineTo(sign * r * .16, -r * .2)
            ..lineTo(-sign * r * .12, r * .25)
            ..lineTo(sign * r * .12, r * .75)
            ..lineTo(sign * r * .75, r * .75)
            ..close(),
          opacity: .4,
        );
        canvas.restore();
      }
    case CardId.fog:
      for (var i = 0; i < 5; i++) {
        final x = r * ((i - 2) * .38 + math.sin(t * 4 + i) * .1);
        final y = r * (math.cos(i * 1.7) * .3 - t * .2);
        final mist = Rect.fromCenter(
          center: Offset(x, y),
          width: r * 1.1,
          height: r * .72,
        );
        canvas.drawOval(
          mist,
          Paint()
            ..shader = RadialGradient(
              colors: [
                bright.withValues(alpha: .18 * alpha),
                color.withValues(alpha: 0),
              ],
            ).createShader(mist),
        );
      }
    case CardId.manaSabotage:
      for (final sign in [-1, 1]) {
        canvas.save();
        canvas.translate(sign * r * (.12 + t * .3), r * t * .25);
        canvas.rotate(sign * t * .3);
        body(
          Path()
            ..moveTo(0, -r * .8)
            ..quadraticBezierTo(-r * .7, r * .45, 0, r * .6)
            ..quadraticBezierTo(r * .7, r * .45, 0, -r * .8)
            ..close(),
          opacity: .34,
        );
        canvas.restore();
      }
    case CardId.cardBlock:
      cardFace(-r * .22, -.18);
      cardFace(r * .22, .18);
      ribbon(Offset(-r * .65, r * .65), Offset(r * .65, -r * .65), r * .14);
    case CardId.rookBend:
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.rotate(math.pi / 4 + i * math.pi / 2);
        ribbon(Offset(0, -r * .2), Offset(0, -r * 1.05), r * .24);
        canvas.restore();
      }
    case CardId.angryN:
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.rotate(i * math.pi / 2);
        ribbon(Offset(0, -r * .28), Offset(0, -r * (1 + settle * .12)), r * .3);
        canvas.restore();
      }
    case CardId.shadowPass:
      for (final sign in [-1, 1]) {
        final rect = Rect.fromCenter(
          center: Offset(sign * r * .68, 0),
          width: r * .5,
          height: r * 1.65,
        );
        canvas.drawOval(
          rect,
          Paint()
            ..shader = RadialGradient(
              colors: [
                dark.withValues(alpha: .8 * alpha),
                color.withValues(alpha: .16 * alpha),
              ],
            ).createShader(rect),
        );
        canvas.drawArc(
          rect,
          sign * t * 3,
          math.pi * 1.5,
          false,
          stroke(.85, .08),
        );
      }
    case CardId.huntVow:
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.rotate(i * math.pi / 2);
        body(
          Path()
            ..moveTo(-r * .15, -r * 1.04)
            ..lineTo(r * .15, -r * 1.04)
            ..lineTo(0, -r * .66)
            ..close(),
          opacity: .7,
        );
        canvas.restore();
      }
    case CardId.watchVow:
      body(
        Path()
          ..moveTo(-r * .9, 0)
          ..quadraticBezierTo(0, -r * .85, r * .9, 0)
          ..quadraticBezierTo(0, r * .85, -r * .9, 0)
          ..close(),
        opacity: .25,
      );
      oval(
        Offset(math.sin(t * math.pi * 2) * r * .13, 0),
        r * .5,
        r * .5,
        opacity: .75,
      );
    case CardId.echo:
      for (var i = 0; i < 3; i++) {
        final phase = (t * .7 + i / 3) % 1;
        final rect = Rect.fromCircle(
          center: Offset.zero,
          radius: r * (.3 + phase),
        );
        canvas.drawArc(rect, -.9, 1.8, false, stroke((1 - phase) * .8, .1));
        canvas.drawArc(
          rect,
          math.pi - .9,
          1.8,
          false,
          stroke((1 - phase) * .8, .1),
        );
      }
    case CardId.fateExchange:
      for (var i = -1; i <= 1; i++) {
        cardFace(i * r * (.42 - t * .15), i * (.28 + settle * .1));
      }
    case CardId.shadowContract:
      cardFace(-r * (.48 - t * .16), -.18);
      cardFace(r * (.48 - t * .16), .18);
      canvas.drawPath(
        Path()
          ..moveTo(-r * .4, 0)
          ..quadraticBezierTo(0, -r * (.3 + settle * .2), r * .4, 0),
        stroke(.9, .07),
      );
    case CardId.boardSeal:
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: r * 1.65,
        height: r * 1.65,
      );
      body(
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r * .14))),
        opacity: .2,
        depth: .1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(r * .13),
          Radius.circular(r * .08),
        ),
        stroke(.65, .04),
      );
  }
  canvas.restore();
}
