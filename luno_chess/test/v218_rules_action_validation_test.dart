import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

PlayerView _ready(List<CardId> cards) {
  final deck =
      [
        ...cards,
        ...CardId.values.where((c) => !cards.contains(c)),
      ].take(10).toList();
  final source = DeckManager.newBattle(white: deck);
  final draft =
      RuleDraft(source.rules)
        ..phase = BattlePhase.card
        ..ownTurns = {PieceColor.white: 2, PieceColor.black: 2}
        ..mana = {PieceColor.white: 6, PieceColor.black: 6}
        ..repetitions = {};
  return PlayerView(
    draft.freeze(),
    PieceColor.white,
    source.hidden.hands[PieceColor.white]!,
    source.hidden.knowledge[PieceColor.white]!,
  );
}

void main() {
  test('square targets cannot be spoofed by their string representation', () {
    final view = _ready([CardId.shelter]);
    for (final target in <Object>[
      '8',
      [8],
      8.0,
      8.5,
      double.nan,
      double.infinity,
    ]) {
      expect(
        () => BattleRulesCore.transition(
          view,
          PlayCardAction(CardId.shelter, target: target),
        ),
        throwsStateError,
      );
      expect(view.rules.used[PieceColor.white], isEmpty);
      expect(view.rules.mana[PieceColor.white], 6);
    }
    expect(
      BattleRulesCore.transition(
        view,
        const PlayCardAction(CardId.shelter, target: 8),
      ).rules.used[PieceColor.white],
      [CardId.shelter],
    );
  });

  test(
    'no-target cards reject empty string targets, including sacrifice cards',
    () {
      final view = _ready([CardId.prophecy, CardId.shadowContract]);
      for (final action in [
        const PlayCardAction(CardId.prophecy, target: ''),
        const PlayCardAction(
          CardId.shadowContract,
          target: '',
          sacrifice: CardId.prophecy,
        ),
      ]) {
        expect(
          () => BattleRulesCore.transition(view, action),
          throwsStateError,
        );
      }
      expect(
        BattleRulesCore.transition(
          view,
          const PlayCardAction(CardId.prophecy),
        ).rules.phase,
        BattlePhase.pending,
      );
    },
  );

  test(
    'sacrifice consumes exactly two cards without burning the chess turn',
    () {
      final view = _ready([CardId.shadowContract, CardId.radar]);
      final result = BattleRulesCore.transition(
        view,
        const PlayCardAction(CardId.shadowContract, sacrifice: CardId.radar),
      );
      expect(result.rules.used[PieceColor.white], [CardId.shadowContract]);
      expect(result.rules.discarded[PieceColor.white], [CardId.radar]);
      expect(
        result.rules.handCounts[PieceColor.white],
        view.ownHand.length - 2,
      );
      expect(result.rules.phase, BattlePhase.chess);
      expect(result.rules.board.turn, PieceColor.white);
      expect(result.rules.fen, view.rules.fen);
      expect(result.rules.modifiers.single.ownTurn, 3);
    },
  );

  test('discard remains free, permanent, and does not skip the chess turn', () {
    final view = _ready([CardId.radar]);
    final result = BattleRulesCore.transition(
      view,
      const DiscardAction(CardId.radar),
    );
    expect(result.rules.mana, view.rules.mana);
    expect(result.rules.discarded[PieceColor.white], [CardId.radar]);
    expect(result.rules.phase, BattlePhase.chess);
    expect(result.rules.fen, view.rules.fen);
  });
}
