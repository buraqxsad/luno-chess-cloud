import '../data/card_pool.dart';
import '../data/pass.dart';
import '../data/username.dart';
import '../data/board_finishes.dart';

/// Emoji ids shared by the collection screen and the server loadout contract.
/// The list is deliberately catalog-backed instead of relying on system emoji.
const kEmojiIds = <String>[
  'smile',
  'heart',
  'laugh',
  'cry',
  'angry',
  'think',
  'fire',
  'star',
  'thunder',
  'bomb',
  'strat',
  'trophy',
  'crown',
  'rainbow',
];

/// Oyuncunun kalıcı verisi (altın/elmas/deste/kartlar/istatistik).
class PlayerData {
  String username;
  String playerCode;
  String country;
  String bio;
  String avatar;
  String avatarEmoji;
  String pieceSet;
  int lvl;
  int xp;

  int gold;
  int gems;
  int trophies;
  int arenaIdx;

  Set<String> ownedCards; // sahiplik anahtarları
  Map<String, int> cardLevel; // aile -> seviye (1..3)
  List<String> deck; // 6 sahiplik anahtarı
  Set<String> ownedEmojis;
  List<String> emojiLoadout; // maç içi hızlı ifade yuvaları (en fazla 4)
  Set<String> ownedPieceSets;
  Set<String> ownedSkins;
  Map<String, int> skinPieces;
  String activeSkin;

  int wins;
  int losses;
  int draws;
  int gamesPlayed;
  int streak;
  int bestStreak;
  int cardsPlayed;
  int chestsOpened;

  int dailyStreak;
  int lastDailyDay; // gün indeksi (epoch/86400000)

  bool premium;
  // Last confirmed server membership, separate from the seasonal paid Pass.
  int premiumUntil;
  bool membershipActive;
  bool get isMembershipActive => membershipActive;
  int passXp;
  int passRewardVersion;
  Set<int> passFreeClaimed;
  Set<int> passPremClaimed;
  Set<String> passUnlocks;
  // A player may own two chests of the same rarity. Keep this as a list so
  // the server's pending-chest inventory remains a multiset instead of
  // silently dropping duplicate rewards.
  List<String> pendingChests;

  PlayerData({
    this.username = 'LunoPlayer',
    this.playerCode = '',
    this.country = 'TR',
    this.bio = '',
    this.avatar = '#e8b840',
    this.avatarEmoji = 'av_pawn',
    this.pieceSet = 'luno',
    this.lvl = 1,
    this.xp = 0,
    required this.gold,
    required this.gems,
    required this.trophies,
    required this.arenaIdx,
    required this.ownedCards,
    required this.cardLevel,
    required this.deck,
    Set<String>? ownedEmojis,
    List<String>? emojiLoadout,
    Set<String>? ownedPieceSets,
    Set<String>? ownedSkins,
    Map<String, int>? skinPieces,
    this.activeSkin = 'classic',
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.gamesPlayed = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.cardsPlayed = 0,
    this.chestsOpened = 0,
    this.dailyStreak = 0,
    this.lastDailyDay = 0,
    this.premium = false,
    this.premiumUntil = 0,
    this.membershipActive = false,
    this.passXp = 0,
    this.passRewardVersion = kPassLegacyRewardVersion,
    Set<int>? passFreeClaimed,
    Set<int>? passPremClaimed,
    Set<String>? passUnlocks,
    List<String>? pendingChests,
  }) : passFreeClaimed = passFreeClaimed ?? {},
       passPremClaimed = passPremClaimed ?? {},
       passUnlocks = passUnlocks ?? {},
       pendingChests = pendingChests ?? [],
       ownedEmojis = ownedEmojis ?? {'smile'},
       emojiLoadout = emojiLoadout ?? [],
       ownedPieceSets = ownedPieceSets ?? {'luno'},
       ownedSkins = ownedSkins ?? {'classic'},
       skinPieces = skinPieces ?? {};

