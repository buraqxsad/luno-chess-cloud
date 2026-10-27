import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/bot_policy.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';

import '../tool/battle_fixture_support.dart';
import 'helpers/battle_v1_response.dart';

void main() {
  final fixtures =
      ((jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
                  as Map)['fixtures']
              as List)
          .cast<Map>();
  Map fixture(String id) => fixtures.singleWhere((f) => f['fixtureId'] == id);

  for (final owner in PieceColor.values) {
    test('Mine is public after placement and reconnect: ${owner.name}', () {
      final f = fixture('card-mine');
      final fen = (f['fen'] as String).split(' ');
      fen[1] = sideWire(owner);
      final before = fixtureInitial({
        ...f,
        'fen': fen.join(' '),
        'blackDeckOrder': f['whiteDeckOrder'],
      });
      final after = DeckManager.apply(
        before,
        const PlayCardAction(CardId.mine, target: 21),
      );
      expect(after.rules.mana[owner], before.rules.mana[owner]! - 2);
      expect(
        after.rules.boardEffects.single.duration,
        EffectDuration.persistent,
      );
      for (final viewer in PieceColor.values) {
        final uid = viewer.isWhite ? 'self' : 'other';
        final response = v1Response(state: after, version: 1, side: viewer);
        final restored =
            BattleV1Snapshot.fromResponse(
              jsonDecode(jsonEncode(response)) as Map<String, dynamic>,
              uid,
            ).player;
        expect(
          restored.rules.boardEffects.single.toJson(),
          after.rules.boardEffects.single.toJson(),
        );
        expect(restored.rules.boardEffects.single.squares, [21]);
        expect(restored.ownHand, after.hidden.hands[viewer]);
        expect(
          restored.knowledge.toJson(),
          after.hidden.knowledge[viewer]!.toJson(),
        );
        expect(
          restored.toJson().keys,
          unorderedEquals(['rules', 'viewer', 'ownHand', 'knowledge']),
        );
        expect(
          BattleSpellCue.fromViews(
            CardId.mine,
            owner,
            before.view(viewer),
            restored,
          ).squares,
          [21],
        );
      }
    });
  }

  test(
    'Break Seal highlights and previews the same public Mine it removes',
    () {
      final before = fixtureInitial(fixture('card-break_seal'));
      final view = before.view(PieceColor.white);
      final actions = BattleRulesCore.legalActions(view);
      final interaction =
          BattleInteraction()..select(CardId.breakSeal, actions);
      expect(interaction.targets(view, actions), {20});
      expect(interaction.tap(20, view, actions), isEmpty);
      expect(interaction.play!.target, 'trap');
      expect(interaction.preview(), {20});
      final after = DeckManager.apply(before, interaction.play!);
      expect(after.rules.boardEffects, isEmpty);
      expect(after.rules.mana[PieceColor.white], 5);
      for (final viewer in PieceColor.values) {
        expect(
          BattleSpellCue.fromViews(
            CardId.breakSeal,
            PieceColor.white,
            before.view(viewer),
            after.view(viewer),
          ).squares,
          [20],
        );
      }
    },
  );

  for (final kingArrival in [false, true]) {
    test(
      'persistent Mine ignores ${kingArrival ? 'enemy king' : 'own rook'} arrival',
      () {
        final f = jsonDecode(jsonEncode(fixture('mine-watch-castle'))) as Map;
        final rules = (f['setup'] as Map)['rules'] as Map;
        final trap = (rules['boardEffects'] as List).single as Map;
        rules['vows'] = [];
        if (kingArrival) {
          trap['squares'] = [6];
        } else {
          trap['owner'] = 'w';
          trap['responseSide'] = 'b';
        }
        final before = fixtureInitial(f);
        final after = DeckManager.apply(before, const ChessMoveAction('e1g1'));
        expect(
          after.rules.boardEffects.single.toJson(),
          before.rules.boardEffects.single.toJson(),
        );
        expect(after.rules.pieceEffects, isEmpty);
      },
    );
  }

  test(
    'black castling rook triggers public Mine and Watch Vow in the same order',
    () {
      final f = jsonDecode(jsonEncode(fixture('mine-watch-castle'))) as Map;
      f['fen'] = '4k2r/8/8/8/8/8/8/4K3 b k - 0 1';
      final rules = (f['setup'] as Map)['rules'] as Map;
      rules['mana'] = {'w': 1, 'b': 6};
      final trap = (rules['boardEffects'] as List).single as Map;
      trap['owner'] = 'w';
      trap['responseSide'] = 'b';
      trap['squares'] = [61];
      final vow = (rules['vows'] as List).single as Map;
      vow['owner'] = 'w';
      vow['square'] = 61;
      final before = fixtureInitial(f);
      final after = DeckManager.apply(before, const ChessMoveAction('e8g8'));
      expect(after.rules.fen, '5rk1/8/8/8/8/8/8/4K3 w - - 1 2');
      expect(after.rules.boardEffects, isEmpty);
      expect(after.rules.vows, isEmpty);
      expect(after.rules.pieceEffects.single.type, PieceEffectType.mineDebuff);
      expect(after.rules.pieceEffects.single.pieceId, 'r:63');
      expect(after.rules.pieceEffects.single.responseSide, PieceColor.black);
      expect(after.rules.mana[PieceColor.white], 4);
    },
  );

  test('untriggered Mine does not expire at either player turn boundary', () {
    var state = fixtureInitial(fixture('card-mine'));
    state = DeckManager.apply(
      state,
      const PlayCardAction(CardId.mine, target: 21),
    );
    final trap = state.rules.boardEffects.single.toJson();
    for (final action in <BattleAction>[
      const ChessMoveAction('a1b1'),
      const PassAction(),
      const ChessMoveAction('e7e6'),
    ]) {
      state = DeckManager.apply(state, action);
      expect(state.rules.boardEffects.single.toJson(), trap);
    }
  });

  for (final viewer in PieceColor.values) {
    test('AI Mine target set matches authority: ${viewer.name}', () {
      final f = fixture('card-mine');
      final fen = (f['fen'] as String).split(' ');
      fen[1] = sideWire(viewer);
      final initial = fixtureInitial({
        ...f,
        'fen': fen.join(' '),
        'blackDeckOrder': f['whiteDeckOrder'],
      });
      final draft = RuleDraft(initial.rules)
        ..boardEffects.add(
          BoardEffectInstance(
            id: 'enemy-mine',
            type: BoardEffectType.mine,
            owner: viewer.opposite,
            squares: [21],
            responseSide: viewer,
            duration: EffectDuration.persistent,
          ),
        );
      final state = AuthoritativeBattleState(draft.freeze(), initial.hidden);
      final view = state.view(viewer);
      final before = jsonEncode(state.toJson());
      final legal = BattleRulesCore.legalActions(view);
      final legalKeys = legal.map((a) => a.key).toSet();
      expect(
        legal.whereType<PlayCardAction>().where(
          (a) => a.card == CardId.mine && a.target == 21,
        ),
        isEmpty,
      );
      expect(BattleRulesCore.cardTargets(view, CardId.breakSeal), [
        'enemy-mine',
      ]);
      expect(BattleV1BotPolicy.planningView(view).toJson(), view.toJson());
      expect(
        BattleRulesCore.legalActions(
          BattleV1BotPolicy.planningView(view),
        ).map((a) => a.key).toSet(),
        legalKeys,
      );
      for (final level in aiLevels) {
        for (final seed in [7, 31, 101, 219]) {
          final result = BattleV1BotPolicy.decide(view, level, Random(seed));
          expect(result.action, isNotNull);
          expect(legalKeys, contains(result.action!.key));
          expect(result.utilities.keys, unorderedEquals(legalKeys));
          expect(
            () => DeckManager.apply(state, result.action!),
            returnsNormally,
          );
        }
      }
      expect(jsonEncode(state.toJson()), before);
    });
  }

  for (final id in [
    'mine-capture-overlap',
    'fog-mine-overlap',
    'mine-debuff-purify',
    'mine-debuff-piece-captured',
    'mine-watch-castle',
    'persistent-mine',
    'break-one-overlap',
  ]) {
    test(
      'canonical Mine lifecycle remains stable through serialization: $id',
      () {
        final f = fixture(id);
        final expected = runFixture(f);
        var state = fixtureInitial(f);
        for (final value in f['steps'] as List) {
          final step = value as Map;
          state = AuthoritativeBattleState.fromJson(
            jsonDecode(jsonEncode(state.toJson())) as Map,
          );
          if (step['action'] == null) continue;
          final action = BattleAction.fromJson(step['action'] as Map);
          if (step['legal'] == false) {
            final before = state.toJson();
            expect(() => DeckManager.apply(state, action), throwsStateError);
            expect(state.toJson(), before);
          } else {
            state = DeckManager.apply(state, action);
          }
        }
        expect(state.toJson(), expected.toJson());
      },
    );
  }
}
