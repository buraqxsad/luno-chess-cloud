import '../battle_v1/model.dart';
import '../engine/piece.dart';
import 'luno_localizations.dart';

enum BattleCopy {
  arsenal,
  opponent,
  you,
  mana,
  hand,
  deck,
  card,
  move,
  choicePhase,
  firstTurn,
  yourTurn,
  opponentTurn,
  play,
  discard,
  pass,
  cancel,
  close,
  detail,
  unused,
  used,
  discarded,
  target,
  choosePiece,
  chooseSquare,
  chooseZone,
  chooseCard,
  chooseEffect,
  chooseSacrifice,
  boundMove,
  confirm,
  privateChoice,
  take,
  next,
  afterwards,
  privateKnowledge,
  inHand,
  notInHand,
  stale,
  upcoming,
  syncing,
  pending,
  unavailable,
  retry,
  loading,
  emptyHand,
  menu,
  resign,
  resigned,
  resignQuestion,
  leave,
  home,
  victory,
  defeat,
  draw,
  check,
  timeout,
  checkmate,
  stalemate,
  ended,
  rematch,
  newMatch,
  trophyChange,
  settlementPending,
  promotion,
  empty,
  white,
  black,
  earlier,
  later,
  legalTarget,
  seventyFive,
  fivefold,
}

class BattleCardExplanation {
  final String selection, effect, duration, caution;
  const BattleCardExplanation({
    required this.selection,
    required this.effect,
    required this.duration,
    required this.caution,
  });
}

extension BattleV1Copy on LunoLocalizations {
  String battle(BattleCopy key) => _copy[key]![isEnglish ? 1 : 0];
  String battleCardName(CardId card) => _names[card]![isEnglish ? 1 : 0];
  String battleCardShortDescription(CardId card) =>
      _descriptions[card]![isEnglish ? 1 : 0];
  String battleCardDescription(CardId card) => battleCardShortDescription(card);
  String battlePendingChoiceInstruction(CardId card) =>
      card == CardId.fateExchange
          ? (isEnglish
              ? 'Take 1 card from your deck and confirm the order of the rest. Then move a piece.'
              : 'Destenden 1 kart seç; kalanların sırasını onayla. Sonra taşını oynat.')
          : (isEnglish
              ? 'Choose and confirm your upcoming card order. Then move a piece.'
              : 'Destendeki kartların sırasını seç ve onayla. Sonra taşını oynat.');
  String battleCardOutcome(
    CardId card, {
    bool ours = true,
    bool choicePending = true,
  }) {
    if (!choicePending &&
        (card == CardId.prophecy || card == CardId.fateExchange)) {
      return ours
          ? (isEnglish
              ? 'Your private card choice is complete.'
              : 'Özel kart seçimin tamamlandı.')
          : (isEnglish
              ? 'The opponent\'s private card choice is complete. Their choice stays hidden from you.'
              : 'Rakibin özel kart seçimi tamamlandı. Seçim sana gizli.');
    }
    final private = ours ? null : _opponentPrivateOutcomes[card];
    return (private ?? _outcomes[card]!)[isEnglish ? 1 : 0];
  }

  BattleCardExplanation battleCardExplanation(CardId card) =>
      _details[card]![isEnglish ? 1 : 0];
  String get battleCardSelectionLabel => isEnglish ? 'Choose' : 'Seç';
  String get battleCardEffectLabel => isEnglish ? 'What happens' : 'Ne olur';
  String get battleCardDurationLabel =>
      isEnglish ? 'When it ends' : 'Ne zaman biter';
  String get battleCardCautionLabel => isEnglish ? 'Important rules' : 'Dikkat';
  String battleCardDetail(CardId card) {
    final cost = cardDefinitions[card]!.cost;
    final explanation = battleCardExplanation(card);
    final heading =
        isEnglish ? 'Base cost: $cost mana.' : 'Temel maliyet: $cost mana.';
    return [
      heading,
      '$battleCardSelectionLabel\n${explanation.selection}',
      '$battleCardEffectLabel\n${explanation.effect}',
      '$battleCardDurationLabel\n${explanation.duration}',
      '$battleCardCautionLabel\n${explanation.caution}',
    ].join('\n\n');
  }

  String get battleTimeControl => '5+2';
  String get battleTimeControlDescription =>
      isEnglish
          ? '5 minutes per player; +2 seconds after each completed chess move. The clock keeps running while you choose, discard or resolve a card.'
          : 'Her oyuncuya 5 dakika; tamamlanan her taş hamlesinden sonra +2 saniye. Kart seçerken, feda ederken veya özel seçimini tamamlarken saat işlemeye devam eder.';
  String battleCardCount(int count) =>
      isEnglish ? '$count cards' : '$count kart';
  String battleRarity(Rarity rarity) => switch (rarity) {
    Rarity.common => isEnglish ? 'Common' : 'Sıradan',
    Rarity.rare => isEnglish ? 'Rare' : 'Nadir',
    Rarity.epic => isEnglish ? 'Epic' : 'Destansı',
    Rarity.legendary => isEnglish ? 'Legendary' : 'Efsanevi',
  };
  String battlePiece(PieceType type) => switch (type) {
    PieceType.pawn => isEnglish ? 'Pawn' : 'Piyon',
    PieceType.knight => isEnglish ? 'Knight' : 'At',
    PieceType.bishop => isEnglish ? 'Bishop' : 'Fil',
    PieceType.rook => isEnglish ? 'Rook' : 'Kale',
    PieceType.queen => isEnglish ? 'Queen' : 'Vezir',
    PieceType.king => isEnglish ? 'King' : 'Şah',
  };
  String battleReason(String reason) => switch (reason) {
    'checkmate' => battle(BattleCopy.checkmate),
    'stalemate' => battle(BattleCopy.stalemate),
    'timeout' => battle(BattleCopy.timeout),
    'resign' || 'resignation' => battle(BattleCopy.resigned),
    'seventy_five_moves' => battle(BattleCopy.seventyFive),
    'fivefold' => battle(BattleCopy.fivefold),
    _ => battle(BattleCopy.ended),
  };
}

