import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart'
    show renderBattle, visualTap, closeCapture, editedFixture;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    testWidgets('narrow battle uses the vertical fallback: $language', (
      tester,
    ) async {
      await renderBattle(
        tester,
        size: const Size(240, 568),
        language: language,
        theme: LunoTheme.darkFor(language),
      );
      expect(find.byKey(const ValueKey('battle-side-scroll')), findsNothing);
      expect(tester.getSize(find.byType(BattleBoard)).width, 224);
      await visualTap(tester, 'hand-shelter');
      await visualTap(tester, 'square-12');
      expect(tester.takeException(), isNull);
      await closeCapture(tester);
    });
    for (final textScale in [1.0, 1.1]) {
      for (final count in [3, 4]) {
        testWidgets(
          'compact opening shows board, mana and $count cards: $language scale $textScale',
          (tester) async {
            await renderBattle(
              tester,
              state: editedFixture(
                (_) {},
                hand: [
                  CardId.shelter,
                  CardId.chain,
                  CardId.lockedSquare,
                  if (count == 4) CardId.slow,
                ],
              ),
              size: const Size(320, 568),
              language: language,
              textScale: textScale,
              theme: LunoTheme.darkFor(language),
              longNames: true,
            );
            const safe = Rect.fromLTWH(0, 24, 320, 520);
            final board = tester.getRect(find.byType(BattleBoard));
            final own = tester.getRect(
              find.byWidgetPredicate(
                (widget) => widget is BattlePlayerHeader && widget.own,
              ),
            );
            final hand = tester.getRect(find.byType(BattleHand));
            expect(board.bottom, lessThanOrEqualTo(hand.top));
            expect(own.bottom, lessThanOrEqualTo(hand.top));
            for (final rect in [board, own, hand]) {
              expect(safe.contains(rect.topLeft), isTrue);
              expect(
                safe.contains(rect.bottomRight - const Offset(.01, .01)),
                isTrue,
              );
            }
            expect(board.width, greaterThanOrEqualTo(224));
            expect(hand.height, greaterThanOrEqualTo(116));
            final card = find.byKey(const ValueKey('hand-shelter'));
            expect(card.hitTestable(), findsOneWidget);
            await tester.tap(card);
            await tester.pumpAndSettle();
            expect(tester.widget<BattleCardTile>(card).selected, isTrue);
            expect(tester.takeException(), isNull);
            await closeCapture(tester);
          },
        );
      }
    }
    for (final textScale in [1.3, 1.5]) {
      for (final count in [3, 4]) {
        testWidgets(
          'enlarged compact battle keeps readable cells and $count cards: $language scale $textScale',
          (tester) async {
            await renderBattle(
              tester,
              size: const Size(320, 568),
              language: language,
              textScale: textScale,
              theme: LunoTheme.darkFor(language),
              state: editedFixture((_) {}, hand: [
                CardId.shelter,
                CardId.chain,
                CardId.lockedSquare,
                if (count == 4) CardId.slow,
              ]),
            );
            final board = tester.getRect(find.byType(BattleBoard));
            final hand = tester.getRect(find.byType(BattleHand));
            expect(board.width / 8, greaterThanOrEqualTo(24));
            if (count == 4) {
              expect(find.text(language == 'en'
                  ? 'Hand full · Make space'
                  : 'El dolu · Yer aç'), findsOneWidget);
            }
            expect(board.bottom, lessThanOrEqualTo(hand.top));
            expect(hand.top, greaterThanOrEqualTo(0));
            expect(hand.bottom, lessThanOrEqualTo(544));
            for (final id in [
              CardId.shelter,
              CardId.chain,
              CardId.lockedSquare,
              if (count == 4) CardId.slow,
            ]) {
              expect(find.byKey(ValueKey('hand-${id.wire}')).hitTestable(),
                  findsOneWidget);
            }
            expect(find.byKey(const ValueKey('pass-card')).hitTestable(),
                findsOneWidget);
            expect(find.byKey(const ValueKey('open-menu')).hitTestable(),
                findsOneWidget);
            expect(tester.takeException(), isNull);
            await closeCapture(tester);
          },
        );
      }
    }
    testWidgets(
      'compact taller battle uses available height for card art: $language',
      (tester) async {
        await renderBattle(
          tester,
          size: const Size(320, 640),
          language: language,
          theme: LunoTheme.darkFor(language),
          state: editedFixture((_) {}, hand: const [
            CardId.shadowContract,
            CardId.fateExchange,
            CardId.pawnDeviation,
            CardId.boardSeal,
          ]),
        );
        expect(tester.getSize(find.byType(BattleBoard)).width,
            greaterThanOrEqualTo(224));
        expect(tester.getSize(find.byType(BattleHand)).height, 152);
        for (final art in find.descendant(
          of: find.byType(BattleHand),
          matching: find.byType(BattleCardArt),
        ).evaluate()) {
          expect(tester.getSize(find.byWidget(art.widget)).height,
              greaterThanOrEqualTo(44));
        }
        expect(find.byKey(const ValueKey('pass-card')).hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeCapture(tester);
      },
    );
    testWidgets(
      'compact battle keeps readable squares and reachable hand: $language',
      (tester) async {
        await renderBattle(
          tester,
          size: const Size(320, 568),
          language: language,
          theme: LunoTheme.darkFor(language),
        );
        final board = tester.getSize(find.byType(BattleBoard));
        expect(
          board.width,
          greaterThanOrEqualTo(224),
          reason: 'Eight ranks need at least 28 logical pixels per square',
        );
        await visualTap(tester, 'hand-shelter');
        await visualTap(tester, 'square-12');
        expect(tester.takeException(), isNull);
        await closeCapture(tester);
      },
    );
  }
}
