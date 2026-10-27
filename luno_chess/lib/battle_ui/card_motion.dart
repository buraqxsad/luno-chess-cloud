import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';

class BattleCardMotion {
  final double lift, sideways, tilt, turn, scale, impactTurn, impactX, impactY;
  const BattleCardMotion(
    this.lift,
    this.sideways,
    this.tilt,
    this.turn,
    this.scale,
    this.impactTurn,
    this.impactX,
    this.impactY,
  );
}

// Each gesture follows the card's action; all are bounded and return to rest.
BattleCardMotion battleCardMotion(CardId card, double progress) {
  final t = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
  final life = math.sin(t * math.pi), wave = math.sin(t * math.pi * 2) * life;
  final quick = math.sin(t * math.pi * 4) * life;
  BattleCardMotion pose(
    double lift,
    double side,
    double tilt,
    double turn,
    double scale,
    double rotation,
    double x,
    double y,
  ) => BattleCardMotion(
    lift * life,
    side,
    tilt * life,
    turn,
    1 + scale * life,
    rotation * life * .5,
    1 + x * .6,
    1 + y * .6,
  );
  return switch (card) {
    CardId.radar => pose(
      .45,
      .3 * wave,
      -.12,
      .28 * wave,
      .12,
      t * math.pi * .65,
      .06 * life,
      -.06 * life,
    ),
    CardId.prophecy => pose(
      .8,
      .22 * math.sin(t * math.pi * 3) * life,
      .16,
      .65 * life,
      .18,
      .12 * wave,
      -.08 * life,
      .13 * life,
    ),
    CardId.shelter => pose(
      .7,
      -.08 * wave,
      -.08,
      .18 * life,
      .24,
      0,
      .13 * life,
      .08 * life,
    ),
    CardId.chain => pose(
      .3,
      .24 * quick * (1 - t),
      .28,
      .5 * wave,
      .08,
      -.3 * wave,
      -.13 * life,
      -.13 * life,
    ),
    CardId.slow => pose(
      .35,
      .035 * quick,
      .07,
      .15 * wave,
      .05,
      .06 * math.sin(t * math.pi * 3) * life,
      -.04 * life,
      .09 * life,
    ),
    CardId.pawnDeviation => pose(
      .4,
      .34 * wave,
      -.23,
      -.42 * wave,
      .13,
      -.12 * wave,
      .18 * life,
      -.05 * life,
    ),
    CardId.pawnAdvance => pose(
      .95,
      0,
      -.02,
      .12 * life,
      .17,
      0,
      -.09 * life,
      .23 * life,
    ),
    CardId.lockedSquare => pose(
      .25,
      0,
      .11,
      -.18 * life,
      .09,
      .035 * quick,
      .15 * life,
      -.1 * life,
    ),
    CardId.freeze => pose(
      .62,
      .09 * quick,
      -.16,
      .46 * life,
      .2,
      -.14 * life,
      .04 * quick,
      .1 * life,
    ),
    CardId.purify => pose(
      .88,
      -.1 * wave,
      .04,
      -.34 * life,
      .16,
      .35 * t * life,
      .2 * life,
      .2 * life,
    ),
    CardId.mine => pose(
      .17,
      -.04 * wave,
      .18,
      .08 * life,
      -.05,
      0,
      .09 * quick,
      -.14 * life,
    ),
    CardId.breakSeal => pose(
      .52,
      .16 * math.sin(t * math.pi * 3) * life,
      -.32,
      .24 * wave,
      .27,
      .24 * wave,
      .24 * life,
      .04 * life,
    ),
    CardId.fog => pose(
      .4,
      .32 * wave,
      .09,
      -.18 * wave,
      .1,
      .05 * wave,
      .28 * life,
      -.12 * life,
    ),
    CardId.manaSabotage => pose(
      -.15,
      .14 * wave,
      .21,
      -.28 * life,
      .12,
      -.1 * wave,
      -.12 * life,
      .2 * life,
    ),
    CardId.cardBlock => pose(
      .48,
      -.12 * wave,
      -.12,
      .65 * life,
      .11,
      .1 * wave,
      -.16 * life,
      .04 * life,
    ),
    CardId.rookBend => pose(
      .45,
      .4 * life * (t < .5 ? t * 2 : 2 - t * 2),
      .19,
      .26 * life,
      .15,
      .17 * wave,
      .12 * life,
      -.04 * life,
    ),
    CardId.angryN => pose(
      1.15,
      -.26 * wave,
      -.2,
      .4 * wave,
      .25,
      -.2 * wave,
      .06 * life,
      .24 * quick,
    ),
    CardId.shadowPass => pose(
      .32,
      .38 * wave,
      .24,
      -.75 * life,
      -.12,
      .28 * wave,
      -.23 * life,
      .21 * life,
    ),
    CardId.huntVow => pose(
      .28,
      .1 * quick * (1 - t),
      -.26,
      .2 * life,
      .22,
      .08 * wave,
      -.2 * life,
      -.2 * life,
    ),
    CardId.watchVow => pose(
      .58,
      .12 * wave,
      .02,
      .32 * wave,
      .14,
      -.04 * wave,
      .19 * life,
      -.08 * quick,
    ),
    CardId.echo => pose(
      .55,
      .18 * quick,
      -.09,
      .3 * wave,
      .16,
      .09 * quick,
      .2 * quick,
      .2 * quick,
    ),
    CardId.fateExchange => pose(
      .72,
      -.3 * wave,
      .26,
      .85 * life,
      .23,
      .22 * wave,
      .18 * life,
      -.03 * life,
    ),
    CardId.shadowContract => pose(
      .66,
      .2 * wave,
      -.17,
      -.58 * life,
      .19,
      -.18 * wave,
      -.05 * life,
      .17 * life,
    ),
    CardId.boardSeal => pose(
      .2,
      .06 * quick,
      .14,
      .14 * life,
      .26,
      .045 * wave,
      .16 * life,
      .16 * life,
    ),
  };
}

Offset battleCardFlightPoint(CardId card, Offset from, Offset to, double t) {
  final progress = t.isFinite ? t.clamp(0.0, 1.0) : 0.0;
  if (progress == 0) return from;
  if (progress == 1) return to;
  final motion = battleCardMotion(card, progress), delta = to - from;
  final perpendicular =
      delta.distance < 1
          ? const Offset(1, 0)
          : Offset(-delta.dy, delta.dx) / delta.distance;
  final distance = math.min(80.0, delta.distance * .22);
  final curve = switch (card) {
    CardId.mine ||
    CardId.lockedSquare ||
    CardId.boardSeal => Curves.easeInCubic,
    CardId.pawnAdvance || CardId.angryN => Curves.easeOutCubic,
    CardId.slow || CardId.fog || CardId.shadowPass => Curves.easeInOutSine,
    _ => Curves.easeInOutCubic,
  };
  return Offset.lerp(from, to, curve.transform(progress))! +
      perpendicular * motion.sideways * distance -
      Offset(0, motion.lift * distance);
}
