import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

Set<int> effectSquares(PlayerView view, Object? target) => {
  for (final effect in view.rules.boardEffects)
    if (effect.id == target) ...effect.squares,
  for (final effect in view.rules.pieceEffects)
    if (effect.id == target)
      for (var square = 0; square < 64; square++)
        if (view.rules.pieceIds[square] == effect.pieceId) square,
};

void main() {
  for (final card in CardId.values) {
    for (final side in PieceColor.values) {
      test(
        '${card.wire}/${side.name}: all 64 square taps respect card targets',
        () {
          final view = cardScenario(card, side).view(side);
          final actions = BattleRulesCore.legalActions(view);
          final options =
              actions
                  .whereType<PlayCardAction>()
                  .where((action) => action.card == card)
                  .toList();
          expect(options, isNotEmpty, reason: 'Do not silently skip a card.');
          final targetType = cardDefinitions[card]!.target;
          final boardIgnored = {
            CardTargetType.none,
            CardTargetType.opponentCard,
            CardTargetType.sacrifice,
          }.contains(targetType);
          final highlighted = {
            ...options.map((action) => action.target).whereType<int>(),
            for (final action in options) ...effectSquares(view, action.target),
          };
          final selected = BattleInteraction()..select(card, actions);
          expect(selected.targets(view, actions), highlighted);
          for (var square = 0; square < 64; square++) {
            final selection = BattleInteraction()..select(card, actions);
            final previous = selection.play;
            final returned = selection.tap(square, view, actions);
            expect(selection.card, card);
            if (boardIgnored) {
              expect(returned, isEmpty);
              expect(selection.play?.key, previous?.key);
              expect(selection.preview(), isEmpty);
              continue;
            }
            final eligible =
                options
                    .where(
                      (action) =>
                          action.target == square ||
                          effectSquares(view, action.target).contains(square),
                    )
                    .toList();
            if (eligible.length == 1) {
              final action = eligible.single;
              expect(returned, isEmpty);
              expect(selection.play?.key, action.key);
              expect(selection.invalidTarget, isFalse);
              expect(
                selection.preview(),
                action.target is int
                    ? targetType == CardTargetType.zone
                        ? boardZone(square).toSet()
                        : {square}
                    : effectSquares(view, action.target),
              );
            } else if (eligible.isEmpty) {
              expect(returned, isEmpty);
              expect(selection.play, isNull);
              expect(selection.preview(), isEmpty);
              expect(selection.invalidTarget, isTrue);
            } else {
              expect(
                returned.map((action) => action.key).toSet(),
                eligible.map((action) => action.key).toSet(),
              );
              expect(selection.play, isNull);
              expect(selection.invalidTarget, isFalse);
            }
          }

          if (movementCards.contains(card)) {
            for (final source
                in options.map((action) => action.target).cast<int>()) {
              for (final move in BattleRulesCore.specialMoves(
                view.rules,
                card,
                source,
                side,
              )) {
                final selection = BattleInteraction()..select(card, actions);
                expect(selection.tap(source, view, actions), isEmpty);
                expect(selection.tap(move.to, view, actions), isEmpty);
                expect(selection.piece, source);
                expect(selection.specialDestination?.uci, move.uci);
                expect(selection.preview(), {source, move.to});
                expect(selection.invalidTarget, isFalse);
              }
            }
          }

          final firstBoardTarget =
              options
                  .where(
                    (action) =>
                        action.target is int ||
                        effectSquares(view, action.target).isNotEmpty,
                  )
                  .firstOrNull;
          if (firstBoardTarget != null && !movementCards.contains(card)) {
            final selection = BattleInteraction()..select(card, actions);
            final initialSquare =
                firstBoardTarget.target is int
                    ? firstBoardTarget.target as int
                    : effectSquares(view, firstBoardTarget.target).first;
            selection.tap(initialSquare, view, actions);
            expect(selection.play, isNotNull);
            final invalid =
                List.generate(
                  64,
                  (index) => index,
                ).where((square) => !highlighted.contains(square)).firstOrNull;
            if (invalid != null) {
              selection.tap(invalid, view, actions);
              expect(
                selection.play,
                isNull,
                reason: 'An invalid new tap must not retain the prior target.',
              );
              expect(selection.preview(), isEmpty);
            }
          }
        },
      );
    }
  }
}
