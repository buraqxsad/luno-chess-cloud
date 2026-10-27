import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'rc_surface_word_fit_test.dart' show expectWholeWord;
import 'v216_progression_visual_test.dart' show captureProgression;

void expectArenaWords(WidgetTester tester, Finder scope) {
  final texts = find.descendant(of: scope, matching: find.byType(RichText));
  expect(texts, findsWidgets);
  for (final element in texts.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final label = paragraph.text.toPlainText();
    final widths = label.split(RegExp(r'\s+')).map((word) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: paragraph.text.style),
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    });
    expect(
      paragraph.size.width + .1,
      greaterThanOrEqualTo(widths.reduce(math.max)),
      reason: 'Whole arena word does not fit: $label',
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: label);
  }
}

void main() {
  setupPracticeTestAssets();
  var account = 0;
  setUp(() async {
    await GameStore.instance.bindAccount('v216-arena-${++account}');
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true;
  });

  for (final language in ['tr', 'en']) {
    final l = LunoLocalizations(Locale(language));
    for (final scale in [1.0, 1.5]) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(430, 932),
        const Size(768, 1024),
      ]) {
        void viewport(WidgetTester tester) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }

        final suffix =
            '$language-${size.width.toInt()}-text${(scale * 100).toInt()}';
        testWidgets('V216 arena integration whole hero words $suffix', (
          tester,
        ) async {
          viewport(tester);
          await tester.pumpWidget(
            shell(
              const ArenasScreen(),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          for (final arena in kArenaCatalog) {
            GameStore.instance.applyServerState({
              'trophies': arena.minTrophies,
              'arenaIdx': arena.index,
            });
            await tester.pumpAndSettle();
            final title =
                '${l.translate(arena.displayName)} \u00b7 ARENA ${arena.index + 1}';
            expect(find.text(title), findsOneWidget);
            expectWholeWord(tester, title);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(title),
            );
            expect(paragraph.textScaler.scale(18), closeTo(18 * scale, .01));
            expect(
              tester
                  .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator),
                  )
                  .value,
              arena.index == 8 ? 1 : 0,
            );
            noOverflow(tester);
          }
          await tester.pumpWidget(const SizedBox());
        });

        testWidgets('V216 arena integration whole row words $suffix', (
          tester,
        ) async {
          viewport(tester);
          GameStore.instance.data.trophies = 450;
          await tester.pumpWidget(
            shell(
              const ArenasScreen(),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          for (final arena in kArenaCatalog) {
            final row = find.byKey(ValueKey('arena-row-${arena.index}'));
            await tester.scrollUntilVisible(
              row,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expectArenaWords(tester, row);
            expect(
              find.descendant(
                of: row,
                matching: find.text(l.translate(arena.name)),
              ),
              findsOneWidget,
            );
            if (language == 'en' && arena.name == 'Luno Kraliyeti') {
              expect(find.descendant(of: row,
                matching: find.text('Luno Royalty')), findsOneWidget);
              expect(find.text('Luno Kraliyeti'), findsNothing);
            }
            noOverflow(tester);
          }
          await tester.pumpWidget(const SizedBox());
        });

        testWidgets('V216 arena integration actual frames $suffix', (
          tester,
        ) async {
          viewport(tester);
          await tester.pumpWidget(
            shell(
              const ArenasScreen(),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          for (final (name, trophies, arena) in [
            ('arenas', 0, 0),
            ('arenas-sovereign', 450, 2),
            ('arenas-progress', 620, 3),
            ('arenas-max', 4000, 8),
          ]) {
            GameStore.instance.applyServerState({
              'trophies': trophies,
              'arenaIdx': arena,
            });
            await tester.pumpAndSettle();
            noOverflow(tester);
            expect(
              tester
                  .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator),
                  )
                  .value,
              closeTo(arenaProgress(trophies, arena), .0001),
              reason: '$name-$suffix must capture the current rank progress',
            );
            await captureProgression(tester, '$name-$suffix');
          }
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('arena-row-8')),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          noOverflow(tester);
          await captureProgression(tester, 'arenas-road-$suffix');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }

    testWidgets('V216 arena integration canonical live rank and rights $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = GameStore.instance;
      store.data.ownedPieceSets.add('viking');
      final cards = {...store.data.ownedCards};
      final sets = {...store.data.ownedPieceSets};
      final emotes = {...store.data.ownedEmojis};
      final deck = [...store.data.deck];
      await tester.pumpWidget(
        shell(
          const ArenasScreen(),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      for (final (trophies, arena, remaining) in [
        (450, 2, 150),
        (620, 3, 380),
        (4000, 8, 0),
        (100, 1, 200),
      ]) {
        store.applyServerState({
          'battleV1Rank': {
            'protocolVersion': 'LUNO_BATTLE_V1',
            'uid': store.accountUid,
            'trophies': trophies,
            'arenaIdx': arena,
          },
        });
        await tester.pumpAndSettle();
        expect(store.data.trophies, 0);
        final title =
            '${l.translate(arenaForIndex(arena).displayName)} \u00b7 ARENA ${arena + 1}';
        expect(find.text(title), findsOneWidget);
        expectWholeWord(tester, title);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(arenaProgress(trophies, arena), .0001),
        );
        if (arena == 8) {
          expect(
            find.text(
              language == 'en'
                  ? 'Highest arena reached'
                  : 'En y\u00fcksek arenadas\u0131n',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              language == 'en' ? 'trophies to' : 'kupa kald\u0131',
            ),
            findsNothing,
          );
        } else {
          expect(
            find.textContaining(
              language == 'en'
                  ? '$remaining trophies to'
                  : '$remaining kupa kald\u0131',
            ),
            findsOneWidget,
          );
        }
        final libraryFinder = find.byKey(const ValueKey('arena-card-library'));
        await tester.scrollUntilVisible(libraryFinder, 120,
            scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(libraryFinder);
        await tester.pumpAndSettle();
        expect(libraryFinder.hitTestable(), findsOneWidget);
        expect(
          find.text(
            language == 'en'
                ? 'Cards unlock separately in every arena.'
                : 'Kartlar her arenada, ayr\u0131 ko\u015fullarla a\u00e7\u0131l\u0131r.',
          ),
          findsOneWidget,
        );
        final library = tester.widget<LunoButton>(
          find.byKey(const ValueKey('arena-card-library')),
        );
        expect(library.onPressed, isNotNull);
        expect(
          library.label,
          language == 'en' ? 'CARD PROGRESS' : 'KART \u0130LERLEMES\u0130',
        );
        expect(store.data.ownedCards, cards);
        expect(store.data.ownedPieceSets, sets);
        expect(store.data.ownedEmojis, emotes);
        expect(store.data.deck, deck);
        noOverflow(tester);
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
