import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/match/mpiece.dart';

void main() {
  test('başlangıç: 20 yasal hamle, mana 1/0', () {
    final m = MatchState.newGame();
    expect(m.allLegal(PieceColor.white).length, 20);
    expect(m.manaOf(PieceColor.white), 1);
    expect(m.manaOf(PieceColor.black), 0);
  });

  test('effectsiz konumlar saf motoru kullanır ve terfi seçimi zorunludur', () {
    MatchState promotionMatch() {
      final m = MatchState();
      for (var i = 0; i < 64; i++) {
        m.board[i] = null;
      }
      m.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
      m.board[Square.of(4, 7)] = MPiece(PieceColor.black, PieceType.king);
      m.board[Square.of(0, 6)] = MPiece(PieceColor.white, PieceType.pawn);
      m.turn = PieceColor.white;
      return m;
    }

    final preview = promotionMatch();
    expect(preview.isOrthodoxPosition, isTrue);
    expect(preview.legalFrom(Square.of(0, 6)), contains(Square.of(0, 7)));
    expect(preview.makeMove(Square.of(0, 6), Square.of(0, 7)), isFalse);

    for (final type in const [
      PieceType.queen,
      PieceType.rook,
      PieceType.bishop,
      PieceType.knight,
    ]) {
      final match = promotionMatch();
      expect(
        match.makeMove(Square.of(0, 6), Square.of(0, 7), promotion: type),
        isTrue,
      );
      expect(match.board[Square.of(0, 7)]?.type, type);
    }
  });

  test('saf satrançta talep edilebilir ve otomatik beraberlikler ayrıdır', () {
    MatchState rookPosition({int halfmove = 0}) {
      final m = MatchState.newGame();
      for (var i = 0; i < 64; i++) {
        m.board[i] = null;
      }
      m.board[Square.of(4, 0)] = MPiece(
        PieceColor.white,
        PieceType.king,
        moved: true,
      );
      m.board[Square.of(4, 7)] = MPiece(
        PieceColor.black,
        PieceType.king,
        moved: true,
      );
      m.board[Square.of(0, 0)] = MPiece(
        PieceColor.white,
        PieceType.rook,
        moved: true,
      );
      m.turn = PieceColor.white;
      m.halfmoveClock = halfmove;
      m.epTarget = null;
      return m;
    }

    final claimable = rookPosition(halfmove: 100);
    expect(claimable.makeMove(Square.of(0, 0), Square.of(0, 1)), isTrue);
    expect(claimable.result, MatchResult.ongoing);
    expect(claimable.canClaimFiftyMove, isTrue);
    expect(claimable.claimFiftyMove(), isTrue);
    expect(claimable.result, MatchResult.draw);

    final repeating = rookPosition();
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(repeating.makeMove(Square.of(0, 0), Square.of(0, 1)), isTrue);
      expect(repeating.makeMove(Square.of(4, 7), Square.of(4, 6)), isTrue);
      expect(repeating.makeMove(Square.of(0, 1), Square.of(0, 0)), isTrue);
      expect(repeating.makeMove(Square.of(4, 6), Square.of(4, 7)), isTrue);
    }
    expect(repeating.result, MatchResult.ongoing);
    expect(repeating.canClaimThreefoldRepetition, isTrue);
    expect(repeating.claimThreefoldRepetition(), isTrue);
    expect(repeating.result, MatchResult.draw);

    final automatic = rookPosition(halfmove: 149);
    expect(automatic.makeMove(Square.of(0, 0), Square.of(0, 1)), isTrue);
    expect(automatic.result, MatchResult.draw);
  });

  test('rakip şahı hedef kare olarak üretilmez', () {
    final board = Board.fromFen('4k3/8/8/8/8/8/4R3/K7 w - - 0 1');
    final rookFrom = Square.of(4, 1);
    final blackKing = Square.of(4, 7);
    final legal = MoveGen.legal(board);
    expect(
      legal.any((move) => move.from == rookFrom && move.to == blackKing),
      isFalse,
    );

    final match = MatchState();
    match.board[Square.of(0, 0)] = MPiece(PieceColor.white, PieceType.king);
    match.board[rookFrom] = MPiece(PieceColor.white, PieceType.rook);
    match.board[blackKing] = MPiece(PieceColor.black, PieceType.king);
    match.turn = PieceColor.white;
    expect(match.legalFrom(rookFrom), isNot(contains(blackKing)));
  });

  test('radar: mana düşer, sıra geçmez (hamle hakkı kalır)', () {
    final m = MatchState.newGame();
    final before = m.visualRevision;
    expect(m.playCard('radar1'), true);
    expect(m.visualRevision, greaterThan(before));
    expect(m.manaOf(PieceColor.white), 0);
    expect(m.cardUsed, true);
    expect(m.turn, PieceColor.white);
  });

  test('maç durumu değiştikçe tahta görsel revizyonu ilerler', () {
    final m = MatchState.newGame();
    expect(m.visualRevision, 0);
    m.forcePassTurn();
    expect(m.visualRevision, 1);
    m.forcePassTurn();
    expect(m.visualRevision, 2);
  });

  test('taş alımı görsel geri bildirim için yakalanan taşı saklar', () {
    final m = MatchState.newGame();
    const from = 0; // a1
    const to = 8; // a2
    m.board[4] = MPiece(PieceColor.white, PieceType.king); // e1
    m.board[60] = MPiece(PieceColor.black, PieceType.king); // e8
    m.board[from] = MPiece(PieceColor.white, PieceType.rook);
    final captured = MPiece(PieceColor.black, PieceType.pawn);
    m.board[to] = captured;

    m.makeMove(from, to);

    expect(m.board[to]?.color, PieceColor.white);
    expect(m.lastCaptured, same(captured));
    expect(m.lastCaptureSquare, to);
  });

  test('mana yetmezse kart oynanmaz', () {
    final m = MatchState.newGame();
    // freeze 7 mana ister, beyazda 1 var
    expect(m.playCard('freeze', idx: m.cardTargets('freeze').first), false);
  });

  test('freeze: rakibi dondurur ve sırayı geçirir', () {
    final m = MatchState.newGame();
    m.mana[PieceColor.white] = 10;
    final t = m.cardTargets('freeze').first;
    expect(m.playCard('freeze', idx: t), true);
    expect(m.turn, PieceColor.black, reason: 'skipMove sırayı geçirmeli');
    expect(m.board[t]!.frozen > 0, true);
  });

  test('öfkeli at: normal hamleler yerine (±1, 3 ileri)', () {
    final m = MatchState.newGame(white: [...kStarterCards, 'angry_n']);
    m.mana[PieceColor.white] = 10;
    final kn = Square.of(1, 0); // b1
    expect(m.playCard('angry_n', idx: kn), true);
    final moves = m.legalFrom(kn).toSet();
    expect(moves.contains(Square.of(2, 3)), true); // (+1,+3)
    expect(moves.contains(Square.of(0, 3)), true); // (-1,+3)
    expect(moves.contains(Square.of(2, 2)), false); // normal c3 artık yok
  });

  test('er birleşmesi: arkadaki boş karelere piyon ekler', () {
    final m = MatchState.newGame(white: ['reinforce']);
    m.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
    m.board[Square.of(0, 7)] = MPiece(PieceColor.black, PieceType.king);
    m.board[Square.of(4, 4)] = MPiece(PieceColor.white, PieceType.pawn); // e5
    m.turn = PieceColor.white;
    m.mana[PieceColor.white] = 10;
    expect(m.playCard('reinforce', idx: Square.of(4, 4)), true);
    expect(m.board[Square.of(4, 3)]?.type, PieceType.pawn);
    expect(m.board[Square.of(4, 2)]?.type, PieceType.pawn);
    expect(m.board[Square.of(4, 1)]?.type, PieceType.pawn);
  });

  test('bağışıklık: olumsuz etkileri temizler', () {
    final m = MatchState.newGame(white: ['immunity']);
    final idx = Square.of(4, 4);
    m.board[idx] = MPiece(
      PieceColor.white,
      PieceType.knight,
      frozen: 3,
      trapped: 2,
    );
    m.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
    m.board[Square.of(0, 7)] = MPiece(PieceColor.black, PieceType.king);
    m.turn = PieceColor.white;
    m.mana[PieceColor.white] = 10;
    expect(m.playCard('immunity', idx: idx), true);
    expect(m.board[idx]!.frozen, 0);
    expect(m.board[idx]!.trapped, 0);
  });

  test('seviye seçimi: trap1 ve trap3 farklı mana', () {
    final m = MatchState.newGame(white: ['trap1']);
    m.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
    m.board[Square.of(0, 7)] = MPiece(PieceColor.black, PieceType.king);
    m.turn = PieceColor.white;
    m.mana[PieceColor.white] = 10;
    expect(m.playCard('trap1', idx: Square.of(3, 3)), true); // 3 mana
    expect(m.manaOf(PieceColor.white), 7);
  });
}
