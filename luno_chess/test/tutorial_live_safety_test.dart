import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, warm, noOverflow;

void main() {
  setupPracticeTestAssets();

  for (final language in ['tr', 'en']) {
    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(360, 640), 1.6),
      (const Size(430, 932), 2.0),
    ]) {
      testWidgets('welcome real taps advance, persist and grant nothing: '
          '$language $size text$scale', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = GameStore.createForTesting();
        addTearDown(store.dispose);
        await tester.runAsync(store.load);
        // Use a canonical profile name: default-name normalization on reload
        // is an existing profile rule, separate from tutorial/economy changes.
        store.data.username = 'tutoriallearner';
        final before = jsonEncode(store.data.toJson());
        await tester.pumpWidget(
          shell(
            BattleWelcomeScreen(playerStore: store),
            language: language,
            scale: scale,
            reduced: true,
          ),
        );
        await warm(tester);

        for (var step = 0; step < GameStore.welcomeStepCount; step++) {
          expect(store.welcomeStep, step);
          final next = find.byKey(const ValueKey('welcome-next'));
          expect(next.hitTestable(), findsOneWidget);
          final oldCallback = tester.widget<BattleCommand>(next).onPressed!;
          await tester.tap(next);
          // A callback queued from the prior frame must not skip the next
          // instruction, even before the persistence future has completed.
          oldCallback();
          await tester.pumpAndSettle();
          expect(store.welcomeStep, step + 1);
          noOverflow(tester);
          expect(store.hasCompletedTutorial, isFalse);
          expect(jsonEncode(store.data.toJson()), before);
        }

        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.flush);
        final restored = GameStore.createForTesting();
        addTearDown(restored.dispose);
        await tester.runAsync(restored.load);
        expect(restored.welcomeStep, GameStore.welcomeStepCount);
        expect(restored.hasCompletedTutorial, isFalse);
        expect(jsonEncode(restored.data.toJson()), before);
      });
    }
  }

  testWidgets('welcome cannot advance while paused or covered, then resumes', (
    tester,
  ) async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await tester.runAsync(store.load);
    await tester.pumpWidget(
      shell(BattleWelcomeScreen(playerStore: store), reduced: true),
    );
    await warm(tester);
    final next = find.byKey(const ValueKey('welcome-next'));
    final callback = tester.widget<BattleCommand>(next).onPressed!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    callback();
    expect(store.welcomeStep, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final navigator = Navigator.of(
      tester.element(find.byType(BattleWelcomeScreen)),
    );
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    callback();
    expect(store.welcomeStep, 0);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(store.welcomeStep, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.flush);
  });

  testWidgets('departed welcome callbacks cannot advance another account', (
    tester,
  ) async {
    final store =
        (await tester.runAsync(() async {
          final store = GameStore.createForTesting();
          await store.bindAccount('tutorial-owner');
          return store;
        }))!;
    addTearDown(store.dispose);
    await tester.pumpWidget(
      shell(BattleWelcomeScreen(playerStore: store), reduced: true),
    );
    await warm(tester);
    final callback =
        tester
            .widget<BattleCommand>(find.byKey(const ValueKey('welcome-next')))
            .onPressed!;
    await tester.runAsync(() => store.bindAccount('tutorial-new-owner'));
    final before = jsonEncode(store.data.toJson());
    callback();
    await tester.pump();
    expect(store.welcomeStep, 0);
    expect(store.hasCompletedTutorial, isFalse);
    expect(jsonEncode(store.data.toJson()), before);
    await tester.pumpWidget(const SizedBox());
    callback();
    await tester.pump();
    expect(store.welcomeStep, 0);
    expect(tester.takeException(), isNull);
  });
}
