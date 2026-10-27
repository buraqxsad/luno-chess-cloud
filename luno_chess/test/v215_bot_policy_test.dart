import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/bot_policy.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import '../tool/battle_fixture_support.dart';

void main() {
  final fixtures =
      ((jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
                  as Map)['fixtures']
              as List)
          .cast<Map>();
  Map fixture(CardId card) =>
      fixtures.singleWhere((f) => f['fixtureId'] == 'card-${card.wire}');
  PlayerView viewFor(CardId card) =>
      fixtureInitial(fixture(card)).view(PieceColor.white);

  for (final card in CardId.values) {
    test(
      '${card.wire}: six difficulties, seeded legality, finite utility, bounded search',
      () {
        final view = viewFor(card);
        final snapshot = jsonEncode(view.toJson());
        final canonical = BattleAction.fromJson(
          ((fixture(card)['steps'] as List).first as Map)['action'] as Map,
        );
        for (final level in aiLevels) {
          for (final seed in [7, 31, 101]) {
            final result = BattleV1BotPolicy.decide(view, level, Random(seed));
            final legal = BattleRulesCore.legalActions(
              view,
            );
            expect(result.action, isNotNull);
            expect(legal.map((a) => a.key), contains(result.action!.key));
            expect(result.utilities.keys, contains(canonical.key));
            expect(result.utilities.values.every((v) => v.isFinite), isTrue);
            expect(
              result.searchedNodes,
              inInclusiveRange(0, result.nodeBudget),
            );
            final replay = BattleV1BotPolicy.decide(view, level, Random(seed));
            expect(replay.action!.key, result.action!.key);
            expect(replay.utilities, result.utilities);
            expect(jsonEncode(view.toJson()), snapshot);
          }
        }
      },
    );
  }

  test(
    'public enemy Mine locations and repetition history remain available to policy',
    () {
      final original = viewFor(CardId.freeze);
      PlayerView withMine(int square) {
        final draft =
            RuleDraft(original.rules)
              ..boardEffects.add(
                BoardEffectInstance(
                  id: 'public-enemy-mine',
                  type: BoardEffectType.mine,
                  owner: PieceColor.black,
                  squares: [square],
                  responseSide: PieceColor.white,
                  duration: EffectDuration.persistent,
                ),
              );
        draft.repetitions[BattleRulesCore.publicFingerprint(draft.freeze())] = 4;
        return PlayerView(
          draft.freeze(),
          original.viewer,
          original.ownHand,
          original.knowledge,
        );
      }

      final a = withMine(21), b = withMine(42);
      for (final view in [a, b]) {
        expect(BattleV1BotPolicy.planningView(view).toJson(), view.toJson());
        final legal = BattleRulesCore.legalActions(view).map((a) => a.key);
        for (final level in aiLevels) {
          final decision = BattleV1BotPolicy.decide(view, level, Random(33));
          expect(legal, contains(decision.action!.key));
        }
      }
      expect(BattleV1BotPolicy.planningView(a).toJson(), isNot(b.toJson()));
      expect(a.rules.boardEffects.last.squares, [21]);
    },
  );

  test(
    'difficulty affects frequency, target quality and legal search budget',
    () {
      final view = viewFor(CardId.freeze);
      final counts = <int>[], averages = <double>[];
      for (final level in [aiLevels.first, aiLevels.last]) {
        var casts = 0;
        var utility = 0.0;
        for (var seed = 0; seed < 160; seed++) {
          final result = BattleV1BotPolicy.decide(view, level, Random(seed));
          if (result.action is PlayCardAction) {
            casts++;
            utility += result.utilities[result.action!.key]!;
          }
          expect(result.searchedNodes, lessThanOrEqualTo(result.nodeBudget));
        }
        counts.add(casts);
        averages.add(utility / casts);
      }
      expect(counts.first, inInclusiveRange(25, 65));
      expect(counts.last, inInclusiveRange(80, 125));
      expect(counts.last, greaterThan(counts.first));
      expect(averages.last, greaterThan(averages.first));
    },
  );

  for (final card in [CardId.prophecy, CardId.fateExchange]) {
    test(
      '${card.wire}: private pending choice uses known cards and remains legal',
      () {
        final f = fixture(card);
        final state = DeckManager.apply(
          fixtureInitial(f),
          BattleAction.fromJson(
            ((f['steps'] as List).first as Map)['action'] as Map,
          ),
        );
        final view = state.view(PieceColor.white);
        expect(view.rules.phase, BattlePhase.pending);
        final decision = BattleV1BotPolicy.decide(
          view,
          aiLevels.last,
          Random(19),
        );
        expect(decision.action, isA<ResolveAction>());
        final scores = decision.utilities.values.toList()..sort();
        expect(decision.utilities[decision.action!.key], scores.last);
        expect(
          () => DeckManager.apply(state, decision.action!),
          returnsNormally,
        );
      },
    );
  }

  for (final card in [
    CardId.pawnDeviation,
    CardId.pawnAdvance,
    CardId.rookBend,
    CardId.angryN,
    CardId.shadowPass,
  ]) {
    test(
      '${card.wire}: authorized special chess phase is not filtered to ordinary moves',
      () {
        final f = fixture(card);
        final state = DeckManager.apply(
          fixtureInitial(f),
          BattleAction.fromJson(
            ((f['steps'] as List).first as Map)['action'] as Map,
          ),
        );
        final view = state.view(PieceColor.white);
        final result = BattleV1BotPolicy.decide(
          view,
          aiLevels.last,
          Random(11),
        );
        expect(result.action, isA<ChessMoveAction>());
        expect(
          view.rules.special!.moves,
          contains((result.action as ChessMoveAction).uci),
        );
        expect(() => DeckManager.apply(state, result.action!), returnsNormally);
      },
    );
  }
}