const _copy = <BattleCopy, List<String>>{
  BattleCopy.arsenal: ['Rakibin Kartları', 'Opponent Cards'],
  BattleCopy.opponent: ['Rakip', 'Opponent'],
  BattleCopy.you: ['Sen', 'You'],
  BattleCopy.mana: ['Mana', 'Mana'],
  BattleCopy.hand: ['El', 'Hand'],
  BattleCopy.deck: ['Deste', 'Deck'],
  BattleCopy.card: ['KART', 'CARD'],
  BattleCopy.move: ['HAMLE', 'MOVE'],
  BattleCopy.choicePhase: ['SEÇİM', 'CHOICE'],
  BattleCopy.firstTurn: [
    'İlk tur: yalnızca satranç hamlesi',
    'First turn: chess move only',
  ],
  BattleCopy.yourTurn: ['Sıra sende', 'Your turn'],
  BattleCopy.opponentTurn: ['Rakibin sırası', "Opponent's turn"],
  BattleCopy.play: ['Oyna', 'Play'],
  BattleCopy.discard: ['Feda Et', 'Discard'],
  BattleCopy.pass: ['Kartı Geç', 'Skip Card'],
  BattleCopy.cancel: ['Vazgeç', 'Cancel'],
  BattleCopy.close: ['Kapat', 'Close'],
  BattleCopy.detail: ['Kart bilgisi', 'Card details'],
  BattleCopy.unused: ['Kullanılmadı', 'Unused'],
  BattleCopy.used: ['Kullanıldı', 'Used'],
  BattleCopy.discarded: ['Feda edildi', 'Discarded'],
  BattleCopy.target: ['Hedef seç', 'Choose a target'],
  BattleCopy.choosePiece: ['Bir taş seç', 'Choose a piece'],
  BattleCopy.chooseSquare: ['Bir kare seç', 'Choose a square'],
  BattleCopy.chooseZone: ['2 × 2 alan seç', 'Choose a 2 × 2 zone'],
  BattleCopy.chooseCard: [
    'Rakibin Kartları içinden kullanılmamış bir kart seç',
    'Choose an unused card from Opponent Cards',
  ],
  BattleCopy.chooseEffect: [
    'Kaldırılacak etkiyi seç',
    'Choose the effect to remove',
  ],
  BattleCopy.chooseSacrifice: [
    'Feda edeceğin diğer kartı seç',
    'Choose another card to sacrifice',
  ],
  BattleCopy.boundMove: [
    'İşaretli taşla özel hamleni tamamla',
    'Complete the special move with the marked piece',
  ],
  BattleCopy.confirm: ['Onayla', 'Confirm'],
  BattleCopy.privateChoice: [
    'Yalnızca senin görebildiğin kartlar',
    'Cards only you can see',
  ],
  BattleCopy.take: ['AL', 'TAKE'],
  BattleCopy.next: ['SONRA', 'NEXT'],
  BattleCopy.afterwards: ['ARDINDAN', 'AFTER'],
  BattleCopy.privateKnowledge: ['Özel bilgiler', 'Private knowledge'],
  BattleCopy.inHand: ['Elde', 'In hand'],
  BattleCopy.notInHand: ['Elde değil', 'Not in hand'],
  BattleCopy.stale: ['Güncel değil', 'Stale'],
  BattleCopy.upcoming: ['Bilinen sonraki kartlar', 'Known upcoming cards'],
  BattleCopy.syncing: ['Yeniden bağlanıyor', 'Reconnecting'],
  BattleCopy.pending: ['Hamle doğrulanıyor', 'Confirming action'],
  BattleCopy.unavailable: [
    'Maç verisi şu anda doğrulanamıyor',
    'Match data cannot be verified right now',
  ],
  BattleCopy.retry: ['Tekrar dene', 'Retry'],
  BattleCopy.loading: ['Tahtan hazırlanıyor', 'Preparing your board'],
  BattleCopy.emptyHand: ['Elinde kart yok', 'Your hand is empty'],
  BattleCopy.menu: ['Maç menüsü', 'Match menu'],
  BattleCopy.resign: ['Teslim ol', 'Resign'],
  BattleCopy.resigned: ['Teslim olundu', 'Resigned'],
  BattleCopy.resignQuestion: [
    'Bu maçta teslim olmak istiyor musun?',
    'Do you want to resign this match?',
  ],
  BattleCopy.leave: ['Maç ekranından ayrıl', 'Leave the match screen'],
  BattleCopy.home: ['Ana menü', 'Home'],
  BattleCopy.victory: ['Zafer', 'Victory'],
  BattleCopy.defeat: ['Yenilgi', 'Defeat'],
  BattleCopy.draw: ['Berabere', 'Draw'],
  BattleCopy.check: ['Şah', 'Check'],
  BattleCopy.timeout: ['Süre doldu', 'Time expired'],
  BattleCopy.checkmate: ['Şah mat', 'Checkmate'],
  BattleCopy.stalemate: ['Pat', 'Stalemate'],
  BattleCopy.ended: ['Maç sona erdi', 'Match ended'],
  BattleCopy.rematch: ['Yeniden oyna', 'Play again'],
  BattleCopy.newMatch: ['Yeni sıralı maç', 'New ranked match'],
  BattleCopy.trophyChange: ['Kupa değişimi', 'Trophy change'],
  BattleCopy.settlementPending: [
    'Maç sonucu işleniyor',
    'Processing match result',
  ],
  BattleCopy.promotion: ['Terfi taşı seç', 'Choose a promotion piece'],
  BattleCopy.empty: ['Boş', 'Empty'],
  BattleCopy.white: ['Beyaz', 'White'],
  BattleCopy.black: ['Siyah', 'Black'],
  BattleCopy.earlier: ['Öne al', 'Earlier'],
  BattleCopy.later: ['Sona al', 'Later'],
  BattleCopy.legalTarget: ['Geçerli hedef', 'Legal target'],
  BattleCopy.seventyFive: ['75 hamle kuralı', '75-move rule'],
  BattleCopy.fivefold: ['Beş kez tekrar', 'Fivefold repetition'],
};
const _names = <CardId, List<String>>{
  CardId.radar: ['Radar', 'Radar'],
  CardId.prophecy: ['Kehanet', 'Prophecy'],
  CardId.shelter: ['Siper', 'Shelter'],
  CardId.chain: ['Zincir', 'Chain'],
  CardId.slow: ['Yavaşlatma', 'Slow'],
  CardId.pawnDeviation: ['Piyon Sapması', 'Pawn Deviation'],
  CardId.pawnAdvance: ['Piyon Atılımı', 'Pawn Advance'],
  CardId.lockedSquare: ['Kilitli Kare', 'Locked Square'],
  CardId.freeze: ['Dondurma', 'Freeze'],
  CardId.purify: ['Arındırma', 'Purify'],
  CardId.mine: ['Mayın', 'Mine'],
  CardId.breakSeal: ['Mühür Bozma', 'Break Seal'],
  CardId.fog: ['Sis', 'Fog'],
  CardId.manaSabotage: ['Mana Sabotajı', 'Mana Sabotage'],
  CardId.cardBlock: ['Kart Kilidi', 'Card Block'],
  CardId.rookBend: ['Kale Kıvrımı', 'Rook Bend'],
  CardId.angryN: ['At İsyanı', 'Knight Revolt'],
  CardId.shadowPass: ['Gölge Geçişi', 'Shadow Pass'],
  CardId.huntVow: ['Av Yemini', 'Hunt Vow'],
  CardId.watchVow: ['Gözcü Yemini', 'Watch Vow'],
  CardId.echo: ['Yankı', 'Echo'],
  CardId.fateExchange: ['Kader Takası', 'Fate Exchange'],
  CardId.shadowContract: ['Gölge Antlaşması', 'Shadow Contract'],
  CardId.boardSeal: ['Tahta Mührü', 'Board Seal'],
};
const _descriptions = <CardId, List<String>>{
  CardId.radar: [
    'Rakibin bir kullanılmamış kartını seç. Şu an elinde mi, yalnızca sen öğren.',
    'Choose an unused opponent card. Privately learn whether it is in their hand right now.',
  ],
  CardId.prophecy: [
    'Destenin başındaki en fazla 2 kartı gör ve sırala. Eline kart eklemez; sonra taş hamleni yaparsın.',
    'Look at and reorder up to 2 cards at the front of your deck. You take no card; your chess move follows.',
  ],
  CardId.shelter: [
    'Şah dışındaki bir taşını seç. Rakibin sonraki kart seçimi bitene kadar o taşı doğrudan hedefleyen kartları engelle; taş yemeyi engellemez.',
    'Choose your non-king piece. Block cards that directly target it until the opponent finishes their next card choice; captures still work.',
  ],
  CardId.chain: [
    'Şah dışındaki bir rakip taşı seç. Rakibin sonraki taş hamlesinde taş yiyemez; boş kareye gidebilir. Başka taş oynansa da etki biter.',
    'Choose an opposing non-king piece. It cannot capture on their next chess move, but may move to an empty square. Any completed move ends it.',
  ],
  CardId.slow: [
    'Bir rakip fil, kale veya vezir seç. Rakibin sonraki taş hamlesinde en fazla 2 kare gider; başka taş oynansa da etki biter.',
    'Choose an opposing bishop, rook or queen. Limit it to 2 squares on their next chess move; the effect ends even if another piece moves.',
  ],
  CardId.pawnDeviation: [
    'Bir piyonunu seç; bu tur onunla çapraz ileri 1 kare boş hedefe git. Ek hamle vermez, taş yemez ve son sıraya gidemez.',
    'Choose your pawn; use this turn\'s move to go 1 square diagonally forward to an empty square. No extra move, capture or final-rank landing.',
  ],
  CardId.pawnAdvance: [
    'Bir piyonunu seç; bu tur onunla tam 2 kare ileri git. İki kare de boş olmalı; son sıraya gidemez. Başlangıç karesinde olması gerekmez.',
    'Choose your pawn; use this turn\'s move to advance exactly 2 squares. Both squares must be empty; not the final rank. No starting-rank requirement.',
  ],
  CardId.lockedSquare: [
    'Boş bir kare seç. Rakibin sonraki taş hamlesinde şah dışındaki taşları oraya inemez. Kare dolarsa normal taş yeme mümkündür.',
    'Choose an empty square. Opposing non-king pieces cannot land there on their next chess move. Normal captures remain possible if it becomes occupied.',
  ],
  CardId.freeze: [
    'Şah dışındaki bir rakip taşı seç. Rakibin sonraki taş hamlesinde hareket edemez; başka taş oynansa da etki biter.',
    'Choose an opposing non-king piece. It cannot move on their next chess move; the effect ends even if they move another piece.',
  ],
  CardId.purify: [
    'Bir taşındaki tek bir Zincir, Yavaşlatma, Dondurma veya tetiklenmiş Mayın etkisini seç ve hemen kaldır. Diğer etkiler kalır.',
    'Choose and immediately remove one Chain, Slow, Freeze or triggered Mine effect from your piece. Other effects remain.',
  ],
  CardId.mine: [
    'Boş kareye görünür Mayın koy. Gelen rakip taşın sonraki kendi hareketinde taş yemesini engeller; taşı yok etmez. Şah tetiklemez.',
    'Place a visible Mine on an empty square. An arriving enemy cannot capture on its next own move; it is not destroyed. Kings do not trigger it.',
  ],
  CardId.breakSeal: [
    'Rakibin tahtadaki tek bir Mayın, Kilitli Kare, Sis veya Tahta Mührü etkisini seç ve hemen kaldır. Çakışan diğer etkiler kalır.',
    'Choose and immediately remove one opposing Mine, Locked Square, Fog or Board Seal on the board. Other overlapping effects remain.',
  ],
  CardId.fog: [
    '2 × 2 alan seç. İçindeki taşlarını rakibin sonraki kart seçimi bitene kadar doğrudan hedefleyen kartlardan koru; taşları gizlemez.',
    'Choose a 2 × 2 zone. Protect your pieces inside from direct card targets until the opponent finishes their next card choice; pieces stay visible.',
  ],
  CardId.manaSabotage: [
    'Rakibin bir kullanılmamış kartını seç. Sonraki kart aşamasında o kartın bedeli +1 mana olur; rakibin mevcut manasını azaltmaz.',
    'Choose an unused opponent card. It costs +1 mana during their next card phase; this does not remove mana they already have.',
  ],
  CardId.cardBlock: [
    'Rakibin bir kullanılmamış kartını seç. Sonraki kart aşamasında oynanamaz; yine de feda edilebilir. Kilit o aşama bitince kalkar.',
    'Choose an unused opponent card. They cannot play it in their next card phase, but may discard it. The block ends with that phase.',
  ],
  CardId.rookBend: [
    'Bir kaleni seç; bu tur onunla çapraz 1 kare boş hedefe git. Ek hamle vermez ve taş yemez; o taraftaki rok hakkı geri gelmez.',
    'Choose your rook; use this turn\'s move to go 1 square diagonally to an empty square. No extra move or capture; castling rights are not restored.',
  ],
  CardId.angryN: [
    'Bir atını seç; bu tur onunla yatay veya dikey 1 kare git. Rakip taşı yiyebilir. Ek hamle veya Av Yemini ödülü vermez.',
    'Choose your knight; use this turn\'s move to go 1 square horizontally or vertically. It may capture, but gives no extra move or Hunt Vow reward.',
  ],
  CardId.shadowPass: [
    'Fil veya kaleni seç; bu tur tam bir dost taşın üzerinden geçip boş kareye git. Şah aşılamaz; taş yemez ve ek hamle vermez.',
    'Choose your bishop or rook; use this turn\'s move to pass through exactly 1 friendly non-king piece to an empty square. No capture or extra move.',
  ],
  CardId.huntVow: [
    'Bir rakip taşı işaretle. Bu tur dahil 2 kendi taş hamlen içinde normal hamleyle yersen +2 mana al; özel hamleyle yersen ödül yok. Şah seçilemez.',
    'Mark an opposing non-king piece. Capture it normally within 2 own chess moves, including this turn, for +2 mana. Special-move captures give no reward.',
  ],
  CardId.watchVow: [
    'Boş kareyi işaretle. Rakibin sonraki taş hamlesi sonunda orada rakip taş varsa +2 mana al; şah da sayılır. Sonra yemin biter.',
    'Mark an empty square. Gain +2 mana if an opposing piece, including a king, is there after their next chess move. The vow then ends.',
  ],
  CardId.echo: [
    'Rakibin bir kullanılmamış kartını seç. Sonraki kart aşamasında onu oynarsa sen +2 mana alırsın; feda eder veya geçerse ödül yok.',
    'Choose an unused opponent card. Gain +2 mana if they play it in their next card phase; discarding or skipping gives no reward.',
  ],
  CardId.fateExchange: [
    'Başka bir el kartını feda et. Destendeki sıradaki en fazla 3 kartı gör; birini eline al, kalanları sırala. Aldığın kartı bu tur oynayamazsın.',
    'Sacrifice another hand card. Inspect up to 3 upcoming cards; take 1 and reorder the rest. You cannot play the card you take this turn.',
  ],
  CardId.shadowContract: [
    'Başka bir el kartını feda et. Sonraki kendi kart aşamanda bedeller 2 azalır, en az 1 mana ödersin. Bu tur indirim veya mana vermez.',
    'Sacrifice another hand card. On your next card phase, costs decrease by 2, to at least 1 mana. No discount or mana is granted this turn.',
  ],
  CardId.boardSeal: [
    '2 × 2 alan seç. Rakibin sonraki taş hamlesinde şah dışındaki taşları alanın boş karelerine inemez; dolu karede normal taş yeme mümkündür.',
    'Choose a 2 × 2 zone. Opposing non-king pieces cannot land on its empty squares on their next chess move; normal captures on occupied squares still work.',
  ],
};

