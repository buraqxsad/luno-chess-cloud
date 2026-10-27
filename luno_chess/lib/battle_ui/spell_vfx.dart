import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import 'effects.dart';
import 'card_motion.dart';
import 'effect_timing.dart';
import 'spell_material.dart';

double battleSpellEnvelope(double progress) {
  if (!progress.isFinite || progress <= 0 || progress >= 1) return 0;
  if (progress < .18) return Curves.easeOutCubic.transform(progress / .18);
  if (progress <= battleCastSettleFraction) return 1;
  return (1 - progress) / (1 - battleCastSettleFraction);
}

/// Only public changes can supply a target, including either player's visible Mine.
class BattleSpellCue {
  final CardId card;
  final PieceColor side;
  final List<int> squares;
  final List<String> boundPieceIds;
  final PieceColor? resourceSide;
  BattleSpellCue(
    this.card,
    this.side,
    Iterable<int> squares, {
    this.resourceSide,
    Iterable<String> boundPieceIds = const [],
  }) : squares = List.unmodifiable(
         squares.where((s) => s >= 0 && s < 64).toSet().take(4),
       ),
       boundPieceIds = List.unmodifiable(boundPieceIds.toSet().take(4));

  bool get isActive => boundPieceIds.isEmpty || squares.isNotEmpty;

  BattleSpellCue following(RuleState rules) {
    if (boundPieceIds.isEmpty) return this;
    final current =
        boundPieceIds
            .map(rules.pieceIds.indexOf)
            .where((square) => square >= 0)
            .toList();
    return BattleSpellCue(
      card,
      side,
      current,
      resourceSide: resourceSide,
      boundPieceIds: boundPieceIds,
    );
  }

  factory BattleSpellCue.fromViews(
    CardId card,
    PieceColor side,
    PlayerView before,
    PlayerView after,
  ) {
    final old = before.rules, next = after.rules;
    final targets = <int>{};
    final pieces = <String>{};
    for (final e in next.pieceEffects) {
      if (e.owner == side &&
          pieceEffectCard(e.type) == card &&
          !old.pieceEffects.any((p) => p.id == e.id)) {
        targets.add(next.pieceIds.indexOf(e.pieceId));
        pieces.add(e.pieceId);
      }
    }
    for (final e in next.boardEffects) {
      if (e.owner == side &&
          boardEffectCard(e.type) == card &&
          !old.boardEffects.any((p) => p.id == e.id)) {
        targets.addAll(e.squares);
      }
    }
    for (final v in next.vows) {
      if (v.owner == side &&
          (v.type == VowType.hunt ? CardId.huntVow : CardId.watchVow) == card &&
          !old.vows.any((p) => p.id == v.id)) {
        targets.add(
          v.square ??
              (v.pieceId == null ? -1 : next.pieceIds.indexOf(v.pieceId)),
        );
        if (v.pieceId != null) pieces.add(v.pieceId!);
      }
    }
    if (next.special?.card == card && next.board.turn == side) {
      targets.add(next.special!.from);
      final pieceId = next.pieceIds[next.special!.from];
      if (pieceId != null) pieces.add(pieceId);
    }
    if (movementCards.contains(card) &&
        targets.isEmpty &&
        next.ply - old.ply <= 2) {
      for (var s = 0; s < 64; s++) {
        final id = next.pieceIds[s];
        if (id != null && next.board.pieceAt(s)?.color == side) {
          final from = old.pieceIds.indexOf(id);
          if (from >= 0 && from != s) {
            targets.add(s);
            pieces.add(id);
          }
        }
      }
    }
    if (card == CardId.purify) {
      final removed =
          old.pieceEffects.where((e) {
            final square = old.pieceIds.indexOf(e.pieceId);
            return square >= 0 &&
                e.type != PieceEffectType.shelter &&
                old.board.pieceAt(square)?.color == side &&
                !next.pieceEffects.any((p) => p.id == e.id);
          }).toList();
      // Multiple expired effects in a batched update do not identify a cast target.
      if (removed.length == 1 && next.ply == old.ply) {
        targets.add(next.pieceIds.indexOf(removed.single.pieceId));
        pieces.add(removed.single.pieceId);
      }
    }
    if (card == CardId.breakSeal) {
      final removed =
          old.boardEffects
              .where(
                (e) =>
                    e.owner != side &&
                    !next.boardEffects.any((p) => p.id == e.id),
              )
              .toList();
      if (removed.length == 1 && next.ply == old.ply) {
        targets.addAll(removed.single.squares);
      }
    }
    return BattleSpellCue(
      card,
      side,
      targets,
      // Echo's cast marks the opponent's named card. Its later mana-payoff
      // cue is constructed directly and must remain on the caster's side.
      resourceSide: card == CardId.echo ? side.opposite : null,
      boundPieceIds: pieces,
    );
  }
}

