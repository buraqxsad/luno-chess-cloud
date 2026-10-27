import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

AuthoritativeBattleState cardScenario(
  CardId card,
  PieceColor side, {
  int mana = 6,
}) {
  final deck = [card, ...CardId.values.where((c) => c != card).take(9)];
  final white = Board.fromFen('4k3/rnbq1p2/8/3p4/3P4/8/1PNR1B2/4K3 w - - 0 10');
  final board =
      side.isWhite
          ? white
          : Board(
            squares:
                white.squares.reversed
                    .map((p) => p?.copyWith(color: p.color.opposite))
                    .toList(),
            turn: side,
            castling: 0,
            enPassant: null,
            halfmoveClock: 0,
            fullmoveNumber: 10,
          );
  final initial = DeckManager.newBattle(
    board: board,
    white: side.isWhite ? deck : starterDeck,
    black: side.isWhite ? starterDeck : deck,
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
        ..ownTurns[side] = 2
        ..ownTurns[side.opposite] = 2
        ..mana[side] = mana
        ..effectSequence = 10;
  final pawn = side.isWhite ? 9 : 54;
  if (card == CardId.purify) {
    draft.pieceEffects.addAll([
      ActivePieceEffect(
        id: 'e9',
        type: PieceEffectType.chain,
        owner: side.opposite,
        pieceId: draft.pieceIds[pawn]!,
        responseSide: side,
        duration: EffectDuration.move,
      ),
      ActivePieceEffect(
        id: 'e10',
        type: PieceEffectType.shelter,
        owner: side,
        pieceId: draft.pieceIds[pawn]!,
        responseSide: side.opposite,
        duration: EffectDuration.card,
      ),
    ]);
  }
  if (card == CardId.breakSeal) {
    draft.boardEffects.add(
      BoardEffectInstance(
        id: 'e9',
        type: BoardEffectType.mine,
        owner: side.opposite,
        squares: [side.isWhite ? 28 : 35],
        responseSide: side,
        duration: EffectDuration.persistent,
      ),
    );
  }
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}
