import 'package:flutter/material.dart';

import '../cards/card_catalog.dart';
import '../data/card_pool.dart';
import '../engine/piece.dart';
import 'luno_visual_assets.dart';

/// The same art family used by the polished HTML build, addressed from native
/// Flutter widgets so visual changes stay centralized.
class LunoAssets {
  static const profileSceneV29 = 'assets/native_art/profile-scene-v29.png';
  static const seasonSceneV29 = 'assets/native_art/season-scene-v29.png';
  static const lobbySceneV29 = 'assets/native_art/lobby-scene-v29.png';
  static const collectionSceneV28 =
      'assets/native_art/collection-scene-v28.png';
  static const gameplaySceneV28 = 'assets/native_art/gameplay-scene-v28.png';
  static const battleActionV28 = 'assets/native_art/battle-action-v28.png';
  static const passSceneV27 = 'assets/native_art/pass-scene-v27.png';
  static const missionsSceneV27 = 'assets/native_art/missions-scene-v27.png';
  static const inboxSceneV27 = 'assets/native_art/inbox-scene-v27.png';
  static const settingsSceneV27 = 'assets/native_art/settings-scene-v27.png';
  static const actionSurfaceV27 = LunoVisualAssets.secondary;
  static const shopSurfaceV26 = 'assets/native_art/shop-surface-v26.png';
  static const passSurfaceV26 = 'assets/native_art/pass-surface-v26.png';
  const LunoAssets._();

  static const menuLuno = 'assets/native_art/menu-luno-idle-v10-mobile.webp';
  static const lunoPortrait = 'assets/native_art/luno-portrait-v212.webp';
  static const loadingScene = 'assets/native_art/loading-scene-v212.webp';
  static const menuLunoTalk =
      'assets/native_art/menu-luno-talk-v10-mobile.webp';
  static const menuLunoWave =
      'assets/native_art/menu-luno-wave-v10-mobile.webp';
  static const menuLunoThink =
      'assets/native_art/menu-luno-point-v10-mobile.webp';
  static const menuArenaCrest = 'assets/native_art/menu-arena-crest-v9.png';
  static const menuBattleGate = 'assets/native_art/menu-battle-gate-v2.png';
  static const menuBattlePanel = 'assets/native_art/menu-battle-panel-v25.png';
  static const menuShortcutSurface =
      'assets/native_art/menu-shortcut-surface-v25.png';
  static const battleArena = 'assets/native_art/screen-battle-arena-v23.webp';
  static const phase2GameplayAtmosphere =
      'assets/native_art/phase2/gameplay-atmosphere-v2.png';
  static const phase2RankingPodium =
      'assets/native_art/phase2/ranking-podium-v2.png';
  static const phase2TutorialAcademy =
      'assets/native_art/phase2/tutorial-academy-v204.png';
  static const phase2ShopShowcase =
      'assets/native_art/phase2/shop-showcase-v2.png';
  static const phase2ResultVictory =
      'assets/native_art/phase2/result-victory-v2.png';
  static const menuScene = 'assets/native_art/menu-battle-hero-v23.webp';
  static const warRoom = 'assets/native_art/screen-war-room-v15.webp';
  static const battleButton =
      'assets/native_art/embedded/b3aab6dee0f7f6a95ec56c53.webp';
  // Build 12'nin tahta katmanları: dokulu kareler + ayrı şeffaf çerçeve.
  static const board =
      'assets/native_art/embedded/c5d2902c1b863e5be2be3056.webp';
  static const boardLight = 'assets/native_art/board-tile-light-v22.webp';
  static const boardDark = 'assets/native_art/board-tile-dark-v22.webp';
  static const boardFrame = 'assets/native_art/board-frame-v15.webp';
  static const arenaRoad = 'assets/native_art/screen-arena-road-v15.webp';
  static const seasonRoad =
      'assets/native_art/season-road-luno-v15-mobile.webp';
  static const collection = 'assets/native_art/screen-card-album.png';
  static const deck = 'assets/native_art/luno-deck.png';
  static const shop = 'assets/native_art/screen-shop-bundle.png';
  static const pass = 'assets/native_art/pass-season-v5.png';
  static const guide = 'assets/native_art/luno-guide.png';
  static const tutorial = 'assets/native_art/screen-tutorial-academy-v23.webp';
  static const premium = 'assets/native_art/screen-premium-ticket.png';
  static const resultVictory = 'assets/native_art/result-victory.png';
  static const resultDefeat = 'assets/native_art/result-defeat.png';
  static const resultDraw = 'assets/native_art/result-draw.png';
  static const matchChat =
      'assets/native_art/match-control-chat-v12-mobile.webp';
  static const matchContinue =
      'assets/native_art/match-control-continue-v12-mobile.webp';
  static const matchDraw =
      'assets/native_art/match-control-draw-v12-mobile.webp';
  static const matchEmoji =
      'assets/native_art/match-control-emoji-v12-mobile.webp';
  static const matchResign =
      'assets/native_art/match-control-resign-v12-mobile.webp';
  static const matchSettings =
      'assets/native_art/match-control-settings-v12-mobile.webp';

