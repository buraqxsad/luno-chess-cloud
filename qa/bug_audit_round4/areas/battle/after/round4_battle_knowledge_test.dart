import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/interaction_test.dart' show Harness;

void _advance(Harness harness, BattleAction action) {
  final view = harness.state.view(harness.state.rules.board.turn);
  expect(BattleRulesCore.isLegalAction(view, action), isTrue);
  harness.state = DeckManager.apply(harness.state, action);
  harness.version++;
}

Future<Harness> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final harness = Harness(
    hand: const [CardId.prophecy, CardId.shelter, CardId.chain],
  );
  _advance(harness, const PlayCardAction(CardId.prophecy));
  final order = harness.state.view(PieceColor.white).knowledge.pendingCards;
  _advance(harness, ResolveAction(order));
  await harness.controller.reconnect();
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
  expect(harness.controller.view!.knowledge.knownUpcomingCards, hasLength(2));
  return harness;
}

VoidCallback _open(WidgetTester tester) =>
    tester
        .widget<BattleKnowledgePreview>(find.byType(BattleKnowledgePreview))
        .onOpen!;

Future<void> _drawNext(Harness harness) async {
  _advance(harness, const ChessMoveAction('e2e4'));
  _advance(harness, const ChessMoveAction('e7e5'));
  await harness.controller.reconnect();
}

void main() {
  setupPracticeTestAssets();

  testWidgets('queued knowledge opener cannot restore a consumed deck order', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final open = _open(tester);
    final before = harness.controller.view!.knowledge.knownUpcomingCards;
    await _drawNext(harness);
    final current = harness.controller.view!.knowledge.knownUpcomingCards;
    expect(current, before.skip(1));
    expect(harness.controller.view!.ownHand, contains(before.first));
    // The snapshot changes before Flutter paints the next frame. This opener
    // still belongs to the previously painted two-card forecast.
    open();
    await tester.pumpAndSettle();
    final sheets = tester.widgetList<PrivateKnowledgeSheet>(
      find.byType(PrivateKnowledgeSheet),
    );
    for (final sheet in sheets) {
      expect(sheet.knowledge.knownUpcomingCards, current);
    }
    expect(harness.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current knowledge opener shows the remaining deck order', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _drawNext(harness);
    await tester.pumpAndSettle();
    _open(tester)();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PrivateKnowledgeSheet>(find.byType(PrivateKnowledgeSheet))
          .knowledge
          .knownUpcomingCards,
      harness.controller.view!.knowledge.knownUpcomingCards,
    );
    expect(harness.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queued own deck opener cannot restore old hand membership', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final open =
        tester
            .widget<IconButton>(find.byKey(const ValueKey('open-own-deck')))
            .onPressed!;
    final before = harness.controller.view!.ownHand.toSet();
    await _drawNext(harness);
    final current = harness.controller.view!.ownHand.toSet();
    expect(current.difference(before), hasLength(1));
    open();
    await tester.pumpAndSettle();
    final sheets = tester.widgetList<OpponentArsenalSheet>(
      find.byType(OpponentArsenalSheet),
    );
    for (final sheet in sheets) {
      expect(sheet.ownHand, current);
      expect(sheet.rules.deckCounts, harness.controller.view!.rules.deckCounts);
    }
    expect(harness.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current own deck opener shows the newly drawn hand membership', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await _drawNext(harness);
    await tester.pumpAndSettle();
    tester
        .widget<IconButton>(find.byKey(const ValueKey('open-own-deck')))
        .onPressed!();
    await tester.pumpAndSettle();
    final sheet = tester.widget<OpponentArsenalSheet>(
      find.byType(OpponentArsenalSheet),
    );
    expect(sheet.ownHand, harness.controller.view!.ownHand.toSet());
    expect(sheet.rules.deckCounts, harness.controller.view!.rules.deckCounts);
    expect(harness.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged knowledge remains openable after a harmless refresh', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final open = _open(tester);
    await harness.controller.reconnect();
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PrivateKnowledgeSheet>(find.byType(PrivateKnowledgeSheet))
          .knowledge
          .knownUpcomingCards,
      harness.controller.view!.knowledge.knownUpcomingCards,
    );
    expect(harness.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