Offset battleSquareCenter(int square, PieceColor viewer, double cell) => Offset(
  (viewer.isWhite ? Square.fileOf(square) : 7 - Square.fileOf(square)) * cell +
      cell / 2,
  (viewer.isWhite ? 7 - Square.rankOf(square) : Square.rankOf(square)) * cell +
      cell / 2,
);

class BattleSpellPainter extends CustomPainter {
  final BattleSpellCue cue;
  final PieceColor viewer;
  final double progress;
  final Color color;
  final bool showProjectile;
  BattleSpellPainter({
    required this.cue,
    required this.viewer,
    required this.progress,
    required this.color,
    this.showProjectile = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!cue.isActive ||
        !progress.isFinite ||
        progress <= 0 ||
        progress >= 1 ||
        size.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final cell = size.shortestSide / 8;
    final own = cue.side == viewer;
    final origin = Offset(
      size.width * .5,
      own ? size.height - cell * .15 : cell * .15,
    );
    final resourceOwn =
        cue.resourceSide != null
            ? cue.resourceSide == viewer
            : switch (cue.card) {
              CardId.radar || CardId.manaSabotage || CardId.cardBlock => !own,
              _ => own,
            };
    final resource = Offset(
      size.width * .5,
      resourceOwn ? size.height - cell * 1.1 : cell * 1.1,
    );
    final target =
        cue.squares.isEmpty
            ? resource
            : cue.squares
                    .map((s) => battleSquareCenter(s, viewer, cell))
                    .reduce((a, b) => a + b) /
                cue.squares.length.toDouble();
    final t = battleImpactProgress(progress);
    final strength = battleSpellEnvelope(progress);
    final paint =
        Paint()
          ..color = color.withValues(alpha: .9 * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.7, cell * .072)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    if (showProjectile) _flight(canvas, origin, target, cell, paint);
    if (progress < battleCastArrivalFraction) {
      canvas.restore();
      return;
    }
    if (cue.squares.isNotEmpty) {
      final anchor =
          Paint()
            ..color = paint.color.withValues(alpha: paint.color.a * .35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, cell * .025);
      for (final square in cue.squares) {
        final center = battleSquareCenter(square, viewer, cell);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: cell * .94,
              height: cell * .94,
            ),
            Radius.circular(cell * .12),
          ),
          Paint()..color = color.withValues(alpha: .13 * strength),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: cell * .88,
              height: cell * .88,
            ),
            Radius.circular(cell * .12),
          ),
          anchor,
        );
      }
    }
    canvas.translate(target.dx, target.dy);
    final radius = cell * (cue.squares.length > 1 ? 1.08 : .82);
    _depth(canvas, radius, t, strength);
    _impactAccent(canvas, radius, t, strength);
    paintBattleSpellMaterial(
      canvas,
      cue.card,
      radius,
      t,
      color,
      strength,
      forwardUp: cue.side == viewer,
    );
    final motion = battleCardMotion(cue.card, t);
    canvas.save();
    canvas.rotate(motion.impactTurn);
    canvas.scale(motion.impactX, motion.impactY);
    _spell(canvas, radius, t, paint);
    canvas.restore();
    if (t < 1) _particles(canvas, radius, t, paint);
    canvas.restore();
  }

  void _impactAccent(Canvas c, double r, double t, double strength) {
    final open = Curves.easeOutCubic.transform((t * 3).clamp(0, 1));
    final accent =
        Paint()
          ..color = color.withValues(alpha: .3 * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.8, r * .09)
          ..strokeCap = StrokeCap.round;
    final category = cardDefinitions[cue.card]!.category;
    if (category == CardCategory.board || category == CardCategory.modifier) {
      for (var i = 0; i < 4; i++) {
        c.save();
        c.rotate(i * math.pi / 2);
        c.drawPath(
          Path()
            ..moveTo(-r * .35, -r * 1.14 * open)
            ..lineTo(-r * .95 * open, -r * 1.14 * open)
            ..lineTo(-r * 1.14 * open, -r * .95 * open)
            ..lineTo(-r * 1.14 * open, -r * .35),
          accent,
        );
        c.restore();
      }
    } else if (category == CardCategory.knowledge) {
      c.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * 1.18),
        -math.pi / 2 + t * math.pi * 2,
        math.pi * .65,
        false,
        accent,
      );
      c.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * 1.38),
        math.pi / 2 - t * math.pi * 2,
        math.pi * .45,
        false,
        accent,
      );
    } else if (category == CardCategory.movement) {
      final direction = cue.side == viewer ? -1.0 : 1.0;
      for (var i = 0; i < 3; i++) {
        final y = direction * r * (.5 + i * .28 + t * .3);
        c.drawLine(
          Offset(-r * .75, y - direction * r * .22),
          Offset(-r * .48, y),
          accent,
        );
        c.drawLine(
          Offset(r * .75, y - direction * r * .22),
          Offset(r * .48, y),
          accent,
        );
      }
    } else {
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3 + cue.card.index * .15;
        final direction = Offset(math.cos(angle), math.sin(angle));
        c.drawLine(
          direction * r * (1.02 + t * .12),
          direction * r * (1.22 + open * .16),
          accent,
        );
      }
    }
  }

  void _depth(Canvas c, double r, double t, double strength) {
    final impact = Curves.easeOutCubic.transform((t * 3).clamp(0, 1));
    final floor = Rect.fromCenter(
      center: Offset(0, r * .42),
      width: r * 2.1 * impact,
      height: r * .55 * impact,
    );
    c.drawOval(floor, Paint()..color = color.withValues(alpha: .06 * strength));
    c.drawOval(
      floor,
      Paint()
        ..color = color.withValues(alpha: .2 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .035,
    );
    if (cue.card == CardId.freeze) {
      for (var i = 0; i < 6; i++) {
        c.save();
        c.rotate(i * math.pi / 3);
        final tip = Offset(0, -r * (.7 + impact * .3));
        final left = Offset(-r * .13, -r * .38);
        final right = Offset(r * .13, -r * .38);
        final base = Offset(0, -r * .23);
        c.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(base.dx, base.dy)
            ..close(),
          Paint()..color = color.withValues(alpha: .28 * strength),
        );
        c.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(right.dx, right.dy)
            ..lineTo(base.dx, base.dy)
            ..close(),
          Paint()..color = Colors.white.withValues(alpha: .48 * strength),
        );
        c.restore();
      }
    } else if (cue.card == CardId.shelter) {
      final shield =
          Path()
            ..moveTo(0, -r)
            ..lineTo(r * .8, -r * .65)
            ..quadraticBezierTo(r * .9, r * .45, 0, r)
            ..quadraticBezierTo(-r * .9, r * .45, -r * .8, -r * .65)
            ..close();
      c.drawPath(
        shield,
        Paint()..color = color.withValues(alpha: .12 * strength),
      );
      c.drawLine(
        Offset(0, -r * .8),
        Offset(0, r * .65),
        Paint()
          ..color = Colors.white.withValues(alpha: .7 * strength)
          ..strokeWidth = r * .045,
      );
    }
  }

  void _flight(
    Canvas canvas,
    Offset from,
    Offset to,
    double cell,
    Paint paint,
  ) {
    if (progress >= battleCastArrivalFraction) return;
    final flight = battleTravelProgress(progress);
    Offset point(double t) => battleCardFlightPoint(cue.card, from, to, t);
    for (var i = 0; i < 9; i++) {
      final a = (flight - i * .028).clamp(0.0, 1.0);
      final b = (a - .03).clamp(0.0, 1.0);
      canvas.drawLine(
        point(b),
        point(a),
        Paint()
          ..color = color.withValues(alpha: (1 - i / 9) * .65)
          ..strokeWidth = cell * (.12 - i * .009)
          ..strokeCap = StrokeCap.round,
      );
    }
    final head = point(flight);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    _fragment(
      canvas,
      cell * .13,
      Paint()..color = Color.lerp(color, Colors.white, .45)!,
    );
    canvas.restore();
  }

  void _particles(Canvas canvas, double r, double t, Paint paint) {
    final fill =
        Paint()..color = paint.color.withValues(alpha: paint.color.a * .65);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + cue.card.index * .23;
      final distance = r * (.55 + t * .8);
      canvas.save();
      canvas.translate(math.cos(angle) * distance, math.sin(angle) * distance);
      canvas.rotate(angle);
      _fragment(canvas, r * .12 * (1 - t * .75), fill);
      canvas.restore();
    }
  }

  void _fragment(Canvas c, double r, Paint fill) {
    final p =
        Paint()
          ..color = fill.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.8, r * .32)
          ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    switch (cue.card) {
      case CardId.radar:
        c.drawCircle(Offset.zero, r * .55, fill);
        c.drawLine(Offset(r, 0), Offset(r * 2, 0), p);
      case CardId.prophecy:
        c.drawPath(
          Path()
            ..moveTo(0, -r * 1.6)
            ..lineTo(r, 0)
            ..lineTo(0, r * 1.6)
            ..lineTo(-r, 0)
            ..close(),
          p,
        );
      case CardId.shelter:
        c.drawArc(rect, math.pi * .2, math.pi * 1.6, false, p);
        c.drawLine(Offset(-r * .6, 0), Offset(r * .6, 0), p);
      case CardId.chain:
        for (final x in [-.5, .5]) {
          c.drawOval(rect.shift(Offset(r * x, 0)), p);
        }
      case CardId.slow:
        c.drawPath(
          Path()
            ..moveTo(-r, -r)
            ..lineTo(r, -r)
            ..lineTo(-r, r)
            ..lineTo(r, r)
            ..close(),
          p,
        );
      case CardId.pawnDeviation:
        c.drawPath(
          Path()
            ..moveTo(-r, -r)
            ..lineTo(0, 0)
            ..lineTo(r, -r),
          p,
        );
        c.drawLine(Offset(0, r), Offset(r, 0), p);
      case CardId.pawnAdvance:
        for (final y in [-.6, .6]) {
          c.drawPath(
            Path()
              ..moveTo(-r, r * y)
              ..lineTo(0, r * (y - .8))
              ..lineTo(r, r * y),
            p,
          );
        }
      case CardId.lockedSquare:
        c.drawRect(rect, p);
        c.drawLine(Offset.zero, Offset(0, r * .6), p);
      case CardId.freeze:
        for (var i = 0; i < 3; i++) {
          c.save();
          c.rotate(i * math.pi / 3);
          c.drawLine(Offset(-r * 1.4, 0), Offset(r * 1.4, 0), p);
          c.restore();
        }
      case CardId.purify:
        c.drawLine(Offset(-r, 0), Offset(r, 0), p);
        c.drawLine(Offset(0, -r), Offset(0, r), p);
      case CardId.mine:
        c.drawCircle(Offset.zero, r * .7, fill);
        c.drawCircle(Offset(r, r), r * .25, fill);
      case CardId.breakSeal:
        c.drawPath(
          Path()
            ..moveTo(-r * 1.5, -r)
            ..lineTo(-r * .2, 0)
            ..lineTo(r * .4, -r * .6)
            ..lineTo(r * 1.5, r),
          p,
        );
      case CardId.fog:
        c.drawPath(
          Path()
            ..moveTo(-r * 2, 0)
            ..cubicTo(-r, -r * 2, r, r * 2, r * 2, 0),
          p,
        );
      case CardId.manaSabotage:
        c.drawPath(
          Path()
            ..moveTo(0, -r * 1.5)
            ..quadraticBezierTo(-r * 1.5, r, 0, r)
            ..quadraticBezierTo(r * 1.5, r, 0, -r * 1.5),
          p,
        );
      case CardId.cardBlock:
        c.drawRect(
          Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 2.4),
          p,
        );
        c.drawLine(Offset(-r, r), Offset(r, -r), p);
      case CardId.rookBend:
        c.drawPath(
          Path()
            ..moveTo(-r, -r)
            ..lineTo(-r, r)
            ..lineTo(r, r),
          p,
        );
      case CardId.angryN:
        c.drawPath(
          Path()
            ..moveTo(0, -r * 1.6)
            ..lineTo(-r, 0)
            ..lineTo(r, 0)
            ..lineTo(0, r * 1.6),
          p,
        );
      case CardId.shadowPass:
        c.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r, height: r * 3),
          p,
        );
      case CardId.huntVow:
        c.drawCircle(Offset.zero, r, p);
        c.drawLine(Offset(-r * 1.5, 0), Offset(r * 1.5, 0), p);
      case CardId.watchVow:
        c.drawPath(
          Path()
            ..moveTo(-r * 1.5, 0)
            ..quadraticBezierTo(0, -r * 1.5, r * 1.5, 0)
            ..quadraticBezierTo(0, r * 1.5, -r * 1.5, 0),
          p,
        );
        c.drawCircle(Offset.zero, r * .25, fill);
      case CardId.echo:
        for (final size in [.6, 1.2, 1.8]) {
          c.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: r * size),
            -.6,
            1.2,
            false,
            p,
          );
        }
      case CardId.fateExchange:
        c.drawRect(rect.shift(Offset(-r * .5, -r * .5)), p);
        c.drawRect(rect.shift(Offset(r * .5, r * .5)), p);
      case CardId.shadowContract:
        c.drawPath(
          Path()
            ..moveTo(-r * 1.4, -r)
            ..quadraticBezierTo(0, r, r * 1.4, -r),
          p,
        );
        c.drawPath(
          Path()
            ..moveTo(-r * 1.4, r)
            ..quadraticBezierTo(0, -r, r * 1.4, r),
          p,
        );
      case CardId.boardSeal:
        for (final sign in [-1, 1]) {
          c.drawPath(
            Path()
              ..moveTo(r * sign, 0)
              ..lineTo(r * sign, r * sign)
              ..lineTo(0, r * sign),
            p,
          );
        }
    }
  }

  void _arrow(Canvas c, Offset from, Offset to, Paint p, double head) {
    c.drawLine(from, to, p);
    final a = math.atan2(to.dy - from.dy, to.dx - from.dx);
    c.drawLine(to, to - Offset(math.cos(a - .6), math.sin(a - .6)) * head, p);
    c.drawLine(to, to - Offset(math.cos(a + .6), math.sin(a + .6)) * head, p);
  }

  void _ring(
    Canvas c,
    double radius,
    Paint p, [
    double start = 0,
    double sweep = math.pi * 2,
  ]) => c.drawArc(
    Rect.fromCircle(center: Offset.zero, radius: radius),
    start,
    sweep,
    false,
    p,
  );

  void _spell(Canvas c, double r, double t, Paint p) {
    final expand = Curves.easeOutCubic.transform((t * 2).clamp(0.0, 1.0));
    final spin = t * math.pi * 2;
    final shift = math.sin(t * math.pi);
    switch (cue.card) {
      case CardId.radar:
        for (var i = 0; i < 3; i++) {
          _ring(c, r * (.3 + i * .28) * expand, p);
        }
        _arrow(
          c,
          Offset.zero,
          Offset(math.cos(spin), math.sin(spin)) * r,
          p,
          r * .18,
        );
        for (var i = 0; i < 4; i++) {
          final d = Offset(
            math.cos(i * math.pi / 2),
            math.sin(i * math.pi / 2),
          );
          c.drawLine(d * r * .85, d * r * 1.1, p);
        }
      case CardId.prophecy:
        for (final sign in [-1, 1]) {
          _ring(c, r * .8, p, sign * spin, math.pi * .65);
          c.drawCircle(Offset(sign * r * .35, 0), r * .18 * expand, p);
        }
        _arrow(c, Offset(0, r * .7), Offset(0, -r * .7), p, r * .2);
      case CardId.shelter:
        final shield =
            Path()
              ..moveTo(0, -r)
              ..lineTo(r * .8, -r * .65)
              ..quadraticBezierTo(r * .9, r * .45, 0, r)
              ..quadraticBezierTo(-r * .9, r * .45, -r * .8, -r * .65)
              ..close();
        c.save();
        c.scale(.7 + expand * .3);
        c.drawPath(shield, p);
        c.restore();
        _ring(c, r * (1 + t * .4), p, math.pi * .15, math.pi * .7);
      case CardId.chain:
        for (var i = 0; i < 10; i++) {
          final angle = i * math.pi / 5 + spin * .25;
          c.save();
          c.rotate(angle);
          c.translate(0, r * (1.35 - expand * .5));
          c.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: r * .62,
              height: r * .24,
            ),
            p,
          );
          c.restore();
        }
      case CardId.slow:
        final hourglass =
            Path()
              ..moveTo(-r * .45, -r * .85)
              ..lineTo(r * .45, -r * .85)
              ..lineTo(-r * .45, r * .85)
              ..lineTo(r * .45, r * .85)
              ..close();
        c.drawPath(hourglass, p);
        for (var i = 0; i < 3; i++) {
          c.drawCircle(Offset(0, r * (((t * 2 + i / 3) % 1) - .5)), r * .06, p);
        }
      case CardId.pawnDeviation:
        final sign = cue.side == viewer ? -1.0 : 1.0;
        for (final x in [-1.0, 1.0]) {
          _arrow(
            c,
            Offset(0, -sign * r * .6),
            Offset(x * r * expand, sign * r * .7),
            p,
            r * .25,
          );
        }
      case CardId.pawnAdvance:
        final sign = cue.side == viewer ? -1.0 : 1.0;
        for (var i = 0; i < 2; i++) {
          final y = sign * r * (t * .6 + i * .5 - .5);
          _arrow(
            c,
            Offset(0, y - sign * r * .4),
            Offset(0, y + sign * r * .35),
            p,
            r * .25,
          );
        }
      case CardId.lockedSquare:
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: Offset.zero, radius: r * expand),
            const Radius.circular(3),
          ),
          p,
        );
        c.drawArc(
          Rect.fromCenter(
            center: Offset(0, -r * .2),
            width: r * .5,
            height: r * .65,
          ),
          math.pi,
          math.pi,
          false,
          p,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(0, r * .12),
              width: r * .65,
              height: r * .5,
            ),
            const Radius.circular(2),
          ),
          p,
        );
      case CardId.freeze:
        for (var i = 0; i < 6; i++) {
          c.save();
          c.rotate(i * math.pi / 3);
          final end = r * (.45 + expand * .55);
          c.drawLine(Offset(0, -end * .3), Offset(0, -end), p);
          for (final sign in [-1, 1]) {
            c.drawLine(
              Offset(0, -end * .65),
              Offset(sign * end * .23, -end * .82),
              p,
            );
          }
          c.restore();
        }
        _ring(c, r * (.7 + t * .6), p, spin, math.pi * .6);
      case CardId.purify:
        for (var i = 0; i < 3; i++) {
          _ring(c, r * (.3 + i * .3) * expand, p, spin + i, math.pi * 1.3);
        }
        c.drawLine(Offset(-r * .28, 0), Offset(r * .28, 0), p);
        c.drawLine(Offset(0, -r * .28), Offset(0, r * .28), p);
      case CardId.mine:
        _ring(c, r * expand, p);
        _ring(c, r * .5, p, spin, math.pi * 1.6);
        for (var i = 0; i < 6; i++) {
          final d = Offset(
            math.cos(i * math.pi / 3),
            math.sin(i * math.pi / 3),
          );
          c.drawLine(d * r * .6, d * r * .85, p);
        }
      case CardId.breakSeal:
        for (var i = 0; i < 4; i++) {
          c.save();
          c.rotate(i * math.pi / 2);
          c.translate(r * t * .5, -r * t * .5);
          c.drawPath(
            Path()
              ..moveTo(0, -r)
              ..lineTo(r, -r)
              ..lineTo(r, 0),
            p,
          );
          c.restore();
        }
        _arrow(c, Offset(-r * .6, r * .6), Offset(r * .6, -r * .6), p, r * .2);
      case CardId.fog:
        for (var i = 0; i < 3; i++) {
          final y = (i - 1) * r * .42;
          c.drawPath(
            Path()
              ..moveTo(-r, y)
              ..cubicTo(
                -r * .4,
                y - r * .3 * shift,
                r * .4,
                y + r * .3 * shift,
                r,
                y,
              ),
            p,
          );
        }
        _ring(c, r * .75, p, spin * .3, math.pi * .5);
      case CardId.manaSabotage:
        final drop =
            Path()
              ..moveTo(0, -r * .8)
              ..cubicTo(-r, r * .2, -r * .5, r * .7, 0, r * .7)
              ..cubicTo(r * .5, r * .7, r, r * .2, 0, -r * .8)
              ..close();
        c.drawPath(drop, p);
        for (final sign in [-1, 1]) {
          _arrow(
            c,
            Offset(sign * r * .55, -r * .2),
            Offset(sign * r, r * .6),
            p,
            r * .2,
          );
        }
      case CardId.cardBlock:
        for (final sign in [-1, 1]) {
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(sign * r * .15, 0),
                width: r * .9,
                height: r * 1.5,
              ),
              const Radius.circular(3),
            ),
            p,
          );
        }
        c.drawLine(Offset(-r * .7, r * .8), Offset(r * .7, -r * .8), p);
        _ring(c, r * expand, p, math.pi * .1, math.pi * .8);
      case CardId.rookBend:
        for (var i = 0; i < 4; i++) {
          final angle = math.pi / 4 + i * math.pi / 2;
          final d = Offset(math.cos(angle), math.sin(angle));
          _arrow(c, d * r * .3, d * r * (.6 + expand * .4), p, r * .22);
        }
        c.drawRect(
          Rect.fromCenter(center: Offset.zero, width: r * .35, height: r * .35),
          p,
        );
      case CardId.angryN:
        for (var i = 0; i < 4; i++) {
          final d = Offset(
            math.cos(i * math.pi / 2),
            math.sin(i * math.pi / 2),
          );
          _arrow(c, d * r * .35, d * r * (1 + t * .2), p, r * .25);
        }
        c.drawCircle(Offset.zero, r * .2, p);
      case CardId.shadowPass:
        for (final sign in [-1, 1]) {
          c.drawOval(
            Rect.fromCenter(
              center: Offset(sign * r * .65, 0),
              width: r * .45,
              height: r * 1.5 * expand,
            ),
            p,
          );
        }
        for (var i = 0; i < 4; i++) {
          c.drawLine(
            Offset(r * (i * .3 - .6) + t * r * .2, 0),
            Offset(r * (i * .3 - .45) + t * r * .2, 0),
            p,
          );
        }
      case CardId.huntVow:
        _ring(c, r * (1.3 - expand * .45), p);
        for (var i = 0; i < 4; i++) {
          final d = Offset(
            math.cos(i * math.pi / 2),
            math.sin(i * math.pi / 2),
          );
          c.drawLine(d * r * .65, d * r * 1.1, p);
        }
      case CardId.watchVow:
        final eye =
            Path()
              ..moveTo(-r, 0)
              ..quadraticBezierTo(0, -r * expand, r, 0)
              ..quadraticBezierTo(0, r * expand, -r, 0)
              ..close();
        c.drawPath(eye, p);
        c.drawCircle(Offset.zero, r * .3 * expand, p);
        _ring(c, r * 1.15, p, -spin * .2, math.pi * .45);
      case CardId.echo:
        for (var i = 0; i < 3; i++) {
          final radius = r * ((t + i / 3) % 1);
          _ring(c, radius, p, -.8, 1.6);
          _ring(c, radius, p, math.pi - .8, 1.6);
        }
      case CardId.fateExchange:
        for (var i = 0; i < 3; i++) {
          c.save();
          c.rotate((i - 1) * .4 + spin * .08);
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset((i - 1) * r * .55 * (1 - t * .5), 0),
                width: r * .6,
                height: r,
              ),
              const Radius.circular(3),
            ),
            p,
          );
          c.restore();
        }
        _ring(c, r * 1.1, p, spin, math.pi * .65);
      case CardId.shadowContract:
        for (final sign in [-1, 1]) {
          c.save();
          c.translate(sign * r * .6 * (1 - t * .35), 0);
          c.rotate(sign * .2);
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: r * .6, height: r),
              const Radius.circular(3),
            ),
            p,
          );
          c.restore();
        }
        c.drawPath(
          Path()
            ..moveTo(-r * .5, 0)
            ..quadraticBezierTo(0, -r * shift, r * .5, 0),
          p,
        );
      case CardId.boardSeal:
        c.drawRect(Rect.fromCircle(center: Offset.zero, radius: r * expand), p);
        for (var i = 0; i < 4; i++) {
          c.save();
          c.rotate(i * math.pi / 2);
          c.drawPath(
            Path()
              ..moveTo(-r * .7, -r)
              ..lineTo(-r, -r)
              ..lineTo(-r, -r * .7),
            p,
          );
          c.restore();
        }
        c.drawLine(Offset(-r * .45, 0), Offset(r * .45, 0), p);
        c.drawLine(Offset(0, -r * .45), Offset(0, r * .45), p);
    }
  }

  @override
  bool shouldRepaint(BattleSpellPainter old) =>
      old.cue != cue ||
      old.progress != progress ||
      old.viewer != viewer ||
      old.color != color ||
      old.showProjectile != showProjectile;
}
