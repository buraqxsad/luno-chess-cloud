import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

void assertEffect(
  CardId card,
  PlayCardAction action,
  AuthoritativeBattleState before,
  AuthoritativeBattleState after,
  PieceColor side,
) {
  final rules = after.rules;
  if (movementCards.contains(card)) {
    expect(rules.special?.card, card);
    expect(rules.special?.from, action.target);
    final moves =
        BattleRulesCore.legalActions(
          after.view(side),
        ).whereType<ChessMoveAction>();
    expect(moves, isNotEmpty);
    expect(moves.every((m) => rules.special!.moves.contains(m.uci)), isTrue);
    return;
  }
  switch (card) {
    case CardId.radar:
      final result = after.hidden.knowledge[side]!.radarObservations.last;
      expect(result.queriedCardId.wire, action.target);
      expect(
        result.inHand,
        before.hidden.hands[side.opposite]!.contains(result.queriedCardId),
      );
      expect(after.hidden.knowledge[side.opposite]!.radarObservations, isEmpty);
    case CardId.prophecy:
    case CardId.fateExchange:
      expect(rules.phase, BattlePhase.pending);
      expect(rules.pending?.card, card);
      expect(
        after.hidden.knowledge[side]!.pendingCards,
        before.hidden.decks[side]!.take(card == CardId.prophecy ? 2 : 3),
      );
    case CardId.shelter:
    case CardId.chain:
    case CardId.slow:
    case CardId.freeze:
      final effect = rules.pieceEffects.last;
      expect(effect.pieceId, before.rules.pieceIds[action.target as int]);
      expect(effect.owner, side);
      expect(effect.responseSide, side.opposite);
      expect(effect.type, switch (card) {
        CardId.shelter => PieceEffectType.shelter,
        CardId.chain => PieceEffectType.chain,
        CardId.slow => PieceEffectType.slow,
        _ => PieceEffectType.freeze,
      });
      expect(
        effect.duration,
        card == CardId.shelter ? EffectDuration.card : EffectDuration.move,
      );
    case CardId.purify:
      expect(rules.pieceEffects.map((e) => e.id), ['e10']);
    case CardId.breakSeal:
      expect(rules.boardEffects, isEmpty);
    case CardId.mine:
    case CardId.lockedSquare:
    case CardId.fog:
    case CardId.boardSeal:
      final effect = rules.boardEffects.last;
      expect(effect.owner, side);
      expect(
        effect.squares,
        card == CardId.fog || card == CardId.boardSeal
            ? boardZone(action.target as int)
            : [action.target],
      );
      expect(effect.type, switch (card) {
        CardId.mine => BoardEffectType.mine,
        CardId.lockedSquare => BoardEffectType.lockedSquare,
        CardId.fog => BoardEffectType.fog,
        _ => BoardEffectType.boardSeal,
      });
    case CardId.manaSabotage:
    case CardId.cardBlock:
    case CardId.echo:
    case CardId.shadowContract:
      final effect = rules.modifiers.last;
      expect(effect.owner, side);
      expect(
        effect.responseSide,
        card == CardId.shadowContract ? side : side.opposite,
      );
      expect(effect.targetCard?.wire, action.target);
      expect(effect.ownTurn, before.rules.ownTurns[effect.responseSide]! + 1);
      expect(effect.type, switch (card) {
        CardId.manaSabotage => ModifierType.manaSabotage,
        CardId.cardBlock => ModifierType.cardBlock,
        CardId.echo => ModifierType.echo,
        _ => ModifierType.discount,
      });
    case CardId.huntVow:
    case CardId.watchVow:
      final vow = rules.vows.single;
      expect(vow.owner, side);
      expect(vow.remainingMoves, card == CardId.huntVow ? 2 : 1);
      expect(vow.square, card == CardId.watchVow ? action.target : null);
      expect(
        vow.pieceId,
        card == CardId.huntVow
            ? before.rules.pieceIds[action.target as int]
            : null,
      );
    default:
      fail('Uncovered card ${card.wire}');
  }
}

