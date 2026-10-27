import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'card_copy.dart';

/// Runtime copy for the two supported game languages.
///
/// The source language remains Turkish so older saved data and existing
/// content keep their meaning. New UI should read from this object instead of
/// duplicating translated strings in a screen.
class LunoLocalizations {
  final Locale locale;

  const LunoLocalizations(this.locale);

  static const supportedLocales = <Locale>[Locale('tr'), Locale('en')];
  static const delegate = _LunoLocalizationsDelegate();

  static LunoLocalizations of(BuildContext context) {
    final value = Localizations.of<LunoLocalizations>(
      context,
      LunoLocalizations,
    );
    return value ?? const LunoLocalizations(Locale('tr'));
  }

  bool get isEnglish => locale.languageCode == 'en';

  String get languageName => isEnglish ? 'English' : 'Türkçe';
  String get settingsTitle => isEnglish ? 'SETTINGS' : 'AYARLAR';
  String get soundAndDisplay =>
      isEnglish ? 'SOUND & DISPLAY' : 'SES VE GÖRÜNTÜ';
  String get preferences => isEnglish ? 'PREFERENCES' : 'TERCİHLER';
  String get account => isEnglish ? 'ACCOUNT' : 'HESAP';
  String get language => isEnglish ? 'Language' : 'Dil';
  String get vibration => isEnglish ? 'Vibration' : 'Titreşim';
  String get effectsVolume => isEnglish ? 'Sound effects' : 'Ses efektleri';
  String get musicVolume => isEnglish ? 'Background music' : 'Arka plan müziği';
  String get low => isEnglish ? 'LOW' : 'DÜŞÜK';
  String get medium => isEnglish ? 'MEDIUM' : 'ORTA';
  String get high => isEnglish ? 'HIGH' : 'YÜKSEK';
  String get googleLink =>
      isEnglish ? 'Link Google account' : 'Google hesabını bağla';
  String get googleLinking =>
      isEnglish ? 'Linking Google account...' : 'Google hesabı bağlanıyor...';
  String get googleSubtitle =>
      isEnglish
          ? 'Protect your progress with a secure account'
          : 'İlerlemeyi güvenli hesaba bağla';
  String get replayGuide =>
      isEnglish ? 'Replay the guide' : 'Rehberi yeniden izle';
  String get signOut => isEnglish ? 'Sign out' : 'Çıkış yap';
  String get guestAccount => isEnglish ? 'Guest account' : 'Misafir hesabı';
  String get guestDescription =>
      isEnglish
          ? 'In this version, your progress is linked to the guest account on this device. Signing out before linking a secure provider can make you lose your progress.'
          : 'Bu sürümde ilerlemen cihazındaki misafir hesabına bağlı. Hesabını güvenli bir sağlayıcıya bağlamadan çıkış yapmak ilerlemeni kaybetmene neden olabilir.';
  String get ok => isEnglish ? 'OK' : 'TAMAM';
  String get friendlyRoomCreate =>
      isEnglish ? 'CREATE ROOM' : 'ODA KODU OLUŞTUR';
  String friendlyRoomDuration(int minutes) =>
      isEnglish
          ? '$minutes minutes per player'
          : 'Oyuncu başına $minutes dakika';

  String cardLevel(int level, int maximum) =>
      isEnglish ? 'Lv$level (max $maximum)' : 'Sv$level (en fazla $maximum)';

  String selectedEmotes(int count) =>
      isEnglish ? '$count / 4 selected' : '$count / 4 seçili';

  String pieceSetTitle(String id, String turkishName) {
    if (!isEnglish) return '$turkishName SETİ';
    const names = {
      'luno': 'LUNO',
      'ottoman': 'OTTOMAN',
      'roma': 'ROMAN',
      'brit': 'BRITISH',
      'viking': 'VIKING',
      'tasdevri': 'STONE AGE',
      'samuray': 'SAMURAI',
      'ice': 'ICE KINGDOM',
      'dragon': 'DRAGON',
      'neon': 'NEON KINGDOM',
    };
    return '${names[id] ?? turkishName} SET';
  }

  String get googleLinked =>
      isEnglish ? 'Google account linked.' : 'Google hesabı bağlandı.';
  String get googleCancelled =>
      isEnglish
          ? 'Google account linking was cancelled.'
          : 'Google bağlantısı iptal edildi.';
  String get googleAlreadyLinked =>
      isEnglish
          ? 'This Google account is linked to another Luno account.'
          : 'Bu Google hesabı başka bir Luno hesabına bağlı.';
  String get googleNotEnabled =>
      isEnglish
          ? 'Google sign-in is not enabled in Firebase.'
          : 'Google ile giriş Firebase tarafında etkin değil.';
  String get googleRetry =>
      isEnglish
          ? 'Could not link the Google account. Try again.'
          : 'Google hesabı bağlanamadı. Tekrar dene.';
  String get linkInProgress =>
      isEnglish
          ? 'Another account link is already in progress.'
          : 'Başka bir hesap bağlantısı devam ediyor.';
  String get secureLinkRetry =>
      isEnglish
          ? 'Could not create a secure account link. Try again.'
          : 'Güvenli hesap bağlantısı kurulamadı. Tekrar dene.';

  String get usernameTitle =>
      isEnglish ? 'CHOOSE USERNAME' : 'KULLANICI ADI SEÇ';
  String get usernameDescription =>
      isEnglish
          ? 'This name is unique. Choose it carefully!'
          : 'Bu ad benzersizdir. Dikkatli seç!';
  String get usernameHint => isEnglish ? 'player' : 'oyuncu';
  String get usernameRule =>
      isEnglish
          ? '3-16 characters · letters, numbers, _'
          : '3-16 karakter · harf, rakam, _';
  String get usernameInvalid =>
      isEnglish
          ? 'Use 3-16 characters: letters, numbers or _'
          : '3-16 karakter kullan: harf, rakam veya _';
  String get usernameChooseFirst =>
      isEnglish
          ? 'Choose a valid username first.'
          : 'Önce geçerli bir kullanıcı adı seç.';
  String get preparing => isEnglish ? 'PREPARING...' : 'HAZIRLANIYOR...';
  String get usernameSaving => preparing;
  String get confirm => isEnglish ? 'CONFIRM' : 'ONAYLA';
  String get continueOffline =>
      isEnglish ? 'CONTINUE OFFLINE' : 'ÇEVRİMDIŞI DEVAM ET';
  String get usernameTaken =>
      isEnglish
          ? 'That username is already in use. Try another.'
          : 'Bu kullanıcı adı kullanılıyor. Başka bir ad dene.';
  String get usernameBusy =>
      isEnglish
          ? 'Username is being updated. Try again in a few seconds.'
          : 'Kullanıcı adı güncelleniyor. Birkaç saniye sonra tekrar dene.';
  String get usernameOffline =>
      isEnglish
          ? 'Could not create a secure connection. Try again or continue offline.'
          : 'Güvenli bağlantı kurulamadı. Tekrar dene veya çevrimdışı devam et.';
  String get usernameSaveFailed =>
      isEnglish
          ? 'Could not save the username to the server. Try again.'
          : 'Kullanıcı adı sunucuya kaydedilemedi. Tekrar dene.';

