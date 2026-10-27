import 'luno_localizations.dart';

class BattleLesson {
  final String title, body, hint;
  const BattleLesson(this.title, this.body, this.hint);
}

// Ten stable steps preserve the existing onboarding checkpoint indices.
const _trLessons = <BattleLesson>[
  BattleLesson(
    'LUNO CHESS\'E HOŞ GELDİN',
    'Hedefin rakibin şahını mat etmek. Kartlar tahtadaki planına yeni seçenekler katar.',
    'Ben Luno. Önce bir hamle, sonra kartlarla tanışalım.',
  ),
  BattleLesson(
    'TAHTAYI OKU',
    'Beyaz bir taşa dokun. İşaretli karelerden birini seçerek hamle yap.',
    'Bu küçük deneme hesabını veya maçlarını etkilemez. Şahını tehdit altında bırakan hamleler seçilemez.',
  ),
  BattleLesson(
    'ÖNCE KART, SONRA HAMLE',
    'İki oyuncu da ilk kendi turunda yalnızca satranç hamlesi yapar. Sonraki turlarda önce kart aşaması, ardından taş hamlesi gelir.',
    'Bir kart oyna, bir kartı feda et veya Kartı Geç. Ardından taş hamleni yaparsın; feda etmek hamle hakkını tüketmez. Kart aşamasında saat durmaz.',
  ),
  BattleLesson(
    'MANANI ZAMANLA',
    '1 mana ile başlarsın. İkinci kendi turundan itibaren tur başında +1 mana gelir; en fazla 6 birikir.',
    'Karttaki sayı maliyetidir. Mana yetmiyorsa kart oynanamaz. Bir kartı feda etmek mana kazandırmaz.',
  ),
  BattleLesson(
    'KARTLARINI TANI',
    'Bir kart seç. Etkisini dene, sonra taş hamleni tamamla.',
    'Zincir, rakibin sıradaki hamlesinde bir taşın yeme hakkını kısıtlar. Yavaşlatma bir fil, kale veya veziri 2 kareyle sınırlar. Özel hareket kartını kullanınca seçtiğin taşla hamleyi tamamlamalısın.',
  ),
  BattleLesson(
    'DOĞRU HEDEFİ SEÇ',
    'Bir kart ve işaretli bir hedef seç. Kartı Oyna ile etkiyi tahtada gör.',
    'Siper kendi şahın dışındaki bir taşına uygulanır. Özel hareket kartlarında işaretlenen taşın hamlesini tamamlamalısın.',
  ),
  BattleLesson(
    'ON KARTLIK DESTEN',
    'Bir savaş destesi 10 farklı kart içerir. Elinde 3 kartla başlarsın; el sınırı 4 karttır.',
    'Maç bitmediyse kendi taş hamlenden sonra, elinde yer ve destende kart varsa bir kart çekersin. Deste kalan gizli kartlardır; El şu an kullanabileceğin kartlardır. Kullanılan veya feda edilen kart o maçta geri gelmez.',
  ),
  BattleLesson(
    'BİLGİYİ AVANTAJA ÇEVİR',
    'Rakibin Kartları paneli maça getirdiği 10 kartı gösterir. Hangi kartların kullanıldığını ya da feda edildiğini görürsün; elindeki kartlar gizlidir.',
    'Radar bir kartın şu an elde olup olmadığını söyler; eski kayıt geleceği garanti etmez. Kehanet sıradaki kartlarını gösterip sıralar, eline kart eklemez.',
  ),
  BattleLesson(
    'MODUNU VE ÖDÜLÜNÜ SEÇ',
    'Sıralı maçlar kupa yarışıdır. Yapay zekâ ve yüz yüze maçlar antrenmandır; kupanı değiştirmez. 5+2, her oyuncuya 5 dakika ve tamamlanan her taş hamlesinden sonra +2 saniye demektir.',
    'Koleksiyonda kartları tanı. Görev, sezon ve Pass ödüllerini kendi ekranlarından al; çevrimiçi ödüller doğrulandıktan sonra eklenir.',
  ),
  BattleLesson(
    'HAZIRSIN',
    'Şahını koru, mananı planla, kartını seç ve hamleni tamamla. Her tur yeni bir karar.',
    'Bebek Luno ile ilk öğretici maçında Luno sana eşlik eder. Maçtan sonra kullanıcı adını seçersin. Daha fazla çalışmak istersen Rehber içindeki Akademi isteğe bağlıdır. Maçta kartın bilgi simgesinden ayrıntıları okuyabilir, ifadeler düğmesinden emoji gönderebilirsin.',
  ),
];
const _enLessons = <BattleLesson>[
  BattleLesson(
    'WELCOME TO LUNO CHESS',
    'Checkmate the opposing king. Cards add new options to your plan on the board.',
    'I am Luno. Let us try a move, then meet your cards.',
  ),
  BattleLesson(
    'READ THE BOARD',
    'Tap a white piece. Choose a marked square to make a move.',
    'This practice does not affect your account or matches. Moves that leave your king in check cannot be selected.',
  ),
  BattleLesson(
    'CARD FIRST, THEN MOVE',
    'Each player makes only a chess move on their first own turn. Later turns begin with a card phase, followed by a chess move.',
    'Play one card, discard one card or Skip Card. Your chess move follows; discarding does not consume that move. The clock keeps running during the card phase.',
  ),
  BattleLesson(
    'PLAN YOUR MANA',
    'You start with 1 mana. From your second own turn, gain +1 at the start of each turn, up to 6.',
    'The number on a card is its cost. You need enough mana to play it. Discarding does not grant mana.',
  ),
  BattleLesson(
    'MEET YOUR CARDS',
    'Choose a card. Try its effect, then complete your chess move.',
    'Chain blocks a piece from capturing during the next opposing chess move. Slow limits a bishop, rook or queen to 2 squares. A movement card requires you to finish a move with the chosen piece.',
  ),
  BattleLesson(
    'CHOOSE THE RIGHT TARGET',
    'Choose a card and a marked target. Use Play Card to see the effect on the board.',
    'Shelter targets one of your pieces, but not your king. Movement cards require a move with the marked piece.',
  ),
  BattleLesson(
    'YOUR TEN-CARD DECK',
    'A battle deck contains 10 different cards. Start with 3 cards in hand; the hand limit is 4.',
    'After a non-terminal own chess move, draw one card if your hand has room and your deck is not empty. Deck means your remaining hidden cards; Hand means the cards you can currently use. Used or discarded cards do not return in that match.',
  ),
  BattleLesson(
    'TURN KNOWLEDGE INTO AN ADVANTAGE',
    'Opponent Cards shows the 10 cards brought to the match, including used or discarded cards. Their current hand and the order of their remaining deck stay hidden.',
    'Radar reports whether a card is currently in hand; old observations do not guarantee the future. Prophecy privately reveals and orders upcoming cards without adding one to your hand.',
  ),
  BattleLesson(
    'CHOOSE YOUR MODE AND REWARDS',
    'Ranked matches are the trophy competition. AI and face-to-face matches are practice and do not change your trophies. 5+2 means 5 minutes per player and +2 seconds after each completed chess move.',
    'Study cards in Collection. Claim mission, season and Pass rewards on their screens; online rewards are added after verification.',
  ),
  BattleLesson(
    'YOU ARE READY',
    'Protect your king, plan your mana, choose a card and finish your move. Every turn is a new decision.',
    'Luno accompanies you in your first learning match with Baby Luno. Choose your username after that match. For more practice, Academy in Guide is optional. During a match, use a card\'s info icon to read its details and the emotes button to send an expression.',
  ),
];

extension BattleLearningCopy on LunoLocalizations {
  List<BattleLesson> get battleLessons => isEnglish ? _enLessons : _trLessons;
  String learning(String tr, String en) => isEnglish ? en : tr;
}