const _outcomes = <CardId, List<String>>{
  CardId.radar: [
    'Rakibin kartının elde olup olmadığı öğrenildi.',
    'The opponent card was checked for hand presence.',
  ],
  CardId.prophecy: [
    'Sıradaki kartların açıldı. Çekilme sırasını sen seç.',
    'Your upcoming cards are revealed. Choose their order.',
  ],
  CardId.shelter: [
    'Hedef taş doğrudan kart hedeflerine karşı korundu; normal şekilde yenebilir.',
    'The target is protected from direct card targets, but can still be captured.',
  ],
  CardId.chain: [
    'Hedef taş, sahibinin sonraki taş hamlesinde taş yiyemez.',
    'The target cannot capture on its owner\'s next chess move.',
  ],
  CardId.slow: [
    'Hedef taş, sahibinin sonraki taş hamlesinde en fazla 2 kare gider.',
    'The target is limited to 2 squares on its owner\'s next chess move.',
  ],
  CardId.pawnDeviation: [
    'Seçili piyon bu tur çapraz ileri boş kareye gidebilir.',
    'The selected pawn may move to an empty forward diagonal this turn.',
  ],
  CardId.pawnAdvance: [
    'Seçili piyon bu tur tam 2 kare ileri gidebilir.',
    'The selected pawn may advance exactly 2 squares this turn.',
  ],
  CardId.lockedSquare: [
    'Boş kareye iniş engeli uygulandı; şah bundan etkilenmez.',
    'Empty-square landing restriction applied; kings are exempt.',
  ],
  CardId.freeze: [
    'Hedef taş, sahibinin sonraki taş hamlesinde hareket edemez.',
    'The target cannot move on its owner\'s next chess move.',
  ],
  CardId.purify: [
    'Seçilen olumsuz taş etkisi kaldırıldı.',
    'The selected negative piece effect was removed.',
  ],
  CardId.mine: [
    'Mayın yerleştirildi. Tetikleyen taş, sonraki kendi hareketinde taş yiyemez.',
    'Mine placed. The triggering piece cannot capture on its next own move.',
  ],
  CardId.breakSeal: [
    'Seçilen tahta etkisi tüm alanıyla kaldırıldı.',
    'The selected opposing board effect was removed from its entire zone.',
  ],
  CardId.fog: [
    'Alandaki dost taşlar doğrudan kart hedeflerine karşı korundu.',
    'Friendly pieces in the zone are protected from direct card targets.',
  ],
  CardId.manaSabotage: [
    'Hedef kart, sahibinin sonraki kart aşamasında +1 mana tutar.',
    'The target card costs +1 mana in its owner\'s next card phase.',
  ],
  CardId.cardBlock: [
    'Hedef kart, sahibinin sonraki kart aşamasında oynanamaz; feda edilebilir.',
    'The target card cannot be played in its owner\'s next card phase, but may be discarded.',
  ],
  CardId.rookBend: [
    'Seçili kale bu tur çapraz 1 boş kareye gidebilir.',
    'The selected rook may move 1 diagonal square to an empty destination this turn.',
  ],
  CardId.angryN: [
    'Seçili at bu tur yatay veya dikey 1 kare gidebilir.',
    'The selected knight may move 1 horizontal or vertical square this turn.',
  ],
  CardId.shadowPass: [
    'Seçili taş bu tur bir dost taş üzerinden geçebilir.',
    'The selected piece may pass through 1 friendly piece this turn.',
  ],
  CardId.huntVow: [
    'Kartı oynayan, hedefi 2 kendi hamlesi içinde normal yakalarsa +2 mana alır.',
    'The caster gains +2 mana for a normal target capture within 2 own moves.',
  ],
  CardId.watchVow: [
    'Rakibin sonraki taş hamlesi sonunda bu karede rakip taş varsa kartı oynayan +2 mana alır.',
    'The caster gains +2 mana if an opposing piece occupies this square after their next chess move.',
  ],
  CardId.echo: [
    'Hedef kart sonraki kart aşamasında oynanırsa Yankı sahibine +2 mana verir.',
    'If the target is played in its next card phase, Echo grants its owner +2 mana.',
  ],
  CardId.fateExchange: [
    'Bir kart feda edildi. Açılan kartlardan birini al, kalanları sırala.',
    'A card was sacrificed. Take 1 revealed card and order the rest.',
  ],
  CardId.shadowContract: [
    'Bir kart feda edildi. Kartı oynayanın sonraki kart aşamasında 2 mana indirim.',
    'A card was sacrificed. The caster\'s next card phase has a 2-mana discount.',
  ],
  CardId.boardSeal: [
    'Alanda boş kareye iniş engeli uygulandı; şah bundan etkilenmez.',
    'Empty-square landing restriction applied in the zone; kings are exempt.',
  ],
};

