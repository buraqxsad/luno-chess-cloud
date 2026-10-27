import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'battle_ui/fixtures.dart';

void main() {
  test('wrong square clears a previously selected piece-card target', () {
    final view = battleFixture().view(PieceColor.white);
    final actions = BattleRulesCore.legalActions(view);
    final interaction = BattleInteraction()..select(CardId.shelter, actions);
    interaction.tap(12, view, actions);
    expect(interaction.play?.target, 12);
    interaction.tap(60, view, actions);
    expect(interaction.play, isNull);
    expect(interaction.preview(), isEmpty);
    expect(interaction.card, CardId.shelter);
  });

  test(
    'wrong occupied square clears a previously selected board-card target',
    () {
      final view = battleFixture().view(PieceColor.white);
      final actions = BattleRulesCore.legalActions(view);
      final interaction =
          BattleInteraction()..select(CardId.lockedSquare, actions);
      interaction.tap(28, view, actions);
      expect(interaction.play?.target, 28);
      interaction.tap(12, view, actions);
      expect(interaction.play, isNull);
      expect(interaction.preview(), isEmpty);
    },
  );

  test(
    'wrong movement destination cannot reuse an earlier valid destination',
    () {
      final view = battleFixture(
        hand: const [CardId.pawnDeviation, CardId.chain],
      ).view(PieceColor.white);
      final actions = BattleRulesCore.legalActions(view);
      final interaction =
          BattleInteraction()..select(CardId.pawnDeviation, actions);
      interaction.tap(12, view, actions);
      interaction.tap(19, view, actions);
      expect(interaction.specialDestination?.uci, 'e2d3');
      interaction.tap(60, view, actions);
      expect(interaction.specialDestination, isNull);
      expect(interaction.piece, 12);
      expect(interaction.play?.target, 12);
      expect(interaction.preview(), {12});
    },
  );

  test('a fresh valid target can be selected after rejecting a wrong one', () {
    final view = battleFixture().view(PieceColor.white);
    final actions = BattleRulesCore.legalActions(view);
    final interaction = BattleInteraction()..select(CardId.shelter, actions);
    interaction.tap(12, view, actions);
    interaction.tap(60, view, actions);
    interaction.tap(11, view, actions);
    expect(interaction.play?.target, 11);
    expect(interaction.preview(), {11});
  });

  test('irrelevant board taps do not cancel untargeted information cards', () {
    final view = battleFixture(
      hand: const [CardId.prophecy, CardId.chain],
    ).view(PieceColor.white);
    final actions = BattleRulesCore.legalActions(view);
    final interaction = BattleInteraction()..select(CardId.prophecy, actions);
    expect(interaction.play, isNotNull);
    interaction.tap(12, view, actions);
    expect(interaction.play?.card, CardId.prophecy);
    expect(interaction.play?.target, isNull);
  });
}
