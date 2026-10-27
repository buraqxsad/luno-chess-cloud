import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, visibleTap;

int square(String name) =>
    name.codeUnitAt(0) - 97 + 8 * (int.parse(name[1]) - 1);

Future<void> makeLessonMove(WidgetTester tester) async {
  final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
  final move =
      BattleRulesCore.legalActions(
        board.view,
      ).whereType<ChessMoveAction>().first;
  await visibleTap(tester, 'square-${square(move.uci.substring(0, 2))}');
  await visibleTap(tester, 'square-${square(move.uci.substring(2, 4))}');
  await tester.pump();
}

Future<void> completeLesson(WidgetTester tester, int step) async {
  if (!BattleLessonStage.requiresInteraction(step)) return;
  if (step == 2 || step == 6) {
    await visibleTap(tester, step == 2 ? 'lesson-discard' : 'lesson-pass');
  } else if (step != 1) {
    final card = battleLessonCards(step).first;
    if (step == 3) {
      tester
          .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
          .onChanged!(6);
      await tester.pump();
    }
    if (cardDefinitions[card]!.target == CardTargetType.opponentCard) {
      final target = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .firstWhere(
            (button) => button.key.toString().contains('lesson-opponent-'),
          );
      await tester.ensureVisible(find.byKey(target.key!));
      await tester.tap(find.byKey(target.key!));
      await tester.pump();
    } else if (cardDefinitions[card]!.target != CardTargetType.none) {
      final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
      await visibleTap(tester, 'square-${board.targets.first}');
    }
    await visibleTap(tester, 'lesson-play-card');
    expect(
      find.byKey(const ValueKey('lesson-play-card')),
      findsNothing,
      reason: 'A played card cannot be submitted again',
    );
  }
  if (step != 7) await makeLessonMove(tester);
  await tester.pump();
}

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    testWidgets(
      'guide requires a real chess move before continuing: $language',
      (tester) async {
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..tutorialStep = 1;
        addTearDown(store.dispose);
        await tester.pumpWidget(
          shell(
            TutorialScreen(onboarding: true, playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        await tester.pump();
        final button = find.byType(LunoButton);
        expect(tester.widget<LunoButton>(button).onPressed, isNull);
        expect(store.tutorialStep, 1);
        await makeLessonMove(tester);
        await tester.pump();
        expect(tester.widget<LunoButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        await tester.pump();
        expect(store.tutorialStep, 2);
        expect(tester.widget<LunoButton>(button).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
