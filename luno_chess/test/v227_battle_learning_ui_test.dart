import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show noOverflow;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart' show renderBattle, captureKey, closeCapture;
import 'helpers/battle_v1_response.dart';
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  setUp(() => GameStore.instance.loaded = true);

  for (final card in [
    CardId.radar,
    CardId.echo,
    CardId.cardBlock,
    CardId.shadowContract,
  ]) {
    testWidgets(
      'normal battle discard-only ${card.wire} opens no target sheet',
      (tester) async {
        var state = battleFixture(hand: [card]);
        final draft = RuleDraft(state.rules)..mana[PieceColor.white] = 0;
        state = AuthoritativeBattleState(draft.freeze(), state.hidden);
        final sent = <BattleAction>[];
        final controller = await renderBattle(
          tester,
          state: state,
          theme: LunoTheme.dark,
          requestOverride: (path, body) async {
            if (path == '/submitBattleV1Action') {
              final action = BattleAction.fromJson(body['intent'] as Map);
              sent.add(action);
              state = DeckManager.apply(state, action);
            }
            return v1Response(state: state, version: sent.length);
          },
        );
        final tile = find.byKey(ValueKey('hand-${card.wire}'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.byType(OpponentArsenalSheet), findsNothing);
        expect(find.byType(BattleSheet), findsNothing);
        final discard = find.byKey(const ValueKey('discard-card'));
        await tester.ensureVisible(discard);
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(discard).onPressed, isNotNull);
        expect(
          tester
              .widget<BattleCommand>(find.byKey(const ValueKey('play-card')))
              .onPressed,
          isNull,
        );
        await tester.tap(discard);
        await tester.pumpAndSettle();
        expect(sent.single, isA<DiscardAction>());
        expect(controller.view!.rules.phase, BattlePhase.chess);
        expect(controller.view!.rules.mana[PieceColor.white], 0);
        expect(
          BattleRulesCore.legalActions(
            controller.view!,
          ).whereType<ChessMoveAction>(),
          isNotEmpty,
        );
        noOverflow(tester);
        await closeCapture(tester);
      },
    );
  }

  for (final language in ['tr', 'en']) {
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 568), 1.0),
      (const Size(360, 640), 1.6),
      (const Size(768, 1024), 1.0),
      (const Size(844, 390), 1.0),
    ]) {
      testWidgets('normal battle learning cues $language $size text $scale', (
        tester,
      ) async {
        await renderBattle(
          tester,
          size: size,
          language: language,
          textScale: scale,
          theme: LunoTheme.dark,
        );
        noOverflow(tester);
        expect(find.byType(BattleBoard), findsOneWidget);
        expect(find.byKey(const ValueKey('open-own-deck')), findsOneWidget);
        expect(find.byKey(const ValueKey('open-emotes')), findsOneWidget);
        for (final tile in find.byType(BattleCardTile).evaluate()) {
          await tester.ensureVisible(find.byWidget(tile.widget));
          await tester.pump();
          expect(find.byWidget(tile.widget).hitTestable(), findsOneWidget);
        }
        await capture(
          tester,
          'battle-$language-${size.width.toInt()}-${size.height.toInt()}',
          repaintKey: captureKey,
          outputDirectory: 'qa/v227/screens',
        );
        await closeCapture(tester);
      });
    }
  }
}
