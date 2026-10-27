import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

void main() {
  for (final card in [CardId.purify, CardId.breakSeal]) {
    for (final side in PieceColor.values) {
      test(
        '${card.wire}/${side.name}: ambiguous effect ID is never a removal target',
        () {
          final initial = cardScenario(card, side);
          final draft = RuleDraft(initial.rules);
          if (card == CardId.purify) {
            final ours = side.isWhite ? 9 : 54;
            final theirs = side.isWhite ? 35 : 28;
            draft.pieceEffects.addAll([
              ActivePieceEffect(
                id: 'collision',
                type: PieceEffectType.freeze,
                owner: side.opposite,
                pieceId: draft.pieceIds[ours]!,
                responseSide: side,
                duration: EffectDuration.move,
              ),
              ActivePieceEffect(
                id: 'collision',
                type: PieceEffectType.shelter,
                owner: side,
                pieceId: draft.pieceIds[ours]!,
                responseSide: side.opposite,
                duration: EffectDuration.card,
              ),
              ActivePieceEffect(
                id: 'collision',
                type: PieceEffectType.chain,
                owner: side,
                pieceId: draft.pieceIds[theirs]!,
                responseSide: side.opposite,
                duration: EffectDuration.move,
              ),
            ]);
          } else {
            draft.boardEffects.addAll([
              BoardEffectInstance(
                id: 'collision',
                type: BoardEffectType.mine,
                owner: side.opposite,
                squares: [18],
                responseSide: side,
                duration: EffectDuration.persistent,
              ),
              BoardEffectInstance(
                id: 'collision',
                type: BoardEffectType.lockedSquare,
                owner: side.opposite,
                squares: [19],
                responseSide: side,
                duration: EffectDuration.move,
              ),
              BoardEffectInstance(
                id: 'collision',
                type: BoardEffectType.mine,
                owner: side,
                squares: [20],
                responseSide: side.opposite,
                duration: EffectDuration.persistent,
              ),
            ]);
          }
          final state = AuthoritativeBattleState.fromJson(
            AuthoritativeBattleState(draft.freeze(), initial.hidden).toJson(),
          );
          final frozen = jsonEncode(state.toJson());
          final action = PlayCardAction(card, target: 'collision');
          expect(
            BattleRulesCore.cardTargets(state.view(side), card),
            isNot(contains('collision')),
          );
          expect(
            BattleRulesCore.isLegalAction(state.view(side), action),
            isFalse,
          );
          expect(() => DeckManager.apply(state, action), throwsStateError);
          expect(jsonEncode(state.toJson()), frozen);
          expect(
            BattleRulesCore.legalActions(
              state.view(side),
            ).whereType<PassAction>(),
            hasLength(1),
          );
          expect(
            BattleRulesCore.isLegalAction(
              state.view(side),
              DiscardAction(card),
            ),
            isTrue,
          );
          expect(
            BattleRulesCore.isLegalAction(
              state.view(side),
              PlayCardAction(card, target: 'e9'),
            ),
            isTrue,
            reason:
                'Only ambiguous identities are excluded, not valid single effects.',
          );
        },
      );
    }
  }
}
