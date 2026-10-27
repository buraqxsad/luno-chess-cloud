import 'dart:io';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/resource_amount.dart';
import 'package:luno_chess/widgets/match_offer_banner.dart';
import 'package:luno_chess/widgets/match_confirmation.dart';
import 'package:luno_chess/widgets/promotion_sheet.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/widgets/card_level_sheet.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/guide_screen.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/deck_screen.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const screen = String.fromEnvironment('CAPTURE_SCREEN', defaultValue: 'home');
  const scroll = int.fromEnvironment('CAPTURE_SCROLL', defaultValue: 0);
  const fixture = bool.fromEnvironment('CAPTURE_FIXTURE');
  const details = bool.fromEnvironment('CAPTURE_DETAILS');
  const cardActions = bool.fromEnvironment('CAPTURE_CARD_ACTIONS');
  const socialState = String.fromEnvironment('CAPTURE_SOCIAL_STATE');
  const rankingMode = String.fromEnvironment(
    'CAPTURE_RANKING_MODE',
    defaultValue: 'trophies',
  );
  testWidgets('capture current production $screen screen', (tester) async {
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    store.data = PlayerData.initial();
    store.loaded = true;
    store.hasChosenUsername = true;
    store.hasCompletedTutorial = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry
          in {
            'Cinzel': 'assets/fonts/cinzel-latin.ttf',
            'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
            'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
            'Spectral': 'assets/fonts/spectral/spectral-regular-latin.ttf',
            'SpectralTurkish':
                'assets/fonts/spectral/spectral-regular-turkish.ttf',
            'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
          }.entries) {
        await (FontLoader(entry.key)
          ..addFont(rootBundle.load(entry.value))).load();
      }
    });
    final key = GlobalKey();
    if (fixture && screen == 'deck-upgrades') {
      GameStore.instance.data.ownedCards.addAll(['trap', 'radar', 'deploy']);
      GameStore.instance.data.cardLevel.addAll({
        'trap': 1,
        'radar': 1,
        'deploy': 2,
      });
      GameStore.instance.data.trophies = 300;
      GameStore.instance.data.gold = 3000;
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: LunoTheme.dark,
          home: switch (screen) {
            'shop' => const ShopScreen(),
            'shop-reward' => Scaffold(
              body: ShopRewardDialog(
                title: 'GÜNLÜK ÖDÜL',
                art: LunoAssets.shopDaily,
                message: '+500 altın hesabına eklendi.',
                reward: ResourceAmount.coin(500, iconSize: 40, fontSize: 20),
              ),
            ),
            'offer' => Scaffold(
              body: Center(
                child: MatchOfferBanner(
                  title: 'Rakip beraberlik teklif etti.',
                  firstLabel: 'KABUL ET',
                  secondLabel: 'REDDET',
                  onFirst: () {},
                  onSecond: () {},
                ),
              ),
            ),
            'chest' => const Scaffold(
              body: ChestRevealDialog(
                chestId: 'rare',
                rewards: [
                  {'type': 'gold', 'amount': 1500},
                  {'type': 'gems', 'amount': 30},
                  {
                    'type': 'card',
                    'id': 'freeze',
                    'name': 'Dondurma',
                    'amount': 1,
                    'unlocked': true,
                  },
                ],
              ),
            ),
            'pass' => const PassScreen(),
            'settings' => const SettingsScreen(),
            'missions' => const MissionsScreen(),
            'inbox' => const InboxScreen(),
            'collection' => const CollectionScreen(),
            'deck' => const BattleDeckScreen(),
            'deck-upgrades' => const DeckScreen(),
            'cards' => const BattleDeckScreen(catalogOnly: true),
            'emojis' => const EmojiCollectionScreen(),
            'costumes' => const PieceCostumeScreen(),
            'play' => const PlayModeScreen(),
            'game' => GameScreen(level: aiLevels.first, local: true),
            'online-hand' => OnlineMatchScreen(
              matchId: 'capture-fixture',
              initialView: {
                'status': 'active',
                'viewerColor': 'W',
                'turn': 'W',
                'phase': 'card',
                'hand': kCards.keys.take(6).toList(),
                'mana': {'W': 10, 'B': 10},
                'player': {'name': 'LunoPlayer', 'trophies': 100},
                'opponent': {'name': 'Rakip', 'trophies': 120},
                'board': List.generate(64, (i) {
                  if (i >= 16 && i < 48) return null;
                  return {
                    'c': i < 16 ? 'W' : 'B',
                    't':
                        (i >= 8 && i < 56)
                            ? 'P'
                            : ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'][i % 8],
                  };
                }),
              },
            ),
            'result' => ResultScreen(
              result: MatchResult.blackWins,
              level: aiLevels.first,
              reward: 0,
              local: true,
            ),
            'profile' => const ProfileScreen(),
            'edit-profile' => const EditProfileScreen(),
            'ranking' => const RankingScreen(),
            'achievements' => const AchievementsScreen(),
            'history' => const MatchHistoryScreen(),
            'friends' => const FriendsScreen(),
            'difficulty' => const DifficultyScreen(),
            'guide' => const TutorialScreen(),
            'legacy-guide' => const GuideScreen(),
            'friendly' => const FriendlyOnlineScreen(),
            'ranked' => const OnlineHubScreen(),
            'arenas' => const ArenasScreen(),
            'dm' => const DirectMessageScreen(
              targetUid: 'fixture',
              targetName: 'Deniz',
            ),
            'public-profile' => const PlayerDetailsScreen(
              name: 'Deniz',
              trophies: 1450,
              wins: 84,
              games: 120,
              country: 'TR',
              bio: 'Her hamlede yeni bir fikir.',
              avatarArt: 'assets/native_art/avatar-pawn-v9.png',
            ),
            'season' => const SeasonScreen(),
            'premium' => const LunoPremiumScreen(),
            'levels' => const LevelRewardsScreen(),
            _ => const HomeScreen(),
          },
        ),
      ),
    );
    if (fixture && screen == 'dm') {
      final dynamic state = tester.state(find.byType(DirectMessageScreen));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      state.setState(() {
        state.error = null;
        state.messagesStream = Stream.value(<Map<String, dynamic>>[
          {'from': 'friend', 'text': 'Bir dostluk maçı oynayalım mı?'},
          {'from': null, 'text': 'Olur! Oda kodunu bekliyorum.'},
        ]);
      });
      await tester.pump();
    }
    if (fixture && screen == 'ranking') {
      final dynamic state = tester.state(find.byType(RankingScreen));
      state.setState(() {
        state.mode = rankingMode;
        state.loading = false;
        state.error = null;
        state.rows = <Map<String, dynamic>>[
          for (var i = 0; i < 8; i++)
            {
              'uid': 'fixture-$i',
              'username': ['Deniz', 'LunoUstasi', 'Mavi'][i % 3],
              'trophies': 3200 - i * 200,
              'collectionScore': 12000 - i * 500,
              'seasonScore': 8000 - i * 300,
              'avatarEmoji': 'av_pawn',
              'country': 'TR',
            },
        ];
      });
      await tester.pump();
    }
    if (fixture && screen == 'achievements') {
      final dynamic state = tester.state(find.byType(AchievementsScreen));
      for (var i = 0; i < 20 && state.loading == true; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      state.setState(() {
        state.loading = false;
        state.error = null;
        state.serverAchievements = <Map<String, dynamic>>[
          {
            'id': 'first_win',
            'title': 'İlk Zafer',
            'description': 'İlk maçını kazan.',
            'target': 1,
            'progress': 1,
            'reward': {'gold': 100},
          },
          {
            'id': 'win_10',
            'title': 'Acemi Savaşçı',
            'description': '10 maç kazan.',
            'target': 10,
            'progress': 4,
            'reward': {'gold': 300},
          },
          {
            'id': 'streak_3',
            'title': 'Sıcak Eller',
            'description': '3 maç üst üste kazan.',
            'target': 3,
            'progress': 3,
            'claimed': true,
            'reward': {'gold': 200},
          },
        ];
      });
      await tester.pump();
    }
    if (fixture && screen == 'friends') {
      final dynamic state = tester.state(find.byType(FriendsScreen));
      for (var i = 0; i < 20 && state.socialLoading == true; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      state.setState(() {
        state.socialLoading = false;
        state.friendRows = <Map<String, dynamic>>[
          {
            'uid': 'fixture-one',
            'username': 'uzunoyuncuismi',
            'trophies': 3200,
          },
          {'uid': 'fixture-two', 'username': 'deniz', 'trophies': 1450},
        ];
        if (socialState == 'requests' || socialState == 'requests-empty') {
          state.tab = 1;
          state.requestRows =
              socialState == 'requests'
                  ? <Map<String, dynamic>>[
                    {
                      'fromUid': 'fixture-one',
                      'fromUsername': 'uzunoyuncuismi',
                      'avatarEmoji': 'av_knight',
                    },
                  ]
                  : <Map<String, dynamic>>[];
        }
      });
      await tester.pump();
    }
    if (fixture && screen == 'season') {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final dynamic state = tester.state(find.byType(SeasonScreen));
      state.setState(() {
        state.loading = false;
        state.error = null;
        state.season = <String, dynamic>{
          'status': 'active',
          'seasonNumber': 4,
          'score': 150,
          'progress': .25,
          'nextTrophies': 300,
          'claimableCount': 1,
          'serverTime': 1800000000000,
          'seasonEndAt': 1800604800000,
          'path': [
            {
              'id': 'one',
              'title': 'İlk adım',
              'minTrophies': 0,
              'state': 'claimed',
              'reward': {'gold': 100},
            },
            {
              'id': 'two',
              'title': 'Piyon Vadisi',
              'minTrophies': 100,
              'state': 'unlocked',
              'canClaim': true,
              'reward': {'gold': 250, 'gems': 10},
            },
            {
              'id': 'three',
              'title': 'Hükümdar',
              'minTrophies': 300,
              'state': 'locked',
              'isCurrent': true,
              'reward': {'gold': 500, 'gems': 20},
            },
          ],
        };
      });
      await tester.pump();
    }
    if (fixture && (screen == 'missions' || screen == 'inbox')) {
      // Visual fixtures exercise real widgets; they do not verify live services.
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final dynamic state = tester.state(
        find.byType(screen == 'missions' ? MissionsScreen : InboxScreen),
      );
      state.setState(() {
        state.error = null;
        if (screen == 'missions') {
          state.loading = false;
          state.missions = <String, List<Map<String, dynamic>>>{
            'daily': [
              {
                'id': 'daily_play',
                'title': 'Tahtaya çık',
                'description': 'Bugün 3 maçı tamamla.',
                'target': 3,
                'progress': 1,
                'reward': {'gold': 150},
                'passXp': 40,
              },
              {
                'id': 'daily_win',
                'title': 'Zafer zamanı',
                'description': 'Bir maç kazan.',
                'target': 1,
                'progress': 1,
                'reward': {'gold': 200, 'gems': 5},
                'passXp': 60,
              },
              {
                'id': 'daily_card',
                'title': 'Kart ustası',
                'description': 'Maçlarda 5 kart kullan.',
                'target': 5,
                'progress': 5,
                'claimed': true,
                'reward': {'gold': 100},
                'passXp': 30,
              },
            ],
            'weekly': [],
            'special': [],
          };
        } else {
          state.inboxStream = Stream<List<Map<String, dynamic>>>.value([]);
          state.notificationStream = Stream<List<Map<String, dynamic>>>.value([
            {
              'notificationId': 'visual-1',
              'type': 'friend_accepted',
              'fromName': 'Deniz',
              'message':
                  'Deniz arkadaşlık isteğini kabul etti. Artık birbirinizi maça davet edebilirsiniz.',
              'read': false,
            },
            {
              'notificationId': 'visual-2',
              'type': 'match_invite',
              'fromName': 'LunoUstası',
              'message': 'Arkadaşın seni dostluk maçına davet etti.',
              'read': false,
            },
            {
              'notificationId': 'visual-3',
              'type': 'general',
              'message':
                  'Yeni hedefler seni bekliyor. Günlük görevlerini görevler ekranından inceleyebilirsin.',
              'read': true,
            },
          ]);
        }
      });
      await tester.pump();
    }
    if (details && screen == 'costumes') {
      await tester.tap(find.text('Siyah'));
      await tester.pumpAndSettle();
    }
    if (scroll > 0) {
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(
        scroll.toDouble().clamp(0, scrollable.position.maxScrollExtent),
      );
      await tester.pump();
    }
    await tester.runAsync(() async {
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      for (final image in images) {
        await precacheImage(image.image, key.currentContext!);
      }
      for (final box in tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      )) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.image != null) {
          await precacheImage(decoration.image!.image, key.currentContext!);
        }
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    // Stream-driven rows may appear after the first image collection.
    await tester.runAsync(() async {
      for (final image
          in tester.widgetList<Image>(find.byType(Image)).toList()) {
        await precacheImage(image.image, key.currentContext!);
      }
    });
    await tester.pump();
    if (details &&
        screen == 'game' &&
        const bool.fromEnvironment('CAPTURE_PROMOTION')) {
      showPromotionSheet(
        tester.element(find.byType(Scaffold).first),
        color: PieceColor.white,
        pieceSet: 'luno',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (details &&
        screen == 'game' &&
        !const bool.fromEnvironment('CAPTURE_PROMOTION')) {
      showCardLevelSheet(
        tester.element(find.byType(Scaffold).first),
        kCards.values.firstWhere((c) => c.upgradeable && c.level == 3),
        10,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (screen == 'levels' && details) {
      showMatchConfirmation(
        tester.element(find.byType(Scaffold).first),
        title: 'Teslim ol?',
        message: 'Teslim olursan bu maç yenilgi olarak kaydedilir.',
        confirmLabel: 'ONAYLA',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (screen == 'game' &&
        (const bool.fromEnvironment('CAPTURE_MENU') ||
            const bool.fromEnvironment('CAPTURE_RESTART'))) {
      await tester.tap(
        find.byTooltip(
          const bool.fromEnvironment('CAPTURE_RESTART')
              ? 'Yeniden başlat'
              : 'Maç menüsü',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (screen == 'game' && const bool.fromEnvironment('CAPTURE_TIME')) {
      showGameTimeControlPicker(tester.element(find.byType(GameScreen)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (screen == 'chest') {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
        for (final box in tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        )) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration && decoration.image != null) {
            await precacheImage(decoration.image!.image, key.currentContext!);
          }
        }
      });
      await tester.pump();
    }
    if (details && screen == 'deck-upgrades') {
      final upgrade =
          find
              .byWidgetPredicate((w) => w is TextButton && w.onPressed != null)
              .first;
      await tester.ensureVisible(upgrade);
      await tester.tap(upgrade);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (details && screen == 'deck') {
      await tester.scrollUntilVisible(
        find.text('Dondurma'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Dondurma').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (details && fixture && screen == 'friends') {
      await tester.tap(find.byTooltip('Arkadaşlıktan çıkar').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pump();
    }
    if (details && screen == 'inbox') {
      await tester.tap(find.text('Luno bildirimi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        for (final box in tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        )) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration && decoration.image != null) {
            await precacheImage(decoration.image!.image, key.currentContext!);
          }
        }
      });
    }
    // Repaint cached layers after asynchronous image decoding before capture.
    for (final render in tester.allRenderObjects) {
      render.markNeedsPaint();
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('qa').create(recursive: true);
      await File(
        'qa/current-flutter-$screen${fixture ? '-fixture' : ''}${screen == 'ranking' && rankingMode != 'trophies' ? '-$rankingMode' : ''}${socialState.isNotEmpty ? '-$socialState' : ''}${details ? '-details' : ''}${cardActions ? '-actions' : ''}${scroll > 0 ? '-scroll-$scroll' : ''}-2026-09-08.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