  // HTML ana menüsünde kullanılan, etiketleri görselin içine gömülü hızlı
  // erişim ve alt navigasyon taşları.
  static const navPass = 'assets/native_art/menu-action-pass-v2.png';
  static const navFriends = 'assets/native_art/menu-action-friends-v2.png';
  static const navMissions = 'assets/native_art/menu-action-missions-v2.png';
  static const navRanking = 'assets/native_art/menu-action-ranking-v2.png';
  static const navGuide = 'assets/native_art/menu-action-guide-v2.png';
  static const navSettings = 'assets/native_art/menu-action-settings-v2.png';
  static const navShop = 'assets/native_art/nav-shop.png';
  static const navCollection = 'assets/native_art/nav-collection.png';
  static const navBattle = 'assets/native_art/nav-battle.png';
  static const navSeason = 'assets/native_art/nav-season.png';
  static const navProfile = 'assets/native_art/nav-profile.png';
  static const navChat = 'assets/native_art/menu-status-dm-v2.png';
  static const statusProfile = 'assets/native_art/menu-status-profile-v2.png';
  static const statusTrophy = 'assets/native_art/menu-status-trophy-v2.png';
  static const statusGold = 'assets/native_art/menu-status-gold-v2.png';
  static const statusGem = 'assets/native_art/menu-status-gem-v2.png';

  // Build 12'nin ekran bazlı final art kataloğu. Bu dosyalar tester APK'sinden
  // aynı adlarla alındı; ekranlar eski gömülü varyantlara geri dönmesin.
  static const shopPremium = 'assets/native_art/shop-premium-v3.png';
  static const shopDaily = 'assets/native_art/shop-daily-v3.png';
  static const shopStarter = 'assets/native_art/shop-starter-v3.png';
  static const shopExpert = 'assets/native_art/shop-expert-v3.png';
  static const shopCostumeShowcase =
      'assets/native_art/shop-costume-showcase-v1.png';
  static const shopChestLegendary =
      'assets/native_art/shop-chest-legendary-v3.png';
  static const shopChestRoyal = 'assets/native_art/shop-chest-royal-v3.png';
  static const shopGoldMedium = 'assets/native_art/shop-gold-medium-v3.png';
  static const shopGemMedium = 'assets/native_art/shop-gem-medium-v3.png';

  static const passSeason = 'assets/native_art/pass-season-v5.png';
  static const passMissions = 'assets/native_art/pass-missions-v5.png';
  static const passPremium = 'assets/native_art/pass-premium-v5.png';
  static const passTrackFree = 'assets/native_art/pass-track-free-v5.png';
  static const passTrackPremium = 'assets/native_art/pass-track-premium-v5.png';
  static const passLevelFrame = 'assets/native_art/pass-level-frame-v5.png';

  static const friendsTab = 'assets/native_art/friends-tab-v6.png';
  static const friendsRequestsTab =
      'assets/native_art/friends-requests-tab-v6.png';
  static const friendsRankingTab =
      'assets/native_art/friends-ranking-tab-v6.png';
  static const friendsSearch = 'assets/native_art/friends-search-v6.png';
  static const friendsEmpty = 'assets/native_art/friends-empty-v6.png';
  static const friendsRequestsEmpty =
      'assets/native_art/friends-requests-empty-v6.png';
  static const friendsActionMessage =
      'assets/native_art/friends-action-message-v6.png';
  static const friendsActionBattle =
      'assets/native_art/friends-action-battle-v6.png';
  static const friendsActionRemove =
      'assets/native_art/friends-action-remove-v6.png';
  static const friendsActionAccept =
      'assets/native_art/friends-action-accept-v6.png';
  static const friendsActionReject =
      'assets/native_art/friends-action-reject-v6.png';
  static const friendsActionAdd = 'assets/native_art/friends-action-add-v6.png';

