import '../battle_v1/model.dart';

const battleCastArrivalFraction = .30;
const battleCastSettleFraction = .80;
const battleCastCardFadeEndFraction = .40;
const battleCleanupDuration = Duration(milliseconds: 700);

class BattleEffectTiming {
  final int milliseconds;
  const BattleEffectTiming(this.milliseconds);

  Duration get total => Duration(milliseconds: milliseconds);
  Duration get travel => Duration(milliseconds: (milliseconds * .30).round());
  Duration get impact => Duration(milliseconds: (milliseconds * .50).round());
  Duration get settle => Duration(milliseconds: (milliseconds * .20).round());
}

// Explicit identities, not rarity: a scan, a leap and a contract need different
// reading time. All share the same phase boundaries across the two renderers.
BattleEffectTiming battleEffectTiming(CardId card) => switch (card) {
  CardId.radar => const BattleEffectTiming(1600),
  CardId.prophecy => const BattleEffectTiming(1800),
  CardId.shelter => const BattleEffectTiming(1600),
  CardId.chain => const BattleEffectTiming(1700),
  CardId.slow => const BattleEffectTiming(1800),
  CardId.pawnDeviation => const BattleEffectTiming(1500),
  CardId.pawnAdvance => const BattleEffectTiming(1400),
  CardId.lockedSquare => const BattleEffectTiming(1600),
  CardId.freeze => const BattleEffectTiming(1900),
  CardId.purify => const BattleEffectTiming(1700),
  CardId.mine => const BattleEffectTiming(1800),
  CardId.breakSeal => const BattleEffectTiming(1700),
  CardId.fog => const BattleEffectTiming(2000),
  CardId.manaSabotage => const BattleEffectTiming(1800),
  CardId.cardBlock => const BattleEffectTiming(1700),
  CardId.rookBend => const BattleEffectTiming(1800),
  CardId.angryN => const BattleEffectTiming(1800),
  CardId.shadowPass => const BattleEffectTiming(2000),
  CardId.huntVow => const BattleEffectTiming(1900),
  CardId.watchVow => const BattleEffectTiming(1900),
  CardId.echo => const BattleEffectTiming(2100),
  CardId.fateExchange => const BattleEffectTiming(2200),
  CardId.shadowContract => const BattleEffectTiming(2100),
  CardId.boardSeal => const BattleEffectTiming(2200),
};

double battleTravelProgress(double progress) =>
    progress.isFinite
        ? (progress / battleCastArrivalFraction).clamp(0.0, 1.0)
        : 0;

double battleImpactProgress(double progress) =>
    progress.isFinite
        ? ((progress - battleCastArrivalFraction) /
                (battleCastSettleFraction - battleCastArrivalFraction))
            .clamp(0.0, 1.0)
        : 0;

double battleCastCardOpacity(double progress) {
  if (!progress.isFinite ||
      progress <= 0 ||
      progress >= battleCastCardFadeEndFraction) {
    return 0;
  }
  if (progress < .06) return progress / .06;
  if (progress <= battleCastArrivalFraction) return 1;
  return (battleCastCardFadeEndFraction - progress) /
      (battleCastCardFadeEndFraction - battleCastArrivalFraction);
}

// The external card owns travel; the board painter begins at its impact phase.
double battleExternalImpactProgress(double progress) {
  if (!progress.isFinite || progress <= battleCastArrivalFraction) return 0;
  return progress.clamp(0.0, 1.0);
}

/// Presentation timing only. Never delays a rules action or stops a clock.
Duration battleEffectDuration(CardId card) => battleEffectTiming(card).total;

/// Compatibility for the screen's existing local-session pacing callback.
/// Do not couple that callback to the longer canvas presentation duration.
Duration battleCardFeedbackPacingDuration(CardId card) => Duration(
  milliseconds: switch (cardDefinitions[card]!.rarity) {
    Rarity.common => 480,
    Rarity.rare => 580,
    Rarity.epic => 680,
    Rarity.legendary => 820,
  },
);

int battleImpactDelay(CardId card) =>
    battleEffectTiming(card).travel.inMilliseconds;
