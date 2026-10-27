import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_state.dart';

void main() {
  bool containsMove(Board board, int from, int to) =>
      MoveGen.legal(board).any((move) => move.from == from && move.to == to);

  group('final orthodox rule audit', () {
    test('FEN rejects malformed placement and counters', () {
      expect(
        () => Board.fromFen('8/8/8/8/8/8/8/9 w - - 0 1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Board.fromFen('8/8/8/8/8/8/8/8 x - - 0 1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Board.fromFen('8/8/8/8/8/8/8/8 w - z9 0 1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('both castling sides are legal only with clear safe transit', () {
      final board = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final king = Square.of(4, 0);
      expect(containsMove(board, king, Square.of(6, 0)), isTrue);
      expect(containsMove(board, king, Square.of(2, 0)), isTrue);

      final attackedTransit = Board.fromFen(
        'r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1',
      );
      expect(containsMove(attackedTransit, king, Square.of(6, 0)), isFalse);
    });

    test('en passant requires the actual capturable pawn', () {
      final legal = Board.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      expect(containsMove(legal, Square.of(4, 4), Square.of(3, 5)), isTrue);
      final invalid = Board.fromFen('4k3/8/8/4P3/8/8/8/4K3 w - d6 0 1');
      expect(containsMove(invalid, Square.of(4, 4), Square.of(3, 5)), isFalse);

      final occupiedTarget = Board.fromFen(
        '4k3/8/3N4/3pP3/8/8/8/4K3 w - d6 0 1',
      );
      expect(
        containsMove(occupiedTarget, Square.of(4, 4), Square.of(3, 5)),
        isFalse,
      );
    });

    test('en passant is filtered when it exposes the moving king', () {
      final board = Board.fromFen('4r1k1/8/8/3pP3/8/8/4K3/8 w - d6 0 1');
      expect(containsMove(board, Square.of(4, 4), Square.of(3, 5)), isFalse);
    });

    test('en passant removes the passed pawn and resets the counters', () {
      final board = Board.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 37 12');
      final move = MoveGen.legal(board).firstWhere(
        (candidate) =>
            candidate.from == Square.of(4, 4) &&
            candidate.to == Square.of(3, 5),
      );
      final after = board.apply(move);
      expect(
        after.pieceAt(Square.of(3, 5)),
        const Piece(PieceColor.white, PieceType.pawn),
      );
      expect(after.pieceAt(Square.of(3, 4)), isNull);
      expect(after.enPassant, isNull);
      expect(after.halfmoveClock, 0);
      expect(after.fullmoveNumber, 12);
    });

    test('pawns only receive a double step from their starting rank', () {
      final board = Board.fromFen('4k3/8/8/8/8/4P3/8/4K3 w - - 0 1');
      final moves = MoveGen.legal(board);
      expect(
        moves.any(
          (move) => move.from == Square.of(4, 2) && move.to == Square.of(4, 3),
        ),
        isTrue,
      );
      expect(
        moves.any(
          (move) => move.from == Square.of(4, 2) && move.to == Square.of(4, 4),
        ),
        isFalse,
      );
    });

    test('all four promotion pieces work for captures as well as pushes', () {
      final board = Board.fromFen('1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      final promotions =
          MoveGen.legal(board)
              .where(
                (move) =>
                    move.from == Square.of(0, 6) && move.to == Square.of(1, 7),
              )
              .map((move) => move.promotion)
              .toSet();
      expect(promotions, {
        PieceType.queen,
        PieceType.rook,
        PieceType.bishop,
        PieceType.knight,
      });
      final knight = MoveGen.legal(board).firstWhere(
        (move) =>
            move.from == Square.of(0, 6) &&
            move.to == Square.of(1, 7) &&
            move.promotion == PieceType.knight,
      );
      expect(
        board.apply(knight).pieceAt(Square.of(1, 7)),
        const Piece(PieceColor.white, PieceType.knight),
      );
    });

    test('castling moves the rook and permanently revokes both rights', () {
      final board = Board.fromFen('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1');
      final castle = MoveGen.legal(board).firstWhere(
        (move) => move.from == Square.of(4, 0) && move.to == Square.of(6, 0),
      );
      final after = board.apply(castle);
      expect(
        after.pieceAt(Square.of(6, 0)),
        const Piece(PieceColor.white, PieceType.king),
      );
      expect(
        after.pieceAt(Square.of(5, 0)),
        const Piece(PieceColor.white, PieceType.rook),
      );
      expect(after.castling & (Castling.whiteKing | Castling.whiteQueen), 0);
    });

    test('rook moves and rook captures revoke only the matching right', () {
      final moved = Board.fromFen('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1');
      final rookMove = MoveGen.legal(moved).firstWhere(
        (move) => move.from == Square.of(7, 0) && move.to == Square.of(6, 0),
      );
      final afterRookMove = moved.apply(rookMove);
      expect(afterRookMove.castling & Castling.whiteKing, 0);
      expect(afterRookMove.castling & Castling.whiteQueen, isNot(0));

      final capture = Board.fromFen('k6r/8/8/8/8/8/8/R3K2R w KQk - 0 1');
      final captureMove = MoveGen.legal(capture).firstWhere(
        (move) => move.from == Square.of(7, 0) && move.to == Square.of(7, 7),
        orElse: () => throw StateError('expected rook capture'),
      );
      final afterCapture = capture.apply(captureMove);
      expect(afterCapture.castling & Castling.blackKing, 0);
    });

    test('promotion exposes all four orthodox choices', () {
      final board = Board.fromFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      final promotions =
          MoveGen.legal(board)
              .where(
                (move) =>
                    move.from == Square.of(0, 6) && move.to == Square.of(0, 7),
              )
              .map((move) => move.promotion)
              .toSet();
      expect(promotions.length, 4);
    });

    test('checkmate and stalemate are distinguished', () {
      final mate = Board.fromFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      final stalemate = Board.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(MoveGen.legal(mate), isEmpty);
      expect(MoveGen.inCheck(mate, PieceColor.black), isTrue);
      expect(MoveGen.legal(stalemate), isEmpty);
      expect(MoveGen.inCheck(stalemate, PieceColor.black), isFalse);
    });

    test('fifty-move, repetition identity, and insufficient material work', () {
      final board = Board.fromFen('4k3/8/8/8/8/8/8/4K3 w - - 100 40');
      expect(board.isFiftyMoveRule, isTrue);
      expect(board.isSeventyFiveMoveRule, isFalse);
      expect(board.positionKey(), '4k3/8/8/8/8/8/8/4K3 w - -');
      expect(board.isInsufficientMaterial, isTrue);

      final sameColorBishops = Board.fromFen('7k/8/8/8/3B4/8/1B6/K7 w - - 0 1');
      final oppositeColorBishops = Board.fromFen(
        '7k/8/8/8/3B4/8/4B3/K7 w - - 0 1',
      );
      expect(sameColorBishops.isInsufficientMaterial, isTrue);
      expect(oppositeColorBishops.isInsufficientMaterial, isFalse);
      expect(
        Board.fromFen('4k3/8/8/8/8/8/8/4K3 w - - 150 40').isSeventyFiveMoveRule,
        isTrue,
      );
    });

    test('repetition ignores an unusable en-passant square', () {
      final afterDouble = Board.fromFen(
        '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
      ).apply(Move(Square.of(4, 1), Square.of(4, 3)));
      final withoutEp = Board.fromFen('4k3/8/8/8/4P3/8/8/4K3 b - - 0 1');
      expect(
        MoveGen.repetitionKey(afterDouble),
        MoveGen.repetitionKey(withoutEp),
      );

      final usable = Board.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      final noEp = Board.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1');
      expect(MoveGen.repetitionKey(usable), isNot(MoveGen.repetitionKey(noEp)));
    });
  });

  group('card match guards', () {
    test('invalid local moves are rejected without mutating the board', () {
      final match = MatchState.newGame();
      final from = Square.of(4, 1);
      final to = Square.of(4, 4);
      expect(match.makeMove(from, to), isFalse);
      expect(match.board[from]?.type, PieceType.pawn);
      expect(match.turn, PieceColor.white);
    });

    test('a card outside the authoritative hand cannot be played', () {
      final match = MatchState.newGame();
      match.mana[PieceColor.white] = 10;
      expect(match.playCard('angry_n', idx: Square.of(1, 0)), isFalse);
    });
  });
}