  static const missionsHero = 'assets/native_art/missions-hero-v6.png';
  static const missionsDailyTab = 'assets/native_art/missions-daily-tab-v6.png';
  static const missionsWeeklyTab =
      'assets/native_art/missions-weekly-tab-v6.png';
  static const missionsSpecialTab =
      'assets/native_art/missions-special-tab-v6.png';

  static const settingsLanguageTr =
      'assets/native_art/settings-language-tr-v8.png';
  static const settingsLanguageEn =
      'assets/native_art/settings-language-en-v8.png';
  static const settingsSound = 'assets/native_art/settings-sound-v8.png';
  static const settingsMusic = 'assets/native_art/settings-music-v8.png';
  static const settingsVibration =
      'assets/native_art/settings-vibration-v8.png';
  static const settingsAnimation =
      'assets/native_art/settings-animation-v8.png';
  static const settingsGame = 'assets/native_art/settings-game-v8.png';
  static const settingsHints = 'assets/native_art/settings-hints-v8.png';
  static const settingsNotification =
      'assets/native_art/settings-notification-v9.png';
  static const settingsFriendsDm =
      'assets/native_art/settings-friends-dm-v9.png';
  static const settingsGuide = 'assets/native_art/settings-guide-v9.png';
  static const settingsEdit = 'assets/native_art/settings-edit-v9.png';
  static const settingsSignout = 'assets/native_art/settings-signout-v8.png';
  static const settingsInstagram =
      'assets/native_art/settings-instagram-v8.png';
  static const settingsTiktok = 'assets/native_art/settings-tiktok-v8.png';
  static const settingsAbout = 'assets/native_art/settings-about-v8.png';

  static const profileGallery = 'assets/native_art/profile-gallery-v7.png';
  static const profileCrest = 'assets/native_art/screen-profile-crest.png';
  static const profilePhotoRemove =
      'assets/native_art/profile-photo-remove-v7.png';
  static const profileCountry = 'assets/native_art/profile-country-v7.png';
  static const profileSave = 'assets/native_art/profile-save-v7.png';
  static const profileAbout = 'assets/native_art/profile-about-v4.png';
  static const profileMatchStats =
      'assets/native_art/profile-match-stats-v4.png';
  static const profileLoginStreak =
      'assets/native_art/profile-login-streak-v4.png';
  static const profilePass = 'assets/native_art/profile-pass-v4.png';
  static const profileCountryTr = 'assets/native_art/profile-country-tr-v4.png';
  static const profileJoinDate = 'assets/native_art/profile-join-date-v4.png';
  static const profileAchievements =
      'assets/native_art/profile-achievements-v4.png';
  static const profileSignout = 'assets/native_art/profile-signout-v4.png';

  // Savaş modu ve eğitmen seçiminde kullanılan final görseller.
  static const modeRanked = 'assets/native_art/mode-ranked-v12-mobile.webp';
  static const modeAi = 'assets/native_art/mode-ai-v12-mobile.webp';
  static const modeFriend = 'assets/native_art/mode-friend-v12-mobile.webp';
  static const modeLocal = 'assets/native_art/mode-local-v12-mobile.webp';
  static const aiBebek = 'assets/native_art/ai-bebek-v12-mobile.webp';
  static const aiComez = 'assets/native_art/ai-comez-v12-mobile.webp';
  static const aiSovalye = 'assets/native_art/ai-sovalye-v12-mobile.webp';
  static const aiUsta = 'assets/native_art/ai-usta-v12-mobile.webp';
  static const aiBilge = 'assets/native_art/ai-bilge-v12-mobile.webp';
  static const aiEfsane = 'assets/native_art/ai-efsane-v12-mobile.webp';

  static String aiPortrait(String id) => switch (id) {
    'comez' => aiComez,
    'sovalye' => aiSovalye,
    'bilge' => aiBilge,
    'usta' => aiUsta,
    'efsane' => aiEfsane,
    _ => aiBebek,
  };

