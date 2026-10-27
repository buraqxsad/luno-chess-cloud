import 'move.dart';
import 'piece.dart';
import 'square.dart';

/// Rok hakları için bit bayrakları.
class Castling {
  static const int whiteKing = 1;
  static const int whiteQueen = 2;
  static const int blackKing = 4;
  static const int blackQueen = 8;
  static const int all = whiteKing | whiteQueen | blackKing | blackQueen;
}

/// Değişmez (immutable) tahta durumu. Her hamle yeni bir Board üretir;
/// bu, geri-al/kart-efekti simülasyonlarını basit ve hatasız kılar.
class Board {
  final List<Piece?> squares; // uzunluk 64
  final PieceColor turn;
  final int castling; // bit maskesi
  final int? enPassant; // geçerken-al hedef karesi, ya da null
  final int halfmoveClock;
  final int fullmoveNumber;

  Board({
    required List<Piece?> squares,
    required this.turn,
    required this.castling,
    required this.enPassant,
    required this.halfmoveClock,
    required this.fullmoveNumber,
  }) : squares = List<Piece?>.unmodifiable(squares);

  /// Standart başlangıç dizilimi.
  factory Board.start() {
    final sq = List<Piece?>.filled(64, null);
    const back = [
      PieceType.rook,
      PieceType.knight,
      PieceType.bishop,
      PieceType.queen,
      PieceType.king,
      PieceType.bishop,
      PieceType.knight,
      PieceType.rook,
    ];
    for (int f = 0; f < 8; f++) {
      sq[Square.of(f, 0)] = Piece(PieceColor.white, back[f]);
      sq[Square.of(f, 1)] = const Piece(PieceColor.white, PieceType.pawn);
      sq[Square.of(f, 6)] = const Piece(PieceColor.black, PieceType.pawn);
      sq[Square.of(f, 7)] = Piece(PieceColor.black, back[f]);
    }
    return Board(
      squares: sq,
      turn: PieceColor.white,
      castling: Castling.all,
      enPassant: null,
      halfmoveClock: 0,
      fullmoveNumber: 1,
    );
  }

