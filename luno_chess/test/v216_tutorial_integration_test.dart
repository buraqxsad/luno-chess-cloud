import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, warm, noOverflow, boundaryKey;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = false
      ..practiceStage = null;
  });
  for (final language in ['tr', 'en']) {
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 568), 1.5),
    ]) {
      for (final step in [4, 5]) {
        testWidgets('V216 tutorial action precedes optional catalog '
            '$language $step ${size.width} $scale', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          GameStore.instance.tutorialStep = step;
          final before = GameStore.instance.data.toJson();
          await tester.pumpWidget(shell(
            const TutorialScreen(onboarding: true),
            language: language,
            scale: scale,
            reduced: true,
          ));
          await warm(tester);
          final command = find.byKey(const ValueKey('lesson-play-card'));
          final catalog = find.byKey(ValueKey(
            step == 4 ? 'lesson-card-chain' : 'lesson-card-shelter',
          ));
          expect(tester.getRect(command).bottom,
              lessThanOrEqualTo(tester.getRect(catalog).top));
          if (scale == 1) {
            expect(command.hitTestable(), findsOneWidget);
          }
          expect(tester.widget<BattleCommand>(command).onPressed, isNull);
          final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
          expect(board.targets, isNotEmpty);
          final selectedCard = step == 4 ? CardId.chain : CardId.shelter;
          final mana = board.view.rules.mana[PieceColor.white]!;
          final target = find.byKey(ValueKey('square-${board.targets.first}'));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pump();
          await tester.ensureVisible(command);
          await tester.pumpAndSettle();
          expect(command.hitTestable(), findsOneWidget);
          expect(tester.widget<BattleCommand>(command).onPressed, isNotNull);
          noOverflow(tester);
          await capture(tester,
            'lesson-$step-$language-${size.width.toInt()}-target-ready',
            repaintKey: boundaryKey,
            outputDirectory: 'qa/v216/after/tutorial-integration');
          await tester.tap(command);
          await tester.pumpAndSettle();
          final after = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
          expect(after.rules.phase, BattlePhase.chess);
          expect(after.rules.used[PieceColor.white], contains(selectedCard));
          expect(after.rules.mana[PieceColor.white],
              mana - cardDefinitions[selectedCard]!.cost);
          expect(GameStore.instance.data.toJson(), before);
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
