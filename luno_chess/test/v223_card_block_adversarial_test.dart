import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_card_block_cases.dart';

void _partition(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final cards = [
      ...state.hidden.hands[side]!,
      ...state.hidden.decks[side]!,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    expect(
      cards.length,
      10,
      reason: 'Fixture/transition must conserve ten cards',
    );
    expect(cards.toSet().length, 10, reason: 'No duplicate card identities');
    expect(cards.toSet(), state.rules.arsenals[side]!.toSet());
    expect(state.rules.handCounts[side], state.hidden.hands[side]!.length);
    expect(state.rules.deckCounts[side], state.hidden.decks[side]!.length);
    expect(state.rules.drawCounts[side], 10 - state.hidden.decks[side]!.length);
  }
}

void _reject(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(state.toJson());
  final view = state.view(state.rules.board.turn);
  expect(BattleRulesCore.isLegalAction(view, action), isFalse);
  expect(() => BattleRulesCore.transition(view, action), throwsStateError);
  expect(() => DeckManager.apply(state, action), throwsStateError);
  expect(
    jsonEncode(state.toJson()),
    before,
    reason: 'Rejection must be atomic',
  );
  _partition(state);
}

List<String> _moves(AuthoritativeBattleState state) =>
    BattleRulesCore.legalActions(
        state.view(state.rules.board.turn),
      ).whereType<ChessMoveAction>().map((a) => a.uci).toList()
      ..sort();

void _chessWindow(
  AuthoritativeBattleState before,
  AuthoritativeBattleState after,
  PieceColor side, {
  String witness = 'g8h8',
  PieceColor? perspective,
}) {
  expect(after.rules.phase, BattlePhase.chess);
  expect(after.rules.fen, before.rules.fen);
  expect(after.rules.ply, before.rules.ply);
  expect(after.rules.ownTurns, before.rules.ownTurns);
  expect(after.rules.board.turn, side);
  expect(after.rules.pending, isNull);
  expect(after.rules.special, isNull);
  expect(
    after.rules.modifiers.where((m) => m.type == ModifierType.cardBlock),
    isEmpty,
  );
  expect(
    BattleRulesCore.isLegalAction(
      after.view(side),
      ChessMoveAction(cardBlockMove(witness, perspective ?? side.opposite)),
    ),
    isTrue,
  );
  _partition(after);
}

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor side, {
  int version = 40,
}) {
  final response = v1Response(state: state, side: side, version: version);
  final public = (response['view'] as Map)['public'] as Map;
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  return response;
}

