import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/lifecycle_accessibility_test.dart' show app;
import 'v214_active_deck_test.dart' show setup, reply;
import 'battle_deck_account_test.dart' show response;

void main() {
  setupPracticeTestAssets();
  testWidgets('covered local battle does not resume bot until visible', (
    tester,
  ) async {
    final (store, online, _) = await setup((_) async => reply(response()));
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    await online.getBattleV1Deck();
    await tester.pumpWidget(app(BattleV1Screen(deckOnline: online)));
    await tester.pump();
    await tester.pump();
    final dynamic state = tester.state(find.byType(BattleV1Screen));
    final session = state.localSession as BattleV1LocalSession;
    final first = session.legalActions.whereType<ChessMoveAction>().first;
    expect(await session.submit(first), true);
    expect(session.view.rules.board.turn, PieceColor.black);
    final navigator = Navigator.of(tester.element(find.byType(BattleV1Screen)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(session.view.rules.board.turn, PieceColor.black);
    expect(find.text('Cover'), findsOneWidget);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(session.version, greaterThan(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
