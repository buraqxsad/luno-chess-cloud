import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

const rbBaseFen = '7k/8/8/8/3R4/8/8/K7 w - - 37 10';
const rbMateFen = 'k7/2K5/1R6/2B5/8/8/8/8 w - - 149 10';
const rbStalemateFen = 'k1K5/8/1R6/2B5/8/8/8/8 w - - 0 10';
const rbDeck = [
  CardId.rookBend,
  CardId.radar,
  CardId.prophecy,
  CardId.shelter,
  CardId.chain,
  CardId.slow,
  CardId.pawnDeviation,
  CardId.pawnAdvance,
  CardId.lockedSquare,
  CardId.freeze,
];

int rbIndex(String square) =>
    square.codeUnitAt(0) - 97 + 8 * (square.codeUnitAt(1) - 49);
String rbName(int square) =>
    '${String.fromCharCode(97 + square % 8)}${square ~/ 8 + 1}';
int rbSquare(PieceColor side, String whiteSquare) =>
    rbIndex(whiteSquare) ^ (side.isWhite ? 0 : 56);
String rbUci(PieceColor side, String whiteUci) =>
    '${rbName(rbSquare(side, whiteUci.substring(0, 2)))}'
    '${rbName(rbSquare(side, whiteUci.substring(2, 4)))}'
    '${whiteUci.substring(4)}';

// Rank reflection preserves king/queen-side castling, unlike a 180-degree turn.
Board rbBoard(Board white, PieceColor side) {
  if (side.isWhite) return white;
  return Board(
    squares: [
      for (var square = 0; square < 64; square++)
        white.squares[square ^ 56]?.copyWith(
          color: white.squares[square ^ 56]!.color.opposite,
        ),
    ],
    turn: white.turn.opposite,
    castling: ((white.castling & 3) << 2) | ((white.castling & 12) >> 2),
    enPassant: white.enPassant == null ? null : white.enPassant! ^ 56,
    halfmoveClock: white.halfmoveClock,
    fullmoveNumber: white.fullmoveNumber,
  );
}

AuthoritativeBattleState rbFixture({
  PieceColor side = PieceColor.white,
  String fen = rbBaseFen,
  Board? whiteBoard,
  int mana = 6,
  List<CardId> deck = rbDeck,
}) {
  final initial = DeckManager.newBattle(
    white: deck,
    black: deck,
    board: rbBoard(whiteBoard ?? Board.fromFen(fen), side),
  );
  if (initial.rules.terminal != null) {
    throw StateError('rook-bend-harness-started-terminal:$fen');
  }
  return rbEdit(initial, (draft) {
    draft.phase = BattlePhase.card;
    draft.ownTurns[side] = 2;
    draft.ownTurns[side.opposite] = 2;
    draft.mana[side] = mana;
    draft.effectSequence = 100;
    draft.repetitions.clear();
  });
}

AuthoritativeBattleState rbEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

ActivePieceEffect rbPieceEffect(
  AuthoritativeBattleState state,
  PieceEffectType type, {
  String source = 'd4',
  String? id,
  PieceColor? owner,
  PieceColor? responseSide,
}) {
  final side = state.rules.board.turn;
  return ActivePieceEffect(
    id: id ?? 'rb-${type.name}',
    type: type,
    owner: owner ?? (type == PieceEffectType.shelter ? side : side.opposite),
    pieceId: state.rules.pieceIds[rbSquare(side, source)]!,
    responseSide:
        responseSide ??
        (type == PieceEffectType.shelter ? side.opposite : side),
    duration:
        type == PieceEffectType.shelter
            ? EffectDuration.card
            : type == PieceEffectType.mineDebuff
            ? EffectDuration.pieceMove
            : EffectDuration.move,
  );
}

BoardEffectInstance rbBoardEffect(
  AuthoritativeBattleState state,
  BoardEffectType type,
  List<String> whiteSquares, {
  String? id,
  PieceColor? owner,
}) {
  final side = state.rules.board.turn;
  return BoardEffectInstance(
    id: id ?? 'rb-${type.name}',
    type: type,
    owner: owner ?? side.opposite,
    squares: whiteSquares.map((s) => rbSquare(side, s)).toList(),
    responseSide: (owner ?? side.opposite).opposite,
    duration:
        type == BoardEffectType.mine
            ? EffectDuration.persistent
            : type == BoardEffectType.fog
            ? EffectDuration.card
            : EffectDuration.move,
  );
}

