import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  late GameStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = GameStore.createForTesting();
    store.loaded = true;
    store.hasCompletedTutorial = false;
    store.hasChosenUsername = false;
    store.practiceStage = null;
    store.tutorialStep = 0;
    addTearDown(store.dispose);
  });
  for (final language in ['tr', 'en']) {
    testWidgets(
      'skip guide completes onboarding without mandatory practice or reward changes: $language',
      (tester) async {
        final gold = store.data.gold;
        final trophies = store.data.trophies;
        await tester.pumpWidget(
          shell(
            TutorialScreen(onboarding: true, playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        final skip =
            tester
                .widget<TextButton>(
                  find.ancestor(
                    of: find.text(language == 'tr' ? 'ATLA' : 'SKIP'),
                    matching: find.byType(TextButton),
                  ),
                )
                .onPressed!;
        skip();
        skip();
        await tester.pump();
        expect(store.hasCompletedTutorial, true);
        expect(store.practiceStage, isNull);
        expect(store.hasChosenUsername, false);
        expect(store.data.gold, gold);
        expect(store.data.trophies, trophies);
        await tester.pumpWidget(const SizedBox());
        skip();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('old guide callbacks cannot mutate a newly bound account', (
    tester,
  ) async {
    await tester.runAsync(() => store.bindAccount('tutorial-first'));
    store.hasCompletedTutorial = false;
    await tester.pumpWidget(
      shell(
        TutorialScreen(onboarding: true, playerStore: store),
        reduced: true,
      ),
    );
    final advance =
        tester.widget<LunoButton>(find.byType(LunoButton)).onPressed!;
    await tester.runAsync(() => store.bindAccount('tutorial-second'));
    final step = store.tutorialStep;
    advance();
    await tester.pump();
    expect(store.tutorialStep, step);
    expect(store.hasCompletedTutorial, false);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('replay skip closes only the current guide', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Scaffold()),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TutorialScreen(playerStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ATLA'));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsNothing);
    expect(store.hasCompletedTutorial, false);
  });
}