  factory PlayerData.initial() => PlayerData(
    username: 'LunoPlayer',
    gold: 1250,
    gems: 42,
    trophies: 0,
    arenaIdx: 0,
    ownedCards: {...kStarterOwned},
    cardLevel: {for (final f in kFamilies) f: 1},
    deck: List<String>.of(kStarterOwned),
  );

  int passLevel() =>
      (passXp ~/ kPassXpPerLevel).clamp(0, kPassMaxLevel).toInt();

  Map<String, dynamic> toJson() => {
    'username': username,
    'playerCode': playerCode,
    'country': country,
    'bio': bio,
    'avatar': avatar,
    'avatarEmoji': avatarEmoji,
    'pieceSet': pieceSet,
    'lvl': lvl,
    'xp': xp,
    'gold': gold,
    'gems': gems,
    'trophies': trophies,
    'arenaIdx': arenaIdx,
    'ownedCards': ownedCards.toList(),
    'cardLevel': cardLevel,
    'deck': deck,
    'ownedEmojis': ownedEmojis.toList(),
    'emojiLoadout': emojiLoadout.toList(),
    'ownedPieceSets': ownedPieceSets.toList(),
    'ownedSkins': ownedSkins.toList(),
    'skinPieces': skinPieces,
    'activeSkin': activeSkin,
    'wins': wins,
    'losses': losses,
    'draws': draws,
    'gamesPlayed': gamesPlayed,
    'streak': streak,
    'bestStreak': bestStreak,
    'cardsPlayed': cardsPlayed,
    'chestsOpened': chestsOpened,
    'dailyStreak': dailyStreak,
    'lastDailyDay': lastDailyDay,
    'premium': premium,
    'premiumUntil': premiumUntil,
    'membershipActive': membershipActive,
    'passXp': passXp,
    'passRewardVersion': passRewardVersion,
    'passFreeClaimed': passFreeClaimed.toList(),
    'passPremClaimed': passPremClaimed.toList(),
    'passUnlocks': passUnlocks.toList(),
    'pendingChests': pendingChests.toList(),
  };

