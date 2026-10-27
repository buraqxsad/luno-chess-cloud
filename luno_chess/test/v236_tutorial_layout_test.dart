import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, boundaryKey;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'guided board and completion reachable $language $size $scale',
          (tester) async {
            tester.view
              ..physicalSize = size
              ..devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var completed = 0;
            await tester.pumpWidget(
              shell(
                BattleV1Screen(
                  practiceStage: 0,
                  practiceOnboarding: true,
                  guidedFirstMatch: true,
                  practiceCheckpoint: const BattleLearningCheckpoint(
                    moves: 4,
                    cast: true,
                    discarded: true,
                    passed: true,
                  ),
                  onPracticeComplete: () async {
                    completed++;
                  },
                ),
                language: language,
                scale: scale,
                reduced: true,
              ),
            );
            await warm(tester);
            final board = tester.getRect(find.byType(BattleBoard));
            expect(
              board.width,
              greaterThanOrEqualTo(math.min(560, size.width) - 16 - .01),
            );
            expect(find.byType(BattlePracticeCoach), findsOneWidget);
            final next = find.byKey(const ValueKey('practice-next'));
            await tester.ensureVisible(next);
            await tester.pumpAndSettle();
            expect(next.hitTestable(), findsOneWidget);
            await capture(
              tester,
              '$language-${size.width.toInt()}x${size.height.toInt()}-$scale',
              repaintKey: boundaryKey,
              outputDirectory: 'qa/v236/tutorial',
            );
            noOverflow(tester);
            await tester.tap(next);
            await tester.pumpAndSettle();
            expect(completed, 1);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