  static String arena(int index) {
    const names = [
      'acemi',
      'piyon',
      'hukumdar',
      'golge',
      'imparator',
      'usta',
      'kraliyet',
      'legend',
      'mythic',
    ];
    final safeIndex = index.clamp(0, names.length - 1);
    final number = (safeIndex + 1).toString().padLeft(2, '0');
    return 'assets/native_art/arena-$number-${names[safeIndex]}-v24.webp';
  }

  static const uiCollectionDeck =
      'assets/native_art/collection-deck-v10-mobile.webp';
  static const uiCollectionCards =
      'assets/native_art/collection-cards-v10-mobile.webp';
  static const uiCollectionSkins =
      'assets/native_art/collection-costumes-v10-mobile.webp';
  static const uiCollectionEmoji =
      'assets/native_art/collection-emojis-v10-mobile.webp';
  static const uiDailyMission = 'assets/native_art/missions-daily-tab-v6.png';
  static const uiWeeklyMission = 'assets/native_art/missions-weekly-tab-v6.png';
  static const uiSpecialMission =
      'assets/native_art/missions-special-tab-v6.png';
  static const uiEditProfile = 'assets/native_art/profile-gallery-v7.png';
  static const uiLogout = 'assets/native_art/profile-signout-v4.png';
  static const uiGuide = 'assets/native_art/guide-purpose-v7.png';
  static const profileTrophy = 'assets/native_art/profile-stat-trophy-v4.png';
  static const profileWins = 'assets/native_art/profile-stat-wins-v4.png';
  static const profileRate = 'assets/native_art/profile-stat-rate-v4.png';
  static const profileStreak = 'assets/native_art/profile-stat-streak-v4.png';
  static const profileCollection =
      'assets/native_art/profile-collection-v4.png';
  static const profileHistory = 'assets/native_art/profile-history-v4.png';
  static const rankingBackdrop =
      'assets/native_art/ranking-podium-backdrop-v9.jpg';
  static const rankingGold = 'assets/native_art/ranking-podium-gold-v7.png';
  static const rankingSilver = 'assets/native_art/ranking-podium-silver-v7.png';
  static const rankingBronze = 'assets/native_art/ranking-podium-bronze-v7.png';
  static const rankingCrown = 'assets/native_art/ranking-luno-crown-v7.png';
  static const rankingStarGold = 'assets/native_art/ranking-star-gold-v7.png';
  static const rankingStarSilver =
      'assets/native_art/ranking-star-silver-v7.png';
  static const rankingStarBronze =
      'assets/native_art/ranking-star-bronze-v7.png';
  static const coin = 'assets/native_art/luno-coin.png';
  static const gem = 'assets/native_art/luno-gem.png';
  static const trophy = 'assets/native_art/luno-trophy.png';
  static const packGoldSmall = 'assets/native_art/shop-gold-small-v3.png';
  static const packGoldLarge = 'assets/native_art/shop-gold-large-v3.png';
  static const packGemSmall = 'assets/native_art/shop-gem-small-v3.png';
  static const packGemLarge = 'assets/native_art/shop-gem-large-v3.png';
  static const chestCommon = 'assets/native_art/shop-chest-common-v3.png';
  static const chestRare = 'assets/native_art/shop-chest-rare-v3.png';
  static const chestLegendary = 'assets/native_art/shop-chest-legendary-v3.png';
  static const chestRoyal = 'assets/native_art/shop-chest-royal-v3.png';

  static const emojiAssets = <String>[
    'assets/native_art/emoji-hello-v12-mobile.webp',
    'assets/native_art/emoji-heart-v12-mobile.webp',
    'assets/native_art/emoji-laugh-v12-mobile.webp',
    'assets/native_art/emoji-cry-v12-mobile.webp',
    'assets/native_art/emoji-angry-v12-mobile.webp',
    'assets/native_art/emoji-think-v12-mobile.webp',
    'assets/native_art/emoji-fire-v12-mobile.webp',
    'assets/native_art/emoji-star-v12-mobile.webp',
    'assets/native_art/emoji-thunder-v12-mobile.webp',
    'assets/native_art/emoji-oops-v12-mobile.webp',
    'assets/native_art/emoji-timekeeper-v12-mobile.webp',
    'assets/native_art/emoji-trophy-v12-mobile.webp',
    'assets/native_art/emoji-crown-v12-mobile.webp',
    'assets/native_art/emoji-cosmic-v12-mobile.webp',
  ];