const _opponentPrivateOutcomes = <CardId, List<String>>{
  CardId.radar: [
    'Rakip bir kartını sorguladı. Sonuç yalnızca ona gösterilir.',
    'The opponent checked one of your cards. Only they see the result.',
  ],
  CardId.prophecy: [
    'Rakip kendi destesindeki sırayı seçiyor. Kartları sana gizli.',
    'The opponent is ordering their own deck. Those cards stay hidden from you.',
  ],
  CardId.fateExchange: [
    'Rakip bir kart feda etti; kendi destesinden bir kart seçiyor. Seçimi sana gizli.',
    'The opponent sacrificed a card and is choosing one from their own deck. Their choice stays hidden from you.',
  ],
};

const _details = <CardId, List<BattleCardExplanation>>{
  CardId.radar: [
    BattleCardExplanation(
      selection:
          'Rakibin Kartları içinden kullanılmamış ve feda edilmemiş bir kart seç.',
      effect:
          'O kart şu an rakibin elinde mi, yalnızca sen öğrenirsin. Başka kartları veya destedeki çekilme sırasını göstermez.',
      duration:
          '"Elde değil" bilgisi rakip yeni kart alınca; "elde" bilgisi o kart kullanılınca veya feda edilince eskir. Eski bilgi garanti değildir.',
      caution:
          'Bu kartı kullanınca kart aşaman biter; ardından taş hamleni yaparsın. Rakibin elindeki kartı almaz veya kilitlemez.',
    ),
    BattleCardExplanation(
      selection: 'Choose one unused, undiscarded card from Opponent Cards.',
      effect:
          'Only you learn whether it is in their hand right now. No other hidden cards or deck positions are revealed.',
      duration:
          'A "not in hand" result becomes stale when they acquire a card; an "in hand" result becomes stale when that card is used or discarded. Old information is not a guarantee.',
      caution:
          'Your card phase ends; your chess move follows. Radar does not take or block the opponent\'s card.',
    ),
  ],
  CardId.prophecy: [
    BattleCardExplanation(
      selection:
          'Kartı oyna; tahtada hedef seçmezsin. Destende en az 1 kart kalmalı.',
      effect:
          'Destenin başındaki en fazla 2 kartı yalnızca sen görürsün. Hangisinin önce geleceğini seç; tek kart kaldıysa yalnızca onu görürsün. Eline kart eklemez; normal kart çekişi değildir.',
      duration:
          'Sıralamayı onaylayınca kart aşaman biter, taş hamlene geçersin. Seçtiğin sıra kartlar çekilene veya yeniden sıralanana kadar kalır.',
      caution:
          'Bu tur ikinci kart oynayamazsın. Taş hamlenden sonra destende kart ve elinde yer varsa normal şekilde 1 kart çekersin.',
    ),
    BattleCardExplanation(
      selection:
          'Play the card; choose no board target. Your deck must contain at least 1 card.',
      effect:
          'Privately inspect up to 2 cards at the front of your deck and choose their order. With 1 left, inspect only that card. This is not a normal draw and adds no card to your hand.',
      duration:
          'Confirming the order ends your card phase; your chess move follows. The order stays until those cards are drawn or reordered.',
      caution:
          'You cannot play another card this turn. After your chess move, the normal 1-card draw still occurs if your deck has cards and your hand has room.',
    ),
  ],
  CardId.shelter: [
    BattleCardExplanation(
      selection: 'Şah dışındaki kendi taşlarından birini seç.',
      effect:
          'Rakip o taşı doğrudan seçen kartları ona uygulayamaz. Koruma taşla birlikte hareket eder.',
      duration:
          'Rakibin sıradaki kart aşaması kapanınca, yani kart seçimi tamamlanınca biter. Taş daha önce yenirse de kalkar.',
      caution:
          'Normal taş yemeyi, Mayın gibi kare etkilerini veya önceden uygulanmış etkileri engellemez. Taşı görünmez ya da yenilmez yapmaz.',
    ),
    BattleCardExplanation(
      selection: 'Choose one of your non-king pieces.',
      effect:
          'The opponent cannot use cards that directly select that piece. Protection follows the piece as it moves.',
      duration:
          'It ends when the opponent closes their next card phase, before their chess move, or earlier if the piece is captured.',
      caution:
          'It does not stop normal captures, square effects such as Mine, or existing effects. The piece remains visible and can still be captured.',
    ),
  ],
  CardId.chain: [
    BattleCardExplanation(
      selection:
          'Siper veya Sis ile korunmayan bir rakip taş seç; şah seçilemez.',
      effect:
          'Rakibin sıradaki taş hamlesinde bu taş taş yiyemez. Normal ve özel yakalamalar ile geçerken alma engellenir; kurallara uygun boş kareye gidebilir.',
      duration:
          'Rakip hangi taşını oynarsa oynasın, o taş hamlesi sonunda biter. Hedef yenirse de kalkar.',
      caution:
          'Arındırma ile kaldırılabilir. Rakip başka taşını oynayabilir; Zincir hedefin hareket etmesini tamamen durdurmaz.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an opposing non-king piece not protected by Shelter or Fog.',
      effect:
          'It cannot capture on the opponent\'s next chess move, including special captures and en passant. It may legally move to an empty destination.',
      duration:
          'It ends after that chess move even if a different piece moves, or earlier if the target is captured.',
      caution:
          'Purify removes it. The opponent may move another piece; Chain does not stop all movement by the target.',
    ),
  ],
  CardId.slow: [
    BattleCardExplanation(
      selection:
          'Siper veya Sis ile korunmayan bir rakip fil, kale veya vezir seç.',
      effect:
          'Rakibin sıradaki taş hamlesinde bu taş en fazla 2 kare gider. İzin verilen yönde 1 veya 2 kare gidebilir; aradaki taşları aşamaz.',
      duration:
          'Rakip başka taşını oynasa bile o taş hamlesi sonunda biter. Hedef yenirse de kalkar.',
      caution:
          'Piyon, at ve şah seçilemez. Arındırma ile kaldırılabilir. Yakalama tamamen yasak değildir; hedef 2 kare içinde taş yiyebilir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an opposing bishop, rook or queen not protected by Shelter or Fog.',
      effect:
          'On the next opposing chess move, it can travel at most 2 squares along a permitted direction. It cannot jump intervening pieces.',
      duration:
          'It ends after that chess move even if another piece moves, or earlier if the target is captured.',
      caution:
          'Pawns, knights and kings cannot be selected. Purify removes it. Capturing is still allowed within the 2-square limit.',
    ),
  ],
  CardId.pawnDeviation: [
    BattleCardExplanation(
      selection: 'Geçerli özel hamlesi olan kendi piyonlarından birini seç.',
      effect:
          'Bu tur o piyonla çapraz ileri tam 1 kare boş hedefe gitmelisin. Bu, normal taş hamlenin yerine geçer; ek hamle vermez.',
      duration:
          'Seçtiğin piyonun bu hamlesi tamamlanınca kartın hareket izni biter. Bu tur başka taş oynanamaz.',
      caution:
          'Son yataya gidilemez; taş yenemez ve geçerken alma hakkı oluşturmaz. Şahını tehdit altında bırakamazsın; mevcut hareket kısıtları geçerlidir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose one of your pawns with an available legal special move.',
      effect:
          'Use this turn\'s chess move to move that pawn exactly 1 square diagonally forward to an empty destination. This replaces the normal move; it is not an extra move.',
      duration:
          'The permission ends after that pawn moves. You cannot move another piece instead this turn.',
      caution:
          'It cannot reach the final rank or capture, and creates no en passant right. You cannot leave your king in check; active movement restrictions still apply.',
    ),
  ],
  CardId.pawnAdvance: [
    BattleCardExplanation(
      selection: 'Geçerli özel hamlesi olan kendi piyonlarından birini seç.',
      effect:
          'Bu tur o piyonla tam 2 kare ileri gitmelisin. Yol ve hedef boş olmalı. Başlangıç karesi dışında veya önceden hareket etmiş bir piyonla da kullanılabilir.',
      duration:
          'O piyonun bu hamlesi tamamlanınca hareket izni biter. Normal taş hamlenin yerine geçer; ek hamle vermez, başka taş oynayamazsın.',
      caution:
          'Son yataya gidilemez ve taş yenemez. Hareket aynı zamanda hiç oynamamış piyonun normal başlangıç çift adımıysa geçerken alma hakkı doğar; yalnızca kartla mümkün olan çift adım bu hakkı doğurmaz. Şah güvenliği ve hareket kısıtları geçerlidir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose one of your pawns with an available legal special move.',
      effect:
          'Advance it exactly 2 squares this turn; the intervening square and destination must both be empty. It works away from its starting rank or after the pawn has moved.',
      duration:
          'Permission ends after that move. It replaces your normal chess move; it gives no extra move and no other piece may move instead.',
      caution:
          'It cannot capture or reach the final rank. A normal starting-square double-step by an unmoved pawn gives an en passant opportunity; a double-step possible only through the card creates no such right. King safety and movement restrictions still apply.',
    ),
  ],
  CardId.lockedSquare: [
    BattleCardExplanation(
      selection: 'Boş bir kare seç.',
      effect:
          'Rakibin sıradaki taş hamlesinde şah dışındaki taşları, kare hâlâ boşsa oraya inemez. Üzerinden geçebilirler. Kendi taşların etkilenmez.',
      duration:
          'Rakibin sıradaki taş hamlesi sonunda biter; Mühür Bozma ile daha erken kaldırılabilir.',
      caution:
          'Şah muaftır; rokta kale bu kurala uyar. Kare dolarsa oradaki taşı normal yakalamak mümkündür. Geçerken alma boş hedefe indiği için engellenir.',
    ),
    BattleCardExplanation(
      selection: 'Choose an empty square.',
      effect:
          'On the next opposing chess move, their non-king pieces cannot land there while it is empty, but may pass through it. Your pieces are unaffected.',
      duration:
          'The lock expires after the opponent\'s next chess move. Break Seal can remove it earlier.',
      caution:
          'Kings are exempt; a rook moving during castling is not. A normal capture onto an occupied square is allowed. An en passant destination is empty, so it is blocked.',
    ),
  ],
  CardId.freeze: [
    BattleCardExplanation(
      selection:
          'Siper veya Sis ile korunmayan bir rakip taş seç; şah seçilemez.',
      effect:
          'Rakibin sıradaki taş hamlesinde o taş normal veya özel hamle yapamaz. Dondurulmuş kaleyle rok da yapılamaz.',
      duration:
          'Rakip başka bir taş oynasa bile o taş hamlesi sonunda biter. Hedef yenirse de kalkar.',
      caution:
          'Arındırma ile kaldırılabilir. Taş tahtada kalır ve normal şekilde yenebilir; rakibin diğer taşları hareket edebilir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an opposing non-king piece not protected by Shelter or Fog.',
      effect:
          'It cannot make a normal or special move on the opponent\'s next chess move. Castling with a frozen rook is also unavailable.',
      duration:
          'It ends after that chess move even if another piece moves, or earlier if the target is captured.',
      caution:
          'Purify removes it. The piece stays on the board and can still be captured; the opponent may move another piece.',
    ),
  ],
  CardId.purify: [
    BattleCardExplanation(
      selection:
          'Kendi taşlarından birindeki tek bir olumsuz etkiyi seç: Zincir, Yavaşlatma, Dondurma veya tetiklenmiş Mayın.',
      effect:
          'Yalnızca seçtiğin etki hemen kaldırılır. Aynı taşta başka etkiler varsa diğerleri kalır.',
      duration:
          'Kaldırma anlıktır. Ardından taş hamleni yaparsın; kaldırılan etki geri gelmez.',
      caution:
          'Uygun etki yoksa oynanamaz. Siper, tahta üzerindeki Mayın veya mühürler, yeminler ve kart bedeli/kilit etkilerini kaldırmaz.',
    ),
    BattleCardExplanation(
      selection:
          'Choose exactly one negative effect on one of your pieces: Chain, Slow, Freeze or a triggered Mine.',
      effect:
          'Remove that instance immediately; other overlapping effects remain on the piece.',
      duration:
          'Removal is immediate. Your chess move follows; the removed effect does not return.',
      caution:
          'It cannot be played without an eligible effect. It does not remove Shelter, traps or seals on the board, vows, or card cost/block effects.',
    ),
  ],
  CardId.mine: [
    BattleCardExplanation(
      selection:
          'Boş ve başka Mayın bulunmayan bir kare seç. Aynı anda yalnızca bir aktif Mayının olabilir.',
      effect:
          'Görünür tuzak, rakibin şah dışındaki taşı kareye gelince tüketilir. Taşı yok etmez. Tetikleyen hamledeki yakalamayı durdurmaz; taşın sonraki kendi hareketinde taş yemesini engeller.',
      duration:
          'Tuzak tetiklenene veya Mühür Bozma ile kaldırılana kadar kalır. Tetiklenmiş etki başka taşlar oynanınca bitmez; o taş hareket edince veya yenince biter.',
      caution:
          'Kendi taşların ve şahlar tetiklemez; rokta gelen kale tetikleyebilir. Arındırma tetiklenmiş etkiyi kaldırır. Etkilenen taşın boş kareye gitmesi de etkiyi tüketir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an empty square with no Mine. You may have only 1 active Mine.',
      effect:
          'The visible trap is consumed when an opposing non-king piece arrives. It does not destroy the piece or stop a capture by the triggering move. That piece cannot capture on its next own move.',
      duration:
          'The trap lasts until triggered or removed by Break Seal. Moving other pieces does not end the triggered effect; it ends when that piece moves or is captured.',
      caution:
          'Your pieces and kings do not trigger it; a rook arriving during castling can. Purify removes the triggered effect. Moving the affected piece to an empty square also consumes it.',
    ),
  ],
  CardId.breakSeal: [
    BattleCardExplanation(
      selection:
          'Rakibin tahtadaki tek bir Mayın, Kilitli Kare, Sis veya Tahta Mührü etkisini seç.',
      effect:
          'Seçtiğin etki tüm alanıyla hemen kaldırılır. Aynı karelerdeki diğer etkiler kalır.',
      duration:
          'Kaldırma anlıktır. Ardından taş hamleni yaparsın; kaldırılan etki geri gelmez.',
      caution:
          'Uygun rakip tahta etkisi yoksa oynanamaz; kendi etkini kaldıramazsın. Tetiklenmiş Mayın artık taş etkisidir. Siper, Zincir, Yavaşlatma, Dondurma, yeminler ve kart bedeli/kilit etkileri de kaldırılmaz.',
    ),
    BattleCardExplanation(
      selection:
          'Choose one opposing Mine, Locked Square, Fog or Board Seal currently on the board.',
      effect:
          'Remove that whole effect immediately. Other overlapping effects remain.',
      duration:
          'Removal is immediate. Your chess move follows; the removed effect does not return.',
      caution:
          'It requires an eligible opposing board effect; you cannot remove your own. A triggered Mine is a piece effect. Shelter, Chain, Slow, Freeze, vows and card cost/block effects are not removed.',
    ),
  ],
  CardId.fog: [
    BattleCardExplanation(
      selection:
          'Tahtanın içinde kalan bir 2 × 2 alan seç. Alanın boş olması gerekmez.',
      effect:
          'Alandaki kendi taşların doğrudan taş seçen rakip kartlardan korunur. Koruma alanla bağlıdır; dışarı çıkan taş korunmaz.',
      duration:
          'Rakibin sıradaki kart aşaması kapanınca, taş hamlesinden önce biter. Mühür Bozma daha erken kaldırabilir.',
      caution:
          'Taşları gizlemez. Normal taş yemeyi, Mayın gibi kare etkilerini veya önceden uygulanmış etkileri engellemez. Alan ve taşlar herkese görünür.',
    ),
    BattleCardExplanation(
      selection:
          'Choose a 2 × 2 zone fully inside the board. It need not be empty.',
      effect:
          'Protect your pieces inside from opposing cards that directly select a piece. Protection belongs to the zone, not the pieces; a piece leaving it loses protection.',
      duration:
          'It ends when the opponent\'s next card phase closes, before their chess move. Break Seal can remove it earlier.',
      caution:
          'It does not hide pieces or stop normal captures, square effects such as Mine, or existing effects. The zone and pieces remain visible.',
    ),
  ],
  CardId.manaSabotage: [
    BattleCardExplanation(
      selection:
          'Rakibin Kartları içinden kullanılmamış ve feda edilmemiş bir kart seç; elinde olduğunu bilmen gerekmez.',
      effect:
          'Rakibin sıradaki kart aşamasında yalnızca o kartın bedeli +1 mana artar. Rakibin mevcut manasını azaltmaz.',
      duration:
          'O kart aşaması kapanınca, kart oynansa da oynanmasa da biter. Daha sonraki turlara saklanmaz.',
      caution:
          'Gölge Antlaşması indirimiyle birlikte hesaplanır; sonuç en az 1 manadır. Rakip başka kart oynayabilir, feda edebilir veya Kartı Geç seçebilir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an unused, undiscarded opponent card; you need not know whether it is in their hand.',
      effect:
          'Only that card costs +1 mana in the opponent\'s next card phase. No mana is removed from their current balance.',
      duration:
          'It ends when that card phase closes, whether or not they play the card. It does not carry into later turns.',
      caution:
          'Combine it with any Shadow Contract discount before applying the minimum cost of 1 mana. They can play another card, discard or skip.',
    ),
  ],
  CardId.cardBlock: [
    BattleCardExplanation(
      selection:
          'Rakibin Kartları içinden kullanılmamış ve feda edilmemiş bir kart seç; elinde olduğunu bilmen gerekmez.',
      effect:
          'Rakip o kartı sıradaki kart aşamasında oynayamaz. Kartı elinden veya destesinden silmez.',
      duration:
          'Rakibin sıradaki kart aşaması kapanınca kilit biter; daha sonraki turlara kalmaz.',
      caution:
          'Rakip kilitli kartı feda edebilir, başka kart oynayabilir veya Kartı Geç seçebilir. Diğer kartlarını ve ardından gelecek taş hamlesini engellemez.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an unused, undiscarded opponent card; you need not know whether it is in their hand.',
      effect:
          'They cannot play that card in their next card phase. It does not delete the card from their hand or deck.',
      duration:
          'The block ends when that next card phase closes; it does not carry into later turns.',
      caution:
          'They may discard the blocked card, play another card or Skip Card. Other cards and their following chess move are not blocked.',
    ),
  ],
  CardId.rookBend: [
    BattleCardExplanation(
      selection: 'Geçerli özel hamlesi olan kendi kalelerinden birini seç.',
      effect:
          'Bu tur o kaleyle çapraz tam 1 kare boş hedefe gitmelisin. Taş yenemez. Normal taş hamlenin yerine geçer; ek hamle vermez.',
      duration:
          'O hamle tamamlanınca hareket izni biter. Bu tur başka taş oynayamazsın.',
      caution:
          'Başlangıç köşesinden ayrılan kale o taraftaki rok hakkını kalıcı olarak kaybettirir; geri dönmesi hakkı getirmez. Şah güvenliği ve hareket kısıtları geçerlidir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose one of your rooks with an available legal special move.',
      effect:
          'Move that rook exactly 1 diagonal square to an empty destination this turn. It cannot capture. This replaces your normal chess move; it is not an extra move.',
      duration:
          'Permission ends after that move. You cannot move another piece instead this turn.',
      caution:
          'Leaving the original corner permanently removes castling rights on that side; returning the rook does not restore them. King safety and movement restrictions still apply.',
    ),
  ],
  CardId.angryN: [
    BattleCardExplanation(
      selection: 'Geçerli özel hamlesi olan kendi atlarından birini seç.',
      effect:
          'Bu tur o atla yatay veya dikey tam 1 kare gitmelisin. Boş kareye gidebilir veya şah dışındaki bir rakip taşı yiyebilirsin; dost taşın üzerine gidemezsin.',
      duration:
          'O hamle tamamlanınca hareket izni biter. Başka taş oynanamaz; bu, normal taş hamlenin yerine geçer ve ek hamle vermez.',
      caution:
          'Şah güvenliği, Zincir, Dondurma ve tetiklenmiş Mayın gibi hareket kısıtları geçerlidir. Av Yemini bu özel yakalamaya ödül vermez.',
    ),
    BattleCardExplanation(
      selection:
          'Choose one of your knights with an available legal special move.',
      effect:
          'Move it exactly 1 square horizontally or vertically (an orthogonal move). Land on an empty square or capture an opposing non-king piece; not a friendly piece.',
      duration:
          'Permission ends after that move. No other piece may move instead; this replaces the normal chess move, not an extra move.',
      caution:
          'King safety and restrictions such as Chain, Freeze and a triggered Mine still apply. Hunt Vow gives no reward for this special capture.',
    ),
  ],
  CardId.shadowPass: [
    BattleCardExplanation(
      selection:
          'Geçerli özel hamlesi olan kendi fil veya kalelerinden birini seç.',
      effect:
          'Fil çapraz, kale yatay veya dikey gider: tam bir dost şah dışı taşın üzerinden geçip ötesindeki boş kareye inmelidir. Taş yenemez.',
      duration:
          'O hamle tamamlanınca hareket izni biter. Bu, normal taş hamlenin yerine geçer; ek hamle vermez ve başka taş oynayamazsın.',
      caution:
          'İkinci taşın, rakip taşın veya şahın üzerinden geçilemez. Şah güvenliği ve hareket kısıtları geçerlidir. Başlangıç köşesinden ayrılan kale o taraftaki rok hakkını kalıcı olarak kaybettirir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose one of your bishops or rooks with an available legal special move.',
      effect:
          'A bishop moves diagonally; a rook horizontally or vertically. Pass through exactly 1 friendly non-king piece to an empty square beyond it. It cannot capture.',
      duration:
          'Permission ends after that move. This replaces your normal chess move; no extra move and no other piece may move instead.',
      caution:
          'You cannot cross a second piece, an opposing piece or any king. King safety and movement restrictions still apply. A rook leaving its original corner permanently loses that side\'s castling rights.',
    ),
  ],
  CardId.huntVow: [
    BattleCardExplanation(
      selection:
          'Siper veya Sis ile korunmayan bir rakip taşı işaretle; şah seçilemez. Aynı anda yalnızca bir Av veya Gözcü Yeminin olabilir.',
      effect:
          'Karttan hemen sonraki hamle dahil, 2 kendi taş hamlen içinde hedefi normal satranç yakalamasıyla alırsan +2 mana kazanırsın. Toplam mana 6 sınırını aşmaz; işaret taşla birlikte gider.',
      duration:
          'Hedef alınınca veya 2 kendi taş hamlen tamamlanınca biter. Rakibin aradaki hamlesi süreyi azaltmaz.',
      caution:
          'Özel hareket kartıyla yapılan yakalama, normal hamleye benzese bile ödül vermez. Arındırma ve Mühür Bozma yemini kaldırmaz.',
    ),
    BattleCardExplanation(
      selection:
          'Mark an opposing non-king piece not protected by Shelter or Fog. You may have only 1 active Hunt or Watch Vow.',
      effect:
          'Gain +2 mana if you capture it with a normal chess move within your next 2 own chess moves, including the move after this card. Total mana is capped at 6; the mark follows the piece.',
      duration:
          'It ends when the target is captured or your 2 moves are completed. The opposing move between them does not use up this limit.',
      caution:
          'A capture through a movement card gives no reward, even if it resembles a normal move. Purify and Break Seal do not remove the vow.',
    ),
  ],
  CardId.watchVow: [
    BattleCardExplanation(
      selection:
          'Boş bir kareyi işaretle. Aynı anda yalnızca bir Av veya Gözcü Yeminin olabilir.',
      effect:
          'Rakibin sıradaki taş hamlesi sonunda orada bir rakip taş varsa +2 mana kazanırsın; şah da sayılır. Toplam mana 6 sınırını aşmaz.',
      duration:
          'Rakibin o tek taş hamlesi sonunda, ödül kazanılsa da kazanılmasa da biter.',
      caution:
          'Kareye taş getirmez veya inişi engellemez; rakip orayı boş bırakabilir. Arındırma ve Mühür Bozma yemini kaldırmaz.',
    ),
    BattleCardExplanation(
      selection:
          'Mark an empty square. You may have only 1 active Hunt or Watch Vow.',
      effect:
          'Gain +2 mana if an opposing piece is there after the opponent\'s next chess move; a king counts. Total mana is capped at 6.',
      duration:
          'It ends after that single opposing chess move, whether or not you receive the reward.',
      caution:
          'It neither moves pieces onto the square nor blocks landing; they can leave it empty. Purify and Break Seal do not remove the vow.',
    ),
  ],
  CardId.echo: [
    BattleCardExplanation(
      selection:
          'Rakibin Kartları içinden kullanılmamış ve feda edilmemiş bir kart seç; elinde olduğunu bilmen gerekmez.',
      effect:
          'Rakip o kartı sıradaki kart aşamasında oynarsa sen hemen +2 mana kazanırsın. Toplam mana 6 sınırını aşmaz.',
      duration: 'O kart aşaması kapanınca biter; sonraki tura taşınmaz.',
      caution:
          'Kartı feda etmek veya Kartı Geç seçmek ödül vermez. Kartı kopyalamaz, sana vermez veya bedelsiz oynatmaz.',
    ),
    BattleCardExplanation(
      selection:
          'Choose an unused, undiscarded opponent card; you need not know whether it is in their hand.',
      effect:
          'If they play it in their next card phase, you immediately gain +2 mana. Total mana is capped at 6.',
      duration:
          'It ends when that card phase closes; it does not carry into another turn.',
      caution:
          'Discarding the card or choosing Skip Card gives no reward. Echo does not copy the card, give it to you or let you play it for free.',
    ),
  ],
  CardId.fateExchange: [
    BattleCardExplanation(
      selection:
          'Elinden bu kart dışında bir kart seçip feda et. Başka el kartın ve destende en az 1 kart olmalı.',
      effect:
          'Destenin başındaki en fazla 3 kartı yalnızca sen görürsün: birini eline al, kalanların destenin başındaki sırasını seç. Aldığın kart ve sıra gizli kalır.',
      duration:
          'Seçimini onaylayınca kart aşaman biter; aldığın kartı bu tur oynayamazsın. Kader Takası ve feda ettiğin kart bu maçta geri gelmez.',
      caution:
          'Mana bedeline ek olarak diğer kartını kaybedersin. Bu alım normal hamle sonrası çekiş değildir; taş hamlenden sonra yer varsa normal çekiş yine yapılır. Rakibin "elde değil" Radar bilgisi eskiyebilir.',
    ),
    BattleCardExplanation(
      selection:
          'Sacrifice another card from your hand. You need another hand card and at least 1 card in your deck.',
      effect:
          'Privately inspect up to 3 cards at the front of your deck: take 1 and order the others at the front. Your chosen card and order stay private.',
      duration:
          'Confirming ends your card phase; you cannot play the card you take this turn. Fate Exchange and the sacrificed card do not return during this match.',
      caution:
          'You lose the other card in addition to paying mana. This is not the normal post-move draw; that draw still occurs after your chess move if there is room. An opposing "not in hand" Radar result can become stale.',
    ),
  ],
  CardId.shadowContract: [
    BattleCardExplanation(
      selection:
          'Elinden bu kart dışında bir kart seçip feda et. Başka el kartın yoksa oynanamaz.',
      effect:
          'Bir sonraki kendi kart aşamanda kart bedellerin 2 azalır. Mana Sabotajı ile birlikte hesaplanır; en az 1 mana ödersin.',
      duration:
          'İndirim bu turda başlamaz. Sonraki kendi kart aşaman kapanınca, kart oynamasan da biter. Gölge Antlaşması ve feda ettiğin kart bu maçta geri gelmez.',
      caution:
          'Mana kazandırmaz ve kilitli kartı açmaz. Mana bedeline ek olarak diğer kartını kaybedersin; bu tur taş hamleni normal yaparsın.',
    ),
    BattleCardExplanation(
      selection:
          'Sacrifice another card from your hand. You cannot play this without another hand card.',
      effect:
          'In your next own card phase, card costs decrease by 2. Combine with Mana Sabotage before applying the minimum cost of 1 mana.',
      duration:
          'The discount does not start this turn. It ends when your next card phase closes, even if you play no card. Shadow Contract and the sacrificed card do not return this match.',
      caution:
          'It does not grant mana or unblock cards. You lose the other card in addition to paying mana; this turn\'s chess move is still normal.',
    ),
  ],
  CardId.boardSeal: [
    BattleCardExplanation(
      selection:
          'Tahtanın içinde kalan, en az bir boş karesi olan bir 2 × 2 alan seç.',
      effect:
          'Rakibin sıradaki taş hamlesinde şah dışındaki taşları alanın o anda boş karelerine inemez. Üzerinden geçebilirler; kendi taşların etkilenmez.',
      duration:
          'Rakibin sıradaki taş hamlesi sonunda biter. Mühür Bozma tüm alanı daha erken kaldırabilir.',
      caution:
          'Şah muaftır; rokta kale kurala uyar. Alandaki dolu karede bulunan taşı normal yakalamak mümkündür. Geçerken alma boş hedefe indiği için engellenir.',
    ),
    BattleCardExplanation(
      selection:
          'Choose a 2 × 2 zone fully inside the board with at least 1 empty square.',
      effect:
          'On the next opposing chess move, their non-king pieces cannot land on its currently empty squares, but may pass through. Your pieces are unaffected.',
      duration:
          'The seal expires after that chess move. Break Seal can remove the whole zone earlier.',
      caution:
          'Kings are exempt; a rook moving during castling is not. A normal capture onto an occupied square is allowed. An en passant destination is empty, so it is blocked.',
    ),
  ],
};
