import '../battle_v1/model.dart';

enum BattleUnlockKind { rankedMatches, welcomeClaim, dailyClaimDays }

class BattleUnlockRequirement {
  final BattleUnlockKind kind;
  final int current, target;
  const BattleUnlockRequirement(this.kind, this.current, this.target);
  String label({required bool english, bool remaining = false}) {
    final amount = remaining ? (target - current).clamp(0, target) : target;
    return switch (kind) {
      BattleUnlockKind.rankedMatches =>
        english
            ? '$amount meaningful ranked matches${remaining ? " remaining" : ""}'
            : '$amount anlamlı sıralı maç${remaining ? " kaldı" : " tamamla"}',
      BattleUnlockKind.welcomeClaim =>
        english
            ? 'Claim the one-time welcome reward'
            : 'Tek seferlik karşılama ödülünü al',
      BattleUnlockKind.dailyClaimDays =>
        english
            ? 'Claim daily rewards on $amount ${remaining ? "more " : ""}different UTC days'
            : '$amount ${remaining ? "gün daha " : "farklı UTC gününde "}günlük ödül al',
    };
  }
}

class BattleUnlockMilestone {
  final CardId card;
  final int matches;
  final bool owned;
  final List<BattleUnlockRequirement> requirements;

  const BattleUnlockMilestone({
    required this.card,
    required this.matches,
    required this.owned,
    this.requirements = const [],
  });
  String conditionLabel({required bool english, bool remaining = false}) =>
      (requirements.isEmpty
              ? [
                BattleUnlockRequirement(
                  BattleUnlockKind.rankedMatches,
                  0,
                  matches,
                ),
              ]
              : requirements)
          .map(
            (requirement) =>
                requirement.label(english: english, remaining: remaining),
          )
          .join(english ? ' OR ' : ' VEYA ');
}

/// Public-safe presentation data only. This cannot grant ownership or rewards.
class BattleDeckProgression {
  final int meaningfulMatches;
  final int targetMatches;
  final List<BattleUnlockMilestone> path;
  final BattleUnlockMilestone? nextUnlock;

  BattleDeckProgression._({
    required this.meaningfulMatches,
    required this.targetMatches,
    required List<BattleUnlockMilestone> path,
    required this.nextUnlock,
  }) : path = List.unmodifiable(path);

  bool get complete => path.every((entry) => entry.owned);
  bool get hasEarlyUnlocks =>
      path.any((entry) => entry.requirements.length > 1);
  int get unlockedCardCount =>
      starterDeck.length + path.where((e) => e.owned).length;
  double get progress => complete ? 1 : meaningfulMatches / targetMatches;
  int? get matchesToNextUnlock =>
      nextUnlock == null ? null : nextUnlock!.matches - meaningfulMatches;

  String progressLabel({required bool english}) =>
      complete
          ? (english
              ? 'All 24 battle cards unlocked'
              : '24 savaş kartının tamamı açık')
          : english
          ? '$meaningfulMatches / $targetMatches meaningful ranked matches'
          : '$meaningfulMatches / $targetMatches anlamlı sıralı maç';

  String? nextUnlockLabel(String localizedCardName, {required bool english}) {
    if (nextUnlock == null) return null;
    final name =
        localizedCardName.trim().isEmpty
            ? nextUnlock!.card.wire
            : localizedCardName.trim();
    return '${english ? "Next" : "Sıradaki"}: $name · ${nextUnlock!.conditionLabel(english: english, remaining: true)}';
  }

  String qualificationLabel({required bool english}) {
    final ranked =
        english
            ? 'Human ranked matches need at least 12 plies and 4 of your moves. Wins are not required; a clock-expired loss does not count.'
            : 'İnsan rakipli sıralı maçlarda en az 12 yarım hamle ve senin 4 hamlen gerekir. Galibiyet şart değil. Süre aşımıyla kayıp sayılmaz.';
    if (!hasEarlyUnlocks) return ranked;
    return '$ranked ${english ? "Mine also unlocks with the welcome reward; Break Seal and Fog with daily rewards on 2 and 3 different UTC days." : "Mayın karşılama ödülüyle; Mühür Kır ve Sis 2 ve 3 farklı UTC gününde günlük ödül alarak da açılır."}';
  }
}

