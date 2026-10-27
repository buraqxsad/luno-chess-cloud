import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/deck_screen.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/guide_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/resource_amount.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const before = bool.fromEnvironment('V203_BEFORE');

final visualSurfaces = <String, Widget Function()>{
  'home': () => const HomeScreen(),
  'shop': () => const ShopScreen(),
  'pass': () => const PassScreen(),
  'profile': () => const ProfileScreen(),
  'collection': () => const CollectionScreen(),
  'browser': () => const CollectionBrowserScreen(),
  'cards':
      () =>
          before
              ? const CardCollectionScreen()
              : const BattleDeckScreen(catalogOnly: true),
  'costumes': () => const PieceCostumeScreen(),
  'emojis': () => const EmojiCollectionScreen(),
  'deck':
      () =>
          before
              ? const DeckScreen()
              : BattleDeckScreen(
                loadOverride:
                    () async => {
                      'ok': true,
                      'protocolVersion': 'LUNO_BATTLE_V1',
                      'available': true,
                      'deck': starterDeck.map((card) => card.wire).toList(),
                      'entitlements': [
                        ...starterDeck.map((card) => card.wire),
                        'fog',
                      ],
                    },
              ),
  'season': () => const SeasonScreen(),
  'missions': () => const MissionsScreen(),
  'ranking': () => const RankingScreen(),
  'friends': () => const FriendsScreen(),
  'inbox': () => const InboxScreen(),
  'settings': () => const SettingsScreen(),
  'edit-profile': () => const EditProfileScreen(),
  'guide': () => const GuideScreen(),
  'tutorial': () => const TutorialScreen(),
  for (var i = 1; i < 10; i++)
    'tutorial-$i': () {
      GameStore.instance.tutorialStep = i;
      return const TutorialScreen(onboarding: true);
    },
  'premium': () => const LunoPremiumScreen(),
  'achievements': () => const AchievementsScreen(),
  'history': () => const MatchHistoryScreen(),
  'arenas': () => const ArenasScreen(),
  'levels': () => const LevelRewardsScreen(),
  'promotion':
      () => const ArenaPromotionScreen(
        arenaName: 'Piyon Vadisi',
        arenaArt: 'assets/native_art/arena-02-piyon-v24.webp',
      ),
  'season-reward':
      () => const SeasonEndRewardScreen(tier: 'HÜKÜMDAR', gold: 500, gems: 20),
  'public-profile':
      () => const PlayerDetailsScreen(
        name: 'Deniz',
        trophies: 1450,
        wins: 84,
        games: 120,
        country: 'TR',
        bio: 'Her hamlede yeni bir fikir.',
      ),
  'play': () => const PlayModeScreen(),
  'difficulty': () => const DifficultyScreen(),
  'friendly': () => const FriendlyOnlineScreen(),
  'queue': () => const OnlineHubScreen(),
  'dm':
      () => const DirectMessageScreen(
        targetUid: 'visual-fixture',
        targetName: 'Deniz',
      ),
  'victory':
      () => ResultScreen(
        result: MatchResult.whiteWins,
        level: aiLevels.first,
        reward: 50,
      ),
  'defeat':
      () => ResultScreen(
        result: MatchResult.blackWins,
        level: aiLevels.first,
        reward: 0,
      ),
  'draw':
      () => ResultScreen(
        result: MatchResult.draw,
        level: aiLevels.first,
        reward: 0,
      ),
  'daily-reward':
      () => Scaffold(
        body: ShopRewardDialog(
          title: 'GÜNLÜK ÖDÜL',
          art: LunoAssets.shopDaily,
          message: '+500 altın hesabına eklendi.',
          reward: ResourceAmount.coin(500, iconSize: 40, fontSize: 20),
        ),
      ),
  'chest':
      () => const Scaffold(
        body: ChestRevealDialog(
          chestId: 'rare',
          rewards: [
            {'type': 'gold', 'amount': 1500},
            {'type': 'gems', 'amount': 30},
          ],
        ),
      ),
};

