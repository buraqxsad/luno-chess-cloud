import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

void main() {
  for (final side in PieceColor.values) {
    for (final card in [...movementCards, CardId.shelter, CardId.purify]) {
      test(
        '${card.wire}/${side.name}: accepted effect follows its actual piece, not an abandoned square',
        () {
          final initial = cardScenario(card, side);
          final play = BattleRulesCore.legalActions(
            initial.view(side),
          ).whereType<PlayCardAction>().firstWhere(
            (action) =>
                action.card == card &&
                (card != CardId.shelter ||
                    action.target == (side.isWhite ? 9 : 54)),
          );
          final cast = DeckManager.apply(initial, play);
          final cue = BattleSpellCue.fromViews(
            card,
            side,
            initial.view(side),
            cast.view(side),
          );
          expect(cue.boundPieceIds, hasLength(1));
          final id = cue.boundPieceIds.single;
          final from = cast.rules.pieceIds.indexOf(id);
          final moves =
              BattleRulesCore.legalActions(cast.view(side))
                  .whereType<ChessMoveAction>()
                  .where(
                    (move) => cast.rules.pieceIds[square(move.uci, 0)] == id,
                  )
                  .toList();
          expect(moves, isNotEmpty);
          for (final move in moves) {
            final after = DeckManager.apply(cast, move);
            expect(cue.following(after.rules).squares, [
              after.rules.pieceIds.indexOf(id),
            ]);
            expect(cue.following(after.rules).squares, isNot(contains(from)));
            expect(cue.squares, [
              from,
            ], reason: 'An accepted cue is immutable.');
          }
        },
      );
    }
    for (final card in [
      CardId.mine,
      CardId.lockedSquare,
      CardId.fog,
      CardId.boardSeal,
      CardId.breakSeal,
      CardId.watchVow,
    ]) {
      test(
        '${card.wire}/${side.name}: square effects remain anchored to squares',
        () {
          final initial = cardScenario(card, side);
          final play = BattleRulesCore.legalActions(initial.view(side))
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          final cast = DeckManager.apply(initial, play);
          final cue = BattleSpellCue.fromViews(
            card,
            side,
            initial.view(side),
            cast.view(side),
          );
          expect(cue.boundPieceIds, isEmpty);
          expect(cue.squares, isNotEmpty);
          final after = DeckManager.apply(
            cast,
            BattleRulesCore.legalActions(
              cast.view(side),
            ).whereType<ChessMoveAction>().first,
          );
          expect(cue.following(after.rules).squares, cue.squares);
        },
      );
    }

    testWidgets(
      'shelter/${side.name}: combined screen build paints the effect at the moved piece',
      (tester) async {
        var state = cardScenario(CardId.shelter, side);
        final initial = state;
        final tracker =
            BattlePresentationTracker()..observe(state.view(side), 0);
        Widget board() => MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 320,
              child: BattleBoard(
                view: state.view(side),
                acceptedFrames: tracker.frames,
                onTap: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpWidget(board());
        await tester.pump();
        final play = BattleRulesCore.legalActions(
          state.view(side),
        ).whereType<PlayCardAction>().firstWhere(
          (action) =>
              action.card == CardId.shelter &&
              action.target == (side.isWhite ? 9 : 54),
        );
        state = DeckManager.apply(state, play);
        final id = initial.rules.pieceIds[play.target as int]!;
        tracker.observe(state.view(side), 1);
        final move = BattleRulesCore.legalActions(
          state.view(side),
        ).whereType<ChessMoveAction>().firstWhere(
          (move) => state.rules.pieceIds[square(move.uci, 0)] == id,
        );
        state = DeckManager.apply(state, move);
        tracker.observe(state.view(side), 2);
        await tester.pumpWidget(board());
        await tester.pump(const Duration(milliseconds: 800));
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BattleSpellPainter>()
            .where((painter) => painter.cue.card == CardId.shelter);
        expect(painters, isNotEmpty);
        expect(painters.first.cue.squares, [state.rules.pieceIds.indexOf(id)]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

int square(String uci, int offset) =>
    uci.codeUnitAt(offset) - 97 + (uci.codeUnitAt(offset + 1) - 49) * 8;
