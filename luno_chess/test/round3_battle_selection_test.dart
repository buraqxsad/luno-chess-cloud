import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/interaction_test.dart' show Harness;

Future<Harness> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final harness = Harness();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    harness.controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  await tester.pumpWidget(
    shell(
      BattleV1Screen(
        controllerOverride: harness.controller,
        clockOverride: (_) => 300000,
      ),
      language: 'en',
      reduced: true,
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

BattleInteraction _selection(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(BattleV1Screen));
  return state.selection as BattleInteraction;
}

VoidCallback _command(WidgetTester tester, String key) =>
    tester.widget<BattleCommand>(find.byKey(ValueKey(key))).onPressed!;

Future<void> _shelterTarget(WidgetTester tester, int square) async {
  tester.widget<BattleHand>(find.byType(BattleHand)).onSelect(CardId.shelter);
  await tester.pumpAndSettle();
  tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(square);
  await tester.pumpAndSettle();
  expect(_selection(tester).play?.key, 'play:shelter:$square:');
}

void main() {
  setupPracticeTestAssets();

  testWidgets('same-frame target change rejects the previous cast command', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _shelterTarget(tester, 12);
    final confirm = _command(tester, 'play-card');
    // Both inputs arrive before the next frame. The old widget still carries
    // e2, while the interaction model has already accepted d2 as the target.
    tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(11);
    expect(_selection(tester).play?.key, 'play:shelter:11:');
    confirm();
    await tester.pumpAndSettle();
    expect(harness.sent, isEmpty);
    expect(_selection(tester).play?.key, 'play:shelter:11:');
    expect(tester.takeException(), isNull);
  });

  testWidgets('current cast command accepts the newly painted target', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _shelterTarget(tester, 12);
    tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(11);
    await tester.pumpAndSettle();
    _command(tester, 'play-card')();
    await tester.pumpAndSettle();
    expect(harness.sent.map((action) => action.key), ['play:shelter:11:']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unchanged selection keeps its command across harmless rebuilds',
    (tester) async {
      final harness = await _mount(tester);
      await _shelterTarget(tester, 12);
      final confirm = _command(tester, 'play-card');
      await harness.controller.reconnect();
      await tester.pumpAndSettle();
      expect(_selection(tester).play?.key, 'play:shelter:12:');
      confirm();
      await tester.pumpAndSettle();
      expect(harness.sent.map((action) => action.key), ['play:shelter:12:']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-frame card change rejects the previous discard command', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _shelterTarget(tester, 12);
    final discard =
        tester
            .widget<TextButton>(find.byKey(const ValueKey('discard-card')))
            .onPressed!;
    tester.widget<BattleHand>(find.byType(BattleHand)).onSelect(CardId.chain);
    expect(_selection(tester).card, CardId.chain);
    discard();
    await tester.pumpAndSettle();
    expect(harness.sent, isEmpty);
    expect(_selection(tester).card, CardId.chain);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current discard command accepts the newly selected card', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _shelterTarget(tester, 12);
    tester.widget<BattleHand>(find.byType(BattleHand)).onSelect(CardId.chain);
    await tester.pumpAndSettle();
    tester
        .widget<TextButton>(find.byKey(const ValueKey('discard-card')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(harness.sent.map((action) => action.key), ['discard:chain']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame card selection rejects the previous pass command', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final pass = _command(tester, 'pass-card');
    tester.widget<BattleHand>(find.byType(BattleHand)).onSelect(CardId.shelter);
    expect(_selection(tester).card, CardId.shelter);
    pass();
    await tester.pumpAndSettle();
    expect(harness.sent, isEmpty);
    expect(_selection(tester).card, CardId.shelter);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current pass command accepts an explicitly unselected phase', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _shelterTarget(tester, 12);
    tester
        .widget<BattleIconControl>(find.byKey(const ValueKey('cancel-card')))
        .onPressed!();
    await tester.pumpAndSettle();
    _command(tester, 'pass-card')();
    await tester.pumpAndSettle();
    expect(harness.sent.map((action) => action.key), ['pass']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced version rejects a retained otherwise legal cast', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _shelterTarget(tester, 11);
    final confirm = _command(tester, 'play-card');
    // A reconnect can legitimately skip the rest of a turn and the opponent's
    // reply. Shelter is still in hand and d2 remains a legal target next turn.
    for (final action in const <BattleAction>[
      PassAction(),
      ChessMoveAction('e2e4'),
      ChessMoveAction('e7e5'),
    ]) {
      expect(
        BattleRulesCore.isLegalAction(
          harness.state.view(harness.state.rules.board.turn),
          action,
        ),
        isTrue,
      );
      harness.state = DeckManager.apply(harness.state, action);
      harness.version++;
    }
    await harness.controller.reconnect();
    expect(_selection(tester).card, isNull);
    confirm();
    await tester.pumpAndSettle();
    expect(harness.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
