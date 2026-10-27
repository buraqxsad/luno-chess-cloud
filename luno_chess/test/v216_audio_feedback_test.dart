import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/battle_fixture_support.dart';
import 'battle_v1/core_test.dart' show ready, edit, move;
import 'battle_ui/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
    await LunoSettings.instance.setEffectsLevel(3);
  });
  final fixtures =
      ((jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
                  as Map)['fixtures']
              as List)
          .cast<Map>();
  for (final card in CardId.values) {
    test(
      '${card.wire} canonical accepted action: public identity, no replay',
      () {
        final fixture = fixtures.singleWhere(
          (f) => f['fixtureId'] == 'card-${card.wire}',
        );
        final before = fixtureInitial(fixture);
        final action = BattleAction.fromJson(
          ((fixture['steps'] as List).first as Map)['action'] as Map,
        );
        final after = DeckManager.apply(before, action);
        for (final viewer in PieceColor.values) {
          final oldView = before.view(viewer), newView = after.view(viewer);
          final snapshot = jsonEncode(newView.toJson());
          expect(
            battleSoundCues(oldView, newView),
            contains((
              sound: battleImpactSound(card),
              delayMs: battleImpactDelay(card),
            )),
          );
          expect(battleSoundCues(newView, newView), isEmpty);
          expect(battleSoundCues(newView, oldView), isEmpty);
          expect(jsonEncode(newView.toJson()), snapshot);
        }
      },
    );
  }

  test('two public accepted casts keep both identities', () {
    final before = battleFixture().view(PieceColor.white);
    final draft =
        RuleDraft(before.rules)
          ..used[PieceColor.white]!.add(CardId.radar)
          ..used[PieceColor.black]!.add(CardId.freeze);
    final after = PlayerView(
      draft.freeze(),
      before.viewer,
      before.ownHand,
      before.knowledge,
    );
    final cues = battleSoundCues(before, after);
    expect(
      cues.map((cue) => cue.sound),
      containsAll([LunoSound.cardRadar, LunoSound.cardFreeze]),
    );
  });

  test('coalesced terminal owns audio without a late spell after fanfare', () {
    final before = battleFixture().view(PieceColor.white);
    final draft =
        RuleDraft(before.rules)
          ..used[PieceColor.white]!.add(CardId.boardSeal)
          ..terminal = const TerminalState('resign', winner: PieceColor.white);
    final after = PlayerView(
      draft.freeze(),
      before.viewer,
      before.ownHand,
      before.knowledge,
    );
    expect(battleSoundCues(before, after), [
      (sound: LunoSound.victory, delayMs: 400),
    ]);
  });

  test('opaque enemy mine positions cannot change audio', () {
    final before = battleFixture().view(PieceColor.white);
    PlayerView mineAt(int square) {
      final draft = RuleDraft(before.rules)
        ..boardEffects.add(
          BoardEffectInstance(
            id: 'opaque',
            type: BoardEffectType.mine,
            owner: PieceColor.black,
            squares: [square],
            responseSide: PieceColor.white,
            duration: EffectDuration.pieceMove,
          ),
        );
      return PlayerView(
        draft.freeze(),
        before.viewer,
        before.ownHand,
        before.knowledge,
      );
    }

    expect(battleSoundCues(before, mineAt(21)), isEmpty);
    expect(battleSoundCues(before, mineAt(42)), isEmpty);
    expect(battleSoundCues(mineAt(21), mineAt(42)), isEmpty);
  });

  test('Echo payoff follows the actual accepted response, not mere expiry', () {
    final fixture = fixtures.singleWhere((f) => f['fixtureId'] == 'card-echo');
    var state = fixtureInitial(fixture);
    state = DeckManager.apply(
      state,
      BattleAction.fromJson(
        ((fixture['steps'] as List).first as Map)['action'] as Map,
      ),
    );
    final move =
        BattleRulesCore.legalActions(
          state.view(PieceColor.white),
        ).whereType<ChessMoveAction>().first;
    state = DeckManager.apply(state, move);
    final before = state.view(PieceColor.white);
    final response = BattleRulesCore.legalActions(
      state.view(PieceColor.black),
    ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.radar);
    state = DeckManager.apply(state, response);
    final cues = battleSoundCues(before, state.view(PieceColor.white));
    expect(
      cues,
      contains((
        sound: LunoSound.cardEcho,
        delayMs: battleImpactDelay(CardId.radar),
      )),
    );
    final expired = RuleDraft(before.rules)..modifiers.clear();
    final view = PlayerView(
      expired.freeze(),
      before.viewer,
      before.ownHand,
      before.knowledge,
    );
    expect(battleSoundCues(before, view), isEmpty);
  });

  test('Hunt payoff follows a normal capture and not a special capture', () {
    final state = DeckManager.apply(
      ready([CardId.huntVow], fen: '7k/8/8/8/8/8/p7/R3K3 w - - 0 1'),
      const PlayCardAction(CardId.huntVow, target: 8),
    );
    final after = move(state, 'a1a2');
    for (final viewer in PieceColor.values) {
      expect(
        battleSoundCues(state.view(viewer), after.view(viewer)),
        contains((
          sound: LunoSound.cardHuntVow,
          delayMs: battleImpactDelay(CardId.huntVow),
        )),
      );
      expect(battleSoundCues(after.view(viewer), after.view(viewer)), isEmpty);
    }
    final original = ready([
      CardId.angryN,
    ], fen: '7k/8/8/8/8/8/1p6/1N2K3 w - - 0 1');
    var special = edit(
      original,
      (draft) => draft.vows.add(
        VowState(
          id: 'hunt-special',
          type: VowType.hunt,
          owner: PieceColor.white,
          pieceId: original.rules.pieceIds[9],
          square: null,
          remainingMoves: 2,
        ),
      ),
    );
    special = DeckManager.apply(
      special,
      const PlayCardAction(CardId.angryN, target: 1),
    );
    final specialAfter = move(special, 'b1b2');
    expect(
      battleSoundCues(
        special.view(PieceColor.white),
        specialAfter.view(PieceColor.white),
      ).map((cue) => cue.sound),
      isNot(contains(LunoSound.cardHuntVow)),
    );
  });

  test(
    'Watch payoff follows public square occupancy, silent failed expiry',
    () {
      final fixture = fixtures.singleWhere(
        (f) => f['fixtureId'] == 'mine-watch-castle',
      );
      final before = fixtureInitial(fixture);
      final action = BattleAction.fromJson(
        ((fixture['steps'] as List).first as Map)['action'] as Map,
      );
      final after = DeckManager.apply(before, action);
      for (final viewer in PieceColor.values) {
        expect(
          battleSoundCues(before.view(viewer), after.view(viewer)),
          contains((
            sound: LunoSound.cardWatchVow,
            delayMs: battleImpactDelay(CardId.watchVow),
          )),
        );
      }
      final missed = edit(before, (draft) {
        final vow = draft.vows.single;
        draft.vows = [
          VowState(
            id: vow.id,
            type: vow.type,
            owner: vow.owner,
            pieceId: null,
            square: 20,
            remainingMoves: vow.remainingMoves,
          ),
        ];
      });
      final missedAfter = DeckManager.apply(missed, action);
      expect(
        battleSoundCues(
          missed.view(PieceColor.white),
          missedAfter.view(PieceColor.white),
        ).map((cue) => cue.sound),
        isNot(contains(LunoSound.cardWatchVow)),
      );
    },
  );

  final before = battleFixture().view(PieceColor.white);
  final draft = RuleDraft(before.rules)
    ..used[PieceColor.white]!.add(CardId.freeze);
  final after = PlayerView(
    draft.freeze(),
    before.viewer,
    before.ownHand,
    before.knowledge,
  );
  Widget stage(
    PlayerView view,
    List<LunoSound> sounds, {
    bool enabled = true,
    bool reduced = false,
    int epoch = 0,
  }) => MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: BattleAudioFeedback(
          view: view,
          synchronizationEpoch: epoch,
          play: sounds.add,
          child: const SizedBox(),
        ),
      ),
    ),
  );

  testWidgets('OFF then ON cancels an already scheduled impact', (
    tester,
  ) async {
    final sounds = <LunoSound>[];
    await tester.pumpWidget(stage(before, sounds));
    await tester.pumpWidget(stage(after, sounds));
    expect(sounds, [LunoSound.cardCast]);
    await tester.runAsync(() async {
      await LunoSettings.instance.setEffectsLevel(0);
      await LunoSettings.instance.setEffectsLevel(3);
    });
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, [LunoSound.cardCast]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden then visible cannot revive the impact', (tester) async {
    final sounds = <LunoSound>[];
    await tester.pumpWidget(stage(before, sounds));
    await tester.pumpWidget(stage(after, sounds));
    await tester.pumpWidget(stage(after, sounds, enabled: false));
    await tester.pumpWidget(stage(after, sounds));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, [LunoSound.cardCast]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cast accepted while OFF stays silent after ON', (
    tester,
  ) async {
    final sounds = <LunoSound>[];
    await tester.pumpWidget(stage(before, sounds));
    await tester.runAsync(() => LunoSettings.instance.setEffectsLevel(0));
    await tester.pumpWidget(stage(after, sounds));
    await tester.runAsync(() => LunoSettings.instance.setEffectsLevel(3));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion announces impact without a phantom flight delay',
    (tester) async {
      final sounds = <LunoSound>[];
      await tester.pumpWidget(stage(before, sounds, reduced: true));
      await tester.pumpWidget(stage(after, sounds, reduced: true));
      expect(sounds, [LunoSound.cardFreeze]);
      await tester.pump(const Duration(seconds: 1));
      expect(sounds, [LunoSound.cardFreeze]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('terminal transition cancels older delayed spell tails', (
    tester,
  ) async {
    final sounds = <LunoSound>[];
    await tester.pumpWidget(stage(before, sounds));
    await tester.pumpWidget(stage(after, sounds));
    final terminal = RuleDraft(after.rules)
      ..terminal = const TerminalState('resign', winner: PieceColor.white);
    final result = PlayerView(
      terminal.freeze(),
      after.viewer,
      after.ownHand,
      after.knowledge,
    );
    await tester.pumpWidget(stage(result, sounds));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, [LunoSound.cardCast, LunoSound.victory]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'optional local selection contract emits one cue only on change',
    (tester) async {
      final sounds = <LunoSound>[];
      Widget selection({int? piece, CardId? card, int epoch = 0}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: BattleAudioFeedback(
              view: before,
              synchronizationEpoch: epoch,
              selectedPiece: piece,
              selectedCard: card,
              play: sounds.add,
              child: const SizedBox(),
            ),
          );
      await tester.pumpWidget(selection());
      await tester.pumpWidget(selection(piece: 8));
      await tester.pumpWidget(selection(piece: 8));
      await tester.pumpWidget(selection(piece: 8, card: CardId.freeze));
      await tester.pumpWidget(selection());
      await tester.pumpWidget(selection(piece: 9, epoch: 1));
      expect(sounds, [LunoSound.pieceSelect, LunoSound.cardSelect]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
