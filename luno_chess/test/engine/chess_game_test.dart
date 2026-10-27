import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/chess_game.dart';
import 'package:luno_chess/engine/move.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

void main() {
  Move move(String from, String to) => Move(_square(from), _square(to));

  group('cards-free orthodox game state', () {
    test('accepts canonical special moves and rejects illegal moves', () {
      final game = ChessGame();
      expect(game.play(move('e2', 'e5')), isFalse);
      expect(game.play(move('e2', 'e4')), isTrue);
      expect(game.board.enPassant, Square.of(4, 2));
      expect(game.history.single.uci, 'e2e4');

      final castle = ChessGame(
        initialBoard: Board.fromFen('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1'),
      );
      expect(castle.play(move('e1', 'g1')), isTrue);
      expect(castle.history.single.isCastle, isTrue);
    });

    test('keeps claimable draws separate from automatic draws', () {
      final fifty = ChessGame(
        initialBoard: Board.fromFen('4k3/8/8/8/8/8/8/R3K2R w - - 100 1'),
      );
      expect(fifty.status, ChessGameStatus.ongoing);
      expect(fifty.canClaimFiftyMove, isTrue);
      expect(fifty.claimFiftyMove(), isTrue);
      expect(fifty.status, ChessGameStatus.drawByFiftyMoveClaim);

      final seventyFive = ChessGame(
        initialBoard: Board.fromFen('4k3/8/8/8/8/8/8/R3K2R w - - 150 1'),
      );
      expect(seventyFive.status, ChessGameStatus.drawBySeventyFiveMove);
      expect(seventyFive.isOver, isTrue);
    });

    test('tracks threefold claims and fivefold automatic repetition', () {
      final fen = '4k3/8/8/8/8/8/4K3/R7 w - - 0 1';
      final game = ChessGame(initialBoard: Board.fromFen(fen));
      final cycle = [
        move('a1', 'a2'),
        move('e8', 'e7'),
        move('a2', 'a1'),
        move('e7', 'e8'),
      ];

      for (final m in cycle) {
        expect(game.play(m), isTrue);
      }
      for (final m in cycle) {
        expect(game.play(m), isTrue);
      }
      expect(game.currentPositionCount, 3);
      expect(game.canClaimThreefoldRepetition, isTrue);
      expect(game.claimThreefoldRepetition(), isTrue);
      expect(game.status, ChessGameStatus.drawByThreefoldRepetitionClaim);

      final automatic = ChessGame(initialBoard: Board.fromFen(fen));
      for (int i = 0; i < 4; i++) {
        for (final m in cycle) {
          expect(automatic.play(m), isTrue);
        }
      }
      expect(automatic.currentPositionCount, 5);
      expect(automatic.status, ChessGameStatus.drawByFivefoldRepetition);
    });

    test('supports a threefold claim by announcing the next move', () {
      final fen = '4k3/8/8/8/8/8/4K3/R7 w - - 0 1';
      final game = ChessGame(initialBoard: Board.fromFen(fen));
      final cycle = [move('a1', 'a2'), move('e8', 'e7'), move('a2', 'a1')];
      expect(game.play(move('a1', 'a2')), isTrue);
      expect(game.play(move('e8', 'e7')), isTrue);
      expect(game.play(move('a2', 'a1')), isTrue);
      expect(game.play(move('e7', 'e8')), isTrue);
      for (final m in cycle) {
        expect(game.play(m), isTrue);
      }
      final returningMove = move('e7', 'e8');
      expect(game.canClaimThreefoldByMove(returningMove), isTrue);
      expect(
        game.claimThreefoldRepetition(intendedMove: returningMove),
        isTrue,
      );
      expect(game.board.turn, PieceColor.black);
      expect(game.history.length, 7);
    });

    test('distinguishes checkmate, stalemate, and dead position', () {
      final mate = ChessGame(
        initialBoard: Board.fromFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1'),
      );
      expect(mate.status, ChessGameStatus.checkmate);
      expect(mate.winner, PieceColor.white);

      final stalemate = ChessGame(
        initialBoard: Board.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'),
      );
      expect(stalemate.status, ChessGameStatus.stalemate);
      expect(stalemate.winner, isNull);

      final dead = ChessGame(
        initialBoard: Board.fromFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1'),
      );
      expect(dead.status, ChessGameStatus.drawByDeadPosition);
    });

    test('checkmate takes precedence over the seventy-five counter', () {
      final mate = ChessGame(
        initialBoard: Board.fromFen('7k/6Q1/6K1/8/8/8/8/8 b - - 150 1'),
      );
      expect(mate.status, ChessGameStatus.checkmate);
    });

    test('agreement ends only an ongoing game', () {
      final game = ChessGame();
      expect(game.agreeDraw(), isTrue);
      expect(game.status, ChessGameStatus.drawByAgreement);
      expect(game.play(move('e2', 'e4')), isFalse);
      expect(game.agreeDraw(), isFalse);
    });
  });
}

int _square(String algebraic) {
  final file = algebraic.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = int.parse(algebraic[1]) - 1;
  return Square.of(file, rank);
}