  /// FEN dizesinden tahta kur (test/puzzle/senkron için).
  /// Örn: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  factory Board.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4 || parts.length > 6) {
      throw FormatException('FEN must contain 4 to 6 fields');
    }
    final ranks = parts[0].split('/'); // ranks[0]=8. sıra .. ranks[7]=1. sıra
    if (ranks.length != 8) throw const FormatException('FEN needs 8 ranks');
    final sq = List<Piece?>.filled(64, null);
    const types = {
      'p': PieceType.pawn,
      'n': PieceType.knight,
      'b': PieceType.bishop,
      'r': PieceType.rook,
      'q': PieceType.queen,
      'k': PieceType.king,
    };
    for (int r = 0; r < 8; r++) {
      final myRank = 7 - r;
      int file = 0;
      for (final ch in ranks[r].split('')) {
        final digit = int.tryParse(ch);
        if (digit != null) {
          if (digit < 1 || digit > 8) {
            throw const FormatException('Invalid FEN empty-square count');
          }
          file += digit;
        } else {
          final color =
              ch == ch.toUpperCase() ? PieceColor.white : PieceColor.black;
          final type = types[ch.toLowerCase()];
          if (type == null || file >= 8) {
            throw const FormatException('Invalid FEN piece placement');
          }
          sq[Square.of(file, myRank)] = Piece(color, type);
          file++;
        }
      }
      if (file != 8) throw const FormatException('FEN rank is not 8 files');
    }
    final PieceColor turn;
    if (parts[1] == 'w') {
      turn = PieceColor.white;
    } else if (parts[1] == 'b') {
      turn = PieceColor.black;
    } else {
      throw const FormatException('Invalid FEN active color');
    }
    int castling = 0;
    final cr = parts[2];
    if (cr != '-') {
      for (final flag in cr.split('')) {
        switch (flag) {
          case 'K':
            castling |= Castling.whiteKing;
          case 'Q':
            castling |= Castling.whiteQueen;
          case 'k':
            castling |= Castling.blackKing;
          case 'q':
            castling |= Castling.blackQueen;
          default:
            throw const FormatException('Invalid FEN castling rights');
        }
      }
    }
    int? ep;
    if (parts[3] != '-') {
      final epText = parts[3];
      if (!RegExp(r'^[a-h][36]$').hasMatch(epText)) {
        throw const FormatException('Invalid FEN en-passant square');
      }
      final f = epText.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final rk = int.parse(epText[1]) - 1;
      ep = Square.of(f, rk);
    }
    final halfmove = parts.length > 4 ? int.tryParse(parts[4]) : 0;
    final fullmove = parts.length > 5 ? int.tryParse(parts[5]) : 1;
    if (halfmove == null || halfmove < 0 || fullmove == null || fullmove < 1) {
      throw const FormatException('Invalid FEN move counters');
    }
    return Board(
      squares: sq,
      turn: turn,
      castling: castling,
      enPassant: ep,
      halfmoveClock: halfmove,
      fullmoveNumber: fullmove,
    );
  }

  Piece? pieceAt(int idx) => squares[idx];

  int kingSquare(PieceColor c) {
    for (int i = 0; i < 64; i++) {
      final p = squares[i];
      if (p != null && p.type == PieceType.king && p.color == c) return i;
    }
    return -1;
  }

  /// FEN-like position identity. Move counters are omitted because they do
  /// not change whether a position is repeated.
  ///
  /// [includeEnPassant] is kept configurable because a raw FEN identity and
  /// a repetition identity differ when the en-passant square exists but no
  /// legal en-passant capture is available. Use [MoveGen.repetitionKey] for
  /// threefold/fivefold repetition checks.
  String positionKey({bool includeEnPassant = true}) {
    final placement = StringBuffer();
    for (int rank = 7; rank >= 0; rank--) {
      int empty = 0;
      for (int file = 0; file < 8; file++) {
        final p = squares[Square.of(file, rank)];
        if (p == null) {
          empty++;
          continue;
        }
        if (empty > 0) {
          placement.write(empty);
          empty = 0;
        }
        final symbol = switch (p.type) {
          PieceType.pawn => 'p',
          PieceType.knight => 'n',
          PieceType.bishop => 'b',
          PieceType.rook => 'r',
          PieceType.queen => 'q',
          PieceType.king => 'k',
        };
        placement.write(
          p.color == PieceColor.white ? symbol.toUpperCase() : symbol,
        );
      }
      if (empty > 0) placement.write(empty);
      if (rank > 0) placement.write('/');
    }
    final rights = StringBuffer();
    if ((castling & Castling.whiteKing) != 0) rights.write('K');
    if ((castling & Castling.whiteQueen) != 0) rights.write('Q');
    if ((castling & Castling.blackKing) != 0) rights.write('k');
    if ((castling & Castling.blackQueen) != 0) rights.write('q');
    final ep =
        !includeEnPassant || enPassant == null
            ? '-'
            : '${String.fromCharCode(97 + Square.fileOf(enPassant!))}${Square.rankOf(enPassant!) + 1}';
    final castlingText = rights.toString();
    return '$placement ${turn == PieceColor.white ? 'w' : 'b'} '
        '${castlingText.isEmpty ? '-' : castlingText} $ep';
  }

  /// True when the fifty-move draw can be claimed by the side to move.
  bool get isFiftyMoveRule => halfmoveClock >= 100;

  /// True when the automatic 75-move draw threshold has been reached.
  /// Checkmate takes precedence when the last move also checkmates.
  bool get isSeventyFiveMoveRule => halfmoveClock >= 150;

  /// True when no legal checkmate material exists under orthodox chess rules.
  bool get isInsufficientMaterial {
    final minors = <int>[];
    for (int i = 0; i < 64; i++) {
      final p = squares[i];
      if (p == null || p.type == PieceType.king) continue;
      if (p.type == PieceType.bishop || p.type == PieceType.knight) {
        minors.add(i);
      } else {
        return false;
      }
    }
    if (minors.length <= 1) return true;
    final pieces = minors.map((i) => squares[i]!).toList(growable: false);
    if (pieces.every((p) => p.type == PieceType.bishop)) {
      final colors =
          minors.map((i) => (Square.fileOf(i) + Square.rankOf(i)) & 1).toSet();
      return colors.length == 1;
    }
    return false;
  }

  /// [move] uygulanmış yeni bir tahta döndürür.
  /// Hamlenin (sözde-)yasal olduğu varsayılır.
  Board apply(Move move) {
    final sq = List<Piece?>.of(squares);
    final piece = sq[move.from]!;
    final wasCapture = squares[move.to] != null || move.isEnPassant;
    int newCastling = castling;
    int? newEp;

    // Taşı taşı (terfi varsa türü değiştir).
    sq[move.to] =
        move.promotion == null ? piece : Piece(piece.color, move.promotion!);
    sq[move.from] = null;

    // Geçerken-al: hedefin arkasındaki piyonu kaldır.
    if (move.isEnPassant) {
      final dir = piece.color == PieceColor.white ? -1 : 1;
      sq[move.to + dir * 8] = null;
    }

    // Rok: kaleyi de taşı.
    if (move.isCastle) {
      final rank = Square.rankOf(move.from);
      if (Square.fileOf(move.to) == 6) {
        // kısa rok
        sq[Square.of(5, rank)] = sq[Square.of(7, rank)];
        sq[Square.of(7, rank)] = null;
      } else {
        // uzun rok
        sq[Square.of(3, rank)] = sq[Square.of(0, rank)];
        sq[Square.of(0, rank)] = null;
      }
    }

    // Şah/kale oynadıysa ya da kale alındıysa rok haklarını iptal et.
    void revoke(int idx) {
      if (idx == Square.of(4, 0)) {
        newCastling &= ~(Castling.whiteKing | Castling.whiteQueen);
      }
      if (idx == Square.of(4, 7)) {
        newCastling &= ~(Castling.blackKing | Castling.blackQueen);
      }
      if (idx == Square.of(0, 0)) newCastling &= ~Castling.whiteQueen;
      if (idx == Square.of(7, 0)) newCastling &= ~Castling.whiteKing;
      if (idx == Square.of(0, 7)) newCastling &= ~Castling.blackQueen;
      if (idx == Square.of(7, 7)) newCastling &= ~Castling.blackKing;
    }

    revoke(move.from);
    revoke(move.to);

    // Çift piyon hamlesinde geçerken-al hedefi belirle.
    if (piece.type == PieceType.pawn &&
        (Square.rankOf(move.to) - Square.rankOf(move.from)).abs() == 2) {
      newEp = (move.from + move.to) ~/ 2;
    }

    final resetClock = piece.type == PieceType.pawn || wasCapture;

    return Board(
      squares: sq,
      turn: turn.opposite,
      castling: newCastling,
      enPassant: newEp,
      halfmoveClock: resetClock ? 0 : halfmoveClock + 1,
      fullmoveNumber:
          turn == PieceColor.black ? fullmoveNumber + 1 : fullmoveNumber,
    );
  }
}
