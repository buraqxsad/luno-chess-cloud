import 'dart:convert';
import 'dart:io';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}
Board reflect(Board b) => Board(
  squares: [for (var i = 0; i < 64; i++) b.squares[i ^ 56]?.copyWith(color: b.squares[i ^ 56]!.color.opposite)],
  turn: b.turn.opposite,
  castling: ((b.castling & 3) << 2) | ((b.castling & 12) >> 2),
  enPassant: b.enPassant == null ? null : b.enPassant! ^ 56,
  halfmoveClock: b.halfmoveClock,
  fullmoveNumber: b.fullmoveNumber,
);
Move reflectMove(Move m) => Move(m.from ^ 56, m.to ^ 56, promotion: m.promotion, isEnPassant: m.isEnPassant, isCastle: m.isCastle);
String key(Move m) => '${m.uci}:${m.isEnPassant}:${m.isCastle}';
String signature(Board b) => '${b.positionKey()} ${b.halfmoveClock}';
int pieces(Board b) => b.squares.where((p) => p != null).length;
void main() {
  final starts = [
    Board.start(),
    Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'),
    Board.fromFen('7k/6P1/8/8/8/8/8/K7 w - - 0 1'),
    Board.fromFen('k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1'),
    Board.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 99 40'),
  ];
  var states = 0, branches = 0, ep = 0, castles = 0, promotions = 0;
  for (var start = 0; start < starts.length; start++) {
    for (var seed = 0; seed < 4; seed++) {
      var board = starts[start], random = 911 + 53 * start + seed;
      for (var ply = 0; ply < 40; ply++) {
        final mirrored = reflect(board), moves = MoveGen.legal(board);
        final canonical = moves.map(reflectMove).map(key).toList()..sort();
        final reflectedMoves = MoveGen.legal(mirrored).map(key).toList()..sort();
        require(jsonEncode(canonical) == jsonEncode(reflectedMoves), 'Legal set asymmetry start=$start seed=$seed ply=$ply');
        states++;
        if (moves.isEmpty) break;
        final picks = {0, moves.length ~/ 2, moves.length - 1};
        for (final i in picks) {
          final move = moves[i], before = signature(board), next = board.apply(move), other = mirrored.apply(reflectMove(move));
          require(signature(other) == signature(reflect(next)), 'Transition asymmetry ${move.uci}');
          require(signature(board) == before, 'Accepted action mutated retained input');
          final pawn = board.squares[move.from]!.type == PieceType.pawn;
          final capture = board.squares[move.to] != null || move.isEnPassant;
          require(next.halfmoveClock == (pawn || capture ? 0 : board.halfmoveClock + 1), 'Halfmove clock accounting ${move.uci}');
          require(next.fullmoveNumber == board.fullmoveNumber + (board.turn == PieceColor.black ? 1 : 0), 'Fullmove number accounting');
          require(next.turn == board.turn.opposite, 'Turn did not change');
          require((next.castling & ~board.castling) == 0, 'Castling right resurrected');
          require(pieces(next) == pieces(board) - (capture ? 1 : 0), 'Incorrect capture material count');
          require(next.squares.where((p) => p?.type == PieceType.king).length == 2, 'King captured or duplicated');
          require(!MoveGen.inCheck(next, board.turn), 'Legal move leaves own king in check');
          branches++;
          if (move.isEnPassant) ep++;
          if (move.isCastle) castles++;
          if (move.promotion != null) promotions++;
        }
        random = (1664525 * random + 1013904223) & 0xFFFFFFFF;
        board = board.apply(moves[random % moves.length]);
      }
    }
  }
  final result = {'status':'PASS','scope':'Independent color/vertical reflection and counter/material invariants on the pure Dart orthodox move generator; not a complete independent rules oracle.','starts':starts.length,'games':starts.length*4,'states':states,'branchTransitions':branches,'enPassantBranches':ep,'castleBranches':castles,'promotionBranches':promotions};
  File('/workspace/luno-review/bug-audit-round2/rules/orthodox-reflection-results.json').writeAsStringSync('${jsonEncode(result)}\n');
  stdout.writeln(jsonEncode(result));
}
