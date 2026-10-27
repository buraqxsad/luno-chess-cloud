import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'battle_ui/fixtures.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

({PlayerView before, PlayerView after}) payoff(CardId card, {bool success = true}) {
  final base = battleFixture(hand: [card, CardId.radar, CardId.shelter]);
  final d = RuleDraft(base.rules)
    ..board = Board.fromFen(card == CardId.huntVow
        ? '4k3/8/8/8/4p3/8/4R3/4K3 w - - 0 1'
        : '4k3/8/8/3p4/8/8/8/4K3 w - - 0 1')
    ..mana[PieceColor.white] = 4;
  d.pieceIds = List.generate(64, (i) => d.board.pieceAt(i) == null ? null : 'v216-p$i');
  var state = AuthoritativeBattleState(d.freeze(), base.hidden);
  void accept(BattleAction action) {
    final legal = BattleRulesCore.legalActions(state.view(state.rules.board.turn));
    expect(legal.map((a) => a.key), contains(action.key),
      reason: '${card.wire} ${state.rules.phase.name} ${state.rules.board.turn}');
    state = DeckManager.apply(state, action);
  }
  accept(PlayCardAction(card, target: card == CardId.huntVow ? 28 : 27));
  if (card == CardId.watchVow) {
    accept(const ChessMoveAction('e1f1'));
    if (state.rules.phase == BattlePhase.card) accept(const PassAction());
  }
  final before = state.view(PieceColor.white);
  accept(ChessMoveAction(card == CardId.huntVow
      ? (success ? 'e2e4' : 'e2a2') : (success ? 'd5d4' : 'e8f8')));
  return (before: before, after: state.view(PieceColor.white));
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async => LunoSettings.instance.load());
  setUp(() => LunoSettings.instance.effectsLevel = 2);
  for (final card in [CardId.huntVow, CardId.watchVow]) {
    test('V216 exact ${card.wire} payoff is public and never inferred from mana', () {
      final pair = payoff(card), before = pair.before.toJson(), after = pair.after.toJson();
      expect(acceptedBattleVowPayoffs(pair.before, pair.after),
        [(card: card, side: PieceColor.white, square: card == CardId.huntVow ? 28 : 27)]);
      expect(acceptedBattleVowPayoffs(pair.after, pair.after), isEmpty);
      expect(acceptedBattleVowPayoffs(pair.after, pair.before), isEmpty);
      final miss = payoff(card, success: false);
      expect(acceptedBattleVowPayoffs(miss.before, miss.after), isEmpty);
      final d = RuleDraft(pair.after.rules)..ply += 1;
      expect(acceptedBattleVowPayoffs(pair.before,
        PlayerView(d.freeze(), pair.after.viewer, pair.after.ownHand, pair.after.knowledge)), isEmpty);
      expect(pair.before.toJson(), before);
      expect(pair.after.toJson(), after);
    });
    for (final reduced in [false, true]) {
      testWidgets('V216 ${card.wire} accepted payoff timing reduced=$reduced', (tester) async {
        final pair = payoff(card), sounds = <LunoSound>[];
        Widget stage(PlayerView view) => shell(BattleAudioFeedback(view: view,
          play: sounds.add, child: const SizedBox()), reduced: reduced);
        await tester.pumpWidget(stage(pair.before));
        await tester.pumpWidget(stage(pair.after));
        if (!reduced) {
          expect(sounds.where((s) => s == battleImpactSound(card)), isEmpty);
          await tester.pump(Duration(milliseconds: battleImpactDelay(card) - 1));
          expect(sounds.where((s) => s == battleImpactSound(card)), isEmpty);
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(sounds.where((s) => s == battleImpactSound(card)), [battleImpactSound(card)]);
        await tester.pumpWidget(stage(pair.after));
        await tester.pump(const Duration(seconds: 1));
        expect(sounds.where((s) => s == battleImpactSound(card)), hasLength(1));
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final cancel in ['epoch', 'hidden', 'mute', 'background', 'terminal', 'dispose']) {
      testWidgets('V216 ${card.wire} payoff cancels on $cancel', (tester) async {
        final pair = payoff(card), sounds = <LunoSound>[];
        Widget stage(PlayerView view, {int epoch = 0, bool visible = true,
            TerminalState? terminal}) => shell(TickerMode(enabled: visible,
          child: BattleAudioFeedback(view: view, synchronizationEpoch: epoch,
            terminal: terminal, play: sounds.add, child: const SizedBox())));
        await tester.pumpWidget(stage(pair.before));
        await tester.pumpWidget(stage(pair.after));
        switch (cancel) {
          case 'epoch': await tester.pumpWidget(stage(pair.after, epoch: 1));
          case 'hidden': await tester.pumpWidget(stage(pair.after, visible: false));
          case 'mute':
            LunoSettings.instance.effectsLevel = 0;
            LunoSettings.instance.notifyListeners();
            LunoSettings.instance.effectsLevel = 2;
            LunoSettings.instance.notifyListeners();
          case 'background': tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          case 'terminal': await tester.pumpWidget(stage(pair.after,
            terminal: const TerminalState('resign', winner: PieceColor.white)));
          case 'dispose': await tester.pumpWidget(const SizedBox());
        }
        await tester.pump(const Duration(seconds: 1));
        expect(sounds.where((s) => s == battleImpactSound(card)), isEmpty);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
