import '../engine/piece.dart';

/// Bir kartın hedef türü (tryCardTarget mantığı — HTML birebir).
enum CardTarget {
  none, // hedef yok (anında oynanır)
  enemy, // rakip taş (şah hariç, resist'siz)
  enemyQueen, // rakip vezir
  ownPawn, // kendi piyon
  ownPawnPair, // kendi iki piyon (tutkal, iki adımlı)
  ownKnight, // kendi at
  ownBishop, // kendi fil
  ownKnBi, // kendi at veya fil
  ownQueen, // kendi vezir
  ownPiece, // kendi taş (şah hariç)
  empty, // boş kare (blok/kalkan/tuzak yok)
  emptyOwn, // boş ve kendi yarı sahanda
  anySq, // herhangi boş kare
}

enum CardRarity { common, rare, legendary, mythic }

/// Bir kart tanımı. Mana/hedef/etki HTML sürümünden birebir alındı.
class CardDef {
  final String key;
  final String name;
  final String
  family; // yükseltilebilir aile: trap/radar/resist/shield/deploy; yoksa ''
  final int level; // 1..3
  final int maxLevel; // yükseltilemezse 1
  final int mana;
  final CardRarity rarity;
  final CardTarget target;
  final bool skipMove; // oynayınca hamle yapmadan sıra geçer (sadece freeze)
  final bool hidden; // rakipten gizli etki
  final int dur; // temel süre
  final PieceType? deploy; // sefer kartının yerleştirdiği taş
  final String glyph; // arayüz sembolü
  final String desc;

  const CardDef({
    required this.key,
    required this.name,
    required this.mana,
    required this.target,
    required this.glyph,
    required this.desc,
    this.family = '',
    this.level = 1,
    this.maxLevel = 1,
    this.rarity = CardRarity.common,
    this.skipMove = false,
    this.hidden = false,
    this.dur = 0,
    this.deploy,
  });

  bool get upgradeable => maxLevel > 1;
}
