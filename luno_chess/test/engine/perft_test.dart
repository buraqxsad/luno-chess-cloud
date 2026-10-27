import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/perft.dart';
import 'package:luno_chess/engine/piece.dart';

void main() {
  final slow = Platform.environment['LUNO_SLOW_PERFT'] == '1';
  group('perft (başlangıç dizilimi — bilinen referans değerleri)', () {
    test('derinlik 1 = 20', () => expect(perft(Board.start(), 1), 20));
    test('derinlik 2 = 400', () => expect(perft(Board.start(), 2), 400));
    test('derinlik 3 = 8902', () => expect(perft(Board.start(), 3), 8902));
    test('derinlik 4 = 197281', () => expect(perft(Board.start(), 4), 197281));
  });

  group('temel motor mantığı', () {
    test('başlangıçta beyazın 20 yasal hamlesi var', () {
      expect(MoveGen.legal(Board.start()).length, 20);
    });
    test('başlangıçta kimse şahta değil', () {
      expect(MoveGen.inCheck(Board.start(), PieceColor.white), false);
      expect(MoveGen.inCheck(Board.start(), PieceColor.black), false);
    });
  });

  group('standart referans pozisyonları', () {
    test('Kiwipete: rok ve şah güvenliği', () {
      final board = Board.fromFen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      );
      expect(perft(board, 1), 48);
      expect(perft(board, 2), 2039);
      expect(perft(board, 3), 97862);
      if (slow) {
        expect(perft(board, 4), 4085603);
      }
    });

    test('position 3: geçerken-al ve terfi dalları', () {
      final board = Board.fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
      expect(perft(board, 1), 14);
      expect(perft(board, 2), 191);
      expect(perft(board, 3), 2812);
      expect(perft(board, 4), 43238);
    });

    test('position 4: karmaşık rok ve terfi konumu', () {
      final board = Board.fromFen(
        'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
      );
      expect(perft(board, 1), 6);
      expect(perft(board, 2), 264);
      expect(perft(board, 3), 9467);
      if (slow) {
        expect(perft(board, 4), 422333);
      }
    });

    test('position 5: açmazlar ve şah kaçışları', () {
      final board = Board.fromFen(
        'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
      );
      expect(perft(board, 1), 44);
      expect(perft(board, 2), 1486);
      expect(perft(board, 3), 62379);
      if (slow) {
        expect(perft(board, 4), 2103487);
      }
    });

    test('position 6: orta oyun yasal hamle ağacı', () {
      final board = Board.fromFen(
        'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
      );
      expect(perft(board, 1), 46);
      expect(perft(board, 2), 2079);
      expect(perft(board, 3), 89890);
      if (slow) {
        expect(perft(board, 4), 3894594);
      }
    });
  });
}
