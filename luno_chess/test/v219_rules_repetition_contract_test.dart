import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

import '../tool/battle_fixture_support.dart';

void main() {
  final fixtures =
      ((jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
                  as Map)['fixtures']
              as List)
          .cast<Map>();
  Map fixture(String id) => fixtures.singleWhere((f) => f['fixtureId'] == id);
  final base = fixtureInitial(fixture('card-mine')).rules;
  RuleState changed(
    void Function(Map<String, dynamic>) edit, [
    RuleState? rules,
  ]) {
    final json =
        jsonDecode(jsonEncode((rules ?? base).toJson()))
            as Map<String, dynamic>;
    edit(json);
    return RuleState.fromJson(json);
  }

  String key(RuleState rules) => BattleRulesCore.publicFingerprint(rules);

  final changes = <String, void Function(Map<String, dynamic>)>{
    'mana': (j) => (j['mana'] as Map)['w'] = 5,
    'hand counts': (j) => (j['handCounts'] as Map)['w'] = 2,
    'deck counts': (j) => (j['deckCounts'] as Map)['w'] = 6,
    'draw counts': (j) => (j['drawCounts'] as Map)['w'] = 4,
    'used cards': (j) => (j['used'] as Map)['w'] = ['shelter'],
    'discarded cards': (j) => (j['discarded'] as Map)['w'] = ['shelter'],
    'moved pawn rights': (j) => j['movedPawns'] = ['P:8'],
    'piece identity': (j) => (j['pieceIds'] as List)[0] = 'promoted-rook',
    'piece effect':
        (j) =>
            j['pieceEffects'] = [
              {
                'id': 'chain',
                'type': 'chain',
                'owner': 'b',
                'pieceId': 'R:0',
                'responseSide': 'w',
                'duration': 'move',
              },
            ],
    'public Mine':
        (j) =>
            j['boardEffects'] = [
              {
                'id': 'mine',
                'type': 'mine',
                'owner': 'b',
                'squares': [21],
                'responseSide': 'w',
                'duration': 'persistent',
              },
            ],
    'modifier':
        (j) =>
            j['modifiers'] = [
              {
                'id': 'sabotage',
                'type': 'mana_sabotage',
                'owner': 'b',
                'responseSide': 'w',
                'targetCard': 'mine',
                'ownTurn': 2,
              },
            ],
    'castling rights': (j) {
      final fen = (j['fen'] as String).split(' ');
      fen[2] = '-';
      j['fen'] = fen.join(' ');
    },
    'first-turn phase': (j) {
      j['phase'] = 'chess';
      (j['ownTurns'] as Map)['w'] = 1;
    },
  };
  for (final entry in changes.entries) {
    test('Luno repetition distinguishes ${entry.key}', () {
      expect(key(changed(entry.value)), isNot(key(base)));
    });
  }

  test('public Mine location is part of repetition, not secret state', () {
    final first = changed(changes['public Mine']!);
    final second = changed((j) {
      ((j['boardEffects'] as List).single as Map)['squares'] = [22];
    }, first);
    expect(key(first), isNot(key(second)));
  });

  test(
    'absolute counters and repetition history do not change equivalence',
    () {
      final other = changed((j) {
        final fen = (j['fen'] as String).split(' ');
        fen[4] = '99';
        fen[5] = '42';
        j['fen'] = fen.join(' ');
        j['ownTurns'] = {'w': 12, 'b': 12};
        j['ply'] = 82;
        j['effectSequence'] = 99;
        j['repetitions'] = {'historical-public-position': 4};
      });
      expect(key(other), key(base));
    },
  );

  test('modifier timing is relative to the response side own turn', () {
    final modifier = changed(changes['modifier']!);
    final shifted = changed((j) {
      j['ownTurns'] = {'w': 12, 'b': 12};
      ((j['modifiers'] as List).single as Map)['ownTurn'] = 12;
    }, modifier);
    expect(key(shifted), key(modifier));
    expect(
      key(
        changed((j) {
          ((j['modifiers'] as List).single as Map)['ownTurn'] = 13;
        }, shifted),
      ),
      isNot(key(modifier)),
    );
  });

  test('EP contributes only when legal under chess and card restrictions', () {
    final ep =
        fixtureInitial({
          ...fixture('card-mine'),
          'fen': '7k/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
        }).rules;
    RuleState withoutEp(RuleState s) => changed((j) {
      final fen = (j['fen'] as String).split(' ');
      fen[3] = '-';
      j['fen'] = fen.join(' ');
    }, s);
    expect(key(ep), isNot(key(withoutEp(ep))));
    final chained = changed(
      (j) =>
          j['pieceEffects'] = [
            {
              'id': 'chain',
              'type': 'chain',
              'owner': 'b',
              'pieceId': 'P:36',
              'responseSide': 'w',
              'duration': 'move',
            },
          ],
      ep,
    );
    expect(key(chained), key(withoutEp(chained)));
  });

  test('intermediate card resolution never records a repetition', () {
    expect(() => key(changed((j) => j['phase'] = 'chess')), throwsStateError);
    expect(
      () => key(
        changed((j) {
          j['phase'] = 'pending';
          j['pending'] = {'card': 'prophecy', 'owner': 'w'};
        }),
      ),
      throwsStateError,
    );
  });

  for (final card in CardId.values) {
    test(
      '${card.wire}: private hand/deck order cannot alter public repetition',
      () {
        final original = fixtureInitial(fixture('card-${card.wire}'));
        final json = jsonDecode(jsonEncode(original.toJson())) as Map;
        final hidden = json['hidden'] as Map;
        for (final side in ['w', 'b']) {
          for (final field in ['hands', 'decks']) {
            final pair = hidden[field] as Map;
            pair[side] = (pair[side] as List).reversed.toList();
          }
        }
        final other = AuthoritativeBattleState.fromJson(json);
        expect(key(other.rules), key(original.rules));
        final viewer = original.rules.board.turn;
        final opponentOnly = jsonDecode(jsonEncode(original.toJson())) as Map;
        final enemy = sideWire(viewer.opposite);
        final enemyHidden = opponentOnly['hidden'] as Map;
        final hands = enemyHidden['hands'] as Map;
        final decks = enemyHidden['decks'] as Map;
        final handCount = (hands[enemy] as List).length;
        final cards =
            <Object?>[
              ...(hands[enemy] as List),
              ...(decks[enemy] as List),
            ].reversed.toList();
        hands[enemy] = cards.take(handCount).toList();
        decks[enemy] = cards.skip(handCount).toList();
        (enemyHidden['knowledge'] as Map)[enemy] =
            PlayerKnowledgeState(
              knownUpcomingCards: parseCards(
                (decks[enemy] as List).take(2).toList(),
              ),
            ).toJson();
        final redacted = AuthoritativeBattleState.fromJson(
          opponentOnly,
        ).view(viewer);
        expect(redacted.toJson(), original.view(viewer).toJson());
        expect(
          BattleRulesCore.legalActions(redacted).map((a) => a.key),
          orderedEquals(
            BattleRulesCore.legalActions(
              original.view(viewer),
            ).map((a) => a.key),
          ),
        );
      },
    );
  }

  test(
    'private knowledge is excluded while legitimate own knowledge stays visible',
    () {
      final original = fixtureInitial(fixture('card-prophecy'));
      final json = jsonDecode(jsonEncode(original.toJson())) as Map;
      final hidden = json['hidden'] as Map;
      final ownDeck = (hidden['decks'] as Map)['w'] as List;
      (hidden['knowledge'] as Map)['w'] =
          PlayerKnowledgeState(
            knownUpcomingCards: parseCards(ownDeck.take(2).toList()),
          ).toJson();
      final other = AuthoritativeBattleState.fromJson(json);
      expect(key(other.rules), key(original.rules));
      expect(
        other.view(PieceColor.white).knowledge.knownUpcomingCards,
        orderedEquals(parseCards(ownDeck.take(2).toList())),
      );
      expect(
        other.view(PieceColor.black).toJson(),
        original.view(PieceColor.black).toJson(),
      );
    },
  );

  test('canonical finite-deck fivefold remains automatic after reconnect', () {
    final f = fixture('finite-deck-fivefold');
    var state = fixtureInitial(f);
    for (final value in f['steps'] as List) {
      final step = value as Map;
      if (step['action'] == null) continue;
      state = AuthoritativeBattleState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map,
      );
      final before = state;
      state = DeckManager.apply(
        state,
        BattleAction.fromJson(step['action'] as Map),
      );
      if (state.rules.terminal != null) {
        expect(state.rules.drawCounts, before.rules.drawCounts);
        expect(state.rules.handCounts, before.rules.handCounts);
      }
    }
    expect(state.toJson(), runFixture(f).toJson());
    expect(state.rules.terminal!.reason, 'fivefold');
    expect(state.rules.deckCounts.values, everyElement(0));
    for (final viewer in PieceColor.values) {
      expect(BattleRulesCore.legalActions(state.view(viewer)), isEmpty);
    }
  });
}
