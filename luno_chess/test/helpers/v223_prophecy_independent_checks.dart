// Independently authored cloud replacement, 28 October 2026.
// The original qa/v223/prophecy/independent_checks.dart was not transferred.
// This is not a recovered copy. Expectations come from the retained, manually
// authored geometry cases and Battle V1's inspect/reorder/no-draw contract.
// Engine output is observed below, never used to generate expected answers.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

import 'v223_prophecy_cases.dart';

typedef ProphecyIndependentCase = ({String name, void Function() run});

List<String> _fieldMismatches(
  Map<String, Object?> observed,
  Map<String, Object?> expected,
) => [
  for (final key in expected.keys)
    if (jsonEncode(observed[key]) != jsonEncode(expected[key])) key,
];

void _checkFields(
  Map<String, Object?> observed,
  Map<String, Object?> expected,
) {
  expect(
    _fieldMismatches(observed, expected),
    isEmpty,
    reason: 'Expected independent contract fields: $expected; got $observed',
  );
}

String _sideName(PieceColor side) => side.isWhite ? 'w' : 'b';
List<String> _cards(Iterable<CardId> cards) => [for (final c in cards) c.wire];

// Mirror only the authored UCI rank characters; this expectation does not use
// the engine's Square conversion, board parser, legal move generator or targets.
String _uciForSide(String whiteUci, PieceColor side) =>
    side.isWhite
        ? whiteUci
        : '${whiteUci[0]}${9 - int.parse(whiteUci[1])}'
            '${whiteUci[2]}${9 - int.parse(whiteUci[3])}'
            '${whiteUci.substring(4)}';

List<String> _geometryMismatches(
  Set<String> observed,
  List<String> allowed,
  List<String> forbidden,
) => [
  for (final uci in allowed)
    if (!observed.contains(uci)) 'missing:$uci',
  for (final uci in forbidden)
    if (observed.contains(uci)) 'forbidden:$uci',
];

Map<String, Object?> _accounting(
  AuthoritativeBattleState state,
  PieceColor side,
) => {
  'phase': state.rules.phase.name,
  'turn': _sideName(state.rules.board.turn),
  'mana': state.rules.mana[side],
  'hand': _cards(state.hidden.hands[side]!),
  'deck': _cards(state.hidden.decks[side]!),
  'handCount': state.rules.handCounts[side],
  'deckCount': state.rules.deckCounts[side],
  'drawCount': state.rules.drawCounts[side],
  'ownTurn': state.rules.ownTurns[side],
  'ply': state.rules.ply,
  'used': _cards(state.rules.used[side]!),
  'pendingCard': state.rules.pending?.card.wire,
  'pendingOwner':
      state.rules.pending == null
          ? null
          : _sideName(state.rules.pending!.owner),
  'pendingCards': _cards(state.hidden.knowledge[side]!.pendingCards),
  'knownUpcomingCards': _cards(
    state.hidden.knowledge[side]!.knownUpcomingCards,
  ),
};

Map<String, Object?> _opponentPrivacy(
  AuthoritativeBattleState state,
  PieceColor actor,
) {
  final projection = state.view(actor.opposite).toJson();
  final knowledge = projection['knowledge'] as Map;
  return {
    'projectionKeys': projection.keys.toList()..sort(),
    'viewer': projection['viewer'],
    'ownHand': projection['ownHand'],
    'knowledgeKeys': knowledge.keys.cast<String>().toList()..sort(),
    'pendingCards': knowledge['pendingCards'],
    'knownUpcomingCards': knowledge['knownUpcomingCards'],
    'radarObservations': knowledge['radarObservations'],
  };
}

Map<String, Object?> _expectedOpponentPrivacy(PieceColor actor) => {
  'projectionKeys': ['knowledge', 'ownHand', 'rules', 'viewer'],
  'viewer': actor.isWhite ? 'b' : 'w',
  'ownHand': ['mine', 'freeze', 'purify'],
  'knowledgeKeys': ['knownUpcomingCards', 'pendingCards', 'radarObservations'],
  'pendingCards': <String>[],
  'knownUpcomingCards': <String>[],
  'radarObservations': <Object>[],
};

