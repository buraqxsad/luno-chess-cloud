import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

void main() {
  test('introduction uses real draws, mana, mine and checkmate', () {
    final lesson = BattleIntroduction();
    expect(lesson.view.rules.phase, BattlePhase.chess);
    expect(lesson.view.ownHand.length, 3);
    expect(lesson.view.rules.mana[PieceColor.white], 1);
    while (lesson.stage != IntroductionStage.victory) {
      final before = lesson.stage;
      expect(lesson.advanceExpected(), isTrue);
      if (before == IntroductionStage.firstDestination) {
        expect(lesson.view.ownHand.length, 4);
        expect(lesson.view.rules.deckCounts[PieceColor.white], 6);
      }
      if (before == IntroductionStage.draw) {
        expect(lesson.view.rules.phase, BattlePhase.card);
        expect(lesson.view.rules.mana[PieceColor.white], 2);
      }
      if (before == IntroductionStage.mineConfirm) {
        expect(lesson.view.rules.phase, BattlePhase.chess);
        expect(lesson.view.rules.mana[PieceColor.white], 0);
        expect(lesson.view.ownHand, isNot(contains(CardId.mine)));
        expect(
          lesson.view.rules.boardEffects.single.type,
          BoardEffectType.mine,
        );
      }
      if (before == IntroductionStage.opponent) {
        expect(lesson.view.rules.boardEffects, isEmpty);
        expect(
          lesson.view.rules.pieceEffects.single.type,
          PieceEffectType.mineDebuff,
        );
      }
    }
    expect(lesson.view.rules.terminal?.winner, PieceColor.white);
    expect(lesson.view.rules.terminal?.reason, 'checkmate');
    expect(lesson.advanceExpected(), isFalse);
  });
  test('every checkpoint replays the exact deterministic engine state', () {
    final lesson = BattleIntroduction();
    for (final stage in IntroductionStage.values) {
      final restored = BattleIntroduction(checkpoint: stage.index);
      expect(restored.stage, stage);
      expect(
        jsonEncode(restored.state.toJson()),
        jsonEncode(lesson.state.toJson()),
      );
      lesson.advanceExpected();
    }
  });
  test(
    'wrong squares, cards and commands cannot advance or mutate the lesson',
    () {
      final lesson = BattleIntroduction();
      final before = jsonEncode(lesson.state.toJson());
      expect(lesson.tapSquare(0), isFalse);
      expect(lesson.selectCard(CardId.mine), isFalse);
      expect(lesson.continueLesson(), isFalse);
      expect(lesson.checkpoint, 0);
      expect(jsonEncode(lesson.state.toJson()), before);
      expect(lesson.tapSquare(lesson.expectedSquare!), isTrue);
      expect(lesson.tapSquare(lesson.selected!), isFalse);
    },
  );
}
