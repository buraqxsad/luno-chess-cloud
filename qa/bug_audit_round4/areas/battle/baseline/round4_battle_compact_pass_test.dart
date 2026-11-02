import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/interaction_test.dart' show Harness;

Future<Harness> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 568);
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
      scale: 1.2,
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

VoidCallback _pass(WidgetTester tester) =>
    tester
        .widget<BattleIconControl>(find.byKey(const ValueKey('pass-card')))
        .onPressed!;

void main() {
  setupPracticeTestAssets();

  testWidgets('compact queued pass respects a newly selected card', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final pass = _pass(tester);
    tester.widget<BattleHand>(find.byType(BattleHand)).onSelect(CardId.shelter);
    expect(_selection(tester).card, CardId.shelter);
    pass();
    await tester.pumpAndSettle();
    expect(harness.sent, isEmpty);
    expect(_selection(tester).card, CardId.shelter);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact current pass still submits exactly once', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final pass = _pass(tester);
    pass();
    pass();
    await tester.pumpAndSettle();
    expect(harness.sent.map((action) => action.key), ['pass']);
    expect(tester.takeException(), isNull);
  });
}
