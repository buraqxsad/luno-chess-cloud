import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/arena_progression_preview.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/widgets/arena_progression_benefits.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'rc_surface_word_fit_test.dart' show expectWholeWord;
import 'v216_arena_integration_test.dart' show expectArenaWords;

class _ArenaRouteObserver extends NavigatorObserver {
  Route<dynamic>? last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    last = route;
  }
}

void main() {
  setupPracticeTestAssets();
  var account = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GameStore.instance.bindAccount('v216-1-arena-${++account}');
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true;
  });

  test(
    'nine canonical arena thresholds and reward previews remain read-only',
    () {
      expect(kArenaCatalog.map((a) => a.minTrophies), [
        0,
        100,
        300,
        600,
        1000,
        1500,
        2200,
        3000,
        4000,
      ]);
      for (final arena in kArenaCatalog) {
        expect(arenaPathPreview(arena.index).trophies, arena.minTrophies);
        expect(arenaIndexForTrophies(arena.minTrophies), arena.index);
        if (arena.index > 0) {
          expect(arenaIndexForTrophies(arena.minTrophies - 1), arena.index - 1);
        }
      }
      expect(kArenaAchievementPreviews.map((a) => a.arenaNumber), [
        3,
        5,
        7,
        8,
        9,
      ]);
      expect(arenaAchievementPreview(0), isNull);
      expect(arenaAchievementPreview(2)!.gold, 500);
      expect(arenaAchievementPreview(8)!.gems, 75);
      expect(kArenaPathPreviews.last.trophies, 5000);
    },
  );

  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'V216.1 arena live goals benefits rights $language ${size.width} x$scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final store = GameStore.instance;
            store.data
              ..gold = 1234
              ..gems = 56;
            store.data.ownedPieceSets.add('viking');
            final before = jsonDecode(jsonEncode(store.data.toJson()));
            await tester.pumpWidget(
              shell(
                const ArenasScreen(),
                language: language,
                scale: scale,
                reduced: true,
              ),
            );
            final l = LunoLocalizations(Locale(language));
            for (final arena in kArenaCatalog) {
              store.applyServerState({
                'battleV1Rank': {
                  'protocolVersion': 'LUNO_BATTLE_V1',
                  'uid': store.accountUid,
                  'trophies': arena.minTrophies,
                  'arenaIdx': arena.index,
                },
              });
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .jumpTo(0);
              await tester.pumpAndSettle();
              final title =
                  '${l.translate(arena.displayName)} · ARENA ${arena.index + 1}';
              expectWholeWord(tester, title);
              expect(
                tester
                    .widget<LinearProgressIndicator>(
                      find.byType(LinearProgressIndicator),
                    )
                    .value,
                arena.index == 8 ? 1 : 0,
              );
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('arena-real-benefits')),
                220,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectArenaWords(
                tester,
                find.byKey(const ValueKey('arena-real-benefits')),
              );
              for (final key in [
                'arena-season-rewards',
                'arena-achievements',
              ]) {
                expect(
                  tester
                      .widget<TextButton>(find.byKey(ValueKey(key)))
                      .onPressed,
                  isNotNull,
                );
              }
              expect(store.data.toJson(), before);
              noOverflow(tester);
            }
            final library = find.byKey(const ValueKey('arena-card-library'));
            // The last benefits check is below this lazily built list child.
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              library,
              120,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(tester.widget<LunoButton>(library).onPressed, isNotNull);
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            for (final arena in kArenaCatalog) {
              final row = find.byKey(ValueKey('arena-row-${arena.index}'));
              await tester.scrollUntilVisible(
                row,
                220,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectArenaWords(tester, row);
              noOverflow(tester);
            }
            expect(store.data.toJson(), before);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }

    testWidgets(
      'V216.1 promotion translates identities without inventing cards $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l = LunoLocalizations(Locale(language));
        final before = jsonDecode(jsonEncode(GameStore.instance.data.toJson()));
        for (final arena in kArenaCatalog) {
          await tester.pumpWidget(
            shell(
              ArenaPromotionScreen(
                arenaName: arena.name,
                arenaArt: 'assets/native_art/${arena.asset}',
              ),
              language: language,
              scale: 2,
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          expectWholeWord(tester, l.translate(arena.displayName).toUpperCase());
          expect(
            find.text(
              language == 'en' ? 'NEW CARDS UNLOCKED' : 'YENİ KARTLAR AÇILDI',
            ),
            findsNothing,
          );
          expect(find.byType(ArenaProgressionBenefits), findsOneWidget);
          expect(GameStore.instance.data.toJson(), before);
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets('V216.1 arena links use existing server-backed page builders', (
    tester,
  ) async {
    final observer = _ArenaRouteObserver();
    final app = shell(const ArenasScreen(), reduced: true) as MaterialApp;
    await tester.pumpWidget(
      MaterialApp(
        theme: app.theme,
        locale: app.locale,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        builder: app.builder,
        home: app.home,
        navigatorObservers: [observer],
      ),
    );
    await tester.pumpAndSettle();
    for (final (key, type) in [
      ('arena-season-rewards', SeasonScreen),
      ('arena-achievements', AchievementsScreen),
    ]) {
      final button = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(button, 120, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      tester.widget<TextButton>(button).onPressed!();
      // Inspect the actual pushed builder without starting a network lifecycle.
      final route = observer.last! as PageRouteBuilder<dynamic>;
      final page = route.pageBuilder(
        tester.element(button),
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
      );
      expect(page, isA<LunoAccountScope>());
      expect((page as LunoAccountScope).page.runtimeType, type);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      expect(navigator.canPop(), isTrue);
      navigator.pop();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });
}