void main() {
  for (final card in CardId.values) {
    for (final side in PieceColor.values) {
      test(
        '${card.wire}/${side.name}: every generated target applies its actual effect once',
        () {
          final state = cardScenario(card, side);
          final frozen = jsonEncode(state.toJson());
          final actions =
              BattleRulesCore.legalActions(state.view(side))
                  .whereType<PlayCardAction>()
                  .where((a) => a.card == card)
                  .toList();
          expect(
            actions,
            isNotEmpty,
            reason: 'Scenario must exercise this card, not skip it.',
          );
          for (final action in actions) {
            final next = DeckManager.apply(state, action);
            expect(
              jsonEncode(state.toJson()),
              frozen,
              reason: 'Input must stay immutable.',
            );
            expect(next.rules.mana[side], 6 - cardDefinitions[card]!.cost);
            expect(next.rules.fen, state.rules.fen);
            expect(next.rules.ply, state.rules.ply);
            expect(next.rules.used[side], [card]);
            expect(next.hidden.hands[side], isNot(contains(card)));
            expect(
              next.rules.handCounts[side],
              next.hidden.hands[side]!.length,
            );
            assertEffect(card, action, state, next, side);
            expect(
              () => DeckManager.apply(next, action),
              throwsStateError,
              reason: 'A used card must not execute twice.',
            );
            if (next.rules.phase == BattlePhase.pending) {
              for (final choice
                  in BattleRulesCore.legalActions(
                    next.view(side),
                  ).whereType<ResolveAction>()) {
                final resolved = DeckManager.apply(next, choice);
                expect(resolved.rules.phase, BattlePhase.chess);
                expect(resolved.rules.pending, isNull);
                expect(
                  resolved.rules.handCounts[side],
                  resolved.hidden.hands[side]!.length,
                );
                expect(
                  resolved.rules.deckCounts[side],
                  resolved.hidden.decks[side]!.length,
                );
                expect(
                  BattleRulesCore.legalActions(
                    resolved.view(side),
                  ).whereType<PlayCardAction>(),
                  isEmpty,
                );
              }
            }
            if (movementCards.contains(card)) {
              for (final move
                  in BattleRulesCore.legalActions(
                    next.view(side),
                  ).whereType<ChessMoveAction>()) {
                final moved = DeckManager.apply(next, move);
                expect(moved.rules.ply, state.rules.ply + 1);
                expect(moved.rules.special, isNull);
                expect(moved.rules.board.turn, side.opposite);
              }
            }
          }
        },
      );

      test(
        '${card.wire}/${side.name}: insufficient mana, first turn and malformed target never spend',
        () {
          final state = cardScenario(
            card,
            side,
            mana: cardDefinitions[card]!.cost - 1,
          );
          final frozen = jsonEncode(state.toJson());
          expect(
            BattleRulesCore.legalActions(
              state.view(side),
            ).whereType<PlayCardAction>().where((a) => a.card == card),
            isEmpty,
          );
          expect(
            () => DeckManager.apply(state, PlayCardAction(card, target: -1)),
            throwsStateError,
          );
          expect(jsonEncode(state.toJson()), frozen);
          final first =
              RuleDraft(state.rules)
                ..phase = BattlePhase.chess
                ..ownTurns[side] = 1;
          final firstState = AuthoritativeBattleState(
            first.freeze(),
            state.hidden,
          );
          expect(
            BattleRulesCore.legalActions(
              firstState.view(side),
            ).whereType<PlayCardAction>(),
            isEmpty,
          );
          final legalState = cardScenario(card, side);
          final invalid = PlayCardAction(
            card,
            target: 'not-a-square-or-card',
            sacrifice: card,
          );
          expect(
            BattleRulesCore.isLegalAction(legalState.view(side), invalid),
            isFalse,
          );
          expect(
            () => DeckManager.apply(legalState, invalid),
            throwsStateError,
          );
        },
      );
    }
  }
  test(
    'a flagged local match cannot accept even an otherwise legal chess action',
    () async {
      final session = BattleV1LocalSession(hotseat: true, minutes: 0);
      addTearDown(session.dispose);
      expect(session.terminal?.reason, 'timeout');
      final version = session.version;
      final fen = session.view.rules.fen;
      expect(await session.submit(const ChessMoveAction('e2e4')), isFalse);
      expect(session.version, version);
      expect(session.view.rules.fen, fen);
    },
  );
}
