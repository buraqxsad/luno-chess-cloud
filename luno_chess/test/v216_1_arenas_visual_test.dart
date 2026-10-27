import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'helpers/v216_1_arena_before.dart';
import 'rc_screen_capture_test.dart' show capture;
import 'v216_arena_integration_test.dart' show expectArenaWords;

void main() {
  setupPracticeTestAssets();
  final phase = Platform.environment['LUNO_V216_1_PHASE'] ?? 'after';
  assert(phase == 'before' || phase == 'after');
  final before = phase == 'before';
  var account = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GameStore.instance.bindAccount('v216-1-arena-visual-${++account}');
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true;
  });

  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 2.0]) {
        final suffix =
            '$language-${size.width.toInt()}-text${(scale * 100).toInt()}';
        testWidgets('V216.1 arena actual before-after frames $suffix', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          LunoSettings.instance.language = language;
          final store = GameStore.instance;
          final original = jsonDecode(jsonEncode(store.data.toJson()));
          await tester.pumpWidget(
            shell(
              before ? const V216ArenaBeforeScreen() : const ArenasScreen(),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          final directory = 'qa/v216_1/$phase/arenas';
          for (final (name, trophies) in [
            ('arenas-start', 0),
            ('arenas-current', 450),
            ('arenas-progress', 620),
            ('arenas-max', 4000),
          ]) {
            final arena = arenaIndexForTrophies(trophies);
            store.applyServerState({
              'battleV1Rank': {
                'protocolVersion': 'LUNO_BATTLE_V1',
                'uid': store.accountUid,
                'trophies': trophies,
                'arenaIdx': arena,
              },
            });
            // Every head is captured at scroll zero, including after tall 2x content.
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            noOverflow(tester);
            expect(
              tester
                  .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator),
                  )
                  .value,
              closeTo(arenaProgress(trophies, arena), .0001),
            );
            await capture(tester, '$name-$suffix', outputDirectory: directory);
            if (!before && (name == 'arenas-current' || name == 'arenas-max')) {
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('arena-real-benefits')),
                220,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              expectArenaWords(
                tester,
                find.byKey(const ValueKey('arena-real-benefits')),
              );
              await capture(
                tester,
                '$name-benefits-$suffix',
                outputDirectory: directory,
              );
            }
          }
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          for (final index in [2, 8]) {
            final row = find.byKey(ValueKey('arena-row-$index'));
            await tester.scrollUntilVisible(
              row,
              220,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            noOverflow(tester);
            if (!before) expectArenaWords(tester, row);
            await capture(
              tester,
              'arenas-road-${index + 1}-$suffix',
              outputDirectory: directory,
            );
          }
          expect(
            store.data.toJson(),
            original,
            reason:
                'Rendering previews must not mutate legacy state, ownership or economy',
          );
          await tester.pumpWidget(const SizedBox());
          for (final index in [3, 8]) {
            final arena = kArenaCatalog[index];
            await tester.pumpWidget(
              shell(
                before
                    ? V216ArenaPromotionBeforeScreen(
                      arenaName: arena.name,
                      arenaArt: LunoAssets.arena(index),
                    )
                    : ArenaPromotionScreen(
                      arenaName: arena.name,
                      arenaArt: LunoAssets.arena(index),
                    ),
                language: language,
                scale: scale,
                reduced: true,
              ),
            );
            await tester.pumpAndSettle();
            noOverflow(tester);
            await capture(
              tester,
              'arena-promotion-${index + 1}-$suffix',
              outputDirectory: directory,
            );
            if (!before) {
              final finish = find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              );
              await tester.ensureVisible(finish);
              await tester.pumpAndSettle();
              noOverflow(tester);
              await capture(
                tester,
                'arena-promotion-${index + 1}-tail-$suffix',
                outputDirectory: directory,
              );
            }
            expect(store.data.toJson(), original);
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  }
}