void main() {
  for (final blocker in PieceColor.values) {
    final victim = blocker.opposite;
    final label = blocker.name;

    test('card_block/$label literal cast contract and immutable input', () {
      final before = cardBlockFixture(blocker: blocker, victimTurn: 7);
      _partition(before);
      final saved = jsonEncode(before.toJson());
      final cast = cardBlockCast(before, CardId.prophecy);
      expect(jsonEncode(before.toJson()), saved);
      expect(cast.rules.mana[blocker], 3);
      expect(cast.rules.mana[victim], 6);
      expect(cast.rules.used[blocker], [CardId.cardBlock]);
      expect(cast.hidden.hands[blocker], [CardId.radar, CardId.shelter]);
      expect(cast.hidden.hands[victim], before.hidden.hands[victim]);
      expect(cast.hidden.decks, before.hidden.decks);
      expect(cast.rules.phase, BattlePhase.chess);
      expect(cast.rules.fen, before.rules.fen);
      expect(cast.rules.ply, 0);
      expect(cast.rules.ownTurns, before.rules.ownTurns);
      expect(cast.rules.special, isNull);
      expect(cast.rules.pending, isNull);
      expect(cast.rules.effectSequence, 101);
      expect(cast.rules.modifiers.single.toJson(), {
        'id': 'e101',
        'type': 'card_block',
        'owner': sideWire(blocker),
        'responseSide': sideWire(victim),
        'targetCard': 'prophecy',
        'ownTurn': 8,
      });
      for (final side in PieceColor.values) {
        expect(
          cast.view(side).knowledge.toJson(),
          before.view(side).knowledge.toJson(),
        );
      }
      _partition(cast);
      expect(cardBlockRoundTrip(cast).toJson(), cast.toJson());
      _reject(cast, const PlayCardAction(CardId.cardBlock, target: 'prophecy'));
    });

    for (final target in CardId.values) {
      test(
        'card_block/$label blocks only named ${target.wire}, discard/pass survive',
        () {
          final hand =
              {
                target,
                CardId.radar,
                CardId.prophecy,
                CardId.shelter,
              }.take(3).toList();
          final root = cardBlockFixture(
            blocker: blocker,
            target: target,
            victimHand: hand,
            removalTargets: true,
            fen:
                target == CardId.rookBend
                    ? 'r1b3k1/5ppp/1n6/8/8/8/1N3PPP/R1B3K1 w - - 0 21'
                    : cardBlockQuietFen,
          );
          final incoming = cardBlockIncoming(root, blocker, target);
          _partition(incoming);
          expect(incoming.rules.ownTurns[victim], 5);
          final witness = cardBlockWitness(target, victim);
          final unblocked = cardBlockEdit(incoming, (d) => d.modifiers.clear());
          expect(
            BattleRulesCore.isLegalAction(unblocked.view(victim), witness),
            isTrue,
            reason: 'Literal witness must be playable without Card Block',
          );
          _reject(incoming, witness);
          _reject(incoming, BattleAction.fromJson(witness.toJson()));
          final actions = BattleRulesCore.legalActions(incoming.view(victim));
          expect(
            actions.whereType<PlayCardAction>().where((a) => a.card == target),
            isEmpty,
          );
          expect(actions.whereType<PassAction>().length, 1);
          expect(
            actions.whereType<DiscardAction>().map((a) => a.card).toSet(),
            hand.toSet(),
          );
          final passed = DeckManager.apply(
            cardBlockRoundTrip(incoming),
            const PassAction(),
          );
          _chessWindow(incoming, passed, victim);
          expect(passed.hidden.hands, incoming.hidden.hands);
          expect(passed.rules.mana, incoming.rules.mana);
          final discarded = DeckManager.apply(incoming, DiscardAction(target));
          _chessWindow(incoming, discarded, victim);
          expect(discarded.rules.discarded[victim], [target]);
          expect(discarded.rules.used[victim], isEmpty);
          expect(discarded.hidden.hands[victim], isNot(contains(target)));
          expect(discarded.rules.mana, incoming.rules.mana);
          expect(
            _moves(discarded),
            _moves(passed),
            reason: 'Card Block cannot restrict chess',
          );
          final unrelated =
              hand.contains(CardId.radar) && target != CardId.radar
                  ? const PlayCardAction(CardId.radar, target: 'shelter')
                  : cardBlockWitness(CardId.shelter, victim);
          expect(
            BattleRulesCore.isLegalAction(incoming.view(victim), unrelated),
            isTrue,
          );
        },
      );
    }

    test(
      'card_block/$label real opening skips no intended next card window',
      () {
        const deck = [
          CardId.cardBlock,
          CardId.prophecy,
          CardId.shelter,
          CardId.radar,
          CardId.chain,
          CardId.slow,
          CardId.freeze,
          CardId.mine,
          CardId.echo,
          CardId.fog,
        ];
        var state = DeckManager.newBattle(white: deck, black: deck);
        state = DeckManager.apply(state, const ChessMoveAction('e2e4'));
        state = DeckManager.apply(state, const ChessMoveAction('e7e5'));
        state = DeckManager.apply(state, const PassAction());
        state = DeckManager.apply(state, const ChessMoveAction('g1f3'));
        state = DeckManager.apply(state, const PassAction());
        state = DeckManager.apply(state, const ChessMoveAction('g8f6'));
        if (!blocker.isWhite) {
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(state, const ChessMoveAction('b1c3'));
        }
        expect(state.rules.board.turn, blocker);
        expect(state.rules.mana[blocker], 3);
        final previousTurn = state.rules.ownTurns[victim]!;
        state = cardBlockCast(state, CardId.prophecy);
        expect(state.rules.modifiers.single.ownTurn, previousTurn + 1);
        state = DeckManager.apply(
          state,
          ChessMoveAction(blocker.isWhite ? 'b1c3' : 'b8c6'),
        );
        expect(state.rules.phase, BattlePhase.card);
        expect(state.rules.ownTurns[victim], previousTurn + 1);
        _reject(state, const PlayCardAction(CardId.prophecy));
        state = DeckManager.apply(state, const PassAction());
        expect(state.rules.modifiers, isEmpty);
        expect(
          BattleRulesCore.isLegalAction(
            state.view(victim),
            ChessMoveAction(blocker.isWhite ? 'b8c6' : 'd2d3'),
          ),
          isTrue,
        );
        _partition(state);
      },
    );

    test(
      'card_block/$label absent target drawn after expiry is not locked later',
      () {
        final root = cardBlockFixture(
          blocker: blocker,
          target: CardId.shelter,
          victimHand: [CardId.radar, CardId.prophecy, CardId.chain],
          victimDeckPrefix: [CardId.shelter, CardId.slow],
        );
        var state = cardBlockIncoming(root, blocker, CardId.shelter);
        expect(state.hidden.hands[victim], isNot(contains(CardId.shelter)));
        state = DeckManager.apply(state, const PassAction());
        state = DeckManager.apply(
          state,
          ChessMoveAction(cardBlockMove('g8h8', blocker)),
        );
        expect(state.hidden.hands[victim], contains(CardId.shelter));
        expect(state.rules.modifiers, isEmpty);
        state = DeckManager.apply(state, const PassAction());
        state = DeckManager.apply(
          state,
          ChessMoveAction(cardBlockMove('h1g1', blocker)),
        );
        expect(state.rules.board.turn, victim);
        expect(state.rules.phase, BattlePhase.card);
        expect(
          BattleRulesCore.isLegalAction(
            state.view(victim),
            cardBlockWitness(CardId.shelter, victim),
          ),
          isTrue,
        );
        _partition(state);
      },
    );

    test('card_block/$label hand order is not block identity', () {
      final root = cardBlockFixture(
        blocker: blocker,
        target: CardId.shelter,
        victimHand: [CardId.radar, CardId.shelter, CardId.prophecy],
      );
      final incoming = cardBlockIncoming(root, blocker, CardId.shelter);
      for (final hand in [
        [CardId.shelter, CardId.radar, CardId.prophecy],
        [CardId.prophecy, CardId.radar, CardId.shelter],
      ]) {
        final reordered = cardBlockRoundTrip(
          cardBlockReorderHand(incoming, victim, hand),
        );
        _reject(reordered, cardBlockWitness(CardId.shelter, victim));
        expect(
          BattleRulesCore.isLegalAction(
            reordered.view(victim),
            const PlayCardAction(CardId.radar, target: 'shelter'),
          ),
          isTrue,
        );
        expect(
          BattleRulesCore.isLegalAction(
            reordered.view(victim),
            const DiscardAction(CardId.shelter),
          ),
          isTrue,
        );
      }
    });

    for (final close in <BattleAction>[
      const PassAction(),
      const DiscardAction(CardId.radar),
      const PlayCardAction(CardId.radar, target: 'shelter'),
    ]) {
      test(
        'card_block/$label ${close.key} closes the exact response window',
        () {
          final state = cardBlockIncoming(
            cardBlockFixture(
              blocker: blocker,
              target: CardId.shelter,
              victimHand: [CardId.shelter, CardId.radar, CardId.prophecy],
            ),
            blocker,
            CardId.shelter,
          );
          final after = DeckManager.apply(state, close);
          _chessWindow(state, after, victim);
          _reject(after, cardBlockWitness(CardId.shelter, victim));
          final moved = DeckManager.apply(
            after,
            ChessMoveAction(cardBlockMove('g8h8', blocker)),
          );
          expect(moved.rules.ply, state.rules.ply + 1);
          expect(moved.rules.board.turn, blocker);
          expect(moved.rules.modifiers, isEmpty);
          _partition(moved);
        },
      );
    }

    for (final chooser in [CardId.prophecy, CardId.fateExchange]) {
      test(
        'card_block/$label ${chooser.wire} retains block until private resolution',
        () {
          final root = cardBlockFixture(
            blocker: blocker,
            target: CardId.shelter,
            victimHand: [chooser, CardId.shelter, CardId.radar],
            victimDeckPrefix: [CardId.chain, CardId.slow, CardId.freeze],
          );
          final incoming = cardBlockIncoming(root, blocker, CardId.shelter);
          final cast = DeckManager.apply(
            incoming,
            PlayCardAction(
              chooser,
              sacrifice: chooser == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          expect(cast.rules.phase, BattlePhase.pending);
          expect(
            cast.rules.modifiers.single.toJson(),
            incoming.rules.modifiers.single.toJson(),
          );
          expect(cast.rules.ownTurns, incoming.rules.ownTurns);
          expect(cast.rules.ply, incoming.rules.ply);
          expect(
            cast.view(victim).knowledge.pendingCards,
            chooser == CardId.prophecy
                ? [CardId.chain, CardId.slow]
                : [CardId.chain, CardId.slow, CardId.freeze],
          );
          expect(cast.view(blocker).knowledge.pendingCards, isEmpty);
          expect(cast.view(blocker).knowledge.knownUpcomingCards, isEmpty);
          _reject(cast, const PassAction());
          _reject(cast, const DiscardAction(CardId.shelter));
          _reject(cast, cardBlockWitness(CardId.shelter, victim));
          _reject(cast, ChessMoveAction(cardBlockMove('g8h8', blocker)));
          _reject(cast, ResolveAction([CardId.chain, CardId.chain]));
          _reject(cast, ResolveAction([CardId.radar]));
          final choice =
              chooser == CardId.prophecy
                  ? ResolveAction([CardId.slow, CardId.chain])
                  : ResolveAction([
                    CardId.freeze,
                    CardId.chain,
                  ], selected: CardId.slow);
          final resolved = DeckManager.apply(cardBlockRoundTrip(cast), choice);
          _chessWindow(cast, resolved, victim);
          expect(resolved.view(victim).knowledge.pendingCards, isEmpty);
          expect(
            resolved.view(blocker).knowledge.toJson(),
            cast.view(blocker).knowledge.toJson(),
          );
          expect(
            resolved.hidden.decks[victim]!.take(2),
            chooser == CardId.prophecy
                ? [CardId.slow, CardId.chain]
                : [CardId.freeze, CardId.chain],
          );
          if (chooser == CardId.fateExchange) {
            expect(resolved.hidden.hands[victim], [
              CardId.shelter,
              CardId.slow,
            ]);
            expect(resolved.rules.discarded[victim], [CardId.radar]);
          }
          _reject(resolved, choice);
        },
      );
    }

    for (final sacrificeCard in [CardId.fateExchange, CardId.shadowContract]) {
      test(
        'card_block/$label blocked card may be sacrificed to ${sacrificeCard.wire}',
        () {
          final incoming = cardBlockIncoming(
            cardBlockFixture(
              blocker: blocker,
              target: CardId.radar,
              victimHand: [sacrificeCard, CardId.radar, CardId.shelter],
              victimDeckPrefix: [CardId.chain, CardId.slow, CardId.freeze],
            ),
            blocker,
            CardId.radar,
          );
          final cast = DeckManager.apply(
            incoming,
            PlayCardAction(sacrificeCard, sacrifice: CardId.radar),
          );
          expect(cast.rules.discarded[victim], [CardId.radar]);
          expect(cast.rules.used[victim], [sacrificeCard]);
          expect(cast.hidden.hands[victim], [CardId.shelter]);
          expect(
            cast.rules.mana[victim],
            sacrificeCard == CardId.fateExchange ? 3 : 5,
          );
          _partition(cast);
          if (sacrificeCard == CardId.fateExchange) {
            expect(
              cast.rules.modifiers
                  .where((m) => m.type == ModifierType.cardBlock)
                  .length,
              1,
            );
            final resolved = DeckManager.apply(
              cast,
              ResolveAction([
                CardId.freeze,
                CardId.chain,
              ], selected: CardId.slow),
            );
            _chessWindow(cast, resolved, victim);
          } else {
            expect(cast.rules.modifiers.map((m) => m.type), [
              ModifierType.discount,
            ]);
            expect(
              cast.rules.modifiers.single.ownTurn,
              incoming.rules.ownTurns[victim]! + 1,
            );
          }
        },
      );
    }

    test('card_block/$label hidden hand/deck swap cannot become an oracle', () {
      final a = cardBlockFixture(
        blocker: blocker,
        target: CardId.shelter,
        victimHand: [CardId.shelter, CardId.prophecy, CardId.radar],
        victimDeckPrefix: [CardId.chain],
      );
      final b = cardBlockFixture(
        blocker: blocker,
        target: CardId.shelter,
        victimHand: [CardId.chain, CardId.prophecy, CardId.radar],
        victimDeckPrefix: [CardId.shelter],
      );
      expect(a.rules.toJson(), b.rules.toJson());
      expect(a.view(blocker).toJson(), b.view(blocker).toJson());
      const expected = [
        'chain',
        'freeze',
        'locked_square',
        'pawn_advance',
        'pawn_deviation',
        'prophecy',
        'purify',
        'radar',
        'shelter',
        'slow',
      ];
      final targetsA =
          BattleRulesCore.cardTargets(
              a.view(blocker),
              CardId.cardBlock,
            ).cast<String>().toList()
            ..sort();
      final targetsB =
          BattleRulesCore.cardTargets(
              b.view(blocker),
              CardId.cardBlock,
            ).cast<String>().toList()
            ..sort();
      expect(targetsA, expected);
      expect(targetsB, expected);
      final castA = cardBlockCast(a, CardId.shelter);
      final castB = cardBlockCast(b, CardId.shelter);
      expect(castA.rules.toJson(), castB.rules.toJson());
      expect(castA.view(blocker).toJson(), castB.view(blocker).toJson());
      expect(castA.view(blocker).knowledge.radarObservations, isEmpty);
      expect(castB.view(blocker).knowledge.radarObservations, isEmpty);
      expect(
        jsonEncode(castA.view(blocker).toJson()),
        isNot(contains('hidden')),
      );
    });

    test(
      'card_block/$label private choice can acquire blocked identity but cannot reopen its window',
      () {
        final incoming = cardBlockIncoming(
          cardBlockFixture(
            blocker: blocker,
            target: CardId.chain,
            victimHand: [CardId.fateExchange, CardId.shelter, CardId.radar],
            victimDeckPrefix: [CardId.chain, CardId.slow, CardId.freeze],
          ),
          blocker,
          CardId.chain,
        );
        final pending = DeckManager.apply(
          incoming,
          const PlayCardAction(CardId.fateExchange, sacrifice: CardId.radar),
        );
        expect(pending.rules.modifiers.single.targetCard, CardId.chain);
        final chosenChain = DeckManager.apply(
          pending,
          ResolveAction([CardId.freeze, CardId.slow], selected: CardId.chain),
        );
        final chosenSlow = DeckManager.apply(
          pending,
          ResolveAction([CardId.freeze, CardId.chain], selected: CardId.slow),
        );
        expect(chosenChain.hidden.hands[victim], [
          CardId.shelter,
          CardId.chain,
        ]);
        expect(chosenSlow.hidden.hands[victim], [CardId.shelter, CardId.slow]);
        expect(
          chosenChain.view(blocker).toJson(),
          chosenSlow.view(blocker).toJson(),
          reason: 'Selected identity and remainder order are private',
        );
        expect(chosenChain.rules.modifiers, isEmpty);
        _reject(chosenChain, cardBlockWitness(CardId.chain, victim));
        var next = DeckManager.apply(
          chosenChain,
          ChessMoveAction(cardBlockMove('g8h8', blocker)),
        );
        next = DeckManager.apply(next, const PassAction());
        next = DeckManager.apply(
          next,
          ChessMoveAction(cardBlockMove('h1g1', blocker)),
        );
        expect(
          BattleRulesCore.isLegalAction(
            next.view(victim),
            cardBlockWitness(CardId.chain, victim),
          ),
          isTrue,
        );
        _partition(next);
      },
    );

    test('card_block/$label modifier is not a Purify or Break Seal target', () {
      final incoming = cardBlockIncoming(
        cardBlockFixture(
          blocker: blocker,
          victimHand: [CardId.prophecy, CardId.purify, CardId.breakSeal],
        ),
        blocker,
        CardId.prophecy,
      );
      final id = incoming.rules.modifiers.single.id;
      expect(
        BattleRulesCore.cardTargets(incoming.view(victim), CardId.purify),
        isEmpty,
      );
      expect(
        BattleRulesCore.cardTargets(incoming.view(victim), CardId.breakSeal),
        isEmpty,
      );
      _reject(incoming, PlayCardAction(CardId.purify, target: id));
      _reject(incoming, PlayCardAction(CardId.breakSeal, target: id));
      expect(incoming.rules.modifiers.single.id, id);
    });

    for (final spent in ['used', 'discarded']) {
      test(
        'card_block/$label $spent opponent target rejects without spending',
        () {
          final root = cardBlockFixture(
            blocker: blocker,
            target: CardId.chain,
            victimHand: [CardId.radar, CardId.prophecy, CardId.shelter],
            victimUsed: spent == 'used' ? [CardId.chain] : [],
            victimDiscarded: spent == 'discarded' ? [CardId.chain] : [],
          );
          _partition(root);
          expect(
            BattleRulesCore.cardTargets(root.view(blocker), CardId.cardBlock),
            isNot(contains('chain')),
          );
          _reject(
            root,
            const PlayCardAction(CardId.cardBlock, target: 'chain'),
          );
        },
      );
    }

    for (final mana in [0, 1, 2, 3, 6]) {
      test('card_block/$label exact cost boundary $mana', () {
        final root = cardBlockFixture(blocker: blocker, casterMana: mana);
        const action = PlayCardAction(CardId.cardBlock, target: 'prophecy');
        if (mana < 3) {
          _reject(root, action);
        } else {
          final cast = DeckManager.apply(root, action);
          expect(cast.rules.mana[blocker], mana - 3);
          expect(cast.rules.modifiers.length, 1);
          _partition(cast);
        }
      });
    }

    test(
      'card_block/$label malformed named targets and extra sacrifice reject',
      () {
        final root = cardBlockFixture(blocker: blocker);
        for (final target in <Object?>[
          null,
          '',
          'PROPHECY',
          ' prophecy',
          'prophecy ',
          'prophecy:',
          'not_a_card',
          'echo',
          0,
          0.0,
          -1,
          64,
          false,
          true,
          ['prophecy'],
          {'card': 'prophecy'},
        ]) {
          final action = PlayCardAction(CardId.cardBlock, target: target);
          _reject(root, action);
          _reject(root, BattleAction.fromJson(action.toJson()));
        }
        for (final sacrifice in [
          CardId.cardBlock,
          CardId.radar,
          CardId.freeze,
        ]) {
          _reject(
            root,
            PlayCardAction(
              CardId.cardBlock,
              target: 'prophecy',
              sacrifice: sacrifice,
            ),
          );
        }
        for (final card in ['CARD_BLOCK', '', 'card_block:', 42]) {
          expect(
            () => BattleAction.fromJson({
              'type': 'play',
              'card': card,
              'target': 'prophecy',
            }),
            throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
          );
        }
      },
    );

    test(
      'card_block/$label already used/discarded/absent caster card cannot replay',
      () {
        final spent = cardBlockFixture(
          blocker: blocker,
          casterHand: [CardId.radar, CardId.shelter, CardId.prophecy],
          casterUsed: [CardId.cardBlock],
        );
        _reject(
          spent,
          const PlayCardAction(CardId.cardBlock, target: 'prophecy'),
        );
        _reject(spent, const DiscardAction(CardId.cardBlock));
        final root = cardBlockFixture(blocker: blocker);
        final discard = DeckManager.apply(
          root,
          const DiscardAction(CardId.cardBlock),
        );
        _reject(
          discard,
          const PlayCardAction(CardId.cardBlock, target: 'prophecy'),
        );
        _reject(discard, const DiscardAction(CardId.cardBlock));
        final absent = cardBlockFixture(
          blocker: blocker,
          casterHand: [CardId.radar, CardId.shelter, CardId.prophecy],
        );
        _reject(
          absent,
          const PlayCardAction(CardId.cardBlock, target: 'prophecy'),
        );
      },
    );

    for (final offset in [-1, 0, 1]) {
      test('card_block/$label exact own-turn gate offset $offset', () {
        var incoming = cardBlockIncoming(
          cardBlockFixture(blocker: blocker),
          blocker,
          CardId.prophecy,
        );
        final old = incoming.rules.modifiers.single;
        incoming = cardBlockEdit(incoming, (d) {
          d.modifiers[0] = PendingModifier(
            id: old.id,
            type: old.type,
            owner: old.owner,
            responseSide: old.responseSide,
            targetCard: old.targetCard,
            ownTurn: d.ownTurns[victim]! + offset,
          );
        });
        expect(
          BattleRulesCore.isLegalAction(
            incoming.view(victim),
            const PlayCardAction(CardId.prophecy),
          ),
          offset != 0,
        );
        final passed = DeckManager.apply(incoming, const PassAction());
        expect(passed.rules.modifiers.length, offset > 0 ? 1 : 0);
        _partition(passed);
      });
    }

    test(
      'card_block/$label response side and target name are separate gates',
      () {
        final incoming = cardBlockIncoming(
          cardBlockFixture(blocker: blocker),
          blocker,
          CardId.prophecy,
        );
        final old = incoming.rules.modifiers.single;
        final wrongSide = cardBlockEdit(incoming, (d) {
          d.modifiers[0] = PendingModifier(
            id: old.id,
            type: old.type,
            owner: old.owner,
            responseSide: blocker,
            targetCard: CardId.prophecy,
            ownTurn: d.ownTurns[blocker]!,
          );
        });
        expect(
          BattleRulesCore.isLegalAction(
            wrongSide.view(victim),
            const PlayCardAction(CardId.prophecy),
          ),
          isTrue,
        );
        final closed = DeckManager.apply(wrongSide, const PassAction());
        expect(closed.rules.modifiers.single.responseSide, blocker);
        final renamed = cardBlockEdit(incoming, (d) {
          d.modifiers[0] = PendingModifier(
            id: old.id,
            type: old.type,
            owner: old.owner,
            responseSide: old.responseSide,
            targetCard: CardId.shelter,
            ownTurn: old.ownTurn,
          );
        });
        expect(
          BattleRulesCore.isLegalAction(
            renamed.view(victim),
            const PlayCardAction(CardId.prophecy),
          ),
          isTrue,
        );
        _reject(renamed, cardBlockWitness(CardId.shelter, victim));
      },
    );

    test(
      'card_block/$label discounts and Echo cannot bypass or reward a rejected play',
      () {
        var incoming = cardBlockIncoming(
          cardBlockFixture(blocker: blocker),
          blocker,
          CardId.prophecy,
        );
        incoming = cardBlockEdit(incoming, (d) {
          d.mana[blocker] = 0;
          d.modifiers.addAll([
            PendingModifier(
              id: 'cb-discount',
              type: ModifierType.discount,
              owner: victim,
              responseSide: victim,
              targetCard: null,
              ownTurn: d.ownTurns[victim]!,
            ),
            PendingModifier(
              id: 'cb-echo',
              type: ModifierType.echo,
              owner: blocker,
              responseSide: victim,
              targetCard: CardId.prophecy,
              ownTurn: d.ownTurns[victim]!,
            ),
            PendingModifier(
              id: 'cb-future',
              type: ModifierType.cardBlock,
              owner: blocker,
              responseSide: victim,
              targetCard: CardId.radar,
              ownTurn: d.ownTurns[victim]! + 1,
            ),
          ]);
        });
        expect(
          BattleRulesCore.effectiveCost(
            incoming.rules,
            victim,
            CardId.prophecy,
          ),
          1,
        );
        _reject(incoming, const PlayCardAction(CardId.prophecy));
        expect(incoming.rules.mana[blocker], 0);
        final passed = DeckManager.apply(incoming, const PassAction());
        expect(passed.rules.modifiers.map((m) => m.id), ['cb-future']);
        expect(passed.rules.mana[blocker], 0);
      },
    );

    for (final count in [0, 1, 3, 4]) {
      test(
        'card_block/$label victim hand size $count and zero mana still permits pass',
        () {
          final hand =
              [
                CardId.prophecy,
                CardId.radar,
                CardId.shelter,
                CardId.chain,
              ].take(count).toList();
          final incoming = cardBlockEdit(
            cardBlockIncoming(
              cardBlockFixture(
                blocker: blocker,
                victimHand: hand,
                victimMana: 0,
              ),
              blocker,
              CardId.prophecy,
            ),
            (d) => d.mana[victim] = 0,
          );
          expect(
            BattleRulesCore.legalActions(
              incoming.view(victim),
            ).whereType<PassAction>().length,
            1,
          );
          final after = DeckManager.apply(incoming, const PassAction());
          _chessWindow(incoming, after, victim);
        },
      );
    }

    test(
      'card_block/$label empty draw pile does not force an impossible card interaction',
      () {
        const consumed = [
          CardId.radar,
          CardId.prophecy,
          CardId.chain,
          CardId.slow,
          CardId.pawnDeviation,
          CardId.pawnAdvance,
          CardId.lockedSquare,
          CardId.freeze,
          CardId.purify,
        ];
        final incoming = cardBlockIncoming(
          cardBlockFixture(
            blocker: blocker,
            target: CardId.shelter,
            victimHand: [CardId.shelter],
            victimUsed: consumed,
          ),
          blocker,
          CardId.shelter,
        );
        expect(incoming.rules.deckCounts[victim], 0);
        _reject(incoming, cardBlockWitness(CardId.shelter, victim));
        final passed = DeckManager.apply(incoming, const PassAction());
        _chessWindow(incoming, passed, victim);
        final moved = DeckManager.apply(
          passed,
          ChessMoveAction(cardBlockMove('g8h8', blocker)),
        );
        expect(moved.rules.handCounts[victim], 1);
        expect(moved.rules.drawCounts[victim], 10);
        _partition(moved);
      },
    );

    for (final geometry in [
      (
        fen: '4k3/8/8/8/8/8/8/K2R4 w - - 0 31',
        move: 'd1e1',
        expected: ['e8d7', 'e8d8', 'e8f7', 'e8f8'],
      ),
      (
        fen: '7k/5K2/8/8/8/8/8/6R1 w - - 0 31',
        move: 'g1g8',
        expected: ['h8h7'],
      ),
    ]) {
      test(
        'card_block/$label checked response ${geometry.move} has literal chess exits',
        () {
          final incoming = cardBlockIncoming(
            cardBlockFixture(blocker: blocker, fen: geometry.fen),
            blocker,
            CardId.prophecy,
            move: geometry.move,
          );
          expect(incoming.rules.terminal, isNull);
          _reject(incoming, const PlayCardAction(CardId.prophecy));
          final after = DeckManager.apply(incoming, const PassAction());
          expect(
            _moves(after),
            geometry.expected.map((m) => cardBlockMove(m, blocker)).toList()
              ..sort(),
          );
          for (final uci in geometry.expected) {
            final moved = DeckManager.apply(
              after,
              ChessMoveAction(cardBlockMove(uci, blocker)),
            );
            expect(moved.rules.board.turn, blocker);
            expect(moved.rules.ply, 2);
            _partition(moved);
          }
        },
      );
    }

    test(
      'card_block/$label terminal chess result is not a stranded card phase',
      () {
        final incoming = cardBlockIncoming(
          cardBlockFixture(
            blocker: blocker,
            fen: '7k/5K2/8/8/8/8/8/6R1 w - - 0 31',
          ),
          blocker,
          CardId.prophecy,
          move: 'g1h1',
        );
        expect(incoming.rules.phase, BattlePhase.terminal);
        expect(incoming.rules.terminal?.reason, 'checkmate');
        expect(incoming.rules.terminal?.winner, blocker);
        expect(BattleRulesCore.legalActions(incoming.view(victim)), isEmpty);
        _reject(incoming, const PassAction());
        _partition(incoming);
      },
    );

    test(
      'card_block/$label online controller rejects blocked play before persistence/transport',
      () async {
        final incoming = cardBlockIncoming(
          cardBlockFixture(blocker: blocker),
          blocker,
          CardId.prophecy,
        );
        var calls = 0;
        final saved = <String?>[];
        final controller = BattleV1Controller(
          uid: victim.isWhite ? 'self' : 'other',
          matchId: v1MatchId,
          initialResponse: _response(incoming, victim),
          persistPending: (json) async {
            saved.add(json);
          },
          request: (_, _) async {
            calls++;
            return _response(incoming, victim);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(const PlayCardAction(CardId.prophecy)),
          isFalse,
        );
        expect(calls, 0);
        expect(saved, isEmpty);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(controller.snapshot!.stateVersion, 40);
        expect(controller.legalActions.whereType<PassAction>().length, 1);
        expect(
          controller.legalActions.whereType<DiscardAction>().map((a) => a.card),
          contains(CardId.prophecy),
        );
      },
    );

    test(
      'card_block/$label controller discard closes block without stuck pending intent',
      () async {
        var state = cardBlockIncoming(
          cardBlockFixture(blocker: blocker),
          blocker,
          CardId.prophecy,
        );
        var version = 40;
        final requests = <Map<String, dynamic>>[];
        final saved = <String?>[];
        final controller = BattleV1Controller(
          uid: victim.isWhite ? 'self' : 'other',
          matchId: v1MatchId,
          initialResponse: _response(state, victim, version: version),
          persistPending: (json) async {
            saved.add(json);
          },
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            requests.add(body);
            // Dart transport double only; the owned TS suite tests real authority.
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(body['intent'] as Map),
            );
            version++;
            return _response(state, victim, version: version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(const DiscardAction(CardId.prophecy)),
          isTrue,
        );
        expect(requests.length, 1);
        expect(requests.single['intent'], {
          'type': 'discard',
          'card': 'prophecy',
        });
        expect(requests.single['expectedStateVersion'], 40);
        expect(saved.length, 2);
        expect(saved.last, isNull);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(controller.view!.rules.modifiers, isEmpty);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
        expect(
          await controller.submit(const DiscardAction(CardId.prophecy)),
          isFalse,
        );
        expect(requests.length, 1);
        _partition(state);
      },
    );
  }
}