  factory PlayerData.fromJson(Map<String, dynamic> j) {
    final base = PlayerData.initial();
    String stringValue(String key, String fallback) {
      final value = j[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    int intValue(
      String key,
      int fallback, {
      int min = 0,
      int max = 1000000000,
    }) {
      final value = j[key];
      return value is num && value.isFinite
          ? value.toInt().clamp(min, max).toInt()
          : fallback;
    }

    bool boolValue(String key, bool fallback) {
      final value = j[key];
      return value is bool ? value : fallback;
    }

    Set<String> stringSet(String key, Set<String> fallback) {
      final value = j[key];
      if (value is! List) return Set<String>.of(fallback);
      return value.whereType<String>().toSet();
    }

    List<String> stringListValue(String key) {
      final value = j[key];
      if (value is! List) return <String>[];
      return value
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
    }

    final rawOwned = stringSet('ownedCards', const <String>{});
    final normalizedOwned =
        rawOwned.map(ownershipKeyForCard).where(isKnownOwnableKey).toSet();
    final ownedCards =
        normalizedOwned.length >= 6
            ? normalizedOwned
            : <String>{...base.ownedCards};
    final ownedEmojis =
        stringSet('ownedEmojis', const <String>{})
          ..retainWhere(kEmojiIds.contains)
          ..add('smile');
    final emojiLoadout = <String>[];
    for (final id in stringListValue('emojiLoadout')) {
      if (kEmojiIds.contains(id) &&
          ownedEmojis.contains(id) &&
          !emojiLoadout.contains(id)) {
        emojiLoadout.add(id);
      }
      if (emojiLoadout.length == 4) break;
    }

    Set<int> intSet(String key) {
      final value = j[key];
      if (value is! List) return <int>{};
      return value
          .whereType<num>()
          .where(
            (entry) =>
                entry.isFinite &&
                entry >= 1 &&
                entry <= kPassMaxLevel &&
                entry == entry.toInt(),
          )
          .map((entry) => entry.toInt())
          .toSet();
    }

    Map<String, int> levels() {
      final value = j['cardLevel'];
      if (value is! Map) return Map<String, int>.of(base.cardLevel);
      final result = <String, int>{};
      value.forEach((key, raw) {
        if (key is String &&
            kFamilies.contains(key) &&
            raw is num &&
            raw.isFinite) {
          result[key] = raw.toInt().clamp(1, 3).toInt();
        }
      });
      return result.isEmpty ? Map<String, int>.of(base.cardLevel) : result;
    }

    List<String> deckValue() {
      final value = j['deck'];
      return normalizeDeck(
        value is List ? value : const <dynamic>[],
        ownedCards,
        fallback: base.deck,
      );
    }

    final ownedPieceSets =
        stringSet('ownedPieceSets', const <String>{})
          ..removeWhere((set) => set == 'std')
          ..retainWhere(kPieceSetIds.contains)
          ..add('luno');
    final storedPieceSet =
        stringValue('pieceSet', base.pieceSet) == 'std'
            ? 'luno'
            : stringValue('pieceSet', base.pieceSet);
    final pieceSet =
        ownedPieceSets.contains(storedPieceSet) ? storedPieceSet : 'luno';
    final ownedSkins = stringSet('ownedSkins', {'classic'})..add('classic');
    final activeSkin = stringValue('activeSkin', 'classic');

    final rawUsername = j['username'];
    final storedUsername =
        rawUsername is String && rawUsername.isNotEmpty
            ? normalizeUsernameValue(rawUsername)
            : '';

    return PlayerData(
      username:
          isUsernameShapeValid(storedUsername) ? storedUsername : base.username,
      playerCode: stringValue('playerCode', base.playerCode),
      country: stringValue('country', base.country),
      bio: stringValue('bio', base.bio),
      avatar: stringValue('avatar', base.avatar),
      avatarEmoji: stringValue('avatarEmoji', base.avatarEmoji),
      pieceSet: pieceSet,
      lvl: intValue('lvl', base.lvl, min: 1, max: 100),
      xp: intValue('xp', base.xp),
      gold: intValue('gold', base.gold),
      gems: intValue('gems', base.gems),
      trophies: intValue('trophies', 0),
      arenaIdx: intValue('arenaIdx', 0, max: 8),
      ownedCards: ownedCards,
      cardLevel: levels(),
      deck: deckValue(),
      ownedEmojis: ownedEmojis,
      emojiLoadout: emojiLoadout,
      ownedPieceSets: ownedPieceSets,
      ownedSkins: ownedSkins,
      skinPieces: normalizeSkinPieces(j['skinPieces']),
      activeSkin: ownedSkins.contains(activeSkin) ? activeSkin : 'classic',
      wins: intValue('wins', 0),
      losses: intValue('losses', 0),
      draws: intValue('draws', 0),
      gamesPlayed: intValue('gamesPlayed', 0),
      streak: intValue('streak', 0),
      bestStreak: intValue('bestStreak', 0),
      cardsPlayed: intValue('cardsPlayed', 0),
      chestsOpened: intValue('chestsOpened', 0),
      dailyStreak: intValue('dailyStreak', 0),
      lastDailyDay: intValue('lastDailyDay', 0),
      premium: boolValue('premium', false),
      premiumUntil: intValue('premiumUntil', 0, max: 8640000000000000),
      membershipActive: boolValue('membershipActive', false),
      passRewardVersion: normalizePassRewardVersion(j['passRewardVersion']),
      passXp: intValue(
        'passXp',
        0,
        max: kPassMaxLevel * kPassXpPerLevel + kPassXpPerLevel - 1,
      ),
      passFreeClaimed: intSet('passFreeClaimed'),
      passPremClaimed: intSet('passPremClaimed'),
      passUnlocks: stringSet('passUnlocks', const <String>{}),
      pendingChests: stringListValue('pendingChests'),
    );
  }
}
