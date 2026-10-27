import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

String _snapshot(AuthoritativeBattleState state) =>
    jsonEncode(canonicalObject(state.toJson()));

void _inventory(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final hand = state.hidden.hands[side]!;
    final deck = state.hidden.decks[side]!;
    final cards = [
      ...hand,
      ...deck,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    expect(cards.length, 10);
    expect(cards.toSet(), state.rules.arsenals[side]!.toSet());
    expect(cards.toSet().length, 10);
    expect(hand.length, state.rules.handCounts[side]);
    expect(deck.length, state.rules.deckCounts[side]);
    expect(hand.length, lessThanOrEqualTo(4));
    expect(state.rules.mana[side], inInclusiveRange(0, 6));
    final knowledge = state.hidden.knowledge[side]!;
    expect(
      deck.take(knowledge.knownUpcomingCards.length),
      knowledge.knownUpcomingCards,
    );
    expect(deck.take(knowledge.pendingCards.length), knowledge.pendingCards);
    BattleRulesCore.legalActions(state.view(side));
  }
  for (var square = 0; square < 64; square++) {
    expect(
      state.rules.pieceIds[square] == null,
      state.rules.board.squares[square] == null,
    );
  }
  final ids = state.rules.pieceIds.whereType<String>().toList();
  expect(ids.toSet().length, ids.length);
  expect(
    AuthoritativeBattleState.fromJson(state.toJson()).toJson(),
    state.toJson(),
  );
}

AuthoritativeBattleState _modified(
  CardId card,
  PieceColor side,
  String modifier,
) {
  final root = cardScenario(card, side);
  final draft = RuleDraft(root.rules);
  if (modifier == 'discount' || modifier == 'combined') {
    draft.modifiers.add(
      PendingModifier(
        id: 'discount-v224',
        type: ModifierType.discount,
        owner: side,
        responseSide: side,
        targetCard: null,
        ownTurn: draft.ownTurns[side]!,
      ),
    );
  }
  if (modifier == 'sabotage' || modifier == 'combined') {
    draft.modifiers.add(
      PendingModifier(
        id: 'sabotage-v224',
        type: ModifierType.manaSabotage,
        owner: side.opposite,
        responseSide: side,
        targetCard: card,
        ownTurn: draft.ownTurns[side]!,
      ),
    );
  }
  return AuthoritativeBattleState(draft.freeze(), root.hidden);
}

List<CardId> _deck(List<CardId> first) =>
    [
      ...first,
      ...CardId.values.where((card) => !first.contains(card)),
    ].take(10).toList();

String _relativeMove(String uci, PieceColor caster) =>
    caster.isWhite
        ? uci
        : '${uci[0]}${9 - int.parse(uci[1])}${uci[2]}${9 - int.parse(uci[3])}${uci.substring(4)}';

AuthoritativeBattleState _newOpening(
  PieceColor caster,
  List<CardId> own,
  List<CardId> opposing,
) {
  final start = Board.start();
  return DeckManager.newBattle(
    white: caster.isWhite ? _deck(own) : _deck(opposing),
    black: caster.isWhite ? _deck(opposing) : _deck(own),
    board: Board(
      squares: start.squares,
      turn: caster,
      castling: start.castling,
      enPassant: null,
      halfmoveClock: 0,
      fullmoveNumber: 1,
    ),
  );
}

AuthoritativeBattleState _advance(
  AuthoritativeBattleState state,
  PieceColor caster,
  List<Object> actions,
) {
  for (final action in actions) {
    state = DeckManager.apply(
      state,
      action is String
          ? ChessMoveAction(_relativeMove(action, caster))
          : action as BattleAction,
    );
    _inventory(state);
  }
  return state;
}

