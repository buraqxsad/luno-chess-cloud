import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/deck_screen.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/screens/guide_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ScreenFactory = Widget Function();

void main() {
  const viewports = <Size>[
    Size(320, 568),
    Size(360, 740),
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(480, 960),
    Size(600, 1024),
    Size(800, 1280),
  ];
  const textScales = <double>[1.0, 1.15, 1.3];
  const locales = <Locale>[Locale('tr'), Locale('en')];

  final screens = <String, ScreenFactory>{
    'ana menü': () => const HomeScreen(),
    'mağaza': () => const ShopScreen(),
    'Luno Pass': () => const PassScreen(),
    'profil': () => const ProfileScreen(),
    'koleksiyon': () => const CollectionScreen(),
    'koleksiyon tarayıcı': () => const CollectionBrowserScreen(),
    'kart koleksiyonu': () => const BattleDeckScreen(catalogOnly: true),
    'taş kostümleri': () => const PieceCostumeScreen(),
    'emoji koleksiyonu': () => const EmojiCollectionScreen(),
    'deste': () => const BattleDeckScreen(),
    'legacy deste uyumluluğu': () => const DeckScreen(),
    'sezon': () => const SeasonScreen(),
    'görevler': () => const MissionsScreen(),
    'sıralama': () => const RankingScreen(),
    'arkadaşlar': () => const FriendsScreen(),
    'mesaj kutusu': () => const InboxScreen(),
    'ayarlar': () => const SettingsScreen(),
    'profil düzenle': () => const EditProfileScreen(),
    'rehber': () => const GuideScreen(),
    'tutorial': () => const TutorialScreen(),
    'premium': () => const LunoPremiumScreen(),
    'başarımlar': () => const AchievementsScreen(),
    'maç geçmişi': () => const MatchHistoryScreen(),
    'arenalar': () => const ArenasScreen(),
    'seviye ödülleri': () => const LevelRewardsScreen(),
    'arena terfisi':
        () => const ArenaPromotionScreen(
          arenaName: 'Piyon Vadisi',
          arenaArt: 'assets/native_art/arena-02-piyon-v24.webp',
        ),
    'sezon sonu ödülü':
        () =>
            const SeasonEndRewardScreen(tier: 'HÜKÜMDAR', gold: 500, gems: 20),
    'oyuncu profili':
        () => const PlayerDetailsScreen(
          name: 'LunoPlayer',
          trophies: 640,
          wins: 12,
          games: 20,
          country: 'TR',
        ),
    'savaş modu': () => const PlayModeScreen(),
    'AI seçimi': () => const DifficultyScreen(),
    'arkadaşınla oyna': () => const FriendlyOnlineScreen(),
    'online merkez': () => const OnlineHubScreen(),
    'AI maçı': () => GameScreen(level: aiLevels.first),
    'yüz yüze maç': () => GameScreen(level: aiLevels.first, local: true),
    'online maç':
        () => const OnlineMatchScreen(
          matchId: 'smoke-test',
          initialView: {
            'viewerColor': 'W',
            'turn': 'W',
            'phase': 'card',
            'board': <Map<String, Object?>>[],
            'player': {'name': 'Sen', 'trophies': 100},
            'opponent': {'name': 'Rakip', 'trophies': 120},
          },
        ),
    'zafer sonucu':
        () => ResultScreen(
          result: MatchResult.whiteWins,
          level: aiLevels.first,
          reward: 50,
        ),
    'yenilgi sonucu':
        () => ResultScreen(
          result: MatchResult.blackWins,
          level: aiLevels.first,
          reward: 0,
        ),
    'berabere sonucu':
        () => ResultScreen(
          result: MatchResult.draw,
          level: aiLevels.first,
          reward: 0,
        ),
  };

  for (final entry in screens.entries) {
    for (final viewport in viewports) {
      for (final textScale in textScales) {
        for (final locale in locales) {
          testWidgets('${entry.key} ${locale.languageCode} '
              '${viewport.width.toInt()}x${viewport.height.toInt()} '
              'metin ${textScale.toStringAsFixed(2)} taşma ve çökme kontrolü', (
            tester,
          ) async {
            SharedPreferences.setMockInitialValues({});
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1;
            tester.binding.platformDispatcher.textScaleFactorTestValue =
                textScale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
            );

            await tester.pumpWidget(
              MaterialApp(
                locale: locale,
                supportedLocales: LunoLocalizations.supportedLocales,
                localizationsDelegates: const [
                  LunoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: LunoTheme.darkFor(
                  locale.languageCode == 'en' ? 'English' : 'Türkçe',
                ),
                home: entry.value(),
              ),
            );
            await tester.pump(const Duration(milliseconds: 120));

            final exception = tester.takeException();
            if (exception != null) {
              if (exception is FlutterError) {
                debugPrint(
                  '${entry.key} ${locale.languageCode} '
                  '${viewport.width}x${viewport.height} '
                  'scale=$textScale: ${exception.diagnostics.join('\n')}',
                );
                for (final element
                    in find
                        .byWidgetPredicate((w) => w is Row || w is Column)
                        .evaluate()) {
                  final renderObject = element.renderObject;
                  if (renderObject is RenderFlex) {
                    final dump = renderObject.toStringDeep(
                      minLevel: DiagnosticLevel.info,
                    );
                    if (dump.contains('OVERFLOWING')) debugPrint(dump);
                  }
                }
              } else {
                debugPrint(
                  '${entry.key} ${locale.languageCode} '
                  '${viewport.width}x${viewport.height} '
                  'scale=$textScale: $exception',
                );
              }
            }
            expect(exception, isNull);
          });
        }
      }
    }
  }
}
