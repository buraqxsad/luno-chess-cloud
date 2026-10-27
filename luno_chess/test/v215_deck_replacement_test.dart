import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_deck_account_test.dart' show app, response, card;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show noOverflow;

void main() {
  setupPracticeTestAssets();
  setUpAll(() async => GameStore.instance.load());
  for (final language in ['tr', 'en']) {
    testWidgets(
      'full deck explicitly replaces, saves only confirmed ten $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<String>? saved;
        await tester.pumpWidget(
          app(
            BattleDeckScreen(
              loadOverride: () async => response(),
              saveOverride: (deck) async {
                saved = List.of(deck);
                return {'ok': true, 'deck': deck};
              },
            ),
            language,
            textScale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          card(CardId.fog),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        final open = tester.widget<BattleCatalogCard>(card(CardId.fog)).onTap!;
        open();
        open();
        await tester.pumpAndSettle();
        final headline =
            language == 'tr'
                ? 'HANGİ KART DEĞİŞSİN?'
                : 'WHICH CARD TO REPLACE?';
        expect(find.text(headline), findsOneWidget);
        expect(saved, isNull);
        noOverflow(tester);
        final sheetGrid = find.byType(BattleSelectedDeckGrid).last;
        final grid = tester.widget<BattleSelectedDeckGrid>(sheetGrid);
        expect(grid.cards, starterDeck);
        grid.onTap!(CardId.purify);
        grid.onTap!(CardId.radar);
        await tester.pumpAndSettle();
        expect(find.text(headline), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('selected-deck-grid')),
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        final active = tester.widget<BattleSelectedDeckGrid>(
          find.byType(BattleSelectedDeckGrid),
        );
        expect(active.cards, hasLength(10));
        expect(active.cards.toSet(), hasLength(10));
        expect(active.cards, contains(CardId.fog));
        expect(active.cards, contains(CardId.radar));
        expect(active.cards, isNot(contains(CardId.purify)));
        expect(saved, isNull);
        await tester.scrollUntilVisible(
          find.text(language == 'tr' ? 'DESTENİ KAYDET' : 'SAVE DECK'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final save = tester
            .widgetList<LunoButton>(find.byType(LunoButton))
            .singleWhere((b) => b.icon == Icons.save_rounded);
        expect(save.onPressed, isNotNull);
        save.onPressed!();
        await tester.pumpAndSettle();
        expect(saved, active.cards.map((c) => c.wire).toList());
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'cancel leaves deck unchanged and locked card never opens replacement',
    (tester) async {
      await tester.pumpWidget(
        app(BattleDeckScreen(loadOverride: () async => response()), 'en'),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        card(CardId.fog),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      tester.widget<BattleCatalogCard>(card(CardId.fog)).onTap!();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('selected-deck-grid')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
            .cards,
        starterDeck,
      );
      await tester.scrollUntilVisible(
        card(CardId.mine),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      tester.widget<BattleCatalogCard>(card(CardId.mine)).onTap!();
      await tester.pumpAndSettle();
      expect(find.text('WHICH CARD TO REPLACE?'), findsNothing);
      expect(
        find.byKey(const ValueKey('card-unlock-condition')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('selected-deck-grid')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
            .cards,
        starterDeck,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