  static String emoji(String id) {
    const files = {
      'smile': 'emoji-hello-v12-mobile.webp',
      'heart': 'emoji-heart-v12-mobile.webp',
      'laugh': 'emoji-laugh-v12-mobile.webp',
      'cry': 'emoji-cry-v12-mobile.webp',
      'angry': 'emoji-angry-v12-mobile.webp',
      'think': 'emoji-think-v12-mobile.webp',
      'fire': 'emoji-fire-v12-mobile.webp',
      'star': 'emoji-star-v12-mobile.webp',
      'thunder': 'emoji-thunder-v12-mobile.webp',
      'bomb': 'emoji-oops-v12-mobile.webp',
      'strat': 'emoji-timekeeper-v12-mobile.webp',
      'trophy': 'emoji-trophy-v12-mobile.webp',
      'crown': 'emoji-crown-v12-mobile.webp',
      'rainbow': 'emoji-cosmic-v12-mobile.webp',
      'emoji-smile': 'emoji-hello-v12-mobile.webp',
      'emoji-heart': 'emoji-heart-v12-mobile.webp',
      'emoji-laugh': 'emoji-laugh-v12-mobile.webp',
      'emoji-cry': 'emoji-cry-v12-mobile.webp',
      'emoji-angry': 'emoji-angry-v12-mobile.webp',
      'emoji-wow': 'emoji-think-v12-mobile.webp',
      'emoji-oops': 'emoji-oops-v12-mobile.webp',
      'emoji-trophy': 'emoji-trophy-v12-mobile.webp',
    };
    return 'assets/native_art/${files[id] ?? files['smile']!}';
  }

  static String chest(String id) {
    const files = {
      'common': 'shop-chest-common-v3.png',
      'rare': 'shop-chest-rare-v3.png',
      'legendary': 'shop-chest-legendary-v3.png',
      'royal': 'shop-chest-royal-v3.png',
    };
    return 'assets/native_art/${files[id] ?? files['common']!}';
  }

  static const _pieceSets = {
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
  };

  static String setPreview(String set) =>
      set == 'luno' || !_pieceSets.contains(set)
          ? 'assets/native_art/piece-set-luno-v216.webp'
          : 'assets/native_art/piece-set-$set-v216.webp';

  static String avatar(String id) {
    const files = {
      'av_pawn': 'luno-portrait-v212.webp',
      'av_knight': 'avatar-knight-v9.png',
      'av_bishop': 'avatar-bishop-v9.png',
      'av_rook': 'avatar-rook-v9.png',
      'av_queen': 'avatar-queen-v9.png',
      'av_king': 'avatar-king-v9.png',
      'av_robot': 'avatar-robot-v9.png',
      'av_robotcrown': 'avatar-robot-king-v9.png',
      'av_crown': 'avatar-crown-v9.png',
      'av_lightning': 'avatar-lightning-v9.png',
      'av_fire': 'avatar-fire-v9.png',
    };
    return 'assets/native_art/${files[id] ?? files['av_pawn']!}';
  }

  static String countryName(String code) {
    switch (code.trim().toUpperCase()) {
      case 'TR':
        return 'TÜRKİYE';
      case 'US':
        return 'UNITED STATES';
      case 'GB':
        return 'UNITED KINGDOM';
      case 'DE':
        return 'DEUTSCHLAND';
      default:
        return code.trim().isEmpty ? 'ÜLKE SEÇİLMEDİ' : code.toUpperCase();
    }
  }

  static String achievement(String id) =>
      'assets/native_art/achievement-$id-v4.png';

  static String level(int value) {
    final safe = value.clamp(1, 50).toInt();
    return 'assets/native_art/embedded/${_levelFiles[safe - 1]}';
  }

