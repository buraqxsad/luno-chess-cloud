import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

void rejectWithoutMutation(
  AuthoritativeBattleState state,
  PieceColor side,
  BattleAction action,
) {
  final frozen = jsonEncode(state.toJson());
  expect(BattleRulesCore.isLegalAction(state.view(side), action), isFalse);
  expect(
    () => BattleRulesCore.transition(state.view(side), action),
    throwsStateError,
  );
  expect(() => DeckManager.apply(state, action), throwsStateError);
  expect(jsonEncode(state.toJson()), frozen);
}

void main() {
  for (final card in CardId.values) {
    for (final side in PieceColor.values) {
      test('${card.wire}/${side.name}: malformed target alone is rejected', () {
        final state = cardScenario(card, side);
        final valid = BattleRulesCore.legalActions(state.view(side))
            .whereType<PlayCardAction>()
            .firstWhere((action) => action.card == card);
        expect(BattleRulesCore.isLegalAction(state.view(side), valid), isTrue);
        final badTargets = <Object?>[
          false,
          <Object?>[],
          <String, Object?>{'square': valid.target},
          if (valid.target is int) ...[
            '${valid.target}',
            (valid.target as int).toDouble() + .5,
            null,
            -1,
            64,
          ] else if (valid.target is String) ...[
            0,
            null,
            '',
            'missing-effect-or-card',
          ] else ...[
            0,
            '',
          ],
        ];
        for (final target in badTargets) {
          rejectWithoutMutation(
            state,
            side,
            PlayCardAction(card, target: target, sacrifice: valid.sacrifice),
          );
          final wire = valid.toJson()..['target'] = target;
          rejectWithoutMutation(state, side, BattleAction.fromJson(wire));
        }
        if (valid.target is int) {
          final whole = (valid.target as int).toDouble();
          rejectWithoutMutation(
            state,
            side,
            PlayCardAction(card, target: whole, sacrifice: valid.sacrifice),
          );
          final before = state.toJson();
          final wire = valid.toJson()..['target'] = whole;
          final decoded = BattleAction.fromJson(
            jsonDecode(jsonEncode(wire)) as Map,
          );
          expect((decoded as PlayCardAction).target, valid.target);
          expect(
            DeckManager.apply(state, decoded).toJson(),
            DeckManager.apply(state, valid).toJson(),
          );
          expect(state.toJson(), before);
        }
      });

      test('${card.wire}/${side.name}: sacrifice alone is validated', () {
        final state = cardScenario(card, side);
        final valid = BattleRulesCore.legalActions(state.view(side))
            .whereType<PlayCardAction>()
            .firstWhere((action) => action.card == card);
        final unavailable = CardId.values.firstWhere(
          (candidate) => !state.hidden.hands[side]!.contains(candidate),
        );
        final wrongSacrifices = <CardId?>[
          card,
          unavailable,
          if (valid.sacrifice != null) null,
        ];
        for (final sacrifice in wrongSacrifices) {
          rejectWithoutMutation(
            state,
            side,
            PlayCardAction(card, target: valid.target, sacrifice: sacrifice),
          );
        }
      });

      test(
        '${card.wire}/${side.name}: discard preserves a usable chess turn',
        () {
          final state = cardScenario(card, side);
          final after = DeckManager.apply(state, DiscardAction(card));
          expect(after.rules.phase, BattlePhase.chess);
          expect(after.rules.ply, state.rules.ply);
          expect(after.rules.fen, state.rules.fen);
          expect(after.rules.mana, state.rules.mana);
          final moves =
              BattleRulesCore.legalActions(
                after.view(side),
              ).whereType<ChessMoveAction>().toList();
          expect(moves, isNotEmpty);
          for (final move in moves) {
            final moved = DeckManager.apply(after, move);
            expect(moved.rules.ply, state.rules.ply + 1);
            expect(moved.rules.board.turn, side.opposite);
            expect(moved.rules.discarded[side], contains(card));
          }
        },
      );
    }
  }
}