void main() {
  var casts = 0, resolutions = 0, chessContinuations = 0;
  for (final side in PieceColor.values) {
    for (final card in CardId.values) {
      for (final modifier in ['none', 'discount', 'sabotage', 'combined']) {
        test('${side.name}/${card.wire}/$modifier: all admitted branches', () {
          final root = _modified(card, side, modifier);
          final unchanged = _snapshot(root);
          final base = cardDefinitions[card]!.cost;
          final expectedCost = math.max(
            1,
            base +
                (modifier == 'sabotage' || modifier == 'combined' ? 1 : 0) -
                (modifier == 'discount' || modifier == 'combined' ? 2 : 0),
          );
          expect(
            BattleRulesCore.effectiveCost(root.rules, side, card),
            expectedCost,
          );
          final plays =
              BattleRulesCore.legalActions(root.view(side))
                  .whereType<PlayCardAction>()
                  .where((action) => action.card == card)
                  .toList();
          expect(plays, isNotEmpty);
          for (final action in plays) {
            final cast = DeckManager.apply(root, action);
            casts++;
            expect(cast.rules.mana[side], 6 - expectedCost);
            expect(cast.rules.board.turn, side);
            expect(cast.rules.fen, root.rules.fen);
            expect(cast.rules.ply, root.rules.ply);
            expect(cast.rules.used[side], [...root.rules.used[side]!, card]);
            expect(cast.hidden.hands[side], isNot(contains(card)));
            expect(
              cast.hidden.hands[side]!.length,
              root.hidden.hands[side]!.length -
                  1 -
                  (action.sacrifice == null ? 0 : 1),
            );
            if (action.sacrifice != null) {
              expect(
                cast.hidden.hands[side],
                isNot(contains(action.sacrifice)),
              );
              expect(cast.rules.discarded[side], contains(action.sacrifice));
            }
            _inventory(cast);
            expect(() => DeckManager.apply(cast, action), throwsStateError);
            final completions =
                cast.rules.phase == BattlePhase.pending
                    ? BattleRulesCore.legalActions(
                      cast.view(side),
                    ).whereType<ResolveAction>().map((resolution) {
                      final reloaded = AuthoritativeBattleState.fromJson(
                        jsonDecode(_snapshot(cast)) as Map,
                      );
                      final complete = DeckManager.apply(reloaded, resolution);
                      resolutions++;
                      expect(complete.rules.mana[side], cast.rules.mana[side]);
                      expect(complete.rules.pending, isNull);
                      expect(
                        complete.hidden.knowledge[side]!.pendingCards,
                        isEmpty,
                      );
                      expect(
                        () => DeckManager.apply(complete, resolution),
                        throwsStateError,
                      );
                      return complete;
                    }).toList()
                    : [cast];
            expect(completions, isNotEmpty);
            for (final complete in completions) {
              _inventory(complete);
              expect(complete.rules.phase, BattlePhase.chess);
              final moves =
                  BattleRulesCore.legalActions(
                    complete.view(side),
                  ).whereType<ChessMoveAction>().toList();
              expect(
                moves,
                isNotEmpty,
                reason: 'Accepted cast cannot strand its chess phase.',
              );
              expect(
                BattleRulesCore.legalActions(
                  complete.view(side),
                ).whereType<PlayCardAction>(),
                isEmpty,
              );
              final indices = {0, moves.length ~/ 2, moves.length - 1};
              for (final index in indices) {
                final moved = DeckManager.apply(complete, moves[index]);
                chessContinuations++;
                expect(moved.rules.board.turn, side.opposite);
                expect(moved.rules.ply, root.rules.ply + 1);
                expect(MoveGen.inCheck(moved.rules.board, side), isFalse);
                expect(moved.rules.special, isNull);
                _inventory(moved);
                if (moved.rules.terminal == null) {
                  expect(
                    BattleRulesCore.legalActions(moved.view(side.opposite)),
                    isNotEmpty,
                  );
                }
              }
            }
            expect(_snapshot(root), unchanged);
          }
        });
      }
      test('${side.name}/${card.wire}: blocked card remains discardable', () {
        final root = cardScenario(card, side);
        final draft = RuleDraft(root.rules)
          ..modifiers.add(
            PendingModifier(
              id: 'block-v224',
              type: ModifierType.cardBlock,
              owner: side.opposite,
              responseSide: side,
              targetCard: card,
              ownTurn: root.rules.ownTurns[side]!,
            ),
          );
        final state = AuthoritativeBattleState(draft.freeze(), root.hidden);
        final legal = BattleRulesCore.legalActions(state.view(side));
        expect(
          legal.whereType<PlayCardAction>().where((a) => a.card == card),
          isEmpty,
        );
        expect(
          legal.whereType<DiscardAction>().map((a) => a.card),
          contains(card),
        );
        final discarded = DeckManager.apply(state, DiscardAction(card));
        expect(discarded.rules.mana[side], 6);
        expect(discarded.rules.phase, BattlePhase.chess);
        expect(discarded.rules.modifiers, isEmpty);
        expect(BattleRulesCore.legalActions(discarded.view(side)), isNotEmpty);
        _inventory(discarded);
      });
    }
    for (final primary in [CardId.fateExchange, CardId.shadowContract]) {
      for (final sacrifice in CardId.values.where((card) => card != primary)) {
        for (final modifier in [
          CardId.cardBlock,
          CardId.manaSabotage,
          CardId.echo,
        ]) {
          test(
            '${side.name}/${primary.wire}: ${modifier.wire} on sacrificed ${sacrifice.wire}',
            () {
              final spare = CardId.values.firstWhere(
                (card) => card != primary && card != sacrifice,
              );
              var state = _newOpening(
                side,
                [primary, sacrifice, spare],
                [CardId.radar, modifier],
              );
              state = _advance(state, side, [
                'e2e4',
                'e7e5',
                const PassAction(),
                'g1f3',
                PlayCardAction(CardId.radar, target: sacrifice.wire),
                'g8f6',
                const PassAction(),
                'b1c3',
                const PassAction(),
                'b8c6',
                const PassAction(),
                'f1c4',
                PlayCardAction(modifier, target: sacrifice.wire),
                'f8c5',
              ]);
              expect(state.rules.board.turn, side);
              expect(state.rules.ownTurns[side], 5);
              expect(state.rules.mana[side], 5);
              final observation =
                  state
                      .hidden
                      .knowledge[side.opposite]!
                      .radarObservations
                      .single;
              expect(observation.inHand, isTrue);
              expect(observation.stale, isFalse);
              final enemyMana = state.rules.mana[side.opposite];
              final played = DeckManager.apply(
                state,
                PlayCardAction(primary, sacrifice: sacrifice),
              );
              expect(
                played.rules.mana[side],
                primary == CardId.fateExchange ? 2 : 4,
              );
              expect(
                played.rules.mana[side.opposite],
                enemyMana,
                reason: 'Sacrifice is not a named-card play for Echo.',
              );
              expect(played.rules.used[side], [primary]);
              expect(played.rules.discarded[side], [sacrifice]);
              expect(
                played
                    .hidden
                    .knowledge[side.opposite]!
                    .radarObservations
                    .single
                    .stale,
                isTrue,
                reason:
                    'Public sacrifice invalidates an IN_HAND observation immediately.',
              );
              _inventory(played);
              var complete = played;
              if (primary == CardId.fateExchange) {
                expect(
                  played.rules.modifiers.any((m) => m.owner == side.opposite),
                  isTrue,
                );
                final resolution =
                    BattleRulesCore.legalActions(
                      played.view(side),
                    ).whereType<ResolveAction>().last;
                complete = DeckManager.apply(played, resolution);
              }
              expect(
                complete.rules.modifiers.where((m) => m.owner == side.opposite),
                isEmpty,
              );
              expect(complete.rules.phase, BattlePhase.chess);
              state = _advance(complete, side, ['g2g3']);
              expect(state.rules.board.turn, side.opposite);
              expect(state.rules.terminal, isNull);
            },
          );
        }
      }
    }
    for (final sabotage in [false, true]) {
      test(
        '${side.name}: actual Contract -> ${sabotage ? 'Sabotage' : 'pass'} -> Freeze price',
        () {
          var state = _newOpening(
            side,
            [CardId.shadowContract, CardId.freeze, CardId.radar],
            [CardId.manaSabotage, CardId.prophecy, CardId.radar],
          );
          state = _advance(state, side, [
            'e2e4',
            'e7e5',
            const PlayCardAction(
              CardId.shadowContract,
              sacrifice: CardId.radar,
            ),
            'g1f3',
            if (sabotage)
              PlayCardAction(CardId.manaSabotage, target: CardId.freeze.wire)
            else
              const PassAction(),
            'g8f6',
          ]);
          expect(state.rules.mana[side], 2);
          expect(
            BattleRulesCore.effectiveCost(state.rules, side, CardId.freeze),
            sabotage ? 3 : 2,
          );
          final plays =
              BattleRulesCore.legalActions(state.view(side))
                  .whereType<PlayCardAction>()
                  .where((a) => a.card == CardId.freeze)
                  .toList();
          if (sabotage) {
            expect(plays, isEmpty);
            expect(
              () => DeckManager.apply(
                state,
                PlayCardAction(CardId.freeze, target: side.isWhite ? 48 : 8),
              ),
              throwsStateError,
            );
            state = _advance(state, side, [const PassAction(), 'b1c3']);
          } else {
            expect(plays, isNotEmpty);
            state = _advance(state, side, [plays.first, 'b1c3']);
            expect(state.rules.mana[side], 0);
          }
          expect(state.rules.board.turn, side.opposite);
          expect(state.rules.terminal, isNull);
          expect(
            state.rules.modifiers.where((m) => m.responseSide == side),
            isEmpty,
          );
        },
      );
    }
  }
  tearDownAll(() {
    stdout.writeln(
      jsonEncode({
        'v224Branches': {
          'casts': casts,
          'privateResolutions': resolutions,
          'chessContinuations': chessContinuations,
        },
      }),
    );
  });
}