  static const _levelFiles = <String>[
    '1c866713d9f47d451103fd09.webp',
    '2ffd9ee967eddd6251c266d7.webp',
    'cf7d3da23976c6e8dd01352f.webp',
    '964affdf6af0e1f4d2f1dcff.webp',
    '342449433089c942a6ddd6f8.webp',
    '28c8e4e1a425461bc3714795.webp',
    '33712b342996ed5443a9d277.webp',
    '87530a6c954a40062f6c4c61.webp',
    'feb2ed7a6df7d0e5f79ef59d.webp',
    '925d77c739356f49de945fc1.webp',
    'f9bba1d373d1361063c22e7b.webp',
    '6841cb26c51b97391b13483f.webp',
    '46a4085485e739f6ab51a52b.webp',
    'c83b87b1ea97ca9dcf573b67.webp',
    '656039c4d565e17537cbd35c.webp',
    'c73628f4cb6aa3aea5903f38.webp',
    '83ac060de31b97da4251a84a.webp',
    '6ba124f441140662605c7b47.webp',
    'de1949dc4e757ddfbe8ad205.webp',
    '0d9f6ccd0690904fefa6bc52.webp',
    'b6f0d828c088dc13ef48a5b6.webp',
    '4b20901af7d2030e6d5a49de.webp',
    '7c03a3c6f51d10583abb1026.webp',
    '75fdb7dade1cd1f325177a19.webp',
    'ce906005494a71dc4eb52095.webp',
    '0b6711e9248c676be7bd2fdd.webp',
    'e56d6f344fae81cb51008932.webp',
    '176e3a55baa5827c7460ed49.webp',
    '1496e36df690423679f7d83a.webp',
    'c5ca314960213b88b1417ddb.webp',
    '58af8f6e612596e608c03f6f.webp',
    'c707ec7cc6b3c06f4634fc15.webp',
    '99c3c436ceed2272420562ee.webp',
    'eac31582a2a2a5cb88a02b26.webp',
    'a21f0751ce96627033ded6f1.webp',
    '1b7847dcfefe15e62ede2495.webp',
    '3ff9556851ba5a01deeb8e0d.webp',
    'c92fcf9638e47fb497661d94.webp',
    'a9bf9ceb97816b9896ffe2c5.webp',
    '62c4dfc825b9b0cca5206d86.webp',
    '029c29c650ef380bb1c12e8f.webp',
    '40beac69cd5e6d7b2281e2f2.webp',
    'f628bcc7ec3467ca5a1cce77.webp',
    '41a110373d1109cae017fd5f.webp',
    '61c9ad5bc615c9a44ae79a6a.webp',
    'd936d729250f05e0c0c8872f.webp',
    '963768434facf74a7bd151a5.webp',
    'eeebf1fec049cab18ae53436.webp',
    '240f066ae8c3ddfa4a8fe40b.webp',
    '756871914a91db532a0f8f15.webp',
  ];

  static String card(String ownedKey, int level) {
    // Keep an explicit catalog variant (for example a newly unlocked trap3)
    // intact; family aliases still resolve to the player's current level.
    final key =
        kCards.containsKey(ownedKey) ? ownedKey : resolvedKey(ownedKey, level);
    return 'assets/native_art/card-$key-v10-mobile.webp';
  }

  static String piece(PieceColor color, PieceType type) {
    final side = color == PieceColor.white ? 'w' : 'b';
    final name = switch (type) {
      PieceType.king => 'king',
      PieceType.queen => 'queen',
      PieceType.rook => 'rook',
      PieceType.bishop => 'bishop',
      PieceType.knight => 'knight',
      PieceType.pawn => 'pawn',
    };
    return 'assets/native_art/piece-luno-$side-$name-v22-mobile.webp';
  }

  static String pieceForSet(String set, PieceColor color, PieceType type) {
    if (!_pieceSets.contains(set) || set == 'luno') return piece(color, type);
    final side = color == PieceColor.white ? 'w' : 'b';
    final name = switch (type) {
      PieceType.king => 'king',
      PieceType.queen => 'queen',
      PieceType.rook => 'rook',
      PieceType.bishop => 'bishop',
      PieceType.knight => 'knight',
      PieceType.pawn => 'pawn',
    };
    return 'assets/native_art/piece-$set-$side-$name-v216.webp';
  }
}

class LunoArt extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final double decodeScale;

  const LunoArt(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.decodeScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
        final logicalWidth =
            width ??
            (constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : null);
        final logicalHeight =
            height ??
            (constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : null);
        final decodeDpr = dpr * decodeScale;
        final cacheWidth = _decodePixels(logicalWidth, decodeDpr);
        final cacheHeight =
            cacheWidth == null ? _decodePixels(logicalHeight, decodeDpr) : null;

        return Image.asset(
          path,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      },
    );
  }

  static int? _decodePixels(double? logicalSize, num dpr) {
    if (logicalSize == null || !logicalSize.isFinite || logicalSize <= 0) {
      return null;
    }
    return (logicalSize * dpr).ceil().clamp(1, 4096);
  }
}
