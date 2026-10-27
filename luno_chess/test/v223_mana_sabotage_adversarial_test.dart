import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_mana_sabotage_cases.dart';

List<String> _keys(PlayerView view) =>
    BattleRulesCore.legalActions(view).map((action) => action.key).toList();

void _conserved(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final hand = state.hidden.hands[side]!;
    final deck = state.hidden.decks[side]!;
    final partition = [
      ...hand,
      ...deck,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    expect(partition.length, 10);
    expect(partition.toSet().length, 10);
    expect(partition, unorderedEquals(state.rules.arsenals[side]!));
    expect(state.rules.handCounts[side], hand.length);
    expect(state.rules.deckCounts[side], deck.length);
    expect(state.rules.mana[side], inInclusiveRange(0, 6));
  }
}

void _reject(AuthoritativeBattleState state, BattleAction action) {
  final side = state.rules.board.turn;
  final frozen = jsonEncode(state.toJson());
  final legal = _keys(state.view(side));
  expect(BattleRulesCore.isLegalAction(state.view(side), action), isFalse);
  expect(
    () => BattleRulesCore.transition(state.view(side), action),
    throwsStateError,
  );
  expect(() => DeckManager.apply(state, action), throwsStateError);
  expect(
    jsonEncode(state.toJson()),
    frozen,
    reason: 'Reject must preserve hidden and public state.',
  );
  expect(
    _keys(state.view(side)),
    legal,
    reason: 'Reject must not consume the card window.',
  );
  _conserved(state);
}

void _chessContinues(AuthoritativeBattleState state) {
  final side = state.rules.board.turn;
  expect(state.rules.phase, BattlePhase.chess);
  final actions = BattleRulesCore.legalActions(state.view(side));
  expect(
    actions,
    isNotEmpty,
    reason: 'Card closure must not strand this nonterminal board.',
  );
  expect(actions.every((action) => action is ChessMoveAction), isTrue);
  final moved = DeckManager.apply(state, actions.first);
  expect(moved.rules.ply, state.rules.ply + 1);
  expect(moved.rules.board.turn, side.opposite);
  _conserved(moved);
}

PlayCardAction _costAction(CardId card, PieceColor side) => switch (card) {
  CardId.radar => const PlayCardAction(CardId.radar, target: 'radar'),
  CardId.manaSabotage => const PlayCardAction(
    CardId.manaSabotage,
    target: 'radar',
  ),
  CardId.shadowContract => const PlayCardAction(
    CardId.shadowContract,
    sacrifice: CardId.radar,
  ),
  CardId.freeze => PlayCardAction(CardId.freeze, target: side.isWhite ? 48 : 8),
  CardId.boardSeal => const PlayCardAction(CardId.boardSeal, target: 16),
  _ => throw ArgumentError('missing literal cost-case action'),
};

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor side,
  int version,
) {
  final response = v1Response(state: state, side: side, version: version);
  final public = response['view']['public'] as Map;
  final players = public['players'] as Map;
  (players['w'] as Map)['uid'] = side.isWhite ? 'self' : 'other';
  (players['b'] as Map)['uid'] = side.isWhite ? 'other' : 'self';
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  return response;
}

