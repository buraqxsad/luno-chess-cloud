import '../engine/board.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import 'authoritative.dart';
import 'core.dart';
import 'model.dart';

enum IntroductionStage {
  firstPiece,
  firstDestination,
  draw,
  mana,
  mineTarget,
  mineConfirm,
  secondPiece,
  secondDestination,
  opponent,
  mineTriggered,
  finalTurn,
  finalPiece,
  finalDestination,
  victory,
}

/// An isolated, replayable lesson. Every game mutation uses the normal V1 core.
/// This state never enters a match service, inventory, rating or reward endpoint.
class BattleIntroduction {
  late AuthoritativeBattleState state;
  IntroductionStage stage = IntroductionStage.firstPiece;
  int version = 0;
  BattleIntroduction({int checkpoint = 0}) {
    state = DeckManager.newBattle(
      white: [CardId.mine, ...starterDeck.take(9)],
      board: Board.fromFen('7k/p7/1n3KQ1/8/8/8/P7/8 w - - 0 1'),
    );
    final target = checkpoint.clamp(0, IntroductionStage.values.length - 1);
    while (stage.index < target) {
      if (!advanceExpected()) throw StateError('invalid-introduction-script');
    }
  }

  PlayerView get view => state.view(PieceColor.white);
  int get checkpoint => stage.index;
  int? get selected => switch (stage) {
    IntroductionStage.firstDestination => Square.of(0, 1),
    IntroductionStage.secondDestination => Square.of(0, 2),
    IntroductionStage.finalDestination => Square.of(6, 5),
    _ => null,
  };
  CardId? get selectedCard => switch (stage) {
    IntroductionStage.mineTarget ||
    IntroductionStage.mineConfirm => CardId.mine,
    _ => null,
  };
  int? get expectedSquare => switch (stage) {
    IntroductionStage.firstPiece => Square.of(0, 1),
    IntroductionStage.firstDestination => Square.of(0, 2),
    IntroductionStage.mineTarget => Square.of(2, 3),
    IntroductionStage.secondPiece => Square.of(0, 2),
    IntroductionStage.secondDestination => Square.of(0, 3),
    IntroductionStage.finalPiece => Square.of(6, 5),
    IntroductionStage.finalDestination => Square.of(6, 6),
    _ => null,
  };
  bool tapSquare(int square) => expectedSquare == square && advanceExpected();
  bool selectCard(CardId card) =>
      stage == IntroductionStage.mana &&
      card == CardId.mine &&
      advanceExpected();
  bool get hasCommand => const {
    IntroductionStage.draw,
    IntroductionStage.mineConfirm,
    IntroductionStage.opponent,
    IntroductionStage.mineTriggered,
    IntroductionStage.finalTurn,
  }.contains(stage);
  bool continueLesson() => hasCommand && advanceExpected();

  void _apply(BattleAction action) {
    // Also verify the scripted opponent's intent against its own redacted view.
    final legal = BattleRulesCore.legalActions(
      state.view(state.rules.board.turn),
    );
    if (!legal.any((a) => a.key == action.key)) {
      throw StateError('illegal-introduction-action:${action.key}');
    }
    state = DeckManager.apply(state, action);
    version++;
  }

  bool advanceExpected() {
    switch (stage) {
      case IntroductionStage.firstDestination:
        _apply(const ChessMoveAction('a2a3'));
      case IntroductionStage.draw:
        _apply(const ChessMoveAction('a7a6'));
      case IntroductionStage.mineConfirm:
        _apply(PlayCardAction(CardId.mine, target: Square.of(2, 3)));
      case IntroductionStage.secondDestination:
        _apply(const ChessMoveAction('a3a4'));
      case IntroductionStage.opponent:
        _apply(const PassAction());
        _apply(const ChessMoveAction('b6c4'));
      case IntroductionStage.finalTurn:
        _apply(const PassAction());
      case IntroductionStage.finalDestination:
        _apply(const ChessMoveAction('g6g7'));
        if (state.rules.terminal?.winner != PieceColor.white ||
            state.rules.terminal?.reason != 'checkmate') {
          throw StateError('introduction-finish-is-not-mate');
        }
      case IntroductionStage.victory:
        return false;
      default:
        break;
    }
    stage = IntroductionStage.values[stage.index + 1];
    return true;
  }
}
