import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

void main() {
  for (final side in PieceColor.values) {
    for (final card in CardId.values) {
      final definition = cardDefinitions[card]!;
      if (!{
        CardTargetType.ownPiece,
        CardTargetType.opponentPiece,
        CardTargetType.opponentSlider,
        CardTargetType.ownPawn,
        CardTargetType.emptySquare,
        CardTargetType.zone,
        CardTargetType.ownRook,
        CardTargetType.ownKnight,
        CardTargetType.ownBishopRook,
      }.contains(definition.target)) {
        continue;
      }
      test(
        '${side.name}/${card.wire}: equivalent JSON integer spellings agree',
        () {
          final state = cardScenario(card, side);
          final action = BattleRulesCore.legalActions(state.view(side))
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          final target = action.target as int;
          final expected = DeckManager.apply(state, action).toJson();
          for (final number in ['$target', '$target.0', '${target}e0']) {
            final parsed = BattleAction.fromJson(
              jsonDecode(
                    '{"type":"play","card":"${card.wire}","target":$number}',
                  )
                  as Map,
            );
            expect((parsed as PlayCardAction).target, isA<int>());
            expect(DeckManager.apply(state, parsed).toJson(), expected);
          }
          expect(
            () => DeckManager.apply(
              state,
              PlayCardAction(card, target: target.toDouble()),
            ),
            throwsStateError,
            reason:
                'Typed engine calls stay strict; only the JSON boundary normalizes.',
          );
          final snapshot = state.toJson();
          for (final bad in <Object>[
            '$target',
            [target],
            {'square': target},
            target + .5,
            true,
            -1,
            64,
          ]) {
            final parsed = BattleAction.fromJson({
              'type': 'play',
              'card': card.wire,
              'target': bad,
            });
            expect(() => DeckManager.apply(state, parsed), throwsStateError);
            expect(state.toJson(), snapshot);
          }
        },
      );
    }
  }
}