  /// Translates stable UI copy while leaving usernames, room codes and server
  /// content untouched. This lets existing screens migrate without changing
  /// their layout or data contracts all at once.
  String translate(String value) {
    if (!isEnglish) return value;
    final exact = _englishCopy[value];
    if (exact != null) return exact;

    if (value.startsWith('ODA KODU OLUŞTUR · ') && value.endsWith(' DK')) {
      final minutes = value.substring(
        'ODA KODU OLUŞTUR · '.length,
        value.length - ' DK'.length,
      );
      return 'CREATE ROOM · $minutes MIN';
    }
    if (value.endsWith(' dakika / oyuncu')) {
      return '${value.substring(0, value.length - ' dakika / oyuncu'.length)} minutes / player';
    }
    if (value.startsWith('Rakip: ')) {
      return 'Opponent: ${value.substring(7)}';
    }
    if (value.endsWith(' seninle oynamak istiyor.')) {
      return '${value.substring(0, value.length - ' seninle oynamak istiyor.'.length)} wants to play with you.';
    }
    for (final entry in _dynamicEnglishCopy) {
      final match = entry.$1.firstMatch(value);
      if (match != null) return entry.$2(match);
    }
    if (RegExp(
      r'^\d+ (?:altın|elmas)(?: \+ \d+ (?:altın|elmas|Pass XP))+$',
    ).hasMatch(value)) {
      return value.split(' + ').map(translate).join(' + ');
    }
    return value;
  }

  static final _dynamicEnglishCopy = <(RegExp, String Function(Match))>[
    (
      RegExp(r'^\+([\d.,]+) altın hesabına eklendi\.$'),
      (m) => '+${m[1]} gold was added to your account.',
    ),
    (
      RegExp(r'^([\d.,]+)  ·  PREMIUM AKTİFLEŞTİR$'),
      (m) => '${m[1]}  ·  ACTIVATE PREMIUM',
    ),
    (RegExp(r'^([\d.,]+) · PREMIUM AL$'), (m) => '${m[1]} · GET PREMIUM'),
    (RegExp(r'^([\d.,]+)(\+?) kupa$'), (m) => '${m[1]}${m[2]} trophies'),
    (
      RegExp(r'^([\d.,]+) - ([\d.,]+) kupa$'),
      (m) => '${m[1]} - ${m[2]} trophies',
    ),
    (
      RegExp(r'^([\d.,]+) koleksiyon puanı$'),
      (m) => '${m[1]} collection points',
    ),
    (
      RegExp(r'^([\d.,]+) gün ([\d.,]+) saat kaldı$'),
      (m) => '${m[1]}d ${m[2]}h remaining',
    ),
    (RegExp(r'^([\d.,]+) saat kaldı$'), (m) => '${m[1]}h remaining'),
    (
      RegExp(r'^(.+) ödülünü al ve yeni sezona geç\.$'),
      (m) => 'Claim your ${m[1]} reward and start the new season.',
    ),
    (RegExp(r'^([\d.,]+) alınabilir$'), (m) => '${m[1]} claimable'),
    (
      RegExp(r'^Sonraki kademe için ([\d.,]+) kupa$'),
      (m) => 'Next tier at ${m[1]} trophies',
    ),
    (
      RegExp(r'^SEZON (\d+) · LUNO YÜKSELİŞİ$'),
      (m) => 'SEASON ${m[1]} · LUNO ASCENT',
    ),
    (
      RegExp(r'^Bugünün görevleri · (.+)$'),
      (m) => 'Today\'s missions · ${m[1]}',
    ),
    (
      RegExp(r'^Bu haftanın görevleri · (.+)$'),
      (m) => 'This week\'s missions · ${m[1]}',
    ),
    (
      RegExp(r'^(.+) · hedef (\d+)$'),
      (m) =>
          '${const LunoLocalizations(Locale('en')).translate(m[1]!)} · target ${m[2]}',
    ),
    (
      RegExp(r'^(.+) artık arkadaş listende olmayacak\.$'),
      (m) => '${m[1]} will be removed from your friends.',
    ),
    (
      RegExp(r'^(.+) seni maça çağırıyor$'),
      (m) => '${m[1]} invites you to a match',
    ),
    (RegExp(r'^(\d+) arkadaşlık isteği$'), (m) => '${m[1]} friend requests'),
    (RegExp(r'^(\d+) maç daveti$'), (m) => '${m[1]} match invitations'),
    (RegExp(r'^(\d+) dk önce$'), (m) => '${m[1]} min ago'),
    (RegExp(r'^(\d+) sa önce$'), (m) => '${m[1]}h ago'),
    (RegExp(r'^(\d+) gün önce$'), (m) => '${m[1]}d ago'),
    (
      RegExp(r'^(\d+)/29 açık · ([\d.,]+) koleksiyon puanı$'),
      (m) => '${m[1]}/29 unlocked · ${m[2]} collection points',
    ),
    (RegExp(r'^Şu an Seviye (\d+)$'), (m) => 'Current level ${m[1]}'),
    (RegExp(r'^Seviye (\d+)$'), (m) => 'Level ${m[1]}'),
    (RegExp(r'^Seviye (\d+) / (\d+)$'), (m) => 'Level ${m[1]} / ${m[2]}'),
    (RegExp(r'^(\+?)([\d.,]+) altın$'), (m) => '${m[1]}${m[2]} gold'),
    (RegExp(r'^([\d.,]+) elmas$'), (m) => '${m[1]} gems'),
    (
      RegExp(r'^(.+) Luno Chess arenasında mücadele ediyor\.$'),
      (m) => '${m[1]} plays in the Luno Chess arenas.',
    ),
    (
      RegExp(r'^(\d+) Pass sandığı açılmayı bekliyor\.$'),
      (m) => '${m[1]} Pass chests are ready to open.',
    ),
    (
      RegExp(r'^\+([\d.,]+) / -([\d.,]+) · SÜRE (\d+) DK$'),
      (m) => '+${m[1]} / -${m[2]} · ${m[3]} MIN',
    ),
    (
      RegExp(r'^(.+) taşları aktif edildi\.$'),
      (m) => '${m[1]} pieces are now active.',
    ),
    (
      RegExp(r'^(.+) hesabına eklendi ve taşların hazır\.$'),
      (m) => '${m[1]} was added to your account. Your pieces are ready.',
    ),
  ];

