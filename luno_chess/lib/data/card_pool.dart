import '../cards/card_catalog.dart';
import '../cards/card_def.dart';

/// Koleksiyon puanı (nadirliğe göre) — HTML birebir.
const Map<CardRarity, int> kCollectionPts = {
  CardRarity.common: 15,
  CardRarity.rare: 60,
  CardRarity.legendary: 200,
  CardRarity.mythic: 500,
};

/// Yükseltilebilir aileler (destede tek yuva, maçta seviye seçilir).
const List<String> kFamilies = ['trap', 'radar', 'resist', 'shield', 'deploy'];

/// Native UI'nin kullandığı kanonik taş seti kimlikleri. Sunucu varsayılan
/// seti `std` olarak saklar; istemci bunu kullanıcıya `luno` olarak gösterir.
const List<String> kPieceSetIds = [
  'luno',
  'ottoman',
  'roma',
  'brit',
  'viking',
  'tasdevri',
  'samuray',
  'ice',
  'dragon',
  'neon',
];

/// "Sahiplik anahtarı": yükseltilebilir → aile adı ('trap');
/// yükseltilemez → kartın kendi anahtarı ('freeze').
const List<String> kAllOwnable = [
  'trap',
  'radar',
  'resist',
  'shield',
  'deploy',
  'freeze',
  'poison_q',
  'card_block',
  'medium',
  'barbarian',
  'glue',
  'archer',
  'fog',
  'angry_n',
  'angry_b',
  'plague',
  'reinforce',
  'ghosts',
  'immunity',
];

/// Başlangıçta açık kartlar.
const List<String> kStarterOwned = [
  'barbarian',
  'card_block',
  'poison_q',
  'angry_n',
  'glue',
  'freeze',
];

/// Sandıktan çıkabilecekler (başlangıç hariç), kabaca güç sırasıyla.
const List<String> kChestPool = [
  'card_block',
  'angry_b',
  'angry_n',
  'fog',
  'poison_q',
  'medium',
  'glue',
  'archer',
  'deploy',
  'plague',
  'reinforce',
  'ghosts',
  'immunity',
];

bool isFamily(String ownedKey) => kFamilies.contains(ownedKey);

/// Sunucudan gelen yükseltilebilir kart varyantını istemcinin sahiplik
/// anahtarına çevirir. Örn. `trap1` ve `trap3` aynı koleksiyon yuvasıdır.
String ownershipKeyForCard(String rawKey) {
  final key = rawKey.trim();
  if (isFamily(key)) return key;
  final match = RegExp(
    r'^(trap|radar|resist|shield|deploy)[123]$',
  ).firstMatch(key);
  return match?.group(1) ?? key;
}

bool isKnownOwnableKey(String rawKey) =>
    kAllOwnable.contains(ownershipKeyForCard(rawKey));

/// Fiziksel koleksiyon sayacını üretir. Yükseltilebilir aileler tek sahiplik
/// yuvası olsa da her açılmış seviye katalogda ayrı bir kart olarak görünür.
int ownedPhysicalCardCount(
  Iterable<dynamic> rawOwned, [
  Map<String, int> levels = const <String, int>{},
]) {
  final owned =
      rawOwned
          .whereType<String>()
          .map(ownershipKeyForCard)
          .where(isKnownOwnableKey)
          .toSet();
  return kCards.values.where((card) {
    if (card.family.isNotEmpty) {
      final level = (levels[card.family] ?? 1).clamp(1, 3).toInt();
      return owned.contains(card.family) && card.level <= level;
    }
    return owned.contains(card.key);
  }).length;
}

/// Deste girişini kanonik, benzersiz ve sahip olunan altı slota indirger.
/// Geçersiz/eksik bir sunucu veya yerel snapshot'ı hiçbir zaman kısmi deste
/// olarak kabul etmez; bu, maç başlangıcında eksik el oluşmasını önler.
List<String> normalizeDeck(
  Iterable<dynamic> rawDeck,
  Set<String> ownedCards, {
  Iterable<String> fallback = const <String>[],
}) {
  final owned =
      ownedCards.map(ownershipKeyForCard).where(isKnownOwnableKey).toSet();

  List<String> uniqueOwned(Iterable<dynamic> values) {
    final result = <String>[];
    for (final raw in values) {
      if (raw is! String) continue;
      final key = ownershipKeyForCard(raw);
      if (!owned.contains(key) || result.contains(key)) continue;
      result.add(key);
      if (result.length == 6) break;
    }
    return result;
  }

  final primary = uniqueOwned(rawDeck);
  if (primary.length == 6) return primary;
  final backup = uniqueOwned(fallback);
  if (backup.length == 6) return backup;
  return uniqueOwned(kAllOwnable);
}

/// Sahiplik anahtarını + seviyeyi gerçek katalog anahtarına çevirir.
String resolvedKey(String ownedKey, int level) {
  final canonical = ownershipKeyForCard(ownedKey);
  if (!isFamily(canonical)) return canonical;
  final safeLevel = level.clamp(1, 3).toInt();
  return '$canonical$safeLevel';
}

/// Sahiplik anahtarı için katalog tanımı (verilen seviyede).
CardDef cardForOwned(String ownedKey, int level) =>
    kCards[resolvedKey(ownedKey, level)]!;

CardDef? tryCardForOwned(String ownedKey, int level) =>
    kCards[resolvedKey(ownedKey, level)];

/// Arena yükseldikçe sandık havuzu genişler.
List<String> chestPoolForArena(int arenaIdx, {Set<String>? excludeOwned}) {
  final n = (4 + arenaIdx * 2).clamp(4, kChestPool.length);
  final pool = kChestPool.sublist(0, n);
  if (excludeOwned == null) return pool;
  final unowned =
      pool
          .where((key) => !excludeOwned.contains(ownershipKeyForCard(key)))
          .toList();
  return unowned.isNotEmpty ? unowned : pool;
}

/// Bir aileyi sonraki seviyeye yükseltme maliyeti (altın). Seviye 1→2, 2→3.
int upgradeGoldCost(int currentLevel) => currentLevel == 1 ? 2500 : 5000;

// Mirrors functions/lib/catalogs.js CARD_UPGRADE_CATALOG (zero-based arenas).
const kUpgradeArenaRequirements = <String, List<int>>{
  'trap': [2, 4],
  'radar': [2, 4],
  'resist': [3, 5],
  'shield': [4, 6],
  'deploy': [6, 7],
};

int? upgradeRequiredArena(String family, int currentLevel) {
  final requirements = kUpgradeArenaRequirements[ownershipKeyForCard(family)];
  if (requirements == null || currentLevel < 1 || currentLevel > 2) return null;
  return requirements[currentLevel - 1];
}

/// Günlük ödül döngüsü (altın).
const List<int> kDailyGold = [200, 300, 450, 600, 800, 1000, 1500];