/// These cases supplement every pre-existing adversarial/recovery/UI assertion.
/// Mutation checks also prove that the expectation families reject an omitted
/// legal move, a forbidden move, extra mana/draw/deck entries, wrong phase/turn,
/// and a private reveal in the opponent's projection.
List<ProphecyIndependentCase> prophecyIndependentCases() {
  final cases = <ProphecyIndependentCase>[];
  for (final side in PieceColor.values) {
    for (final entry in prophecyGeometryExpectations.entries) {
      cases.add((
        name: '${side.name}: independent geometry ${entry.key}',
        run: () {
          final initial = prophecyCase(side: side, position: entry.key);
          final originalFen = initial.rules.fen;
          final allowed = [
            for (final uci in entry.value.allowed) _uciForSide(uci, side),
          ];
          final forbidden = [
            for (final uci in entry.value.forbidden) _uciForSide(uci, side),
          ];
          final resolved = DeckManager.apply(
            prophecyCast(initial),
            ResolveAction([CardId.slow, CardId.chain]),
          );
          for (final state in [initial, resolved]) {
            final actual = prophecyChess(state).toSet();
            expect(_geometryMismatches(actual, allowed, forbidden), isEmpty);
            // The same oracle must fail if either a positive or a negative
            // authored chess expectation is violated, regardless of engine data.
            expect(
              _geometryMismatches(
                {...actual}..remove(allowed.first),
                allowed,
                forbidden,
              ),
              contains('missing:${allowed.first}'),
            );
            expect(
              _geometryMismatches(
                {...actual, forbidden.first},
                allowed,
                forbidden,
              ),
              contains('forbidden:${forbidden.first}'),
            );
            expect(state.rules.fen, originalFen);
          }
        },
      ));
    }

    for (final handCount in [3, 4]) {
      for (final deckCount in [1, 2, 10 - handCount]) {
        for (final alreadyKnown in [false, true]) {
          for (final reverse in [false, true]) {
            cases.add((
              name:
                  '${side.name}: independent accounting hand=$handCount '
                  'deck=$deckCount known=$alreadyKnown reverse=$reverse',
              run: () {
                // The input deck order is the explicit retained fixture list,
                // not an order calculated by DeckManager or legalActions.
                final hand = prophecyDeck.take(handCount).toList();
                final deck =
                    prophecyDeck.skip(handCount).take(deckCount).toList();
                final reveal = deck.take(2).toList();
                final order = reverse ? reveal.reversed.toList() : reveal;
                final initial = prophecyCase(
                  side: side,
                  handCount: handCount,
                  deckCount: deckCount,
                  known: alreadyKnown,
                );
                final initialFen = initial.rules.fen;
                final cast = prophecyCast(initial);
                final expected = <String, Object?>{
                  'phase': 'pending',
                  'turn': _sideName(side),
                  'mana': 5, // Prophecy costs one of the fixture's six mana.
                  'hand': _cards(hand.skip(1)),
                  'deck': _cards(deck),
                  'handCount': handCount - 1,
                  'deckCount': deckCount,
                  'drawCount': handCount,
                  'ownTurn': 4,
                  'ply': 0,
                  'used': ['prophecy'],
                  'pendingCard': 'prophecy',
                  'pendingOwner': _sideName(side),
                  'pendingCards': _cards(reveal),
                  'knownUpcomingCards':
                      alreadyKnown ? _cards(reveal) : <String>[],
                };
                final observed = _accounting(cast, side);
                _checkFields(observed, expected);
                expect(cast.rules.fen, initialFen);
                // A one- or two-card permutation is the complete pending action
                // set; passing, moving, drawing or selecting a card is not one.
                final expectedResolutions = [
                  'resolve::${_cards(reveal).join(',')}',
                  if (reveal.length == 2)
                    'resolve::${_cards(reveal.reversed).join(',')}',
                ]..sort();
                expect(
                  BattleRulesCore.legalActions(
                      cast.view(side),
                    ).map((action) => action.key).toList()
                    ..sort(),
                  expectedResolutions,
                );
                expect(
                  BattleRulesCore.legalActions(cast.view(side.opposite)),
                  isEmpty,
                );

                final resolved = DeckManager.apply(cast, ResolveAction(order));
                final expectedResolved = <String, Object?>{
                  ...expected,
                  'phase': 'chess',
                  'deck': _cards([...order, ...deck.skip(reveal.length)]),
                  'pendingCard': null,
                  'pendingOwner': null,
                  'pendingCards': <String>[],
                  'knownUpcomingCards': _cards(order),
                };
                final observedResolved = _accounting(resolved, side);
                _checkFields(observedResolved, expectedResolved);
                expect(resolved.rules.fen, initialFen);

                // These mutations are deliberately wrong outcomes; accepting
                // any one would mean this independent oracle lost coverage.
                for (final (key, value) in <(String, Object?)>[
                  ('mana', 4),
                  ('hand', _cards(hand)),
                  ('deck', [..._cards(deck), 'mine']),
                  ('drawCount', handCount + 1),
                  ('phase', 'card'),
                  ('turn', side.isWhite ? 'b' : 'w'),
                ]) {
                  expect(
                    _fieldMismatches({
                      ...observedResolved,
                      key: value,
                    }, expectedResolved),
                    contains(key),
                  );
                }
                expect(
                  _fieldMismatches({
                    ...observed,
                    'pendingOwner': side.isWhite ? 'b' : 'w',
                  }, expected),
                  contains('pendingOwner'),
                );
                final privateExpected = _expectedOpponentPrivacy(side);
                for (final state in [initial, cast, resolved]) {
                  final privateObserved = _opponentPrivacy(state, side);
                  _checkFields(privateObserved, privateExpected);
                  expect(
                    _fieldMismatches({
                      ...privateObserved,
                      'pendingCards': _cards(reveal),
                    }, privateExpected),
                    contains('pendingCards'),
                  );
                  expect(
                    _fieldMismatches({
                      ...privateObserved,
                      'knownUpcomingCards': _cards(reveal),
                    }, privateExpected),
                    contains('knownUpcomingCards'),
                  );
                }
              },
            ));
          }
        }
      }
    }
    cases.add((
      name: '${side.name}: empty deck cannot start a reveal or spend mana',
      run: () {
        final initial = prophecyCase(side: side, deckCount: 0);
        final before = jsonEncode(initial.toJson());
        expect(
          BattleRulesCore.legalActions(initial.view(side))
              .whereType<PlayCardAction>()
              .where((action) => action.card == CardId.prophecy),
          isEmpty,
        );
        expect(() => prophecyCast(initial), throwsStateError);
        expect(jsonEncode(initial.toJson()), before);
      },
    ));
  }
  return cases;
}