  static const _englishCopy = <String, String>{
    'Uzman Paketi': 'Expert Pack',
    'OSMANLI': 'OTTOMAN',
    'ROMA': 'ROMAN',
    'SAMURAY': 'SAMURAI',
    'SEZON': 'SEASON',
    'SEZON SONU': 'SEASON END',
    'SEZON SIRALAMASI': 'SEASON LEADERBOARD',
    'Sezon': 'Season',
    'Profil': 'Profile',
    'ANTRENMAN · KUPASIZ': 'PRACTICE · UNRANKED',
    'ONLINE · DAVET': 'ONLINE · INVITE',
    'YEREL · KUPASIZ': 'LOCAL · UNRANKED',
    'HAKKINDA': 'ABOUT',
    'ORAN': 'WIN RATE',
    'Berabere': 'Draws',
    'En iyi seri': 'Best streak',
    'Oynanan kart': 'Cards played',
    'HAFTALIK': 'WEEKLY',
    'SANDIKLAR': 'CHESTS',
    'AL': 'CLAIM',
    'Altın ve kostüm veya emoji parçaları.':
        'Gold and costume or emote pieces.',
    'Altın, kozmetik parçaları ve nadir içerik şansı.':
        'Gold, cosmetic pieces and a chance of rare content.',
    'Altın, kozmetik parçaları ve efsanevi içerik şansı.':
        'Gold, cosmetic pieces and a chance of legendary content.',
    'Altın ve en seçkin kozmetik içerik havuzu.':
        'Gold and the most exclusive cosmetic content pool.',
    'TAHTAN HAZIR': 'YOUR BOARD IS READY',
    'MEVCUT ARENA': 'CURRENT ARENA',
    'Gizli hedef': 'Hidden objective',
    'Bir maç oyna.': 'Play one match.',
    'Bir maç kazan.': 'Win one match.',
    'Oturumun kapandı. Giriş yaptıktan sonra bu ekranı yeniden aç.':
        'Your session ended. Open this screen again after signing in.',
    'Güvenli uygulama doğrulaması tamamlanamadı. Play Store sürümünü ve bağlantını kontrol et.':
        'Secure app verification failed. Check your Play Store installation and connection.',
    'Misafir oturumu Firebase tarafında kapalı.':
        'Guest sign-in is unavailable on the server.',
    'Oyuncu profili oluşturulamadı.': 'Could not create the player profile.',
    'Sunucuya bağlanılamadı.': 'Could not connect to the server.',
    'Online servis hazır değil.': 'Online service is not ready.',
    'TÜRKİYE': 'TURKEY',
    'ÜLKE SEÇİLMEDİ': 'COUNTRY NOT SELECTED',
    'Acemi Kampı': 'Rookie Camp',
    'ACEMİ KAMPI': 'ROOKIE CAMP',
    'ARENA YOLU': 'ARENA ROAD',
    'ODA KODUYLA KATIL': 'JOIN WITH ROOM CODE',
    'MESAJLAR': 'MESSAGES',
    'Luno bildirimi': 'Luno notification',
    'Bebek Luno': 'Baby Luno',
    'Yeni öğreniyor, ara sıra hata yapar':
        'Still learning; makes occasional mistakes',
    'Çömez Luno': 'Apprentice Luno',
    'Hevesli ama acemi': 'Eager but inexperienced',
    'Şövalye Luno': 'Knight Luno',
    'Dengeli ve disiplinli': 'Balanced and disciplined',
    'Bilge Luno': 'Wise Luno',
    'Planlı oynar, hatası azdır': 'Plans ahead and rarely makes mistakes',
    'Usta Luno': 'Master Luno',
    'Sıkı strateji, yenmesi zor': 'Strong strategy; hard to defeat',
    'Efsane Luno': 'Legend Luno',
    'Krallığın en güçlüsü, acımasız':
        'The strongest in the kingdom; relentless',
    'Piyon Vadisi': 'Pawn Valley',
    'PİYON VADİSİ': 'PAWN VALLEY',
    'HÜKÜMDAR': 'SOVEREIGN',
    'Gölge Hükümdarı': 'Shadow Sovereign',
    'GÖLGE HÜKÜMDARI': 'SHADOW SOVEREIGN',
    'İMPARATOR': 'EMPEROR',
    'Luno Ustası': 'Luno Master',
    'Luno Kraliyeti': 'Luno Royalty',
    'LUNO USTASI': 'LUNO MASTER',
    'LUNO KRALİYETİ': 'LUNO ROYALTY',
    'LUNO KRİYALETİ': 'LUNO ROYALTY',
    "KART ARŞİVİ": "CARD ARCHIVE",
    "Bir karta dokunarak mana, hedef ve etkisini gör.":
        "Tap a card to see its mana cost, target and effect.",
    "DOSTLUK MAÇI": "FRIENDLY MATCH",
    "Maç menüsü": "Match menu",
    "Yeniden başlat?": "Restart?",
    "Bu tahtadaki hamleler sıfırlanacak ve yeni bir maç başlayacak.":
        "The board will reset and a new match will begin.",
    "Maçı bitir?": "End match?",
    "Sırası gelen oyuncu teslim olacak ve rakibi kazanacak.":
        "The current player will resign and their opponent will win.",
    "Teslim olursan bu maç yenilgi olarak kaydedilir.":
        "Resigning records this match as a loss.",
    "Savaşa gir": "Enter battle",
    "Pass ödüllerini güçlendir, profilini parlat ve Luno dünyasının özel avantajlarını aç.":
        "Unlock Premium rewards and a special Luno profile badge.",
    "PREMIUM AKTİF": "PREMIUM ACTIVE",
    "Alındı": "Claimed",
    "Ödülü al": "Claim reward",
    "LUNO KOLEKSİYONU": "LUNO COLLECTION",
    "Sezon yolu hazır değil.": "Season road is not ready.",
    "SEZON SONU ÖDÜLÜNÜ AL": "CLAIM SEASON-END REWARD",
    "Sıralama verileri hazır olduğunda burada görünecek.":
        "Rankings will appear here when available.",
    "Arkadaşlıktan çıkarılsın mı?": "Remove friend?",
    "ÇIKAR": "REMOVE",
    "Kullanıcı adı veya Luno kodu": "Username or Luno code",
    "Mesaj gönder": "Send message",
    "Maça davet et": "Invite to match",
    "Arkadaşlıktan çıkar": "Remove friend",
    "GÖNDERİLDİ": "SENT",
    "BİLDİRİMLER": "NOTIFICATIONS",
    "Tümünü okundu işaretle": "Mark all as read",
    "Henüz bildirim yok": "No notifications yet",
    "Arkadaşlık ve maç hareketlerin burada görünecek.":
        "Friend and match activity will appear here.",
    "Henüz mesaj yok": "No messages yet",
    "Arkadaşlarınla mesajlaştıkça gelen kutun burada dolacak.":
        "Your conversations with friends will appear here.",
    "Mesajlaşma kuralları": "Messaging rules",
    "Mesaj göndermek için Luno Chess kullanım koşullarını ve gizlilik bildirimini kabul etmelisin. Spam, taciz ve uygunsuz içerik gönderme.":
        "To send messages, accept the Luno Chess terms and privacy notice. Do not send spam, harassment or inappropriate content.",
    "Mesaj yaz...": "Write a message...",
    "Gönder": "Send",
    "Kalıcı olarak sil": "Delete permanently",
    "KART ALBÜMÜ": "CARD ALBUM",
    "GERİ DÖN": "GO BACK",
    "Teslim olursan bu maç yenilgi olarak kaydedilir. Devam etmek istiyor musun?":
        "Resigning records this match as a loss. Continue?",
    "Rakip beraberlik teklif etti.": "Opponent offered a draw.",
    "Rakip maçın iptal edilmesini teklif ediyor.":
        "Opponent offered to cancel the match.",
    "İptal teklifin bekliyor.": "Your cancellation offer is pending.",
    "ŞU AN BURADASIN": "YOU ARE HERE",
    "Şu an buradasın": "You are here",
    "Açık": "Unlocked",
    "BİR SONRAKİ SEVİYE": "NEXT LEVEL",
    "Maç oynadıkça XP kazanırsın. Seviye 10 ve 25 gibi dönüm noktalarında başarımlardan ek ödüller açılır.":
        "Earn XP by playing matches. Milestones such as levels 10 and 25 unlock achievement rewards.",
    "YENİ ARENA": "NEW ARENA",
    "YENİ KARTLAR AÇILDI": "NEW CARDS UNLOCKED",
    "SEZON SONU ÖDÜLÜ": "SEASON-END REWARD",
    "Yeni sezonda kupalarını yeniden yükseltmeye hazırsın.":
        "You are ready to climb again in the new season.",
    "MAÇ TEKLİFİ": "MATCH INVITATION",
    "Maç oynayarak Pass XP kazan": "Earn Pass XP by playing matches",
    "ARKADAŞINLA OYNA": "PLAY WITH A FRIEND",
    "Profili düzenle": "Edit profile",
    "İSTATİSTİKLER": "STATISTICS",
    "ELMAS PAKETLERİ": "GEM PACKS",
    "Günlük Ödül": "Daily Reward",
    "NADİR KARTLAR": "RARE CARDS",
    "EFSANEVİ KARTLAR": "LEGENDARY CARDS",
    "MİTİK KARTLAR": "MYTHIC CARDS",
    "BRİTANYA": "BRITISH",
    "VİKİNG": "VIKING",
    "TAŞ DEVRİ": "STONE AGE",
    "BUZ KRALLIĞI": "ICE KINGDOM",
    "Arkadaşınla aynı tahtaya çık.": "Play a match with your friend.",
    "Arkadaş maçı için internet bağlantını kontrol et.":
        "Check your connection to play with a friend.",
    "Oda hazırlanıyor": "Preparing room",
    "Oda oluşturulamadı": "Could not create room",
    "Sunucudan geçerli bir oda kodu alınamadı.":
        "The server did not return a valid room code.",
    "Arkadaşın oda kodunu girince maç başlayacak":
        "The match starts when your friend joins with the room code",
    "Oda bağlantısı yenileniyor...": "Reconnecting to room...",
    "Odaya bağlanılıyor": "Joining room",
    "Oda bulunamadı": "Room not found",
    "Kod geçersiz, dolu veya süresi dolmuş olabilir.":
        "The code may be invalid, full or expired.",
    "Odaya bağlanılamadı": "Could not join room",
    "Oda kapatılıyor": "Closing room",
    "Oda kapatıldı": "Room closed",
    "Oda açık": "Room open",
    "Oda kapanışı doğrulanamadı. Durum yeniden denetleniyor.":
        "Room closure was not confirmed. Checking its status again.",
    "Oda kapatılamadı. Bağlantı düzelince tekrar dene.":
        "Could not close the room. Try again when connected.",
    "Sunucudan geçerli bir maç alınamadı. Tekrar deneyebilirsin.":
        "The server did not return a valid match. Please try again.",
    "Dostluk maçında da hamleler sunucu tarafından doğrulanır. Oda kodları kısa süreli ve tek kullanımlıktır.":
        "Friendly match moves are also validated by the server. Room codes expire and can only be used once.",
    "Arkadaş": "Friend",
    "Sıralama": "Leaderboard",
    "Menü": "Menu",
    "SAVAŞA GİR": "ENTER BATTLE",
    "Modunu ve süreni seç": "Choose your mode and time",
    "Mağaza": "Shop",
    "Savaş": "Battle",
    "SİYAH KAZANDI": "BLACK WINS",
    "YENİLGİ": "DEFEAT",
    "Yüz yüze maç tamamlandı. Kupa ve ödül değişmedi.":
        "Local match complete. Trophies and rewards are unchanged.",
    "Tahtanın kontrolünü elinde tuttun.": "You took control of the board.",
    "İki taraf da avantajı korudu.": "Both players held their ground.",
    "Bu maç bitti; sıradaki hamle için yeniden dene.":
        "Match complete. Try again for your next victory.",
    "Luno Premium etkinleştirildi.": "Luno Premium activated.",
    "Yeterli elmasın yok.": "Not enough gems.",
    "Sezonun premium ödül yolunu aç.":
        "Unlock the season Premium reward track.",
    "ÖZEL PROFİL ROZETİ": "SPECIAL PROFILE BADGE",
    "Profilinde Luno Premium kimliğini göster.":
        "Show your Luno Premium badge on your profile.",
    "GELİŞMİŞ ÖDÜLLER": "PREMIUM REWARDS",
    "Her sezon daha güçlü altın, elmas ve kart ödülleri.":
        "Additional gold, gem and card rewards each season.",
    "İlk Zafer": "First Victory",
    "İlk maçını kazan.": "Win your first match.",
    "Kart Ustası": "Card Master",
    "İlk kartını kullan.": "Play your first card.",
    "Acemi Savaşçı": "Rookie Warrior",
    "10 maç kazan.": "Win 10 matches.",
    "Tahta Ustası": "Board Master",
    "50 maç kazan.": "Win 50 matches.",
    "Şampiyon": "Champion",
    "100 maç kazan.": "Win 100 matches.",
    "500 maç kazan.": "Win 500 matches.",
    "Sıcak Eller": "Hot Streak",
    "3 maç üst üste kazan.": "Win 3 matches in a row.",
    "5 maçlık seri yap.": "Reach a 5-win streak.",
    "10 maçlık seri yap.": "Reach a 10-win streak.",
    "Hükümdar": "Sovereign",
    "3. arenaya ulaş.": "Reach arena 3.",
    "İmparator": "Emperor",
    "5. arenaya ulaş.": "Reach arena 5.",
    "Luno Kraliyeti arenasına ulaş.": "Reach Luno Royalty arena.",
    "Luno Legend arenasına ulaş.": "Reach Luno Legend arena.",
    "Luno Mythic arenasına ulaş.": "Reach Luno Mythic arena.",
    "Denge Ustası": "Balance Master",
    "100 taş ele geçir.": "Capture 100 pieces.",
    "Şah Ustası": "Check Master",
    "50 şah tehdidi oluştur.": "Give check 50 times.",
    "Terfi Ustası": "Promotion Master",
    "3 taş görünümü edin.": "Collect 3 piece sets.",
    "8 taş görünümünü tamamla.": "Collect 8 piece sets.",
    "Tahta Dostları": "Board Friends",
    "5 arkadaş edin.": "Add 5 friends.",
    "Sandık Avcısı": "Chest Hunter",
    "10 sandık aç.": "Open 10 chests.",
    "Toplam 50 maç oyna.": "Play 50 matches.",
    "Tahtanın Sesi": "Voice of the Board",
    "Toplam 200 maç oyna.": "Play 200 matches.",
    "Sadık Oyuncu": "Loyal Player",
    "7 günlük giriş serisi yap.": "Reach a 7-day login streak.",
    "Luno Müdavimi": "Luno Regular",
    "30 günlük giriş serisi yap.": "Reach a 30-day login streak.",
    "Yükselen Yıldız": "Rising Star",
    "10. seviyeye ulaş.": "Reach level 10.",
    "25. seviyeye ulaş.": "Reach level 25.",
    "Her Gün Tahtada": "Daily Player",
    "7 günlük ödül serisi yap.": "Reach a 7-day reward streak.",
    "Kraliyet Üyesi": "Royal Member",
    "Premium üyeliği aç.": "Activate Premium.",
    "Premium Elçisi": "Premium Ambassador",
    "30 gün Premium kal.": "Keep Premium active for 30 days.",
    "Başarımlar sunucudan yüklenemedi.":
        "Could not load achievements from the server.",
    "Henüz tamamlanmış maç yok": "No completed matches yet",
    "İlk maçından sonra zaferlerini ve serilerini burada takip edeceksin.":
        "Track your victories and streaks here after your first match.",
    "Tahtadaki taş setini seç ve önizle.":
        "Choose and preview your board pieces.",
    "Maç sohbetinde kullanacağın ifadeleri görüntüle.":
        "Browse emotes for match chat.",
    "OTTOMAN SETİ": "OTTOMAN SET",
    "ROMA SETİ": "ROMAN SET",
    "BRİTANYA SETİ": "BRITISH SET",
    "VİKİNG SETİ": "VIKING SET",
    "TAŞ DEVRİ SETİ": "STONE AGE SET",
    "SAMURAY SETİ": "SAMURAI SET",
    "EJDERHA SETİ": "DRAGON SET",
    "TAŞLARI GÖR": "VIEW PIECES",
    "Sezon bilgileri sunucudan yüklenemedi.":
        "Could not load the season from the server.",
    "Hesabın değişti. Sezon ekranını yeniden aç.":
        "Your account changed. Reopen the season screen.",
    "Sezon geçişi bekliyor": "Season transition pending",
    "Bu ödül için daha fazla kupa kazanmalısın.":
        "Earn more trophies to unlock this reward.",
    "Sezon değişiminde önce sezon sonu ödülünü almalısın.":
        "Claim your season-end reward before entering the new season.",
    "Sezon servisi şu an kullanılamıyor.":
        "Season service is currently unavailable.",
    "Sezon yolu ödülü hesabına eklendi.":
        "Season road reward added to your account.",
    "Sezon sonu ödülün hesabına eklendi.":
        "Season-end reward added to your account.",
    "Sezon yolu tamamlandı": "Season road complete",
    "SIRADAKİ HEDEF": "NEXT GOAL",
    "Görevler sunucudan yüklenemedi.":
        "Could not load missions from the server.",
    "Hesabın değişti. Görev ekranını yeniden aç.":
        "Your account changed. Reopen the missions screen.",
    "Tahtaya çık": "Take the Board",
    "Zafer zamanı": "Victory Time",
    "Kart ustası": "Card Master",
    "Haftalık hedef": "Weekly Goal",
    "Ödül": "Reward",
    "GÖREVLERİ TAMAMLA": "COMPLETE MISSIONS",
    "Hedeflerini tamamla; altın, elmas ve Pass XP kazan.":
        "Complete goals to earn gold, gems and Pass XP.",
    "GÜNLÜK": "DAILY",
    "ÖZEL": "SPECIAL",
    "Bu bölümde şu an görev yok.": "No missions in this category right now.",
    "Sıralama bağlantısı hazırlanıyor.": "Preparing leaderboard connection.",
    "Sıralama servisine şu anda ulaşılamıyor.":
        "Leaderboard service is currently unavailable.",
    "KOLEKSİYON SIRALAMASI": "COLLECTION LEADERBOARD",
    "Yakında": "Coming soon",
    "Arkadaşlık istekleri şu an yenilenemedi.":
        "Could not refresh friend requests.",
    "Sosyal bilgiler şu an yenilenemedi.":
        "Could not refresh social information.",
    "Yeni bir arkadaşlık isteğin var.": "You have a new friend request.",
    "Geçerli bir kullanıcı adı veya oyuncu kodu yaz.":
        "Enter a valid username or player code.",
    "Oyuncu araması şu an kullanılamıyor.":
        "Player search is currently unavailable.",
    "Arkadaşlık isteği kabul edildi.": "Friend request accepted.",
    "Bu oyuncu zaten arkadaşın.": "This player is already your friend.",
    "Arkadaşlık isteği zaten bekliyor.": "Friend request already pending.",
    "Arkadaşlık isteği gönderildi.": "Friend request sent.",
    "Bu oyuncuyla etkileşim kuramazsın.":
        "You cannot interact with this player.",
    "Arkadaşlık isteği gönderilemedi.": "Could not send friend request.",
    "İstek reddedildi.": "Request declined.",
    "Bu istek artık beklemiyor.": "This request is no longer pending.",
    "İstek güncellenemedi.": "Could not update request.",
    "Arkadaşlıktan çıkarıldı.": "Friend removed.",
    "Arkadaşlık kaldırılamadı.": "Could not remove friend.",
    "Dostluk maçı daveti gönderildi.": "Friendly match invitation sent.",
    "Önce bu oyuncuyla arkadaş olmalısın.":
        "Add this player as a friend first.",
    "Oyunculardan biri şu anda maçta.":
        "One of the players is currently in a match.",
    "Dostluk maçı daveti gönderilemedi.": "Could not send match invitation.",
    "Bu davetin süresi dolmuş.": "This invitation has expired.",
    "Maç daveti güncellenemedi.": "Could not update match invitation.",
    "Sıralanacak arkadaşın yok.": "No friends to rank yet.",
    "Henüz arkadaşın yok. Kullanıcı adıyla ara.":
        "No friends yet. Search by username.",
    "ARKADAŞ": "FRIEND",
    "Bildirimler şu an işaretlenemedi.":
        "Could not mark notifications as read.",
    "Bildirim okunamadı.": "Could not read notification.",
    "Mesaj kutusu şu an açılamıyor.": "Inbox is currently unavailable.",
    "Arkadaşlık isteği kabul edildi": "Friend request accepted",
    "Maç daveti kabul edildi": "Match invitation accepted",
    "Az önce": "Just now",
    "Konuşma açılamadı.": "Could not open conversation.",
    "Mesaj 500 karakteri geçemez.": "Messages cannot exceed 500 characters.",
    "Mesaj gönderilemedi.": "Could not send message.",
    "Profilin, ilerlemen, koleksiyonun ve sosyal verilerin silinecek. Bu işlem geri alınamaz. Satın alma kayıtları yasal zorunluluklar kapsamında saklanabilir.":
        "Your profile, progress, collection and social data will be deleted. This cannot be undone. Purchase records may be retained to meet legal obligations.",
    "Vazgeç": "Cancel",
    "Hesabın silindi.": "Your account has been deleted.",
    "Doğrulama iptal edildi. Hesabın silinmedi.":
        "Verification cancelled. Your account was not deleted.",
    "Bağlı Google hesabını doğrulayıp tekrar dene.":
        "Verify your linked Google account and try again.",
    "Silme işlemi sürüyor. Tamamlamak için Hesabımı sil seçeneğine tekrar dokun.":
        "Deletion is in progress. Tap Delete my account again to finish.",
    "Hesabın silindi. Cihazdaki temizliği tamamlamak için Hesabımı sil seçeneğine tekrar dokun.":
        "Your account is deleted. Tap Delete my account again to finish local cleanup.",
    "Hesabın silindi. Oturumu kapatmak için Hesabımı sil seçeneğine tekrar dokun.":
        "Your account is deleted. Tap Delete my account again to sign out.",
    "Hesap silme işlemi doğrulanamadı. Tekrar dene.":
        "Could not confirm account deletion. Try again.",
    "Türkiye": "Turkey",
    "Hesabın değişti. Profil düzenleyicisini yeniden aç.":
        "Your account changed. Reopen the profile editor.",
    "Profil sunucuya kaydedilemedi. Bağlantıyı kontrol edip tekrar dene.":
        "Could not save your profile. Check your connection and try again.",
    "Profil güncellendi.": "Profile updated.",
    "Şah": "King",
    "Taç": "Crown",
    "Yıldırım": "Lightning",
    "Ülke": "Country",
    "AVATAR İKONU": "AVATAR ICON",
    "Rakip bulundu": "Opponent found",
    "GALİBİYET": "VICTORY",
    "Luno Pass Premium etkinleştirildi.": "Luno Pass Premium activated.",
    "Bu Pass ödülü zaten alınmış.":
        "This Pass reward has already been claimed.",
    "Pass ödülü hesabına eklendi.": "Pass reward added to your account.",
    "Bu Pass ödülü sunucuda henüz tanımlı değil.":
        "This Pass reward is not yet configured on the server.",
    "Özel ödül": "Special reward",
    "Kupa kazan, arenalarda yüksel ve sıralamada yerini al.":
        "Earn trophies, climb arenas and join the leaderboard.",
    "Altı Luno eğitmeninden birini seç, risksiz antrenman yap.":
        "Choose one of six Luno coaches and practise without risking trophies.",
    "Arkadaşını davet et ya da oda koduyla maça katıl.":
        "Invite a friend or join using a room code.",
    "Aynı cihazda beyaz ve siyah sırayla hamle yapsın.":
        "Take turns as white and black on one device.",
    "SAVAŞ": "BATTLE",
    "SAVAŞ MODLARI": "BATTLE MODES",
    "Oyun tarzını seç": "Choose your play style",
    "SERİ": "STREAK",
    "Altın": "Gold",
    "Toplam maç": "Total matches",
    "Mağlubiyet": "Losses",
    "Açılan sandık": "Chests opened",
    "Oynadığın maçların özetini görüntüle": "View your match summary",
    "İlerlemeni, rozetlerini ve hedeflerini görüntüle":
        "View your progress, badges and goals",
    "Bu oyuncunun profili artık mevcut değil.":
        "This player profile no longer exists.",
    "Oyuncu profili yüklenemedi.": "Could not load player profile.",
    "Oyuncu profili hazırlanıyor.": "Preparing player profile.",
    "Güvenli bağlantı doğrulanamadı. Uygulamayı Google Play sürümünden açıp tekrar dene.":
        "Could not verify the secure connection. Open the Google Play version and try again.",
    "Bu ürün zaten hesabında bulunuyor.": "You already own this item.",
    "Hesap doğrulaması tamamlanmadan bu işlem kullanılamaz.":
        "Complete account verification before using this action.",
    "Online servis şu an kullanılamıyor.":
        "Online service is currently unavailable.",
    "Bugünkü ödülünü zaten aldın.": "You already claimed today's reward.",
    "6 ödül ve nadir içerik şansı.": "6 rewards with a chance of rare items.",
    "7 ödül ve efsane içerik şansı.":
        "7 rewards with a chance of legendary items.",
    "8 ödül ve en seçkin içerik havuzu.":
        "8 rewards from the premium item pool.",
    "Başlangıç Paketi": "Starter Pack",
    "5.000 altın + 50 elmas": "5,000 gold + 50 gems",
    "20.000 altın + 300 elmas": "20,000 gold + 300 gems",
    "Bugünkü ödülün hazır": "Today's reward is ready",
    "Yarın tekrar gel": "Come back tomorrow",
    "LUNO PREMIUM AKTİF": "LUNO PREMIUM ACTIVE",
    "Kraliyet ayrıcalıkların açık.": "Your Royal benefits are active.",
    "Kraliyet ayrıcalıklarını keşfet.": "Explore Royal benefits.",
    "SANDIK AÇILDI": "CHEST OPENED",
    "Ödüllerin hazırlanıyor...": "Preparing your rewards...",
    "Ödüller hesabına güvenle eklendi.":
        "Rewards securely added to your account.",
    "Savaş kartı": "Battle card",
    "Skin parçası": "Skin shard",
    "Avatar çerçevesi parçası": "Avatar frame shard",
    "Biyo çerçevesi parçası": "Bio frame shard",
    "SEVİYE SEÇ": "SELECT LEVEL",
    "Yenile": "Refresh",
    "Kilitli": "Locked",
    "Ara": "Search",
    "Reddet": "Decline",
    "Kabul et": "Accept",
    "YAKINDA": "COMING SOON",
    'Online işlemler durduruldu': 'Online actions stopped',
    'Bu ekrandan güvenle çıkabilirsin.': 'You can safely leave this screen.',
    'Bu hesap silinmiş. Bu hesapla online oyuna devam edilemez.':
        'This account has been deleted. Online play is no longer available for this account.',
    'Hesap silme işlemi sürüyor. Online işlemler durduruldu.':
        'Account deletion is in progress. Online actions have been stopped.',
    'Beyaz': 'White',
    'Siyah': 'Black',
    'TAHTA STİLİNİ SEÇ\nSeçtiğin set maç tahtasında kullanılır.':
        'PIECE COLLECTION\nYour selected set appears on the match board.',
    'STANDART': 'STANDARD',
    'NADİR': 'RARE',
    'EFSANEVİ': 'LEGENDARY',
    'MİTİK': 'MYTHIC',
    'AKTİF TAHTA SETİ': 'ACTIVE PIECE SET',
    'BU SETİ KULLAN': 'USE THIS SET',
    'Taş seti sunucuya kaydedilemedi.': 'Could not save your piece set.',
    'MAÇ İFADELERİ': 'MATCH EMOTES',
    'Neşeli Luno': 'Happy Luno',
    'Zafer Lunosu': 'Victory Luno',
    'Osmanlı Taş Seti': 'Ottoman Piece Set',
    'Luno Kalbi': 'Luno Heart',
    'Viking Taş Seti': 'Viking Piece Set',
    'Premium Nadir Sandık': 'Premium Rare Chest',
    'Premium Luno Tepkisi': 'Premium Luno Reaction',
    'Roma Taş Seti': 'Roman Piece Set',
    'Premium Efsanevi Sandık': 'Premium Legendary Chest',
    'Ejderha Taş Seti': 'Dragon Piece Set',
    'Neon Krallık Seti': 'Neon Kingdom Set',
    'Elmas': 'Gems',
    'İlk adım': 'First step',
    'Hükümdarın mührü': 'Sovereign seal',
    'Gölge geçidi': 'Shadow passage',
    'İmparator tacı': 'Emperor crown',
    'Usta hamlesi': 'Master move',
    'Kraliyet kapısı': 'Royal gate',
    'Legend yükselişi': 'Legend ascent',
    'Mythic zirve': 'Mythic peak',
    'Luno şampiyonu': 'Luno champion',
    'Kalpli Luno': 'Loving Luno',
    'Gülen Luno': 'Laughing Luno',
    'Ağlayan Luno': 'Crying Luno',
    'Kızgın Luno': 'Angry Luno',
    'Düşünen Luno': 'Thinking Luno',
    'Alevli Luno': 'Fiery Luno',
    'Yıldız Luno': 'Star Luno',
    'Şimşek Luno': 'Lightning Luno',
    'Oops Luno': 'Oops Luno',
    'Stratejist Luno': 'Strategist Luno',
    'Kupa Luno': 'Trophy Luno',
    'Taçlı Luno': 'Crowned Luno',
    'Gökkuşağı Luno': 'Rainbow Luno',
    'KİLİTLİ': 'LOCKED',
    'SEÇİLİ': 'SELECTED',
    'KULLAN': 'USE',
    'Maçta en fazla 4 hızlı ifade kullanabilirsin.':
        'You can select up to 4 quick emotes.',
    'İfadeler kaydedilemedi. Tekrar dene.':
        'Could not save your emotes. Try again.',
    ...cardEnglishCopy,
    'Koleksiyonunda': 'In your collection',
    'Henüz açılmadı': 'Not unlocked yet',
    'Kart detayları': 'Card details',
    'Desteye ekle': 'Add to deck',
    'Desteden çıkar': 'Remove from deck',
    'Hedefsiz': 'No target',
    'Rakip taş': 'Enemy piece',
    'Rakip vezir': 'Enemy queen',
    'Kendi piyon': 'Your pawn',
    'İki piyon (yan yana)': 'Two adjacent pawns',
    'Kendi at': 'Your knight',
    'Kendi fil': 'Your bishop',
    'Kendi at / fil': 'Your knight / bishop',
    'Kendi vezir': 'Your queen',
    'Kendi taş': 'Your piece',
    'Boş kare': 'Empty square',
    'Hedef': 'Target',
    'Nadirlik': 'Rarity',
    'Seviye': 'Level',
    'Kart yükseltildi.': 'Card upgraded.',
    'Kart veya bakiyen değişti. Güncel bilgileri kontrol edip tekrar dene.':
        'Your card or balance changed. Check the updated details and try again.',
    'Not': 'Note',
    'Sıradan': 'Common',
    'Nadir': 'Rare',
    'Efsanevi': 'Legendary',
    'Mitik': 'Mythic',
    'Oynayınca hamle yapmazsın': 'Playing this card replaces your move',
    'Bu sandık işlemi daha önce tamamlandı. Koleksiyonunu kontrol et.':
        'This chest action was already completed. Check your collection.',
    'Bu ödül daha önce alındı.': 'This reward was already claimed.',
    'İşlem doğrulanamadı. Bağlantı yenilendiğinde durumunu kontrol et.':
        'The action could not be confirmed. Check its status once reconnected.',
    'Premium işlemi doğrulanamadı. Bağlantı yenilendiğinde Pass durumunu kontrol et.':
        'Could not confirm the Premium transaction. Check your Pass after reconnecting.',
    'Ödül işlemi doğrulanamadı. Bağlantı yenilendiğinde ödül durumunu kontrol et.':
        'Could not confirm the reward transaction. Check its status after reconnecting.',
    'Sandık işlemi doğrulanamadı. Bağlantı yenilendiğinde sandıklarını kontrol et.':
        'Could not confirm the chest transaction. Check your chests after reconnecting.',
    'Deste kaydı doğrulanamadı. Önceki desten geri yüklendi.':
        'Could not confirm the deck save. Your previous deck was restored.',
    'Güvenli bağlantı doğrulanamadı.':
        'Could not verify the secure connection.',
    'Yükseltme doğrulanamadı. Bağlantı yenilendiğinde kartını kontrol et.':
        'Could not confirm the upgrade. Check your card after reconnecting.',
    'Sıranın başında 1 mana kazanırsın; en fazla 10 mana biriktirebilirsin. Her kartın kendi maliyeti vardır.':
        'Gain 1 mana at the start of your turn, up to 10. Each card has its own mana cost.',
    'Başlangıç destende Barbar Piyon, Kart Engelleme, Zehirli Vezir, Öfkeli At, Tutkal Piyon ve Dondurma bulunur.':
        'Your starter deck contains Barbarian Pawn, Card Block, Poison Queen, Angry Knight, Glue Pawn and Freeze.',
    'Sıralı maçların sonucu kupanı değiştirir. Yapay zekâ ve yüz yüze maçlar kupanı etkilemez.':
        'Ranked match results change your trophies. AI and local matches do not affect them.',
    'Sezon ve Luno Pass ödüllerini ilgili ekranlardan takip et. Çevrimiçi ödüller sunucu onayıyla hesabına eklenir.':
        'Check the Season and Luno Pass screens for rewards. Online rewards are added after server confirmation.',
    'Oda kodunu kopyala': 'Copy room code',
    'Oda kodu kopyalandı.': 'Room code copied.',
    'Kod kopyalanamadı. Tekrar dene.': 'Could not copy the code. Try again.',
    'Örn. LK7X9M': 'e.g. LK7X9M',
    'Katıl': 'Join',
    'Hazır': 'Ready',
    'Bağlantı gerekli': 'Connection required',
    'Eşleşme için internet bağlantını kontrol et.':
        'Check your internet connection to find a match.',
    'Güvenli eşleşme başlatılıyor': 'Starting matchmaking',
    'Rakip aranıyor': 'Finding an opponent',
    'Bağlantı kurulamadı': 'Could not connect',
    'Eşleşme iptal edildi': 'Matchmaking cancelled',
    'Bağlantı yenileniyor': 'Reconnecting',
    'Eşleşme iptal ediliyor': 'Cancelling matchmaking',
    'Eşleşme araması sürüyor': 'Still finding an opponent',
    'İptal doğrulanamadı. Kuyruk korunuyor; durum yeniden denetleniyor.':
        'Cancellation was not confirmed. You remain in the queue while we check again.',
    'Oyuncu profili hazır değil. Ana menüden bağlantıyı yenile.':
        'Your player profile is not ready. Reconnect from the main menu.',
    'Sunucuya bağlanılamadı. Tekrar deneyebilirsin.':
        'Could not reach the server. Please try again.',
    'ARENA EŞLEŞMESİ': 'ARENA MATCH',
    'Sunucu bağlantısı güvenli': 'Secure connection',
    'Çevrimdışı görünüyorsun': 'You are offline',
    'Rakibin bulunduğunda maç başlayacak.':
        'Your match starts when an opponent is found.',
    'Kupanı koru, gerçek bir rakiple temiz bir maç yap.':
        'Compete against another player for trophies.',
    'EŞLEŞMEYİ BAŞLAT': 'FIND A MATCH',
    'BAĞLANTIYI YENİLE': 'RECONNECT',
    'ARAMAYI İPTAL ET': 'CANCEL SEARCH',
    'MAÇ GÜVENLİĞİ': 'MATCH SECURITY',
    'Her hamle sunucuda doğrulanır. Maç boyunca internet bağlantını açık tut.':
        'Every move is checked by the server. Stay connected throughout the match.',
    'İnternet bağlantını kontrol et, ardından yeniden bağlan.':
        'Check your internet connection, then reconnect.',
    'YAPAY ZEKÂYA KARŞI': 'PLAY AGAINST AI',
    'HAMLEYE GEÇ': 'MAKE YOUR MOVE',
    'TAŞINI SEÇ': 'SELECT A PIECE',
    'KART AŞAMASI': 'CARD PHASE',
    'HAMLE AŞAMASI': 'MOVE PHASE',
    'RAKİP OYNUYOR': 'OPPONENT PLAYING',
    'KARTLARIN': 'YOUR CARDS',
    'Destede': 'In deck',
    'AYARLAR': 'SETTINGS',
    'SES VE GÖRÜNTÜ': 'SOUND & DISPLAY',
    'TERCİHLER': 'PREFERENCES',
    'HESAP': 'ACCOUNT',
    'Dil': 'Language',
    'Titreşim': 'Vibration',
    'Ses efektleri': 'Sound effects',
    'Arka plan müziği': 'Background music',
    'DÜŞÜK': 'LOW',
    'ORTA': 'MEDIUM',
    'YÜKSEK': 'HIGH',
    'Google hesabını bağla': 'Link Google account',
    'Google hesabı bağlanıyor...': 'Linking Google account...',
    'İlerlemeyi güvenli hesaba bağla':
        'Protect your progress with a secure account',
    'Rehberi yeniden izle': 'Replay the guide',
    'Çıkış yap': 'Sign out',
    'Misafir hesabı': 'Guest account',
    'TAMAM': 'OK',
    'VAZGEÇ': 'CANCEL',
    'ONAYLA': 'CONFIRM',
    'KAPAT': 'CLOSE',
    'TEKRAR DENE': 'RETRY',
    'Bekleyen sandık açılışını tamamla.': 'Finish your pending chest opening.',
    'Bekleyen sandık işlemi': 'Pending chest transaction',
    'Bekleyen ürün işlemi': 'Pending item transaction',
    'Bekleyen Premium alımını doğrula.':
        'Confirm your pending Premium purchase.',
    'Önceki sezonun Premium alımı doğrulandı. Yeni sezon etkinleştirilmedi.':
        'Your previous-season Premium purchase is confirmed. The new season was not activated.',
    'Sezon değişti. Güncel Pass durumunu kontrol edip yeniden dene.':
        'The season changed. Check the current Pass status and try again.',
    'SATIN ALIM DOĞRULANDI': 'PURCHASE CONFIRMED',
    'Satın alma doğrulandı. Ürün hesabında.':
        'Purchase confirmed. The item is in your account.',
    'Ürün hesabına eklendi.': 'The item was added to your account.',
    'İşlem henüz sonuçlanmadı. Kısa süre sonra tekrar dene.':
        'This transaction is still pending. Try again shortly.',
    'YENİDEN DENE': 'RETRY',
    'ANA MENÜ': 'MAIN MENU',
    'TEKRAR OYNA': 'PLAY AGAIN',
    'ÇIK': 'EXIT',
    'KAL': 'STAY',
    'KABUL ET': 'ACCEPT',
    'REDDET': 'DECLINE',
    'AÇ': 'OPEN',
    'ÖDÜLÜ AL': 'CLAIM REWARD',
    'ANLADIM': 'GOT IT',
    'DEVAM ET': 'CONTINUE',
    'KAYDET': 'SAVE',
    'DÜZENLE': 'EDIT',
    'ATLA': 'SKIP',
    'MAĞAZA': 'SHOP',
    'KOLEKSİYON': 'COLLECTION',
    'KART KOLEKSİYONU': 'CARD COLLECTION',
    'TAŞ KOSTÜMLERİ': 'PIECE COSTUMES',
    'EMOJİ KOLEKSİYONU': 'EMOTE COLLECTION',
    'DESTE': 'DECK',
    'SEZON YOLU': 'SEASON ROAD',
    'GÖREVLER': 'MISSIONS',
    'SIRALAMA': 'LEADERBOARD',
    'ARKADAŞLAR': 'FRIENDS',
    'MESAJ KUTUSU': 'INBOX',
    'PROFİL': 'PROFILE',
    'PROFİLİ DÜZENLE': 'EDIT PROFILE',
    'REHBER': 'GUIDE',
    'LUNO PREMIUM': 'LUNO PREMIUM',
    'BAŞARIMLAR': 'ACHIEVEMENTS',
    'MAÇ GEÇMİŞİ': 'MATCH HISTORY',
    'ARENALAR': 'ARENAS',
    'SEVİYE ÖDÜLLERİ': 'LEVEL REWARDS',
    'OYUNCU PROFİLİ': 'PLAYER PROFILE',
    'SIRALI EŞLEŞME': 'RANKED MATCHMAKING',
    'SIRALI MAÇ': 'RANKED MATCH',
    'LUNO EĞİTMENİ SEÇ': 'CHOOSE LUNO COACH',
    'ARKADAŞLA OYNA': 'PLAY WITH A FRIEND',
    'YÜZ YÜZE OYNA': 'LOCAL MATCH',
    'YAPAY ZEKA YA KARŞI': 'PLAY AGAINST AI',
    'SÜRE SEÇ': 'CHOOSE TIME',
    'PİYON TERFİSİ': 'PAWN PROMOTION',
    'Önerilen süre': 'Recommended time',
    'Seçili süre': 'Selected time',
    'Kendi yarı alanındaki boş kare': 'Empty square on your half of the board',
    'MAÇ TAMAMLANDI': 'MATCH COMPLETED',
    'Bu karşılaşma tamamlanmadan kapanacak.':
        'This match will close before it is completed.',
    'Maçı bitir': 'Finish match',
    'Teslim ol': 'Resign',
    'Yeniden başlat': 'Restart',
    'Menüye dön': 'Back to menu',
    'Maçtan çık?': 'Leave match?',
    'Maçtan ayrıl?': 'Leave match?',
    'Beraberlik teklif et': 'Offer draw',
    'Beraberlik teklifini geri çek': 'Withdraw draw offer',
    'Maç iptali teklif et': 'Offer match cancellation',
    'İptal teklifini geri çek': 'Withdraw cancellation offer',
    'GÜNLÜK ÖDÜL': 'DAILY REWARD',
    'Altın Sandık': 'Gold Chest',
    'Nadir Sandık': 'Rare Chest',
    'Efsanevi Sandık': 'Legendary Chest',
    'Kraliyet Sandığı': 'Royal Chest',
    'AKTİF': 'ACTIVE',
    'AKTİF ET': 'ACTIVATE',
    'HARİKA': 'AWESOME',
    'AÇILIYOR...': 'OPENING...',
    'ÜCRETSİZ': 'FREE',
    'PREMIUM': 'PREMIUM',
    'DESTEM': 'MY DECK',
    'KARTLAR': 'CARDS',
    'EMOJİLER': 'EMOTES',
    'İSTEKLER': 'REQUESTS',
    'ARAMA': 'SEARCH',
    'Henüz arkadaşın yok': 'You do not have any friends yet',
    'Odayı kapat': 'Close room',
    'ODA KODU İLE KATIL': 'JOIN WITH ROOM CODE',
    'ODA KODU': 'ROOM CODE',
    'KUPA': 'TROPHIES',
    'SIRAN': 'YOUR RANK',
    'EN İYİLER': 'TOP PLAYERS',
    'Koleksiyon': 'Collection',
    'Görevler': 'Missions',
    'Arkadaşlar': 'Friends',
    'Ayarlar': 'Settings',
    'Google hesabı bağlandı.': 'Google account linked.',
    'Google bağlantısı iptal edildi.': 'Google account linking was cancelled.',
    'Google hesabı bağlanamadı.': 'Could not link the Google account.',
    'Google hesabı bağlanamadı. Tekrar dene.':
        'Could not link the Google account. Try again.',
    'Bu Google hesabı başka bir Luno hesabına bağlı.':
        'This Google account is linked to another Luno account.',
    'Google ile giriş Firebase tarafında etkin değil.':
        'Google sign-in is not enabled in Firebase.',
    'Başka bir hesap bağlantısı devam ediyor.':
        'Another account link is already in progress.',
    'Güvenli hesap bağlantısı kurulamadı. Tekrar dene.':
        'Could not create a secure account link. Try again.',
  };
}

class _LunoLocalizationsDelegate
    extends LocalizationsDelegate<LunoLocalizations> {
  const _LunoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => LunoLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<LunoLocalizations> load(Locale locale) {
    return SynchronousFuture<LunoLocalizations>(
      LunoLocalizations(Locale(locale.languageCode == 'en' ? 'en' : 'tr')),
    );
  }

  @override
  bool shouldReload(_LunoLocalizationsDelegate old) => false;
}