/// Missing legacy metadata means no progress display, never an invented unlock.
BattleDeckProgression? parseBattleV1DeckProgression(
  Object? raw, {
  required Set<CardId> owned,
}) {
  if (raw == null) return null;
  const invalid = FormatException('Invalid battle deck progression');
  if (raw is! Map ||
      raw['version'] is! int ||
      !const {1, 2}.contains(raw['version']) ||
      !owned.containsAll(starterDeck)) {
    throw invalid;
  }
  final matches = raw['meaningfulMatches'];
  final target = raw['targetMatches'];
  final rows = raw['path'];
  if (matches is! int ||
      matches < 0 ||
      matches > 20 ||
      target is! int ||
      target != 20 ||
      rows is! List ||
      rows.length != 14) {
    throw invalid;
  }
  final entries = <BattleUnlockMilestone>[];
  final modern = raw['version'] == 2;
  final early = raw['early'];
  if (modern &&
      (early is! Map ||
          early['welcomeClaimed'] is! bool ||
          early['distinctDailyClaims'] is! int ||
          (early['distinctDailyClaims'] as int) < 0 ||
          (early['distinctDailyClaims'] as int) > 3)) {
    throw invalid;
  }
  final cards = <CardId>{};
  var previousThreshold = 0;
  for (final row in rows) {
    if (row is! Map ||
        row['card'] is! String ||
        row['matches'] is! int ||
        row['owned'] is! bool) {
      throw invalid;
    }
    final card = CardId.parse(row['card'] as String);
    final threshold = row['matches'] as int;
    final isOwned = row['owned'] as bool;
    final requirements = <BattleUnlockRequirement>[
      BattleUnlockRequirement(
        BattleUnlockKind.rankedMatches,
        matches,
        threshold,
      ),
      if (modern && card == CardId.mine)
        BattleUnlockRequirement(
          BattleUnlockKind.welcomeClaim,
          early['welcomeClaimed'] == true ? 1 : 0,
          1,
        ),
      if (modern && (card == CardId.breakSeal || card == CardId.fog))
        BattleUnlockRequirement(
          BattleUnlockKind.dailyClaimDays,
          early['distinctDailyClaims'] as int,
          threshold,
        ),
    ];
    if (modern) {
      final value = row['requirements'];
      final anyOf = value is Map ? value['anyOf'] : null;
      if (anyOf is! List || anyOf.length != requirements.length) throw invalid;
      for (var i = 0; i < requirements.length; i++) {
        final expected = requirements[i], declared = anyOf[i];
        final kind = switch (expected.kind) {
          BattleUnlockKind.rankedMatches => 'ranked_matches',
          BattleUnlockKind.welcomeClaim => 'welcome_claim',
          BattleUnlockKind.dailyClaimDays => 'daily_claim_days',
        };
        if (declared is! Map ||
            declared['kind'] != kind ||
            declared['current'] != expected.current ||
            declared['target'] != expected.target) {
          throw invalid;
        }
      }
    }
    if (starterDeck.contains(card) ||
        !cards.add(card) ||
        threshold <= previousThreshold ||
        threshold > 20 ||
        isOwned != owned.contains(card) ||
        (!isOwned && requirements.any((r) => r.current >= r.target))) {
      throw invalid;
    }
    entries.add(
      BattleUnlockMilestone(
        card: card,
        matches: threshold,
        owned: isOwned,
        requirements: List.unmodifiable(requirements),
      ),
    );
    previousThreshold = threshold;
  }
  if (previousThreshold != 20) throw invalid;
  final remaining = entries.where((entry) => !entry.owned);
  final next = remaining.isEmpty ? null : remaining.first;
  final declared = raw['nextUnlock'];
  if (next == null
      ? declared != null
      : declared is! Map ||
          declared['card'] != next.card.wire ||
          declared['matches'] is! int ||
          declared['matches'] != next.matches) {
    throw invalid;
  }
  return BattleDeckProgression._(
    meaningfulMatches: matches,
    targetMatches: 20,
    path: entries,
    nextUnlock: next,
  );
}
