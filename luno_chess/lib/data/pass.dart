/// Luno Pass: 30 seviye. Bu katalog, sunucudaki PASS_CURRENCY_REWARDS ve
/// PASS_CONTENT_REWARDS ile birebir ayni tutulur; istemci sadece on-line
/// sunucu teslimatinin on izlemesini gosterir.
enum PassRewardKind { chest, emoji, costume }

class PassTier {
  final int gold;
  final int gems;
  final PassRewardKind? kind;
  final String? key;
  final String? name;

  const PassTier(this.gold, this.gems, {this.kind, this.key, this.name});
}

const int kPassMaxLevel = 30;
const int kPassXpPerLevel = 250;
const int kPassLegacyRewardVersion = 1;
const int kPassCurrentRewardVersion = 2;

/// Existing live/purchased seasons retain version 1 (540 premium gems).
/// Future version 2 returns 330 premium + 120 free gems against this cost.
const int kPassPremiumCost = 450;

int normalizePassRewardVersion(Object? value) =>
    value == kPassCurrentRewardVersion
        ? kPassCurrentRewardVersion
        : kPassLegacyRewardVersion;

/// RTDB may encode dense numeric tier keys as a list, with null holes.
Set<int> passClaimedLevels(Object? value) {
  final Iterable<MapEntry<Object?, Object?>> entries;
  if (value is Map) {
    entries = value.entries;
  } else if (value is List) {
    entries = value.asMap().entries;
  } else {
    return <int>{};
  }
  final result = <int>{};
  for (final entry in entries) {
    final key = entry.key.toString();
    final level = int.tryParse(key);
    final claim = entry.value;
    final confirmed =
        claim == true ||
        (claim is num && claim.isFinite && claim > 0 && claim == claim.toInt());
    if (level != null &&
        key == level.toString() &&
        level >= 1 &&
        level <= kPassMaxLevel &&
        confirmed) {
      result.add(level);
    }
  }
  return result;
}

void _validatePassLevel(int level) {
  if (level < 1 || level > kPassMaxLevel) {
    throw RangeError.range(level, 1, kPassMaxLevel, 'level');
  }
}

/// Bedava serit odulu (seviye 1..30): 100 + seviye * 20 altin ve her 5'te
/// 20 elmas. Icerik odulleri sunucudaki ayni seviyelerde tanimlidir.
PassTier _contentReward(
  int gold,
  int gems,
  PassRewardKind kind,
  String key,
  String name,
) => PassTier(gold, gems, kind: kind, key: key, name: name);

PassTier passFree(int level) {
  _validatePassLevel(level);
  final gold = 100 + level * 20;
  final gems = level % 5 == 0 ? 20 : 0; // 6 x 20 = 120 elmas
  return switch (level) {
    4 => _contentReward(gold, 0, PassRewardKind.emoji, 'laugh', 'Neşeli Luno'),
    8 => _contentReward(gold, 0, PassRewardKind.chest, 'rare', 'Nadir Sandık'),
    12 => _contentReward(
      gold,
      0,
      PassRewardKind.emoji,
      'trophy',
      'Zafer Lunosu',
    ),
    16 => _contentReward(
      gold,
      0,
      PassRewardKind.chest,
      'legendary',
      'Efsanevi Sandık',
    ),
    20 => _contentReward(
      gold,
      20,
      PassRewardKind.costume,
      'ottoman',
      'Osmanlı Taş Seti',
    ),
    24 => _contentReward(gold, 0, PassRewardKind.emoji, 'heart', 'Luno Kalbi'),
    28 => _contentReward(
      gold,
      0,
      PassRewardKind.chest,
      'royal',
      'Kraliyet Sandığı',
    ),
    30 => _contentReward(
      gold,
      20,
      PassRewardKind.costume,
      'viking',
      'Viking Taş Seti',
    ),
    _ => PassTier(gold, gems),
  };
}

/// The server's season-bound reward version is authoritative. Missing legacy
/// snapshots keep their original reward preview instead of being downgraded.
PassTier passPrem(int level, {int rewardVersion = kPassLegacyRewardVersion}) {
  _validatePassLevel(level);
  final gold = level * 30;
  final gems =
      normalizePassRewardVersion(rewardVersion) == kPassCurrentRewardVersion
          ? 11
          : 18;
  return switch (level) {
    5 => _contentReward(
      gold,
      gems,
      PassRewardKind.chest,
      'rare',
      'Premium Nadir Sandık',
    ),
    10 => _contentReward(
      gold,
      gems,
      PassRewardKind.emoji,
      'angry',
      'Premium Luno Tepkisi',
    ),
    15 => _contentReward(
      gold,
      gems,
      PassRewardKind.costume,
      'roma',
      'Roma Taş Seti',
    ),
    20 => _contentReward(
      gold,
      gems,
      PassRewardKind.chest,
      'legendary',
      'Premium Efsanevi Sandık',
    ),
    25 => _contentReward(
      gold,
      gems,
      PassRewardKind.costume,
      'dragon',
      'Ejderha Taş Seti',
    ),
    30 => _contentReward(
      gold,
      gems,
      PassRewardKind.costume,
      'neon',
      'Neon Krallık Seti',
    ),
    _ => PassTier(gold, gems),
  };
}
