import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/visual_test.dart' show renderBattle, visualTap, editedFixture;
import 'v214_vfx_review_test.dart' as review;

class FlightHarness {
  final board = GlobalKey(), own = GlobalKey(), opponent = GlobalKey();
  final cards = {for (final card in CardId.values) card: GlobalKey()};
  Widget build(PlayerView view, {int epoch = 0, bool reduced = false,
      bool visible = true}) => shell(TickerMode(enabled: visible,
    child: SizedBox.expand(child: BattleCastStage(
      view: view, board: board, own: own, opponent: opponent, cards: cards,
      synchronizationEpoch: epoch,
      child: Stack(children: [
        Positioned(top: 30, left: 150, child: SizedBox(key: opponent, width: 100, height: 40)),
        Positioned(top: 100, left: 34, child: SizedBox(key: board, width: 332, height: 332)),
        Positioned(top: 550, left: 150, child: SizedBox(key: own, width: 100, height: 40)),
        for (var i = 0; i < view.ownHand.length; i++)
          Positioned(top: 650, left: i * 100.0, child: SizedBox(
            key: cards[view.ownHand[i]], width: 80, height: 100)),
      ]),
    )),
  ), reduced: reduced);
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
    await GameStore.instance.load();
    review.fixtures = ((jsonDecode(File('../battle_contract/v1/rules.json')
      .readAsStringSync()) as Map)['fixtures'] as List).cast<Map>();
  });
  testWidgets('V216 screen wires card and piece selection into audio', (tester) async {
    await renderBattle(tester);
    await visualTap(tester, 'hand-shelter');
    expect(tester.widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
      .selectedCard, CardId.shelter);
    await tester.pumpWidget(const SizedBox());
    await renderBattle(tester, state: editedFixture((d) => d.phase = BattlePhase.chess));
    await visualTap(tester, 'square-12');
    expect(tester.widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
      .selectedPiece, 12);
    await tester.pumpWidget(const SizedBox());
  });
  test('V216 public effect target retains its chosen square preview', () {
    final pair = review.cast(CardId.breakSeal), view = pair.before.view(PieceColor.white);
    final legal = BattleRulesCore.legalActions(view);
    final selection = BattleInteraction()..select(CardId.breakSeal, legal);
    selection.tap(20, view, legal);
    expect(selection.play, isNotNull);
    expect(selection.preview(), {20});
    selection.cancel();
    expect(selection.preview(), isEmpty);
  });
  testWidgets('V216 Echo flight reaches opponent not caster resource', (tester) async {
    final h = FlightHarness(), pair = review.cast(CardId.echo);
    await tester.pumpWidget(h.build(pair.before.view(PieceColor.white)));
    await tester.pump();
    await tester.pumpWidget(h.build(pair.after.view(PieceColor.white)));
    await tester.pump();
    await tester.pump(Duration(milliseconds: battleImpactDelay(CardId.echo)));
    final flight = tester.widget<Positioned>(find.byKey(const ValueKey('card-flight-echo')));
    expect(flight.top! + 38, closeTo(50, .1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 mixed rarity source flight keeps its own impact deadline', (tester) async {
    final h = FlightHarness();
    var state = review.cast(CardId.boardSeal).before;
    final before = state.view(PieceColor.white);
    state = DeckManager.apply(state, BattleRulesCore.legalActions(state.view(PieceColor.white))
      .whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.radar));
    state = DeckManager.apply(state, BattleRulesCore.legalActions(state.view(PieceColor.white))
      .whereType<ChessMoveAction>().first);
    state = DeckManager.apply(state, const PassAction());
    state = DeckManager.apply(state, BattleRulesCore.legalActions(state.view(PieceColor.black))
      .whereType<ChessMoveAction>().first);
    state = DeckManager.apply(state, BattleRulesCore.legalActions(state.view(PieceColor.white))
      .whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.boardSeal));
    await tester.pumpWidget(h.build(before));
    await tester.pump();
    await tester.pumpWidget(h.build(state.view(PieceColor.white)));
    await tester.pump();
    await tester.pump(Duration(milliseconds: battleImpactDelay(CardId.radar)));
    final radar = tester.widget<Positioned>(find.byKey(const ValueKey('card-flight-radar')));
    expect(radar.top! + 38, closeTo(50, .1));
    await tester.pump(const Duration(milliseconds: 480 - 365));
    expect(find.byKey(const ValueKey('card-flight-radar')), findsNothing);
    expect(find.byKey(const ValueKey('card-flight-board_seal')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 epoch hidden and reduced motion cancel queued source flights', (tester) async {
    final pair = review.cast(CardId.freeze), h = FlightHarness();
    final before = pair.before.view(PieceColor.white), after = pair.after.view(PieceColor.white);
    await tester.pumpWidget(h.build(before));
    await tester.pump();
    await tester.pumpWidget(h.build(after, epoch: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
    await tester.pumpWidget(h.build(before, epoch: 2));
    await tester.pump();
    await tester.pumpWidget(h.build(after, epoch: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('card-flight-freeze')), findsOneWidget);
    await tester.pumpWidget(h.build(after, epoch: 2, visible: false));
    await tester.pumpWidget(h.build(after, epoch: 2));
    expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
    await tester.pumpWidget(h.build(before, epoch: 3));
    await tester.pumpWidget(h.build(after, epoch: 3, reduced: true));
    expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 account transition clears the old private battle surface', (tester) async {
    final store = GameStore.instance;
    await tester.runAsync(() async {
      await store.flush();
      await store.bindAccount('v216-battle-first');
    });
    await renderBattle(tester);
    await visualTap(tester, 'hand-shelter');
    expect(find.byType(BattleBoard), findsOneWidget);
    await tester.runAsync(() => store.bindAccount('v216-battle-second'));
    await tester.pumpAndSettle();
    expect(find.byType(BattleBoard), findsNothing);
    expect(find.byType(BattleAudioFeedback), findsNothing);
    await tester.runAsync(() => store.bindAccount('v216-battle-first'));
    await tester.pumpAndSettle();
    expect(find.byType(BattleBoard), findsNothing,
      reason: 'Returning to the old account must not revive a stale match surface');
    await tester.pumpWidget(const SizedBox());
  });
  test('V216 duplicate public identities do not duplicate accepted casts', () {
    final pair = review.cast(CardId.freeze), after = pair.after.view(PieceColor.white);
    final d = RuleDraft(after.rules)..used[PieceColor.white]!.add(CardId.freeze);
    final duplicate = PlayerView(d.freeze(), after.viewer, after.ownHand, after.knowledge);
    expect(acceptedBattleCasts(pair.before.view(PieceColor.white), duplicate),
      [(card: CardId.freeze, side: PieceColor.white)]);
  });
  testWidgets('V216 board epoch clears already active accepted VFX', (tester) async {
    final pair = review.cast(CardId.freeze);
    Widget board(PlayerView view, int epoch) => shell(Center(child: SizedBox.square(
      dimension: 332, child: BattleBoard(view: view, synchronizationEpoch: epoch,
        onTap: (_) {}))));
    await tester.pumpWidget(board(pair.before.view(PieceColor.white), 0));
    await tester.pumpWidget(board(pair.after.view(PieceColor.white), 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('spell-freeze-0')), findsOneWidget);
    await tester.pumpWidget(board(pair.after.view(PieceColor.white), 1));
    expect(find.byKey(const ValueKey('spell-freeze-0')), findsNothing);
    await tester.pumpWidget(board(pair.after.view(PieceColor.white), 1));
    expect(find.byKey(const ValueKey('spell-freeze-0')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