AuthoritativeBattleState rbCast(
  AuthoritativeBattleState state, {
  String source = 'd4',
}) => DeckManager.apply(
  state,
  PlayCardAction(
    CardId.rookBend,
    target: rbSquare(state.rules.board.turn, source),
  ),
);

AuthoritativeBattleState rbMove(
  AuthoritativeBattleState state,
  String whiteUci,
) => DeckManager.apply(
  state,
  ChessMoveAction(rbUci(state.rules.board.turn, whiteUci)),
);

// This oracle never calls MoveGen, Board.apply, or any production legality API.
bool rbAttacked(List<Piece?> board, int target, PieceColor attacker) {
  for (var from = 0; from < 64; from++) {
    final piece = board[from];
    if (piece == null || piece.color != attacker || from == target) continue;
    final x = target % 8 - from % 8;
    final y = target ~/ 8 - from ~/ 8;
    if (piece.type == PieceType.pawn) {
      if (x.abs() == 1 && y == (attacker.isWhite ? 1 : -1)) return true;
      continue;
    }
    if (piece.type == PieceType.knight) {
      if (x.abs() * y.abs() == 2) return true;
      continue;
    }
    if (piece.type == PieceType.king) {
      if (x.abs() <= 1 && y.abs() <= 1) return true;
      continue;
    }
    final straight = x == 0 || y == 0;
    final diagonal = x.abs() == y.abs();
    final aligned = switch (piece.type) {
      PieceType.rook => straight,
      PieceType.bishop => diagonal,
      PieceType.queen => straight || diagonal,
      _ => false,
    };
    if (!aligned) continue;
    final distance = x.abs() > y.abs() ? x.abs() : y.abs();
    var clear = true;
    for (var step = 1; step < distance; step++) {
      final at = (from ~/ 8 + step * y.sign) * 8 + from % 8 + step * x.sign;
      if (board[at] != null) {
        clear = false;
        break;
      }
    }
    if (clear) return true;
  }
  return false;
}

List<String> rbOracleMoves(RuleState state, int from, PieceColor side) {
  if (from < 0 || from >= 64) return [];
  final board = state.board.squares;
  final piece = board[from];
  if (piece?.color != side || piece?.type != PieceType.rook) return [];
  if (state.pieceEffects.any(
    (effect) =>
        effect.pieceId == state.pieceIds[from] &&
        effect.type == PieceEffectType.freeze,
  )) {
    return [];
  }
  final king = board.indexWhere(
    (piece) => piece?.color == side && piece?.type == PieceType.king,
  );
  if (king < 0) throw StateError('rook-bend-oracle-missing-king');
  final expected = <String>[];
  for (var to = 0; to < 64; to++) {
    if ((to % 8 - from % 8).abs() != 1 ||
        (to ~/ 8 - from ~/ 8).abs() != 1 ||
        board[to] != null) {
      continue;
    }
    if (state.boardEffects.any(
      (effect) =>
          effect.owner != side &&
          (effect.type == BoardEffectType.lockedSquare ||
              effect.type == BoardEffectType.boardSeal) &&
          effect.squares.contains(to),
    )) {
      continue;
    }
    final after = List<Piece?>.of(board);
    after[from] = null;
    after[to] = piece;
    if (!rbAttacked(after, king, side.opposite)) {
      expected.add('${rbName(from)}${rbName(to)}');
    }
  }
  return expected..sort();
}

Board rbGeometryBoard(int rook) {
  const corners = [0, 7, 56, 63];
  for (final ownKing in corners) {
    if (ownKing == rook) continue;
    for (final enemyKing in corners) {
      if (enemyKing == rook ||
          enemyKing == ownKing ||
          enemyKing % 8 == rook % 8 ||
          enemyKing ~/ 8 == rook ~/ 8) {
        continue;
      }
      final board = List<Piece?>.filled(64, null);
      board[ownKing] = const Piece(PieceColor.white, PieceType.king);
      board[enemyKing] = const Piece(PieceColor.black, PieceType.king);
      board[rook] = const Piece(PieceColor.white, PieceType.rook);
      return Board(
        squares: board,
        turn: PieceColor.white,
        castling: 0,
        enPassant: null,
        halfmoveClock: 37,
        fullmoveNumber: 10,
      );
    }
  }
  throw StateError('rook-bend-geometry-harness-no-kings:$rook');
}
