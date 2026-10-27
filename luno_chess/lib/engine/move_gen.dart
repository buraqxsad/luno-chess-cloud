import 'board.dart';
import 'move.dart';
import 'piece.dart';
import 'square.dart';

/// Hamle üretimi + saldırı/şah tespiti. Tamamen saf Dart, test edilebilir.
class MoveGen {
  static const List<List<int>> _knightDeltas = [
    [1, 2],
    [2, 1],
    [2, -1],
    [1, -2],
    [-1, -2],
    [-2, -1],
    [-2, 1],
    [-1, 2],
  ];
  static const List<List<int>> _kingDeltas = [
    [1, 0],
    [1, 1],
    [0, 1],
    [-1, 1],
    [-1, 0],
    [-1, -1],
    [0, -1],
    [1, -1],
  ];
  static const List<List<int>> _bishopDirs = [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ];
  static const List<List<int>> _rookDirs = [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
  ];

  /// [target] karesi [by] renkli herhangi bir taş tarafından tehdit ediliyor mu?
  static bool isSquareAttacked(Board b, int target, PieceColor by) {
    final tf = Square.fileOf(target);
    final tr = Square.rankOf(target);

    // Piyon tehdidi: 'by' piyonu çapraz-ileri tehdit eder.
    final pawnDir = by == PieceColor.white ? 1 : -1;
    for (final df in const [-1, 1]) {
      final f = tf + df;
      final r = tr - pawnDir; // 'by' piyonunun bulunması gereken kare
      if (Square.onBoard(f, r)) {
        final p = b.squares[Square.of(f, r)];
        if (p != null && p.color == by && p.type == PieceType.pawn) return true;
      }
    }
    // At
    for (final d in _knightDeltas) {
      final f = tf + d[0], r = tr + d[1];
      if (Square.onBoard(f, r)) {
        final p = b.squares[Square.of(f, r)];
        if (p != null && p.color == by && p.type == PieceType.knight) {
          return true;
        }
      }
    }
    // Şah
    for (final d in _kingDeltas) {
      final f = tf + d[0], r = tr + d[1];
      if (Square.onBoard(f, r)) {
        final p = b.squares[Square.of(f, r)];
        if (p != null && p.color == by && p.type == PieceType.king) return true;
      }
    }
    // Fil / Vezir (çaprazlar)
    for (final d in _bishopDirs) {
      int f = tf + d[0], r = tr + d[1];
      while (Square.onBoard(f, r)) {
        final p = b.squares[Square.of(f, r)];
        if (p != null) {
          if (p.color == by &&
              (p.type == PieceType.bishop || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        f += d[0];
        r += d[1];
      }
    }
    // Kale / Vezir (düz)
    for (final d in _rookDirs) {
      int f = tf + d[0], r = tr + d[1];
      while (Square.onBoard(f, r)) {
        final p = b.squares[Square.of(f, r)];
        if (p != null) {
          if (p.color == by &&
              (p.type == PieceType.rook || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        f += d[0];
        r += d[1];
      }
    }
    return false;
  }

  /// Sözde-yasal hamleler (şah bırakma kontrolü yapılmaz).
  static List<Move> pseudoLegal(Board b) {
    final moves = <Move>[];
    final us = b.turn;
    for (int from = 0; from < 64; from++) {
      final p = b.squares[from];
      if (p == null || p.color != us) continue;
      final f = Square.fileOf(from), r = Square.rankOf(from);
      switch (p.type) {
        case PieceType.pawn:
          _pawnMoves(b, from, f, r, us, moves);
          break;
        case PieceType.knight:
          for (final d in _knightDeltas) {
            _addStep(b, from, f + d[0], r + d[1], us, moves);
          }
          break;
        case PieceType.bishop:
          _slide(b, from, f, r, us, _bishopDirs, moves);
          break;
        case PieceType.rook:
          _slide(b, from, f, r, us, _rookDirs, moves);
          break;
        case PieceType.queen:
          _slide(b, from, f, r, us, _bishopDirs, moves);
          _slide(b, from, f, r, us, _rookDirs, moves);
          break;
        case PieceType.king:
          for (final d in _kingDeltas) {
            _addStep(b, from, f + d[0], r + d[1], us, moves);
          }
          _castling(b, from, us, moves);
          break;
      }
    }
    return moves;
  }

  static void _addStep(
    Board b,
    int from,
    int f,
    int r,
    PieceColor us,
    List<Move> moves,
  ) {
    if (!Square.onBoard(f, r)) return;
    final to = Square.of(f, r);
    final t = b.squares[to];
    // Şah alınamaz; oyun şah mat ile biter. Bu hedefi üretmek, özellikle
    // şahların yan yana olduğu pozisyonlarda sahte yasal hamle oluşturur.
    if (t == null || (t.color != us && t.type != PieceType.king)) {
      moves.add(Move(from, to));
    }
  }

  static void _slide(
    Board b,
    int from,
    int f,
    int r,
    PieceColor us,
    List<List<int>> dirs,
    List<Move> moves,
  ) {
    for (final d in dirs) {
      int nf = f + d[0], nr = r + d[1];
      while (Square.onBoard(nf, nr)) {
        final to = Square.of(nf, nr);
        final t = b.squares[to];
        if (t == null) {
          moves.add(Move(from, to));
        } else {
          if (t.color != us && t.type != PieceType.king) {
            moves.add(Move(from, to));
          }
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
  }

  static void _pawnMoves(
    Board b,
    int from,
    int f,
    int r,
    PieceColor us,
    List<Move> moves,
  ) {
    final dir = us == PieceColor.white ? 1 : -1;
    final startRank = us == PieceColor.white ? 1 : 6;
    final promoRank = us == PieceColor.white ? 7 : 0;

    // Tek ileri
    final r1 = r + dir;
    if (Square.onBoard(f, r1) && b.squares[Square.of(f, r1)] == null) {
      _addPawnMove(from, Square.of(f, r1), r1 == promoRank, moves);
      // Çift ileri (sadece başlangıç sırasından, ara kare boşsa)
      if (r == startRank) {
        final r2 = r + 2 * dir;
        if (b.squares[Square.of(f, r2)] == null) {
          moves.add(Move(from, Square.of(f, r2)));
        }
      }
    }
    // Çapraz alışlar + geçerken-al
    for (final df in const [-1, 1]) {
      final cf = f + df, cr = r + dir;
      if (!Square.onBoard(cf, cr)) continue;
      final to = Square.of(cf, cr);
      final t = b.squares[to];
      if (t != null && t.color != us && t.type != PieceType.king) {
        _addPawnMove(from, to, cr == promoRank, moves);
      } else if (t == null && b.enPassant == to) {
        final victim = b.squares[Square.of(cf, r)];
        if (victim != null &&
            victim.color != us &&
            victim.type == PieceType.pawn) {
          moves.add(Move(from, to, isEnPassant: true));
        }
      }
    }
  }

  static void _addPawnMove(int from, int to, bool promo, List<Move> moves) {
    if (promo) {
      for (final pt in const [
        PieceType.queen,
        PieceType.rook,
        PieceType.bishop,
        PieceType.knight,
      ]) {
        moves.add(Move(from, to, promotion: pt));
      }
    } else {
      moves.add(Move(from, to));
    }
  }

  static void _castling(Board b, int from, PieceColor us, List<Move> moves) {
    final rank = us == PieceColor.white ? 0 : 7;
    if (from != Square.of(4, rank)) return; // şah ev karesinde olmalı
    final them = us.opposite;
    if (isSquareAttacked(b, from, them)) return; // şahtan rok yapılamaz

    final kingRight =
        us == PieceColor.white ? Castling.whiteKing : Castling.blackKing;
    final queenRight =
        us == PieceColor.white ? Castling.whiteQueen : Castling.blackQueen;

    // Kısa rok: f,g boş; e,f,g tehdit altında değil; h'de kale.
    if ((b.castling & kingRight) != 0) {
      final f1 = Square.of(5, rank),
          g1 = Square.of(6, rank),
          h1 = Square.of(7, rank);
      final rook = b.squares[h1];
      if (b.squares[f1] == null &&
          b.squares[g1] == null &&
          rook != null &&
          rook.type == PieceType.rook &&
          rook.color == us &&
          !isSquareAttacked(b, f1, them) &&
          !isSquareAttacked(b, g1, them)) {
        moves.add(Move(from, g1, isCastle: true));
      }
    }
    // Uzun rok: b,c,d boş; e,d,c tehdit altında değil; a'da kale.
    if ((b.castling & queenRight) != 0) {
      final d1 = Square.of(3, rank),
          c1 = Square.of(2, rank),
          b1 = Square.of(1, rank),
          a1 = Square.of(0, rank);
      final rook = b.squares[a1];
      if (b.squares[d1] == null &&
          b.squares[c1] == null &&
          b.squares[b1] == null &&
          rook != null &&
          rook.type == PieceType.rook &&
          rook.color == us &&
          !isSquareAttacked(b, d1, them) &&
          !isSquareAttacked(b, c1, them)) {
        moves.add(Move(from, c1, isCastle: true));
      }
    }
  }

  /// Tam yasal hamleler (kendi şahını tehdide bırakanlar elenir).
  static List<Move> legal(Board b) {
    final us = b.turn;
    final them = us.opposite;
    final result = <Move>[];
    for (final m in pseudoLegal(b)) {
      final nb = b.apply(m);
      final ks = nb.kingSquare(us);
      if (ks != -1 && !isSquareAttacked(nb, ks, them)) {
        result.add(m);
      }
    }
    return result;
  }

  /// Position identity used by repetition rules.
  ///
  /// FIDE repetition compares the legal moves available from a position. An
  /// en-passant target therefore matters only when the side to move can
  /// actually make that en-passant capture without exposing its king.
  static String repetitionKey(Board b) {
    final hasLegalEnPassant =
        b.enPassant != null && legal(b).any((move) => move.isEnPassant);
    return b.positionKey(includeEnPassant: hasLegalEnPassant);
  }

  /// [c] rengi şahta mı?
  static bool inCheck(Board b, PieceColor c) {
    final ks = b.kingSquare(c);
    return ks != -1 && isSquareAttacked(b, ks, c.opposite);
  }
}