void main() {
  test('V223 Mana Sabotage literal definition and wire contract', () {
    final definition = cardDefinitions[CardId.manaSabotage]!;
    expect(definition.cost, 2);
    expect(definition.rarity, Rarity.rare);
    expect(definition.category, CardCategory.modifier);
    expect(definition.target, CardTargetType.opponentCard);
    expect(CardId.manaSabotage.wire, 'mana_sabotage');
    expect(
      const PlayCardAction(CardId.manaSabotage, target: 'radar').toJson(),
      {'type': 'play', 'card': 'mana_sabotage', 'target': 'radar'},
    );
  });

  for (final side in PieceColor.values) {
    final enemy = side.opposite;
    final label = 'V223 Mana Sabotage ${side.name}';

    for (final position in ManaSabotagePosition.values) {
      test(
        '$label ${position.name}: every public eligible name creates exactly one next-window tax',
        () {
          final state = manaSabotageState(side: side, position: position);
          final original = jsonEncode(state.toJson());
          final targets = BattleRulesCore.cardTargets(
            state.view(side),
            CardId.manaSabotage,
          );
          expect(
            targets,
            unorderedEquals(
              state.rules.arsenals[enemy]!.map((card) => card.wire),
            ),
          );
          for (final target in targets) {
            final action = PlayCardAction(CardId.manaSabotage, target: target);
            final core = BattleRulesCore.transition(state.view(side), action);
            final after = DeckManager.apply(state, action);
            expect(after.rules.toJson(), core.rules.toJson());
            expect(core.radar, isNull);
            expect(core.inspect, 0);
            expect(core.draw, isNull);
            expect(after.rules.modifiers.length, 1);
            final tax = after.rules.modifiers.single;
            expect(tax.toJson(), {
              'id': 'e41',
              'type': 'mana_sabotage',
              'owner': sideWire(side),
              'responseSide': sideWire(enemy),
              'targetCard': target,
              'ownTurn': 4,
            });
            expect(after.rules.mana[side], 4);
            expect(
              after.rules.mana[enemy],
              3,
              reason: 'Sabotage is not direct mana removal.',
            );
            expect(after.rules.fen, state.rules.fen);
            expect(after.rules.ply, 8);
            expect(after.rules.ownTurns, state.rules.ownTurns);
            expect(after.rules.used[side], [CardId.manaSabotage]);
            expect(after.rules.discarded[side], isEmpty);
            expect(after.hidden.hands[enemy], state.hidden.hands[enemy]);
            expect(after.hidden.decks, state.hidden.decks);
            for (final color in PieceColor.values) {
              expect(
                after.hidden.knowledge[color]!.toJson(),
                state.hidden.knowledge[color]!.toJson(),
              );
            }
            expect(jsonEncode(state.toJson()), original);
            _reject(after, action);
            _chessContinues(after);
            _conserved(after);
          }
        },
      );
    }

    test(
      '$label: used and discarded names are excluded whether retired from hand or deck',
      () {
        final initial = manaSabotageState(side: side);
        for (final card in initial.rules.arsenals[enemy]!) {
          for (final discarded in [false, true]) {
            final state = manaSabotageRetireOpponentCard(
              initial,
              card,
              discarded: discarded,
            );
            final expected =
                initial.rules.arsenals[enemy]!
                    .where((other) => other != card)
                    .map((other) => other.wire)
                    .toList();
            expect(
              BattleRulesCore.cardTargets(
                state.view(side),
                CardId.manaSabotage,
              ),
              unorderedEquals(expected),
            );
            _reject(
              state,
              PlayCardAction(CardId.manaSabotage, target: card.wire),
            );
            expect(_keys(state.view(side)), contains('pass'));
          }
        }
      },
    );

    test(
      '$label: exhausted opponent arsenal leaves pass and discard available',
      () {
        var state = manaSabotageState(side: side);
        final names = [...state.rules.arsenals[enemy]!];
        for (var i = 0; i < names.length; i++) {
          state = manaSabotageRetireOpponentCard(
            state,
            names[i],
            discarded: i.isEven,
          );
        }
        expect(
          BattleRulesCore.cardTargets(state.view(side), CardId.manaSabotage),
          isEmpty,
        );
        final actions = BattleRulesCore.legalActions(state.view(side));
        expect(
          actions.whereType<PlayCardAction>().where(
            (a) => a.card == CardId.manaSabotage,
          ),
          isEmpty,
        );
        expect(actions.whereType<PassAction>(), hasLength(1));
        expect(
          actions.whereType<DiscardAction>().map((a) => a.card),
          contains(CardId.manaSabotage),
        );
        _chessContinues(DeckManager.apply(state, const PassAction()));
        _chessContinues(
          DeckManager.apply(state, const DiscardAction(CardId.manaSabotage)),
        );
      },
    );

    test(
      '$label: naming hand versus deck does not reveal hidden location or order',
      () {
        final inHand = manaSabotageState(side: side);
        final inDeck = manaSabotageSwapOpponentHidden(
          inHand,
          CardId.radar,
          CardId.chain,
        );
        expect(inHand.view(side).toJson(), inDeck.view(side).toJson());
        expect(_keys(inHand.view(side)), _keys(inDeck.view(side)));
        for (final named in ['radar', 'chain']) {
          final action = PlayCardAction(CardId.manaSabotage, target: named);
          final a = DeckManager.apply(inHand, action);
          final b = DeckManager.apply(inDeck, action);
          expect(a.view(side).toJson(), b.view(side).toJson());
          expect(a.hidden.hands[enemy], inHand.hidden.hands[enemy]);
          expect(b.hidden.hands[enemy], inDeck.hidden.hands[enemy]);
          expect(a.hidden.decks[enemy], inHand.hidden.decks[enemy]);
          expect(b.hidden.decks[enemy], inDeck.hidden.decks[enemy]);
          expect(a.hidden.knowledge[side]!.radarObservations, isEmpty);
          expect(b.hidden.knowledge[side]!.pendingCards, isEmpty);
          expect(
            AuthoritativeBattleState.fromJson(a.toJson()).toJson(),
            a.toJson(),
          );
        }
      },
    );

    test(
      '$label: twenty hidden partitions preserve every named action and actor-visible outcome',
      () {
        final original = manaSabotageState(side: side);
        final order = [
          ...original.hidden.hands[enemy]!,
          ...original.hidden.decks[enemy]!,
        ];
        final referenceKeys = _keys(original.view(side));
        for (final reversed in [false, true]) {
          final source = reversed ? order.reversed.toList() : order;
          for (var offset = 0; offset < source.length; offset++) {
            final partition = [...source.skip(offset), ...source.take(offset)];
            final state = manaSabotageOpponentPartition(original, partition);
            expect(state.view(side).toJson(), original.view(side).toJson());
            expect(_keys(state.view(side)), referenceKeys);
            for (final named in order) {
              final action = PlayCardAction(
                CardId.manaSabotage,
                target: named.wire,
              );
              final expected =
                  DeckManager.apply(original, action).view(side).toJson();
              final actual = DeckManager.apply(state, action);
              expect(
                actual.view(side).toJson(),
                expected,
                reason:
                    'hidden partition reversed=$reversed offset=$offset target=${named.wire}',
              );
              expect(actual.hidden.hands[enemy], partition.take(3));
              expect(actual.hidden.decks[enemy], partition.skip(3));
              _conserved(actual);
            }
          }
        }
      },
    );

    for (final opponentTurn in [1, 3, 8, 30]) {
      test(
        '$label: natural next window from opponent own-turn $opponentTurn, not a later window',
        () {
          final initial = manaSabotageState(
            side: side,
            opponentTurn: opponentTurn,
          );
          final cast = DeckManager.apply(
            initial,
            const PlayCardAction(CardId.manaSabotage, target: 'radar'),
          );
          expect(cast.rules.modifiers.single.ownTurn, opponentTurn + 1);
          expect(
            BattleRulesCore.effectiveCost(cast.rules, enemy, CardId.radar),
            1,
          );
          expect(
            BattleRulesCore.effectiveCost(cast.rules, side, CardId.radar),
            1,
          );
          var state = DeckManager.apply(
            cast,
            ChessMoveAction(manaSabotageOwnerMove(side)),
          );
          expect(state.rules.board.turn, enemy);
          expect(state.rules.phase, BattlePhase.card);
          expect(state.rules.ownTurns[enemy], opponentTurn + 1);
          expect(
            BattleRulesCore.effectiveCost(state.rules, enemy, CardId.radar),
            2,
          );
          expect(
            BattleRulesCore.effectiveCost(state.rules, enemy, CardId.prophecy),
            1,
          );
          state = DeckManager.apply(state, const PassAction());
          expect(state.rules.modifiers, isEmpty);
          state = DeckManager.apply(
            state,
            ChessMoveAction(manaSabotageReplyMove(side)),
          );
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(side.isWhite ? 'a3a4' : 'a6a5'),
          );
          expect(state.rules.ownTurns[enemy], opponentTurn + 2);
          expect(
            BattleRulesCore.effectiveCost(state.rules, enemy, CardId.radar),
            1,
          );
          expect(state.rules.modifiers, isEmpty);
          expect(_keys(state.view(enemy)), contains('pass'));
          _conserved(state);
        },
      );
    }

    test(
      '$label: exact response-side, named-card and own-turn matching; close only due modifiers',
      () {
        final state = manaSabotageEdit(
          manaSabotageState(
            side: side,
            hand: const [CardId.radar, CardId.prophecy, CardId.shelter],
          ),
          (draft) {
            draft.modifiers.addAll([
              manaSabotageModifier(id: 'past', responseSide: side, ownTurn: 3),
              manaSabotageModifier(id: 'now', responseSide: side, ownTurn: 4),
              manaSabotageModifier(
                id: 'future',
                responseSide: side,
                ownTurn: 5,
              ),
              manaSabotageModifier(
                id: 'other-side',
                responseSide: enemy,
                ownTurn: 3,
              ),
              manaSabotageModifier(
                id: 'other-card',
                responseSide: side,
                ownTurn: 4,
                target: CardId.shelter,
              ),
              manaSabotageModifier(
                id: 'not-a-tax',
                responseSide: side,
                ownTurn: 4,
                target: CardId.prophecy,
                type: ModifierType.echo,
              ),
            ]);
          },
        );
        expect(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.radar),
          2,
        );
        expect(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.prophecy),
          1,
        );
        expect(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.shelter),
          3,
        );
        final closed = DeckManager.apply(state, const PassAction());
        expect(closed.rules.modifiers.map((m) => m.id), [
          'future',
          'other-side',
        ]);
        expect(closed.rules.mana, state.rules.mana);
        _chessContinues(closed);
      },
    );

    test(
      '$label: a named deck card drawn after expiry is not taxed in a later card window',
      () {
        final initial = manaSabotageState(side: side);
        expect(initial.hidden.decks[enemy]!.first, CardId.chain);
        var state = DeckManager.apply(
          initial,
          const PlayCardAction(CardId.manaSabotage, target: 'chain'),
        );
        state = DeckManager.apply(
          state,
          ChessMoveAction(manaSabotageOwnerMove(side)),
        );
        expect(
          BattleRulesCore.effectiveCost(state.rules, enemy, CardId.chain),
          3,
        );
        expect(state.hidden.hands[enemy], isNot(contains(CardId.chain)));
        state = DeckManager.apply(state, const PassAction());
        state = DeckManager.apply(
          state,
          ChessMoveAction(manaSabotageReplyMove(side)),
        );
        expect(state.hidden.hands[enemy], contains(CardId.chain));
        state = DeckManager.apply(state, const PassAction());
        state = DeckManager.apply(
          state,
          ChessMoveAction(side.isWhite ? 'a3a4' : 'a6a5'),
        );
        expect(state.rules.board.turn, enemy);
        expect(state.rules.ownTurns[enemy], 5);
        expect(
          BattleRulesCore.effectiveCost(state.rules, enemy, CardId.chain),
          2,
        );
        expect(state.rules.modifiers, isEmpty);
        _conserved(state);
      },
    );

    test(
      '$label: taxed opponent Sabotage can create a counter-tax for the following own window',
      () {
        final initial = manaSabotageState(
          side: side,
          opponentHand: const [
            CardId.manaSabotage,
            CardId.radar,
            CardId.prophecy,
          ],
        );
        var state = DeckManager.apply(
          initial,
          const PlayCardAction(CardId.manaSabotage, target: 'mana_sabotage'),
        );
        state = DeckManager.apply(
          state,
          ChessMoveAction(manaSabotageOwnerMove(side)),
        );
        expect(state.rules.mana[enemy], 4);
        expect(
          BattleRulesCore.effectiveCost(
            state.rules,
            enemy,
            CardId.manaSabotage,
          ),
          3,
        );
        _reject(
          state,
          const PlayCardAction(CardId.manaSabotage, target: 'mana_sabotage'),
        );
        state = DeckManager.apply(
          state,
          const PlayCardAction(CardId.manaSabotage, target: 'radar'),
        );
        expect(state.rules.mana[enemy], 1);
        expect(state.rules.modifiers, hasLength(1));
        expect(state.rules.modifiers.single.toJson(), {
          'id': 'e42',
          'type': 'mana_sabotage',
          'owner': sideWire(enemy),
          'responseSide': sideWire(side),
          'targetCard': 'radar',
          'ownTurn': 5,
        });
        expect(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.radar),
          1,
        );
        state = DeckManager.apply(
          state,
          ChessMoveAction(manaSabotageReplyMove(side)),
        );
        expect(state.rules.ownTurns[side], 5);
        expect(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.radar),
          2,
        );
        _conserved(state);
      },
    );

    for (final row in manaSabotageCostRows) {
      for (final reverse in [false, true]) {
        test(
          '$label ${row.card.wire}: ${row.taxes} taxes ${row.discounts} discounts reverse=$reverse literal cost ${row.expected}',
          () {
            expect(cardDefinitions[row.card]!.cost, row.base);
            for (var mana = 0; mana <= 6; mana++) {
              final hand =
                  row.card == CardId.radar
                      ? const [CardId.radar, CardId.prophecy, CardId.shelter]
                      : [row.card, CardId.radar, CardId.prophecy];
              final state = manaSabotageTaxed(
                manaSabotageState(side: side, hand: hand, mana: mana),
                target: row.card,
                taxes: row.taxes,
                discounts: row.discounts,
                reverse: reverse,
              );
              final action = _costAction(row.card, side);
              final frozen = jsonEncode(state.toJson());
              expect(
                BattleRulesCore.effectiveCost(state.rules, side, row.card),
                row.expected,
              );
              if (mana < row.expected) {
                _reject(state, action);
                expect(_keys(state.view(side)), contains('pass'));
                expect(
                  _keys(state.view(side)),
                  contains('discard:${row.card.wire}'),
                );
              } else {
                expect(
                  BattleRulesCore.isLegalAction(state.view(side), action),
                  isTrue,
                );
                final after = DeckManager.apply(state, action);
                expect(after.rules.mana[side], mana - row.expected);
                expect(after.rules.mana[enemy], 3);
                expect(after.rules.used[side], [row.card]);
                expect(
                  after.rules.modifiers.any(
                    (m) =>
                        m.id.startsWith('tax-') || m.id.startsWith('discount-'),
                  ),
                  isFalse,
                );
                _conserved(after);
                _chessContinues(after);
              }
              expect(jsonEncode(state.toJson()), frozen);
            }
          },
        );
      }
    }

    for (final closure in [
      'pass',
      'discard-named',
      'discard-other',
      'play-other',
    ]) {
      test(
        '$label: $closure expires tax even when named card is never played',
        () {
          final state = manaSabotageTaxed(
            manaSabotageState(
              side: side,
              hand: const [CardId.radar, CardId.prophecy, CardId.shelter],
            ),
          );
          final action = switch (closure) {
            'pass' => const PassAction(),
            'discard-named' => const DiscardAction(CardId.radar),
            'discard-other' => const DiscardAction(CardId.shelter),
            _ => PlayCardAction(CardId.shelter, target: side.isWhite ? 8 : 48),
          };
          final after = DeckManager.apply(state, action);
          expect(after.rules.modifiers, isEmpty);
          expect(after.rules.mana[side], closure == 'play-other' ? 4 : 6);
          expect(after.rules.mana[enemy], 3);
          expect(after.rules.fen, state.rules.fen);
          _chessContinues(after);
          _conserved(after);
        },
      );
    }

    test(
      '$label: card block wins over sufficient taxed mana; echo rewards only accepted named play',
      () {
        final taxed = manaSabotageTaxed(
          manaSabotageState(
            side: side,
            hand: const [CardId.radar, CardId.prophecy, CardId.shelter],
            mana: 2,
            opponentMana: 5,
          ),
        );
        final echo = manaSabotageEdit(
          taxed,
          (draft) => draft.modifiers.add(
            manaSabotageModifier(
              id: 'echo',
              responseSide: side,
              ownTurn: 4,
              type: ModifierType.echo,
            ),
          ),
        );
        final played = DeckManager.apply(
          echo,
          const PlayCardAction(CardId.radar, target: 'radar'),
        );
        expect(played.rules.mana[side], 0);
        expect(played.rules.mana[enemy], 6);
        final discarded = DeckManager.apply(
          echo,
          const DiscardAction(CardId.radar),
        );
        expect(discarded.rules.mana[enemy], 5);
        final blocked = manaSabotageEdit(
          echo,
          (draft) => draft.modifiers.add(
            manaSabotageModifier(
              id: 'block',
              responseSide: side,
              ownTurn: 4,
              type: ModifierType.cardBlock,
            ),
          ),
        );
        _reject(blocked, const PlayCardAction(CardId.radar, target: 'radar'));
        expect(
          DeckManager.apply(
            blocked,
            const DiscardAction(CardId.radar),
          ).rules.modifiers,
          isEmpty,
        );
        _chessContinues(DeckManager.apply(blocked, const PassAction()));
      },
    );

    test(
      '$label: taxed Prophecy charges once, rejects bad resolutions atomically, expires at private resolve',
      () {
        final state = manaSabotageEdit(
          manaSabotageTaxed(
            manaSabotageState(
              side: side,
              hand: const [CardId.prophecy, CardId.radar, CardId.shelter],
              deckPrefix: const [CardId.mine, CardId.chain, CardId.slow],
              mana: 3,
            ),
            target: CardId.prophecy,
          ),
          (draft) {
            draft.modifiers.addAll([
              manaSabotageModifier(
                id: 'future',
                responseSide: side,
                ownTurn: 5,
              ),
              manaSabotageModifier(
                id: 'enemy-window',
                responseSide: enemy,
                ownTurn: 4,
              ),
            ]);
          },
        );
        final pending = DeckManager.apply(
          state,
          const PlayCardAction(CardId.prophecy),
        );
        expect(pending.rules.phase, BattlePhase.pending);
        expect(pending.rules.mana[side], 1);
        expect(pending.rules.modifiers.map((m) => m.id), [
          'tax-0',
          'future',
          'enemy-window',
        ]);
        expect(pending.hidden.knowledge[side]!.pendingCards, [
          CardId.mine,
          CardId.chain,
        ]);
        expect(pending.hidden.knowledge[enemy]!.pendingCards, isEmpty);
        _reject(pending, const PassAction());
        _reject(pending, const DiscardAction(CardId.radar));
        _reject(
          pending,
          const PlayCardAction(CardId.manaSabotage, target: 'radar'),
        );
        for (final action in [
          ResolveAction([]),
          ResolveAction([CardId.mine, CardId.mine]),
          ResolveAction([CardId.mine, CardId.radar]),
          ResolveAction([CardId.chain, CardId.mine], selected: CardId.chain),
        ]) {
          _reject(pending, action);
        }
        final a = DeckManager.apply(
          pending,
          ResolveAction([CardId.chain, CardId.mine]),
        );
        final b = DeckManager.apply(
          pending,
          ResolveAction([CardId.mine, CardId.chain]),
        );
        expect(a.rules.mana[side], 1);
        expect(a.rules.pending, isNull);
        expect(a.rules.modifiers.map((m) => m.id), ['future', 'enemy-window']);
        expect(a.hidden.knowledge[side]!.pendingCards, isEmpty);
        expect(a.hidden.knowledge[side]!.knownUpcomingCards, [
          CardId.chain,
          CardId.mine,
        ]);
        expect(a.hidden.decks[side]!.take(2), [CardId.chain, CardId.mine]);
        expect(
          a.view(enemy).toJson(),
          b.view(enemy).toJson(),
          reason: 'Private order must not reach opponent view.',
        );
        _chessContinues(a);
        _conserved(a);
      },
    );

    test(
      '$label: taxed Fate Exchange selection is not a second play of the named selected card',
      () {
        final state = manaSabotageEdit(
          manaSabotageTaxed(
            manaSabotageState(
              side: side,
              hand: const [CardId.fateExchange, CardId.radar, CardId.prophecy],
              deckPrefix: const [CardId.mine, CardId.chain, CardId.slow],
              mana: 4,
            ),
            target: CardId.fateExchange,
          ),
          (draft) {
            draft.modifiers.add(
              manaSabotageModifier(
                id: 'selected-card-tax',
                responseSide: side,
                ownTurn: 4,
                target: CardId.chain,
              ),
            );
          },
        );
        final pending = DeckManager.apply(
          state,
          const PlayCardAction(CardId.fateExchange, sacrifice: CardId.radar),
        );
        expect(pending.rules.mana[side], 0);
        expect(pending.hidden.hands[side], [CardId.prophecy]);
        expect(pending.rules.discarded[side], [CardId.radar]);
        _reject(
          pending,
          ResolveAction([CardId.slow, CardId.chain], selected: CardId.chain),
        );
        _reject(
          pending,
          ResolveAction([CardId.slow, CardId.mine], selected: CardId.radar),
        );
        final a = DeckManager.apply(
          pending,
          ResolveAction([CardId.slow, CardId.mine], selected: CardId.chain),
        );
        final b = DeckManager.apply(
          pending,
          ResolveAction([CardId.slow, CardId.chain], selected: CardId.mine),
        );
        expect(a.rules.mana[side], 0);
        expect(a.hidden.hands[side], [CardId.prophecy, CardId.chain]);
        expect(a.rules.handCounts[side], 2);
        expect(a.rules.deckCounts[side], 6);
        expect(a.rules.drawCounts[side], 4);
        expect(a.rules.modifiers, isEmpty);
        expect(a.view(enemy).toJson(), b.view(enemy).toJson());
        _chessContinues(a);
        _conserved(a);
      },
    );

    test(
      '$label: malformed named targets and extraneous sacrifices cannot spend or advance',
      () {
        final state = manaSabotageState(side: side);
        for (final target in <Object?>[
          null,
          false,
          true,
          0,
          2.0,
          -1,
          64,
          '',
          'RADAR',
          ' radar',
          'radar ',
          'manaSabotage',
          'not_a_card',
          'board_seal',
          <Object?>['radar'],
          <String, Object?>{'card': 'radar'},
          <String, Object?>{'toString': 'radar'},
        ]) {
          _reject(state, PlayCardAction(CardId.manaSabotage, target: target));
          _reject(
            state,
            BattleAction.fromJson({
              'type': 'play',
              'card': 'mana_sabotage',
              'target': target,
            }),
          );
        }
        for (final sacrifice in [
          CardId.manaSabotage,
          CardId.radar,
          CardId.boardSeal,
        ]) {
          _reject(
            state,
            PlayCardAction(
              CardId.manaSabotage,
              target: 'radar',
              sacrifice: sacrifice,
            ),
          );
        }
        expect(
          () => BattleAction.fromJson({
            'type': 'play',
            'card': 'manaSabotage',
            'target': 'radar',
          }),
          throwsFormatException,
        );
        expect(
          () => BattleAction.fromJson({
            'type': 'play',
            'card': 'mana_sabotage',
            'target': 'radar',
            'sacrifice': 'unknown',
          }),
          throwsFormatException,
        );
        expect(
          () => BattleAction.fromJson({
            'type': 'unknown',
            'card': 'mana_sabotage',
          }),
          throwsFormatException,
        );
        _chessContinues(DeckManager.apply(state, const PassAction()));
      },
    );

    test(
      '$label: decoder ignores client-supplied cost/window fields; authority still computes both',
      () {
        final state = manaSabotageState(side: side);
        final decoded = BattleAction.fromJson({
          'type': 'play',
          'card': 'mana_sabotage',
          'target': 'radar',
          'manaCost': 0,
          'ownTurn': 999,
          'responseSide': sideWire(side),
        });
        expect(decoded.toJson(), {
          'type': 'play',
          'card': 'mana_sabotage',
          'target': 'radar',
        });
        final after = DeckManager.apply(state, decoded);
        expect(after.rules.mana[side], 4);
        expect(after.rules.modifiers.single.ownTurn, 4);
        expect(after.rules.modifiers.single.responseSide, enemy);
        _conserved(after);
      },
    );

    test(
      '$label: absent hand, wrong viewer, first turn, chess and terminal reject sabotage',
      () {
        final missing = manaSabotageState(
          side: side,
          hand: const [CardId.radar, CardId.prophecy, CardId.shelter],
          deckPrefix: const [CardId.manaSabotage],
        );
        _reject(
          missing,
          const PlayCardAction(CardId.manaSabotage, target: 'radar'),
        );
        final state = manaSabotageState(side: side);
        final frozen = jsonEncode(state.toJson());
        expect(BattleRulesCore.legalActions(state.view(enemy)), isEmpty);
        expect(
          () => BattleRulesCore.transition(
            state.view(enemy),
            const PlayCardAction(CardId.manaSabotage, target: 'radar'),
          ),
          throwsStateError,
        );
        expect(jsonEncode(state.toJson()), frozen);
        final first = manaSabotageEdit(state, (draft) {
          draft.ownTurns[side] = 1;
          draft.phase = BattlePhase.chess;
        });
        _reject(
          first,
          const PlayCardAction(CardId.manaSabotage, target: 'radar'),
        );
        final chess = DeckManager.apply(state, const PassAction());
        _reject(
          chess,
          const PlayCardAction(CardId.manaSabotage, target: 'radar'),
        );
        final terminal = manaSabotageEdit(state, (draft) {
          draft.phase = BattlePhase.terminal;
          draft.terminal = const TerminalState('resign');
        });
        _reject(
          terminal,
          const PlayCardAction(CardId.manaSabotage, target: 'radar'),
        );
      },
    );

    test(
      '$label: injected late hidden-count failure cannot partially spend or add a tax',
      () {
        final valid = manaSabotageState(side: side);
        final broken = AuthoritativeBattleState(
          valid.rules,
          AuthoritativeHiddenState(
            hands: valid.hidden.hands,
            decks: {
              ...valid.hidden.decks,
              enemy: valid.hidden.decks[enemy]!.skip(1).toList(),
            },
            knowledge: valid.hidden.knowledge,
          ),
        );
        final before = jsonEncode(broken.toJson());
        const action = PlayCardAction(CardId.manaSabotage, target: 'radar');
        expect(
          BattleRulesCore.isLegalAction(broken.view(side), action),
          isTrue,
        );
        expect(
          () => DeckManager.apply(broken, action),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'hidden-count-inconsistent',
            ),
          ),
        );
        expect(jsonEncode(broken.toJson()), before);
        expect(broken.rules.mana[side], 6);
        expect(broken.rules.modifiers, isEmpty);
        expect(broken.rules.used[side], isEmpty);
        final after = DeckManager.apply(valid, action);
        expect(after.rules.mana[side], 4);
        expect(after.rules.modifiers, hasLength(1));
        _conserved(after);
      },
    );

    test(
      '$label controller: unaffordable taxed play never writes or sends; pass still progresses',
      () async {
        var server = manaSabotageTaxed(
          manaSabotageState(
            side: side,
            hand: const [CardId.radar, CardId.prophecy, CardId.shelter],
            mana: 1,
          ),
        );
        var version = 0, sent = 0;
        final stored = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(server, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            sent++;
            server = DeckManager.apply(
              server,
              BattleAction.fromJson(body['intent'] as Map),
            );
            return _response(server, side, ++version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.radar, target: 'radar'),
          ),
          isFalse,
        );
        expect(sent, 0);
        expect(stored, isEmpty);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(await controller.submit(const PassAction()), isTrue);
        expect(sent, 1);
        expect(stored.last, isNull);
        expect(controller.view!.rules.phase, BattlePhase.chess);
        expect(controller.view!.rules.modifiers, isEmpty);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
      },
    );

    test(
      '$label controller: lost sabotage acknowledgement retries one identity without a second tax',
      () async {
        var server = manaSabotageState(side: side);
        var version = 0, commits = 0, attempts = 0;
        String? firstId;
        final stored = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(server, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              attempts++;
              if (firstId == null) {
                firstId = body['actionId'] as String;
                server = DeckManager.apply(
                  server,
                  BattleAction.fromJson(body['intent'] as Map),
                );
                version++;
                commits++;
                throw StateError('simulated lost sabotage acknowledgement');
              }
              expect(body['actionId'], firstId);
              expect(body['expectedStateVersion'], 0);
            }
            return _response(server, side, version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.manaSabotage, target: 'radar'),
          ),
          isFalse,
        );
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isTrue);
        await controller.reconnect();
        await controller.retryPending();
        expect(attempts, 2);
        expect(commits, 1);
        expect(server.rules.modifiers, hasLength(1));
        expect(server.rules.mana[side], 4);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(stored.last, isNull);
        _chessContinues(server);
      },
    );

    test(
      '$label controller: authoritative INVALID_ACTION clears pending; refreshed pass is usable',
      () async {
        var server = manaSabotageState(side: side);
        var version = 0, attempts = 0;
        final stored = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(server, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              attempts++;
              if (attempts == 1) {
                throw const BattleV1Rejection('INVALID_ACTION');
              }
              server = DeckManager.apply(
                server,
                BattleAction.fromJson(body['intent'] as Map),
              );
              version++;
            }
            return _response(server, side, version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.manaSabotage, target: 'radar'),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(stored.last, isNull);
        expect(server.rules.mana[side], 6);
        expect(server.rules.modifiers, isEmpty);
        await controller.reconnect();
        expect(controller.error, isNull);
        expect(await controller.submit(const PassAction()), isTrue);
        expect(attempts, 2);
        _chessContinues(server);
      },
    );
  }
}
