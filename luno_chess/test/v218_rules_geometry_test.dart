import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/chess_game.dart';
import 'package:luno_chess/engine/move_gen.dart';

void main() {
  for (final (placement, side, ep, forbidden) in [
    ('4k3/8/8/4P3/8/8/8/4K3', 'w', 'd6', 'e5d6'),
    ('4k3/8/8/3nP3/8/8/8/4K3', 'w', 'd6', 'e5d6'),
    ('4k3/8/8/3PP3/8/8/8/4K3', 'w', 'd6', 'e5d6'),
    ('4k3/8/3N4/3pP3/8/8/8/4K3', 'w', 'd6', 'e5d6'),
    ('4k3/8/8/8/4p3/8/8/4K3', 'b', 'd3', 'e4d3'),
    ('4k3/8/8/8/3Np3/8/8/4K3', 'b', 'd3', 'e4d3'),
    ('4k3/8/8/8/3pp3/8/8/4K3', 'b', 'd3', 'e4d3'),
    ('4k3/8/8/8/3Pp3/3n4/8/4K3', 'b', 'd3', 'e4d3'),
  ]) {
    test('invalid EP preserves wrong or missing victim: $side $placement', () {
      final board = Board.fromFen('$placement $side - $ep 0 1');
      final withoutEp = Board.fromFen('$placement $side - - 0 1');
      expect(
        MoveGen.legal(board).map((m) => m.uci),
        isNot(contains(forbidden)),
      );
      expect(
        MoveGen.legal(board).map((m) => m.uci).toSet(),
        MoveGen.legal(withoutEp).map((m) => m.uci).toSet(),
      );
      expect(MoveGen.repetitionKey(board), MoveGen.repetitionKey(withoutEp));
    });
  }

  for (final fen in [
    '4k3/8/8/8/8/8/8/4K3 w KQ - 0 1',
    '4k3/8/8/8/8/8/8/N3K2N w KQ - 0 1',
    '4k3/8/8/8/8/8/8/3K3R w K - 0 1',
    'n3k2n/8/8/8/8/8/8/4K3 b kq - 0 1',
    '3k3r/8/8/8/8/8/8/4K3 b k - 0 1',
  ]) {
    test('castling requires home king and same-side rook: $fen', () {
      final board = Board.fromFen(fen);
      expect(MoveGen.legal(board).any((m) => m.isCastle), isFalse);
      expect(
        ChessGame(initialBoard: board).legalMoves.any((m) => m.isCastle),
        isFalse,
      );
    });
  }

  test('valid EP and occupied enemy capture keep distinct semantics', () {
    for (final (fen, expected, ep) in [
      ('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1', 'e5d6', true),
      ('4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 1', 'e4d3', true),
      ('4k3/8/3b4/3pP3/8/8/8/4K3 w - d6 0 1', 'e5d6', false),
    ]) {
      final move = MoveGen.legal(
        Board.fromFen(fen),
      ).singleWhere((m) => m.uci == expected);
      expect(move.isEnPassant, ep);
    }
  });
}
