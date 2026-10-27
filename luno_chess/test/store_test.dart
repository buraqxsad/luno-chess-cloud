import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/data/username.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
  });

  test('başlangıç: 6 kart sahipliği + dolu deste', () {
    final s = GameStore.instance;
    expect(s.data.ownedCards.length, 6);
    expect(s.data.deck.length, 6);
    expect(s.resolvedDeck.contains('barbarian'), true);
    expect(ownedPhysicalCardCount(s.data.ownedCards, s.data.cardLevel), 6);
  });

  test('temiz kurulum varsayılan ilerleme ile onboardingden başlar', () async {
    final s = GameStore.createForTesting();
    await s.load();

    expect(s.data.gold, 1250);
    expect(s.hasChosenUsername, isFalse);
    expect(s.hasCompletedTutorial, isFalse);
    expect(s.tutorialStep, 0);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'luno_player_schema_v2',
      ),
      isFalse,
    );
  });

  test(
    'güncelleme eski ilerlemeyi korur ve oyuncu şemasını normalize eder',
    () async {
      final old =
          PlayerData.initial()
            ..username = 'old_player'
            ..gold = 9000
            ..bio = 'Kaybolmayan profil';
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode(old.toJson()),
      });

      final s = GameStore.createForTesting();
      await s.load();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('luno_player_v1')!);

      expect(s.data.username, 'old_player');
      expect(s.data.gold, 9000);
      expect(s.data.bio, 'Kaybolmayan profil');
      expect(s.hasChosenUsername, isTrue);
      expect(prefs.getInt('luno_player_schema_v2'), 2);
      expect(saved['schemaVersion'], 2);
    },
  );

  test('bozuk yerel snapshot kullanıcıyı onboardingden kilitlemez', () async {
    SharedPreferences.setMockInitialValues({'luno_player_v1': '{bozuk-json'});

    final s = GameStore.createForTesting();
    await s.load();
    final prefs = await SharedPreferences.getInstance();

    expect(s.data.gold, 1250);
    expect(s.hasChosenUsername, isFalse);
    expect(prefs.getString('luno_player_corrupt_backup_v2'), '{bozuk-json');
  });

  test(
    'yükleme tamamlanmadan save çağrısı güncelleme verisini ezmez',
    () async {
      final old = PlayerData.initial()..gold = 7777;
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode(old.toJson()),
      });
      final s = GameStore.createForTesting();

      final pendingSave = s.save();
      await pendingSave;
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('luno_player_v1')!);

      expect(saved['gold'], 7777);
      expect(prefs.getInt('luno_player_schema_v2'), 2);
      expect(s.data.gold, 7777);
    },
  );

  test('sunucu profili biyografiyi gösterir ve boşaltmayı da senkronlar', () {
    final s = GameStore.instance;
    s.data.bio = 'Eski biyo';

    s.applyServerState({
      'profile': {'bio': 'Yeni biyo'},
    });
    expect(s.data.bio, 'Yeni biyo');

    s.applyServerState({
      'profile': {'bio': ''},
    });
    expect(s.data.bio, isEmpty);
  });

  test('sunucu maç istatistikleri beraberlikleri toplam maça katar', () {
    final s = GameStore.instance;
    s.data.gamesPlayed = 99;
    s.applyServerState({
      'stats': {'wins': 2, 'losses': 1, 'draws': 3},
    });
    expect(s.data.wins, 2);
    expect(s.data.losses, 1);
    expect(s.data.draws, 3);
    expect(s.data.gamesPlayed, 6);
  });

  test('sunucu kullanıcı adı yerel önbellekteki eski adı düzeltir', () {
    final s = GameStore.instance;
    s.hasChosenUsername = true;
    s.data.username = 'old_name';
    s.applyServerState({
      'profile': {'username': 'new_name', 'name': 'old_name'},
    });
    expect(s.data.username, 'new_name');
    expect(normalizeUsernameValue('  New_Name  '), 'new_name');
    expect(isUsernameShapeValid('new_name'), true);
    expect(isUsernameShapeValid('two words'), false);
  });

  test(
    'tutorial ilerlemesi kapanışta korunur ve tamamlanınca sıfırlanır',
    () async {
      final s = GameStore.instance;
      await s.load();

      expect(s.hasCompletedTutorial, isFalse);
      expect(s.tutorialStep, 0);

      await s.setTutorialStep(4);
      expect(s.tutorialStep, 4);
      await s.load();
      expect(s.tutorialStep, 4);

      await s.completeTutorial();
      expect(s.hasCompletedTutorial, isTrue);
      expect(s.tutorialStep, 0);
      await s.load();
      expect(s.hasCompletedTutorial, isTrue);
      expect(s.tutorialStep, 0);
    },
  );

  test('kanonik kullanıcı adı okuyucusu eski name alanını geçersiz kılar', () {
    expect(
      usernameFromMap({'username': 'New_Name', 'name': 'old_name'}),
      'new_name',
    );
    expect(
      usernameFromMap({'username': 'two words', 'name': 'Legacy_Name'}),
      'legacy_name',
    );
    expect(usernameFromMap({'username': 42}, fallback: 'Oyuncu'), 'Oyuncu');
  });

  test(
    'sunucu Pass state tokenlarını ve bekleyen sandıkları yerel statee işler',
    () {
      final s = GameStore.instance;
      s.applyServerState({
        'passState': {
          'level': 1,
          'xp': 0,
          'unlocks': ['piece_set:ottoman'],
          'claimed': {
            'free': {'20': 1},
            'premium': {},
          },
        },
        'inventory': {
          'ownedEmojis': ['smile', 'laugh'],
          'ownedSets': ['std', 'ottoman'],
          'pendingChests': ['rare', 'rare'],
          'activePieceSet': 'ottoman',
        },
      });
      expect(s.data.passUnlocks, contains('ottoman'));
      expect(s.data.ownedEmojis, contains('laugh'));
      expect(s.data.ownedPieceSets, contains('luno'));
      expect(s.data.ownedPieceSets, contains('ottoman'));
      expect(s.data.pieceSet, 'ottoman');
      expect(s.data.passFreeClaimed, contains(20));
      expect(s.data.pendingChests, contains('rare'));
      expect(s.data.pendingChests.length, 2);
      expect(s.passLevel(), 1);
      expect(s.data.passXp, kPassXpPerLevel);
    },
  );

  test('Pass ödül sözleşmesi sunucu dağıtımını birebir izler', () {
    final freeGold = List.generate(
      30,
      (i) => passFree(i + 1),
    ).fold<int>(0, (sum, tier) => sum + tier.gold);
    final freeGems = List.generate(
      30,
      (i) => passFree(i + 1),
    ).fold<int>(0, (sum, tier) => sum + tier.gems);
    final premiumGems = List.generate(
      30,
      (i) => passPrem(i + 1),
    ).fold<int>(0, (sum, tier) => sum + tier.gems);
    expect(freeGold, 12300);
    expect(freeGems, 120);
    expect(premiumGems, 540);
    expect(passFree(16).kind, PassRewardKind.chest);
    expect(passFree(16).key, 'legendary');
    expect(passPrem(10).key, 'angry');
    expect(kPassPremiumCost, 450);
  });

  test('yükseltme: altınla aile seviyesi artar', () {
    final s = GameStore.instance;
    s.data.ownedCards.add('trap');
    s.data.deck[0] = 'trap';
    s.data.gold = 10000;
    s.data.trophies = 300;
    expect(s.upgradeCard('trap'), true);
    expect(s.data.gold, 7500);
    expect(s.data.cardLevel['trap'], 2);
    expect(s.resolvedDeck.contains('trap2'), true);
  });

  test('sandık: yeni kart kilidini açar', () {
    final s = GameStore.instance;
    s.data.gems = 1000;
    final before = s.data.ownedCards.length;
    final r = s.openChest(cost: 60, gem: true);
    expect(r, isNotNull);
    expect(r!.isNew, true); // arena 0 havuzu başlangıç kartı içermez
    expect(s.data.ownedCards.length, before + 1);
  });

  test('günlük ödül bir kez alınır', () {
    final s = GameStore.instance;
    expect(s.claimDaily(), isNotNull);
    expect(s.canClaimDaily(), false);
  });

  test('maç sonucu: galibiyet altın + istatistik', () {
    final s = GameStore.instance;
    final g0 = s.data.gold;
    final reward = s.recordResult(win: true, level: aiLevels[2]);
    expect(s.data.wins, 1);
    expect(s.data.gold, g0 + reward);
  });

  test('maç sonucu: beraberlik mağlubiyet sayılmaz', () {
    final s = GameStore.instance;
    final reward = s.recordResult(
      win: false,
      draw: true,
      level: aiLevels.first,
    );
    expect(s.data.gamesPlayed, 1);
    expect(s.data.wins, 0);
    expect(s.data.losses, 0);
    expect(s.data.draws, 1);
    expect(s.data.gold, 1250 + reward);
  });

  test(
    'yerel maç kariyeri günceller ama ekonomi ve Pass ilerlemesi vermez',
    () {
      final s = GameStore.instance;
      final goldBefore = s.data.gold;
      final passXpBefore = s.data.passXp;

      final reward = s.recordResult(
        win: true,
        level: aiLevels.last,
        cardsPlayed: 4,
        grantProgress: false,
      );

      expect(reward, 0);
      expect(s.data.gamesPlayed, 1);
      expect(s.data.wins, 1);
      expect(s.data.cardsPlayed, 4);
      expect(s.data.gold, goldBefore);
      expect(s.data.passXp, passXpBefore);
    },
  );

  test('koleksiyon puanı pozitif', () {
    expect(GameStore.instance.collectionScore() > 0, true);
  });

  test('taş kostümü seçimi kalıcıdır ve geçersiz seçim varsayılana döner', () {
    final s = GameStore.instance;
    s.data.ownedPieceSets.add('ottoman');
    s.setPieceSet('ottoman');
    expect(s.data.pieceSet, 'ottoman');
    expect(
      LunoAssets.pieceForSet('ottoman', PieceColor.white, PieceType.king),
      contains('piece-ottoman-w-king-v216.webp'),
    );

    s.setPieceSet('unknown-set');
    expect(s.data.pieceSet, 'ottoman');
    expect(
      LunoAssets.pieceForSet('old-value', PieceColor.black, PieceType.pawn),
      contains('piece-luno-b-pawn-v22-mobile.webp'),
    );
  });

  test('pass donum noktasi icerik odulunu kalici acar', () {
    final s = GameStore.instance;
    s.data.passXp = kPassMaxLevel * kPassXpPerLevel;
    s.claimPassFree(20);
    expect(s.data.passUnlocks, contains('ottoman'));
    expect(s.data.ownedPieceSets, contains('ottoman'));
    s.data.premium = true;
    s.claimPassPrem(30);
    expect(s.data.passUnlocks, contains('neon'));
    expect(s.data.ownedPieceSets, contains('neon'));
  });

  test('deste karti cikarirken alti kart korunur', () {
    final s = GameStore.instance;
    s.data.ownedCards.add('archer');
    final removed = s.data.deck.first;
    expect(s.removeFromDeck(removed), true);
    expect(s.data.deck.length, 6);
    expect(s.data.deck, isNot(contains(removed)));
  });
}
