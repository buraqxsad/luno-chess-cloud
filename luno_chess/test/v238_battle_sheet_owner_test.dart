import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart' show renderBattle;

Future<VoidCallback> _mountBattle(WidgetTester tester, String owner) async {
  // Create the singleton and its initial account queue in the same real async
  // zone as binding. A fake-zone Future.value would wait for a pump while
  // runAsync itself is waiting for that future.
  final store =
      (await tester.runAsync(() async {
        final store = GameStore.instance;
        await store.bindAccount(owner);
        return store;
      }))!;
  store
    ..loaded = true
    ..data = PlayerData.initial()
    ..hasCompletedTutorial = true
    ..hasChosenUsername = true
    ..firstSessionMatchesStarted = 2;
  await renderBattle(tester);
  final deck = find.byKey(const ValueKey('open-own-deck'));
  await tester.ensureVisible(deck);
  await tester.pumpAndSettle();
  return tester.widget<IconButton>(deck).onPressed!;
}

Future<void> _changeOwner(WidgetTester tester, String owner) async {
  await tester.runAsync(() => GameStore.instance.bindAccount(owner));
}

void main() {
  setupPracticeTestAssets();

  for (final phase in ['before first render', 'after first render']) {
    testWidgets('account change hides private battle sheet $phase', (
      tester,
    ) async {
      final open = await _mountBattle(tester, 'v238-sheet-$phase-a');
      open();
      final dynamic state = tester.state(find.byType(BattleV1Screen));
      if (phase == 'before first render') {
        expect(state.sheetOpen, isTrue);
        expect(state.sheetRoute, isNull);
      } else {
        await tester.pumpAndSettle();
        expect(find.byType(OpponentArsenalSheet), findsOneWidget);
      }

      bool? privateChildAtPaint;
      // Register before ownership changes enqueue exact-route cleanup. This
      // observes the first painted tree before that cleanup could hide a leak.
      tester.binding.addPostFrameCallback((_) {
        privateChildAtPaint =
            find
                .byType(OpponentArsenalSheet, skipOffstage: false)
                .evaluate()
                .isNotEmpty;
      });
      await _changeOwner(tester, 'v238-sheet-$phase-b');
      await tester.pump();
      expect(privateChildAtPaint, isFalse);
      expect(
        find.byType(OpponentArsenalSheet, skipOffstage: false),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(state.sheetOpen, isFalse);
      expect(find.byType(BattleBoard), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(BattleV1Screen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'unbuilt stale private sheet removes only its own covered route',
    (tester) async {
      final open = await _mountBattle(tester, 'v238-covered-sheet-a');
      final navigator = Navigator.of(
        tester.element(find.byType(BattleV1Screen)),
      );
      open();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('New unrelated screen')),
          ),
        ),
      );
      await _changeOwner(tester, 'v238-covered-sheet-b');
      await tester.pumpAndSettle();
      expect(find.text('New unrelated screen'), findsOneWidget);
      expect(
        find.byType(OpponentArsenalSheet, skipOffstage: false),
        findsNothing,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      expect(navigator.canPop(), isFalse);
      expect(find.byType(BattleBoard), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'old sheet callback stays inert when its original account returns',
    (tester) async {
      const owner = 'v238-returned-sheet-a';
      final open = await _mountBattle(tester, owner);
      open();
      await _changeOwner(tester, 'v238-returned-sheet-b');
      await tester.pumpAndSettle();
      await _changeOwner(tester, owner);
      open();
      await tester.pumpAndSettle();
      expect(
        find.byType(OpponentArsenalSheet, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(BattleBoard), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(BattleV1Screen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
