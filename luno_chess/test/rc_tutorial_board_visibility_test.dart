import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final step in [2, 3, 4, 5, 6]) {
      testWidgets('target lesson $step shows its full board first: $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..tutorialStep = step;
        addTearDown(store.dispose);
        await tester.pumpWidget(
          shell(
            TutorialScreen(onboarding: true, playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        await tester.pump();
        final board = tester.getRect(find.byType(BattleBoard));
        final viewport = tester.getRect(
          find.byKey(ValueKey('tutorial-copy-$step')),
        );
        expect(board.width, greaterThanOrEqualTo(240));
        expect(board.top, greaterThanOrEqualTo(viewport.top));
        expect(
          board.bottom,
          lessThanOrEqualTo(viewport.bottom),
          reason: 'The target board must not start below the fold',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