Future<void> warmVisualImages(WidgetTester tester, BuildContext context) async {
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
    for (final box
        in tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .toList()) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        await precacheImage(decoration.image!.image, context);
      }
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'Spectral': 'assets/fonts/spectral/spectral-regular-latin.ttf',
          'SpectralTurkish':
              'assets/fonts/spectral/spectral-regular-turkish.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  for (final entry in visualSurfaces.entries) {
    testWidgets('V203 native surface ${entry.key}', (tester) async {
      for (final channel in [
        'xyz.luan/audioplayers.global/events',
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers',
        for (final id in [
          'luno_music',
          'luno_sfx_0',
          'luno_sfx_1',
          'luno_sfx_2',
        ])
          'xyz.luan/audioplayers/events/$id',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (_) async => null,
        );
      }
      SharedPreferences.setMockInitialValues({});
      await LunoSettings.instance.setLanguage(LunoSettings.languageTurkish);
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial()..bio = 'Her hamlede yeni bir fikir.';
      store.loaded = true;
      store.hasChosenUsername = true;
      store.hasCompletedTutorial = true;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = ValueKey('v203-capture');
      // This golden is the offline state, not a timing race against Firebase.
      final offline = LunoOnlineService.forTesting(bootstrap: () async {});
      addTearDown(offline.dispose);
      if (!before && (entry.key == 'play' || entry.key == 'missions')) {
        await offline.start();
      }
      if (entry.key == 'missions') {
        tester.binding.imageCache.clear();
        tester.binding.imageCache.clearLiveImages();
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('tr'),
            supportedLocales: LunoLocalizations.supportedLocales,
            localizationsDelegates: const [
              LunoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: LunoTheme.dark,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                  ),
                  child: child!,
                ),
            home:
                entry.key == 'achievements'
                    ? AchievementsScreen(online: offline, playerStore: store)
                    : entry.key == 'missions'
                    ? MissionsScreen(online: offline, playerStore: store)
                    : !before && entry.key == 'play'
                    ? PlayModeScreen(online: offline, playerStore: store)
                    : entry.value(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      if (entry.key == 'missions') {
        await tester.pump();
        expect(find.text('Görevler sunucudan yüklenemedi.'), findsOneWidget);
        expect(find.widgetWithText(LunoButton, 'TEKRAR DENE'), findsOneWidget);
      }
      await warmVisualImages(tester, tester.element(find.byKey(capture)));
      if (entry.key == 'missions') {
        // The async error state can introduce a button after the first scan.
        await warmVisualImages(tester, tester.element(find.byKey(capture)));
      }
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(capture)), const Size(390, 844));
      if (!before) {
        switch (entry.key) {
          case 'collection':
            expect(find.text('24 savaş yeteneği'), findsOneWidget);
            expect(find.text('135 koleksiyon puanı'), findsNothing);
          case 'profile':
            expect(find.text('Koleksiyon'), findsNothing);
          case 'ranking':
            expect(find.text('KOLEKSİYON'), findsNothing);
          case 'shop':
            expect(find.text('Havuzdan rastgele bir kart.'), findsNothing);
            expect(
              find.text(
                'Altın, tahta çerçevesi ve ifade parçaları. Rekabetçi kart vermez.',
              ),
              findsOneWidget,
            );
          case 'deck':
            expect(find.text('Ortalama mana: 1.9'), findsOneWidget);
          case 'play':
            expect(
              find.byKey(const ValueKey('battle-deck-retry')),
              findsOneWidget,
            );
            expect(find.text('Deste yükleniyor...'), findsNothing);
        }
      }
      if (!before && entry.key.startsWith('tutorial')) {
        final step =
            entry.key == 'tutorial' ? 0 : int.parse(entry.key.split('-').last);
        expect(find.text('REHBER  ${step + 1}/10'), findsOneWidget);
        final next = tester.widget<LunoButton>(find.byType(LunoButton));
        expect(
          next.onPressed == null,
          BattleLessonStage.requiresInteraction(step),
        );
      }
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile(
          '../qa/v203-${before ? 'before' : 'after'}/${entry.key}.png',
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
