import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/move_gen.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import 'mpiece.dart';

class Trap {
  PieceColor by;
  int dur;
  int lvl;
  int life;
  bool revealed;
  final Set<PieceColor> revealedFor;

  Trap(
    this.by,
    this.dur,
    this.lvl,
    this.life, {
    this.revealed = false,
    Set<PieceColor>? revealedFor,
  }) : revealedFor = {...?revealedFor};

  bool isRevealedFor(PieceColor viewer) =>
      revealed || by == viewer || revealedFor.contains(viewer);
}

class Shield {
  PieceColor by;
  int dur;
  Shield(this.by, this.dur);
}

enum MatchResult { ongoing, whiteWins, blackWins, draw }

/// Kart + mana destekli canlı maç durumu. Saf motorun (Board/MoveGen)
/// kuralları üstüne kart katmanını ekler. HTML sürümünden birebir port.
class MatchState {
  final List<MPiece?> board = List<MPiece?>.filled(64, null);
  PieceColor turn = PieceColor.white;
  final Map<int, Trap> traps = {};
  final Map<int, Shield> shields = {};
  final Map<int, int> blocks = {};
  final Map<PieceColor, int> fog = {PieceColor.white: 0, PieceColor.black: 0};
  final Map<PieceColor, int> cardBlock = {
    PieceColor.white: 0,
    PieceColor.black: 0,
  };
  final Map<PieceColor, int> mediumRevealUntil = {
    PieceColor.white: 0,
    PieceColor.black: 0,
  };
  final Map<PieceColor, int> mana = {PieceColor.white: 1, PieceColor.black: 0};

  int? epTarget;
  bool cardUsed = false;
  int moveCount = 0;
  int halfmoveClock = 0;
  MatchResult result = MatchResult.ongoing;

  final Map<String, int> _positionCounts = {};

  /// Monotonically increases when the board/effect layer changes. The board
  /// painter uses this instead of repainting on every parent rebuild.
  int visualRevision = 0;

  List<String> whiteHand = [];
  List<String> blackHand = [];

  int? lastFrom, lastTo;
  MPiece? lastCaptured;
  int? lastCaptureSquare;

  MatchState();

  factory MatchState.newGame({List<String>? white, List<String>? black}) {
    final m = MatchState();
    const back = [
      PieceType.rook, PieceType.knight, PieceType.bishop, PieceType.queen,
      PieceType.king, PieceType.bishop, PieceType.knight, PieceType.rook, //
    ];
    for (int f = 0; f < 8; f++) {
      m.board[Square.of(f, 0)] = MPiece(PieceColor.white, back[f]);
      m.board[Square.of(f, 1)] = MPiece(PieceColor.white, PieceType.pawn);
      m.board[Square.of(f, 6)] = MPiece(PieceColor.black, PieceType.pawn);
      m.board[Square.of(f, 7)] = MPiece(PieceColor.black, back[f]);
    }
    m.whiteHand = List<String>.of(white ?? kStarterCards);
    m.blackHand = List<String>.of(black ?? kStarterCards);
    m._recordPosition();
    return m;
  }

  bool get over => result != MatchResult.ongoing;

  /// FIDE'de 50 hamle kuralı otomatik bitiş değildir; oyuncu talep edebilir.
  /// Kart etkileri aktifken bu hak, kart varyantının kendi kurallarına bırakılır.
  bool get canClaimFiftyMove =>
      isOrthodoxPosition && !over && halfmoveClock >= 100;

  /// FIDE'de üç tekrar talep edilebilir; beş tekrar ise otomatik beraberliktir.
  bool get canClaimThreefoldRepetition {
    if (!isOrthodoxPosition || over) return false;
    final key = MoveGen.repetitionKey(_standardPosition());
    return (_positionCounts[key] ?? 0) >= 3;
  }

  /// Mevcut saf satranç konumunda 50 hamle beraberliğini talep eder.
  bool claimFiftyMove() {
    if (!canClaimFiftyMove) return false;
    result = MatchResult.draw;
    return true;
  }

  /// Mevcut saf satranç konumunda üç tekrar beraberliğini talep eder.
  bool claimThreefoldRepetition() {
    if (!canClaimThreefoldRepetition) return false;
    result = MatchResult.draw;
    return true;
  }

  PieceColor get _enemy =>
      turn == PieceColor.white ? PieceColor.black : PieceColor.white;
  PieceColor _opp(PieceColor c) =>
      c == PieceColor.white ? PieceColor.black : PieceColor.white;
  int _dir(PieceColor c) => c == PieceColor.white ? 1 : -1;
  List<String> handOf(PieceColor c) =>
      c == PieceColor.white ? whiteHand : blackHand;

  bool _handContains(String key, PieceColor color) {
    final definition = kCards[key];
    if (definition == null) return false;
    return handOf(color).any((held) {
      if (held == key) return true;
      final heldDefinition = kCards[held];
      if (heldDefinition == null || definition.family.isEmpty) return false;
      if (held == definition.family) return definition.level == 1;
      return heldDefinition.family == definition.family &&
          heldDefinition.level >= definition.level;
    });
  }

  /// [from]->[to] kare çiftini, bayrakları (ep/rok/terfi) çözülmüş bir
  /// motor Move'una çevirir (AI araması için).
  Move asMove(int from, int to) {
    final p = board[from]!;
    final isEp = _isEnPassant(from, to);
    final isCastle =
        p.type == PieceType.king &&
        (Square.fileOf(to) - Square.fileOf(from)).abs() == 2;
    final promo =
        (p.type == PieceType.pawn &&
                (Square.rankOf(to) == 7 || Square.rankOf(to) == 0))
            ? PieceType.queen
            : null;
    return Move(
      from,
      to,
      isEnPassant: isEp,
      isCastle: isCastle,
      promotion: promo,
    );
  }

  int kingIdx(PieceColor c) {
    for (int i = 0; i < 64; i++) {
      final p = board[i];
      if (p != null && p.type == PieceType.king && p.color == c) return i;
    }
    return -1;
  }

  // ── Saf motor anlık görüntüsü (saldırı tespiti + AI için yeniden kullanılır) ──
  Board pureBoard() {
    final sq = List<Piece?>.filled(64, null);
    for (int i = 0; i < 64; i++) {
      final p = board[i];
      if (p != null) sq[i] = Piece(p.color, p.type);
    }
    int castling = 0;
    final wk = board[Square.of(4, 0)];
    if (wk != null &&
        wk.type == PieceType.king &&
        wk.color == PieceColor.white &&
        !wk.moved) {
      final rh = board[Square.of(7, 0)];
      if (rh != null && rh.type == PieceType.rook && !rh.moved) {
        castling |= Castling.whiteKing;
      }
      final ra = board[Square.of(0, 0)];
      if (ra != null && ra.type == PieceType.rook && !ra.moved) {
        castling |= Castling.whiteQueen;
      }
    }
    final bk = board[Square.of(4, 7)];
    if (bk != null &&
        bk.type == PieceType.king &&
        bk.color == PieceColor.black &&
        !bk.moved) {
      final rh = board[Square.of(7, 7)];
      if (rh != null && rh.type == PieceType.rook && !rh.moved) {
        castling |= Castling.blackKing;
      }
      final ra = board[Square.of(0, 7)];
      if (ra != null && ra.type == PieceType.rook && !ra.moved) {
        castling |= Castling.blackQueen;
      }
    }
    return Board(
      squares: sq,
      turn: turn,
      castling: castling,
      enPassant: epTarget,
      halfmoveClock: halfmoveClock,
      fullmoveNumber: 1,
    );
  }

  /// True when no card effect changes orthodox chess movement or captures.
  /// Hands and mana do not affect this check; a match can still be in its
  /// opening card phase while the board itself follows standard chess.
  bool get isOrthodoxPosition {
    if (traps.isNotEmpty || shields.isNotEmpty || blocks.isNotEmpty) {
      return false;
    }
    if (fog.values.any((value) => value > 0) ||
        cardBlock.values.any((value) => value > 0)) {
      return false;
    }
    for (final piece in board) {
      if (piece == null) continue;
      if (piece.frozen > 0 ||
          piece.resist > 0 ||
          piece.resistLock ||
          piece.barbarian ||
          piece.poisoned ||
          piece.poisonedDur > 0 ||
          piece.plagueUntil > moveCount ||
          piece.trapped > 0 ||
          piece.angryN ||
          piece.angryB ||
          piece.ghost ||
          piece.ghostDur > 0 ||
          piece.linkTo != null ||
          piece.gluePick) {
        return false;
      }
    }
    return true;
  }

  bool attacked(int idx, PieceColor by) =>
      isOrthodoxPosition
          ? MoveGen.isSquareAttacked(pureBoard(), idx, by)
          : _isSquareAttackedWithCards(board, idx, by);

  bool _isSquareAttackedWithCards(
    List<MPiece?> pieces,
    int target,
    PieceColor by,
  ) {
    if (target < 0 || target >= 64) return false;
    final targetFile = Square.fileOf(target);
    final targetRank = Square.rankOf(target);
    for (int from = 0; from < 64; from++) {
      final piece = pieces[from];
      if (piece == null || piece.color != by) continue;
      final file = Square.fileOf(from);
      final rank = Square.rankOf(from);

      if (piece.type == PieceType.pawn) {
        if (targetRank == rank + _dir(by) && (targetFile - file).abs() == 1) {
          return true;
        }
        continue;
      }
      if (piece.type == PieceType.knight) {
        final deltaRank = targetRank - rank;
        final deltaFile = (targetFile - file).abs();
        final attacks =
            piece.angryN
                ? deltaRank == 3 * _dir(by) && deltaFile == 1
                : (deltaRank.abs() == 2 && deltaFile == 1) ||
                    (deltaRank.abs() == 1 && deltaFile == 2);
        if (attacks) return true;
        continue;
      }
      if (piece.type == PieceType.king) {
        if (from != target &&
            (targetFile - file).abs() <= 1 &&
            (targetRank - rank).abs() <= 1) {
          return true;
        }
        continue;
      }

      final directions = <List<int>>[];
      if (piece.type == PieceType.rook || piece.type == PieceType.queen) {
        directions.addAll(const [
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ]);
      }
      if (piece.type == PieceType.bishop || piece.type == PieceType.queen) {
        directions.addAll(const [
          [1, 1],
          [1, -1],
          [-1, 1],
          [-1, -1],
        ]);
      }
      if (piece.type == PieceType.bishop && piece.angryB) {
        directions.addAll(const [
          [1, 0],
          [-1, 0],
        ]);
      }
      for (final direction in directions) {
        var nextFile = file + direction[0];
        var nextRank = rank + direction[1];
        while (Square.onBoard(nextFile, nextRank)) {
          final square = Square.of(nextFile, nextRank);
          if (square == target) return true;
          if (pieces[square] != null) break;
          nextFile += direction[0];
          nextRank += direction[1];
        }
      }
    }
    return false;
  }

  bool inCheck(PieceColor c) {
    final k = kingIdx(c);
    return k != -1 && attacked(k, _opp(c));
  }

  // ── Kareye giriş engelleri (tuzak lvl1 / düşman kalkan / blok) ──
  bool _entryBlocked(int to, PieceColor mover) {
    final t = traps[to];
    if (t != null && t.lvl == 1) return true; // lvl1 herkese kapalı
    final s = shields[to];
    if (s != null && s.by != mover) return true; // düşman kalkanı
    if ((blocks[to] ?? 0) > 0) return true;
    return false;
  }

  // ── Sözde hamleler (kart modifikasyonlu) ──
  List<int> _pseudoFrom(int from) {
    final p = board[from];
    if (p == null) return const [];
    final us = p.color;
    final f = Square.fileOf(from), r = Square.rankOf(from);
    final out = <int>[];

    void step(int nf, int nr) {
      if (!Square.onBoard(nf, nr)) return;
      final to = Square.of(nf, nr);
      final t = board[to];
      if (t == null || (t.color != us && t.type != PieceType.king)) {
        out.add(to);
      }
    }

    void slide(List<List<int>> dirs) {
      for (final d in dirs) {
        int nf = f + d[0], nr = r + d[1];
        while (Square.onBoard(nf, nr)) {
          final to = Square.of(nf, nr);
          final t = board[to];
          if (t == null) {
            out.add(to);
          } else {
            if (t.color != us && t.type != PieceType.king) out.add(to);
            break;
          }
          nf += d[0];
          nr += d[1];
        }
      }
    }

    switch (p.type) {
      case PieceType.pawn:
        final dir = _dir(us);
        if (p.barbarian) {
          for (int bs = 1; bs <= 2; bs++) {
            final nr = r + dir * bs;
            if (!Square.onBoard(f, nr)) break;
            if (board[Square.of(f, nr)] != null) break;
            out.add(Square.of(f, nr));
          }
        } else {
          final nr = r + dir;
          if (Square.onBoard(f, nr) && board[Square.of(f, nr)] == null) {
            out.add(Square.of(f, nr));
            final start = us == PieceColor.white ? 1 : 6;
            if (r == start && board[Square.of(f, r + 2 * dir)] == null) {
              out.add(Square.of(f, r + 2 * dir));
            }
          }
        }
        // Çapraz alış + geçerken-al
        for (final df in const [-1, 1]) {
          final cf = f + df, cr = r + dir;
          if (!Square.onBoard(cf, cr)) continue;
          final to = Square.of(cf, cr);
          final t = board[to];
          if (t != null && t.color != us && t.type != PieceType.king) {
            out.add(to);
          } else if (t == null && epTarget == to) {
            final victim = board[Square.of(cf, r)];
            if (victim != null &&
                victim.color != us &&
                victim.type == PieceType.pawn &&
                !victim.barbarian &&
                victim.resist <= 0) {
              out.add(to);
            }
          }
        }
        break;
      case PieceType.knight:
        if (p.angryN) {
          final fd = 3 * _dir(us);
          step(f + 1, r + fd);
          step(f - 1, r + fd);
        } else {
          for (final d in const [
            [1, 2],
            [2, 1],
            [2, -1],
            [1, -2],
            [-1, -2],
            [-2, -1],
            [-2, 1],
            [-1, 2],
          ]) {
            step(f + d[0], r + d[1]);
          }
        }
        break;
      case PieceType.bishop:
        slide(const [
          [1, 1],
          [1, -1],
          [-1, 1],
          [-1, -1],
        ]);
        if (p.angryB) {
          step(f + 1, r);
          step(f - 1, r);
        }
        break;
      case PieceType.rook:
        slide(const [
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ]);
        break;
      case PieceType.queen:
        slide(const [
          [1, 1],
          [1, -1],
          [-1, 1],
          [-1, -1],
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ]);
        break;
      case PieceType.king:
        for (final d in const [
          [1, 0],
          [1, 1],
          [0, 1],
          [-1, 1],
          [-1, 0],
          [-1, -1],
          [0, -1],
          [1, -1],
        ]) {
          step(f + d[0], r + d[1]);
        }
        _castle(from, us, out);
        break;
    }
    return out;
  }

  void _castle(int from, PieceColor us, List<int> out) {
    final rank = us == PieceColor.white ? 0 : 7;
    if (from != Square.of(4, rank)) return;
    final k = board[from];
    if (k == null || k.moved) return;
    final them = _opp(us);
    if (attacked(from, them)) return;

    bool castBlocked(int idx) {
      final t = traps[idx];
      if (t != null && t.lvl == 1) return true;
      final s = shields[idx];
      if (s != null && s.by != us) return true;
      return (blocks[idx] ?? 0) > 0;
    }

    // kısa
    final h = board[Square.of(7, rank)];
    if (h != null && h.type == PieceType.rook && h.color == us && !h.moved) {
      final f1 = Square.of(5, rank), g1 = Square.of(6, rank);
      if (board[f1] == null &&
          board[g1] == null &&
          !attacked(f1, them) &&
          !attacked(g1, them) &&
          !castBlocked(f1) &&
          !castBlocked(g1)) {
        out.add(g1);
      }
    }
    // uzun
    final a = board[Square.of(0, rank)];
    if (a != null && a.type == PieceType.rook && a.color == us && !a.moved) {
      final d1 = Square.of(3, rank),
          c1 = Square.of(2, rank),
          b1 = Square.of(1, rank);
      if (board[d1] == null &&
          board[c1] == null &&
          board[b1] == null &&
          !attacked(d1, them) &&
          !attacked(c1, them) &&
          !castBlocked(d1) &&
          !castBlocked(c1)) {
        out.add(c1);
      }
    }
  }

  bool _isEnPassant(int from, int to) {
    final p = board[from];
    if (p == null || p.type != PieceType.pawn) return false;
    final victim = board[Square.of(Square.fileOf(to), Square.rankOf(from))];
    return Square.fileOf(from) != Square.fileOf(to) &&
        board[to] == null &&
        epTarget == to &&
        victim != null &&
        victim.color != p.color &&
        victim.type == PieceType.pawn &&
        !victim.barbarian &&
        victim.resist <= 0;
  }

  bool _selfCheckAfter(int from, int to) {
    final us = board[from]!.color;
    final isEp = _isEnPassant(from, to);
    final isCastle =
        board[from]!.type == PieceType.king &&
        (Square.fileOf(to) - Square.fileOf(from)).abs() == 2;
    final simulated = List<MPiece?>.generate(
      64,
      (index) => board[index]?.clone(),
    );
    if (isEp) {
      simulated[Square.of(Square.fileOf(to), Square.rankOf(from))] = null;
    }
    if (isCastle) {
      final rank = Square.rankOf(from);
      final rookFrom = Square.of(
        Square.fileOf(to) > Square.fileOf(from) ? 7 : 0,
        rank,
      );
      final rookTo = Square.of(
        Square.fileOf(to) > Square.fileOf(from) ? 5 : 3,
        rank,
      );
      simulated[rookTo] = simulated[rookFrom];
      simulated[rookFrom] = null;
    }
    final moving = simulated[from];
    if (moving == null) return true;
    simulated[to] = moving;
    simulated[from] = null;
    if (moving.type == PieceType.pawn &&
        (Square.rankOf(to) == 0 || Square.rankOf(to) == 7)) {
      moving.type = PieceType.queen;
    }
    final landingTrap = traps[to];
    if (landingTrap != null &&
        landingTrap.lvl >= 3 &&
        moving.type != PieceType.king) {
      simulated[to] = null;
    }
    var kingSquare = -1;
    for (var index = 0; index < 64; index++) {
      final piece = simulated[index];
      if (piece?.color == us && piece?.type == PieceType.king) {
        kingSquare = index;
        break;
      }
    }
    return kingSquare != -1 &&
        _isSquareAttackedWithCards(simulated, kingSquare, _opp(us));
  }

  bool _linkedMoveIsLegal(int from, int to, MPiece mover) {
    final mateFrom = mover.linkTo;
    if (mover.type != PieceType.pawn || mateFrom == null) return true;
    final mate = board[mateFrom];
    if (mate == null ||
        mate.type != PieceType.pawn ||
        mate.color != mover.color ||
        mate.linkTo != from) {
      return false;
    }
    final deltaFile = Square.fileOf(to) - Square.fileOf(from);
    final deltaRank = Square.rankOf(to) - Square.rankOf(from);
    final mateFile = Square.fileOf(mateFrom) + deltaFile;
    final mateRank = Square.rankOf(mateFrom) + deltaRank;
    if (!Square.onBoard(mateFile, mateRank)) return false;
    final mateTo = Square.of(mateFile, mateRank);
    if (mateTo == to || _entryBlocked(mateTo, mover.color)) return false;
    final occupied = board[mateTo];
    if (occupied != null &&
        (occupied.color == mover.color ||
            occupied.type == PieceType.king ||
            occupied.resist > 0)) {
      return false;
    }
    final simulated = List<MPiece?>.generate(
      64,
      (index) => board[index]?.clone(),
    );
    simulated[from] = null;
    simulated[mateFrom] = null;
    simulated[to] = mover.clone();
    simulated[mateTo] = mate.clone();
    final mainTrap = traps[to];
    if (mainTrap != null &&
        mainTrap.lvl >= 3 &&
        simulated[to]?.type != PieceType.king) {
      simulated[to] = null;
    }
    final mateTrap = traps[mateTo];
    if (mateTrap != null &&
        mateTrap.lvl >= 3 &&
        simulated[mateTo]?.type != PieceType.king) {
      simulated[mateTo] = null;
    }
    var kingSquare = -1;
    for (var index = 0; index < 64; index++) {
      final piece = simulated[index];
      if (piece?.color == mover.color && piece?.type == PieceType.king) {
        kingSquare = index;
        break;
      }
    }
    return kingSquare != -1 &&
        !_isSquareAttackedWithCards(simulated, kingSquare, _opp(mover.color));
  }

  /// Bir taşın yasal hedef kareleri (kart efektleri uygulanmış).
  List<int> legalFrom(int from) => _legalFrom(from, ignoreEffects: false);

  List<int> _legalFrom(int from, {required bool ignoreEffects}) {
    final p = board[from];
    if (p == null || p.color != turn) return const [];
    if (p.ghost ||
        (!ignoreEffects &&
            (p.frozen > 0 ||
                p.plagueUntil > moveCount ||
                p.trapped > 0 ||
                p.resistLock))) {
      return const [];
    }

    if (isOrthodoxPosition) {
      return MoveGen.legal(pureBoard())
          .where((move) => move.from == from)
          .map((move) => move.to)
          .toSet()
          .toList(growable: false);
    }

    final out = <int>[];
    final f = Square.fileOf(from), r = Square.rankOf(from);
    for (final to in _pseudoFrom(from)) {
      // Giriş engeli
      if (!ignoreEffects && _entryBlocked(to, p.color)) continue;
      // Korumalı (resist) düşman taşı alınamaz
      final t = board[to];
      if (!ignoreEffects &&
          t != null &&
          t.color != p.color &&
          t.type != PieceType.king &&
          t.resist > 0) {
        continue;
      }
      // Zehirli vezir: en fazla 1 kare
      if (p.type == PieceType.queen && p.poisoned) {
        final df = (Square.fileOf(to) - f).abs(),
            dr = (Square.rankOf(to) - r).abs();
        if (df > 1 || dr > 1) continue;
      }
      // Kendi şahını tehdide bırakma
      if (p.linkTo == null && _selfCheckAfter(from, to)) continue;
      if (p.linkTo != null && !_linkedMoveIsLegal(from, to, p)) continue;
      out.add(to);
    }
    return out;
  }

  /// Tüm yasal hamleler (from,to) — sıra kimdeyse.
  List<List<int>> _allLegalWithOptions(
    PieceColor color, {
    required bool ignoreEffects,
  }) {
    final saved = turn;
    turn = color;
    final out = <List<int>>[];
    try {
      for (int i = 0; i < 64; i++) {
        final p = board[i];
        if (p == null || p.color != color) continue;
        for (final to in _legalFrom(i, ignoreEffects: ignoreEffects)) {
          out.add([i, to]);
        }
      }
    } finally {
      turn = saved;
    }
    return out;
  }

  List<List<int>> allLegal(PieceColor color) =>
      _allLegalWithOptions(color, ignoreEffects: false);

  bool _onlyBlockedByEffects(PieceColor color) =>
      allLegal(color).isEmpty &&
      _allLegalWithOptions(color, ignoreEffects: true).isNotEmpty;

  // ── Hamleyi uygula ──
  bool makeMove(int from, int to, {PieceType? promotion}) {
    if (over || from < 0 || from >= 64 || to < 0 || to >= 64) return false;
    final p = board[from];
    if (p == null || p.color != turn || !legalFrom(from).contains(to)) {
      return false;
    }
    final reachesPromotion =
        p.type == PieceType.pawn &&
        (Square.rankOf(to) == 0 || Square.rankOf(to) == 7);
    const promotions = {
      PieceType.queen,
      PieceType.rook,
      PieceType.bishop,
      PieceType.knight,
    };
    if (reachesPromotion && !promotions.contains(promotion)) return false;
    if (!reachesPromotion && promotion != null) return false;
    final wasPawn = p.type == PieceType.pawn;
    var wasCapture = board[to] != null || _isEnPassant(from, to);
    lastCaptured = null;
    lastCaptureSquare = null;
    final us = p.color;
    final ff = Square.fileOf(from), fr = Square.rankOf(from);
    final tf = Square.fileOf(to), tr = Square.rankOf(to);

    // Geçerken-al
    if (p.type == PieceType.pawn &&
        ff != tf &&
        board[to] == null &&
        epTarget == to &&
        _isEnPassant(from, to)) {
      final captureSquare = Square.of(tf, fr);
      lastCaptured = board[captureSquare];
      lastCaptureSquare = lastCaptured == null ? null : captureSquare;
      if (lastCaptured != null) _breakLink(lastCaptured!);
      board[captureSquare] = null;
    }
    // Rok
    bool castle = false;
    if (p.type == PieceType.king && (tf - ff).abs() == 2) {
      castle = true;
      if (tf > ff) {
        final rh = Square.of(7, fr), rf = Square.of(5, fr);
        board[rf] = board[rh];
        board[rh] = null;
        if (board[rf] != null) board[rf]!.moved = true;
      } else {
        final ra = Square.of(0, fr), rd = Square.of(3, fr);
        board[rd] = board[ra];
        board[ra] = null;
        if (board[rd] != null) board[rd]!.moved = true;
      }
    }

    final linkedFrom = p.linkTo;
    if (board[to] != null && board[to]!.color != us) {
      lastCaptured = board[to];
      lastCaptureSquare = to;
      _breakLink(lastCaptured!);
    }
    board[to] = p;
    board[from] = null;
    p.moved = true;

    // Terfi: orthodox chess allows queen, rook, bishop, or knight.
    if (p.type == PieceType.pawn && (tr == 7 || tr == 0)) {
      p.type = promotion!;
      _breakLink(p);
    }

    // Yeni geçerken-al hedefi
    epTarget = null;
    if (p.type == PieceType.pawn && !p.barbarian && (tr - fr).abs() == 2) {
      epTarget = (from + to) ~/ 2;
    }

    // Tuzak tetikleme (kareye basınca)
    _triggerTrap(to);

    // Tutkal: eşi de aynı vektörle kaydır
    if (!castle && linkedFrom != null && board[to] != null) {
      wasCapture =
          _moveLinkedPawn(linkedFrom, to, tf - ff, tr - fr, us) || wasCapture;
    }

    halfmoveClock = wasPawn || wasCapture ? 0 : halfmoveClock + 1;

    lastFrom = from;
    lastTo = to;
    _endTurn();
    visualRevision++;
    return true;
  }

  void _breakLink(MPiece p) {
    final mateIdx = p.linkTo;
    p.linkTo = null;
    if (mateIdx != null) {
      final mate = board[mateIdx];
      if (mate != null && mate.linkTo != null) mate.linkTo = null;
    }
  }

  void _triggerTrap(int index) {
    final trap = traps[index];
    final piece = board[index];
    if (trap == null || piece == null || trap.lvl < 2) return;
    traps.remove(index);
    if (trap.lvl == 2 || piece.type == PieceType.king) {
      piece.trapped = 2;
      return;
    }
    _breakLink(piece);
    board[index] = null;
  }

  bool _moveLinkedPawn(
    int mateFrom,
    int moverTo,
    int df,
    int dr,
    PieceColor us,
  ) {
    final mate = board[mateFrom];
    final mover = board[moverTo];
    if (mate == null || mover == null) return false;
    if (mate.type != PieceType.pawn || mate.color != us) {
      mover.linkTo = null;
      return false;
    }
    final mf = Square.fileOf(mateFrom), mr = Square.rankOf(mateFrom);
    final nf = mf + df, nr = mr + dr;
    if (!Square.onBoard(nf, nr)) {
      mover.linkTo = null;
      mate.linkTo = null;
      return false;
    }
    final mateTo = Square.of(nf, nr);
    final dst = board[mateTo];
    if (dst != null && (dst.color == us || dst.type == PieceType.king)) {
      return false;
    }
    if (_entryBlocked(mateTo, us) || (dst != null && dst.resist > 0)) {
      return false;
    }
    // boş ya da düşman (şah değil) → kay / al
    final captured = dst;
    if (captured != null) {
      _breakLink(captured);
      if (lastCaptured == null) {
        lastCaptured = captured;
        lastCaptureSquare = mateTo;
      }
    }
    board[mateTo] = mate;
    board[mateFrom] = null;
    mate.moved = true;
    if (nr == 7 || nr == 0) {
      mate.type = PieceType.queen;
      mover.linkTo = null;
      mate.linkTo = null;
    } else {
      mover.linkTo = mateTo;
      mate.linkTo = moverTo;
    }
    _triggerTrap(mateTo);
    return captured != null;
  }

  void _endTurn() {
    moveCount++;
    turn = _enemy;
    _advanceTurnEffects();
    _recordPosition();
    _checkEnd();
  }

  void _recordPosition() {
    final key = _repetitionKey();
    _positionCounts[key] = (_positionCounts[key] ?? 0) + 1;
  }

  Board _standardPosition() => pureBoard();

  String _repetitionKey() {
    if (isOrthodoxPosition) return MoveGen.repetitionKey(_standardPosition());
    final out = StringBuffer('turn=${turn == PieceColor.white ? 'W' : 'B'};');
    out.write(
      'ep=${epTarget ?? -1};mana=${mana[PieceColor.white] ?? 0},${mana[PieceColor.black] ?? 0};',
    );
    out.write(
      'block=${cardBlock[PieceColor.white] ?? 0},${cardBlock[PieceColor.black] ?? 0};',
    );
    out.write(
      'fog=${fog[PieceColor.white] ?? 0},${fog[PieceColor.black] ?? 0};',
    );
    out.write(
      'medium=${mediumRevealUntil[PieceColor.white] ?? 0},${mediumRevealUntil[PieceColor.black] ?? 0};',
    );
    out.write(
      'cardUsed=$cardUsed;hands=${whiteHand.join(',')}|${blackHand.join(',')};',
    );
    for (final piece in board) {
      if (piece == null) {
        out.write('.;');
      } else {
        out.write(
          '${piece.color == PieceColor.white ? 'W' : 'B'}${piece.type.index},'
          '${piece.moved ? 1 : 0},${piece.frozen},${piece.resist},'
          '${piece.resistLock ? 1 : 0},${piece.barbarian ? 1 : 0},'
          '${piece.poisoned ? 1 : 0},${piece.poisonedDur},${piece.plagueUntil},'
          '${piece.trapped},${piece.angryN ? 1 : 0},${piece.angryB ? 1 : 0},'
          '${piece.ghost ? 1 : 0},${piece.ghostDur},${piece.linkTo ?? -1};',
        );
      }
    }
    for (final index in traps.keys.toList()..sort()) {
      final trap = traps[index]!;
      final revealed =
          trap.revealedFor.toList()..sort((a, b) => a.index.compareTo(b.index));
      out.write(
        't$index:${trap.by.index},${trap.dur},${trap.lvl},${trap.life},'
        '${trap.revealed ? 1 : 0},${revealed.map((color) => color.index).join(',')};',
      );
    }
    for (final index in shields.keys.toList()..sort()) {
      final shield = shields[index]!;
      out.write('s$index:${shield.by.index},${shield.dur};');
    }
    for (final index in blocks.keys.toList()..sort()) {
      out.write('b$index:${blocks[index]};');
    }
    return out.toString();
  }

  void _advanceTurnEffects() {
    for (int i = 0; i < 64; i++) {
      final p = board[i];
      if (p == null) continue;
      if (p.plagueUntil > 0 && p.plagueUntil <= moveCount) {
        p.plagueUntil = 0;
      }
      if (p.color != turn) continue;
      if (p.frozen > 0) p.frozen--;
      if (p.trapped > 0) p.trapped--;
      if (p.resist > 0) p.resist--;
      if (p.ghost) {
        if (p.ghostDur > 0) p.ghostDur--;
        if (p.ghostDur <= 0) {
          board[i] = null;
          continue;
        }
      }
      if (p.poisonedDur > 0) {
        p.poisonedDur--;
        if (p.poisonedDur <= 0) p.poisoned = false;
      }
    }
    blocks.removeWhere((k, v) {
      blocks[k] = v - 1;
      return blocks[k]! <= 0;
    });
    traps.removeWhere((k, t) {
      t.life -= 1;
      return t.life <= 0;
    });
    if ((cardBlock[turn] ?? 0) > 0) cardBlock[turn] = cardBlock[turn]! - 1;
    shields.removeWhere((k, s) {
      s.dur -= 1;
      return s.dur <= 0;
    });
    if ((fog[turn] ?? 0) > 0) fog[turn] = fog[turn]! - 1;
    // 1 turluk bayrakları (oynayan tarafta) temizle
    for (int i = 0; i < 64; i++) {
      final q = board[i];
      if (q != null && q.color != turn) {
        q.resistLock = false;
        q.angryN = false;
        q.angryB = false;
      }
    }
    mana[turn] = ((mana[turn] ?? 0) + 1).clamp(0, 10);
    cardUsed = false;
  }

  void _checkEnd() {
    final moves = allLegal(turn);
    final standard = _standardPosition();

    // A card effect can temporarily lock every legal move without creating
    // checkmate or stalemate. Keep this in step with the authoritative
    // server: pass the turn only when ignoring temporary effects restores a
    // legal move.
    if (moves.isEmpty && _onlyBlockedByEffects(turn)) {
      forcePassTurn();
      return;
    }

    // Mat/pat, sayaç beraberliklerinden önce gelir. Yasal hamle mevcutken
    // de otomatik beraberlik sayaçları kontrol edilmelidir.
    if (moves.isEmpty && inCheck(turn)) {
      result =
          turn == PieceColor.white
              ? MatchResult.blackWins
              : MatchResult.whiteWins;
      return;
    }
    if (isOrthodoxPosition) {
      // Dead position, 75 hamle ve beş tekrar otomatik bitiştir. 50 hamle
      // ve üç tekrar yalnızca oyuncu talep ederse beraberlik olur.
      if (standard.isInsufficientMaterial || standard.isSeventyFiveMoveRule) {
        result = MatchResult.draw;
        return;
      }
      if ((_positionCounts[MoveGen.repetitionKey(standard)] ?? 0) >= 5) {
        result = MatchResult.draw;
        return;
      }
    } else if (standard.isInsufficientMaterial ||
        standard.isFiftyMoveRule ||
        (_positionCounts[_repetitionKey()] ?? 0) >= 3) {
      // Kart etkili eski varyantın mevcut oyun sözleşmesi korunur.
      result = MatchResult.draw;
      return;
    }

    if (moves.isNotEmpty) return;
    result = MatchResult.draw;
  }

  /// Hamle yapmadan sırayı geçir (skipMove kartı / efekt kilidi).
  void forcePassTurn() {
    if (over) return;
    // Passing consumes the immediate en-passant opportunity too.
    epTarget = null;
    moveCount++;
    turn = _enemy;
    _advanceTurnEffects();
    _recordPosition();
    _checkEnd();
    visualRevision++;
  }

  /// Kart aşamasını tüketip aynı tarafın taş hamlesine geçer.
  ///
  /// Bu, [forcePassTurn] ile aynı şey değildir: oyuncu kart oynamamayı
  /// seçtiğinde rakibe bedava tur verilmemeli, sadece kendi hamle aşamasına
  /// geçilmelidir.
  bool skipCardPhase() {
    if (over || cardUsed) return false;
    cardUsed = true;
    _checkEnd();
    visualRevision++;
    return true;
  }

  /// Re-evaluate a side with no available move after a card effect or an AI
  /// decision. This keeps checkmate, stalemate and effect-pass rules in one
  /// place instead of making callers guess whether a pass is legal.
  bool resolveTurnIfNoLegalMoves() {
    if (over) return false;
    final previousTurn = turn;
    _checkEnd();
    return over || turn != previousTurn;
  }

  // ── KART OYNAMA ──
  int manaOf(PieceColor c) => mana[c] ?? 0;

  bool mediumActiveFor(PieceColor c) => (mediumRevealUntil[c] ?? 0) > moveCount;

  List<String>? revealedHandFor(PieceColor c) {
    if (!mediumActiveFor(c)) return null;
    return List<String>.unmodifiable(handOf(_opp(c)));
  }

  /// Bir kartın geçerli hedef indeksleri (UI/AI için).
  List<int> cardTargets(String key) {
    final c = kCards[key];
    if (c == null) return const [];
    final col = turn;
    final out = <int>[];
    for (int i = 0; i < 64; i++) {
      if (_isValidTarget(c.target, i, col)) out.add(i);
    }
    return out;
  }

  bool _isValidTarget(CardTarget target, int idx, PieceColor col) {
    if (idx < 0 || idx >= 64) return false;
    final p = board[idx];
    final them = _opp(col);
    bool enemyOk(MPiece? x) =>
        x != null &&
        x.color == them &&
        x.type != PieceType.king &&
        x.resist <= 0;
    switch (target) {
      case CardTarget.none:
        return false;
      case CardTarget.enemy:
        return enemyOk(p);
      case CardTarget.enemyQueen:
        return p != null &&
            p.color == them &&
            p.type == PieceType.queen &&
            p.resist <= 0;
      case CardTarget.ownPawn:
        return p != null && p.color == col && p.type == PieceType.pawn;
      case CardTarget.ownPawnPair:
        return p != null && p.color == col && p.type == PieceType.pawn;
      case CardTarget.ownKnight:
        return p != null && p.color == col && p.type == PieceType.knight;
      case CardTarget.ownBishop:
        return p != null && p.color == col && p.type == PieceType.bishop;
      case CardTarget.ownKnBi:
        return p != null &&
            p.color == col &&
            (p.type == PieceType.knight || p.type == PieceType.bishop);
      case CardTarget.ownQueen:
        return p != null && p.color == col && p.type == PieceType.queen;
      case CardTarget.ownPiece:
        return p != null && p.color == col && p.type != PieceType.king;
      case CardTarget.empty:
        return p == null &&
            traps[idx] == null &&
            shields[idx] == null &&
            (blocks[idx] ?? 0) == 0;
      case CardTarget.emptyOwn:
        final ownHalf = col == PieceColor.white ? idx < 32 : idx >= 32;
        return p == null &&
            ownHalf &&
            shields[idx] == null &&
            traps[idx] == null &&
            (blocks[idx] ?? 0) == 0;
      case CardTarget.anySq:
        return p == null;
    }
  }

  /// Kartı oynamaya çalış. Hedefli kartlar için [idx] gerekir;
  /// tutkal için iki kare ([idx],[idx2]). Başarılıysa true.
  bool playCard(String key, {int? idx, int? idx2}) {
    if (over) return false;
    final c = kCards[key];
    if (c == null) return false;
    final col = turn;
    if (!_handContains(key, col)) return false;
    if (idx != null && (idx < 0 || idx >= 64)) return false;
    if (idx2 != null && (idx2 < 0 || idx2 >= 64)) return false;
    if ((cardBlock[col] ?? 0) > 0) return false;
    if (cardUsed) return false;
    if (manaOf(col) < c.mana) return false;
    if (c.skipMove && inCheck(col)) return false;

    if (c.target != CardTarget.none) {
      if (key == 'glue') {
        if (idx == null || idx2 == null) return false;
        if (!_glueValid(idx, idx2, col)) return false;
      } else {
        if (idx == null) return false;
        if (!_isValidTarget(c.target, idx, col)) return false;
      }
    }

    final ok = _applyEffect(key, c, idx, idx2, col);
    if (!ok) return false;

    // mana düş + kilitle
    mana[col] = (manaOf(col) - c.mana).clamp(0, 10);
    cardUsed = true;

    if (c.skipMove) {
      forcePassTurn();
    } else {
      visualRevision++;
    }
    return true;
  }

  bool _glueValid(int a, int b, PieceColor col) {
    if (a < 0 || a >= 64 || b < 0 || b >= 64) return false;
    final pa = board[a], pb = board[b];
    if (pa == null || pb == null) return false;
    if (pa.color != col || pb.color != col) return false;
    if (pa.type != PieceType.pawn || pb.type != PieceType.pawn) return false;
    if (pa.linkTo != null || pb.linkTo != null) return false;
    if (Square.rankOf(a) != Square.rankOf(b)) return false;
    return (Square.fileOf(a) - Square.fileOf(b)).abs() == 1;
  }

  bool _applyEffect(
    String key,
    CardDef c,
    int? idx,
    int? idx2,
    PieceColor col,
  ) {
    final them = _opp(col);
    switch (c.family) {
      case 'trap':
        traps[idx!] = Trap(col, c.dur, c.level, c.dur * 2);
        return true;
      case 'radar':
        _revealTraps(col, c.level);
        return true;
      case 'resist':
        final p = board[idx!];
        if (p == null || p.color != col) return false;
        p.resist = 1;
        p.resistLock = true;
        return true;
      case 'shield':
        shields[idx!] = Shield(col, c.dur * 2);
        return true;
      case 'deploy':
        if (board[idx!] != null) return false;
        board[idx] = MPiece(col, c.deploy!, moved: true, resistLock: true);
        return true;
    }
    switch (key) {
      case 'freeze':
        final p = board[idx!];
        if (p == null || p.color != them) return false;
        p.frozen = c.dur + 1;
        return true;
      case 'poison_q':
        final p = board[idx!];
        if (p == null || p.color != them || p.type != PieceType.queen) {
          return false;
        }
        p.poisoned = true;
        p.poisonedDur = 2;
        return true;
      case 'card_block':
        cardBlock[them] = c.dur + 1;
        return true;
      case 'medium':
        mediumRevealUntil[col] = moveCount + 1;
        return true;
      case 'barbarian':
        final p = board[idx!];
        if (p == null || p.color != col || p.type != PieceType.pawn) {
          return false;
        }
        p.barbarian = true;
        return true;
      case 'glue':
        return _applyGlue(idx!, idx2!);
      case 'archer':
        return _applyArcher(idx!, col);
      case 'fog':
        fog[col] = c.dur + 1;
        return true;
      case 'angry_n':
        final p = board[idx!];
        if (p == null || p.color != col || p.type != PieceType.knight) {
          return false;
        }
        p.angryN = true;
        return true;
      case 'angry_b':
        final p = board[idx!];
        if (p == null || p.color != col || p.type != PieceType.bishop) {
          return false;
        }
        p.angryB = true;
        return true;
      case 'plague':
        for (int i = 0; i < 64; i++) {
          final p = board[i];
          if (p != null && p.type == PieceType.pawn && p.resist <= 0) {
            p.plagueUntil =
                p.plagueUntil > moveCount + 2 ? p.plagueUntil : moveCount + 2;
          }
        }
        return true;
      case 'reinforce':
        return _doReinforce(idx!, col);
      case 'ghosts':
        return _spawnGhosts(col);
      case 'immunity':
        final p = board[idx!];
        if (p == null || p.color != col) return false;
        p.frozen = 0;
        p.plagueUntil = 0;
        p.poisoned = false;
        p.poisonedDur = 0;
        p.trapped = 0;
        return true;
    }
    return false;
  }

  void _revealTraps(PieceColor col, int lvl) {
    final them = _opp(col);
    if ((fog[them] ?? 0) > 0) return; // sis radarı engeller
    traps.forEach((k, t) {
      if (t.by != them) return;
      final r = Square.rankOf(k);
      bool show;
      if (lvl >= 3) {
        show = true;
      } else if (lvl == 2) {
        final ownHalf = col == PieceColor.white ? r <= 3 : r >= 4;
        show = ownHalf || r == 3 || r == 4;
      } else {
        show = col == PieceColor.white ? r <= 3 : r >= 4;
      }
      if (show) t.revealedFor.add(col);
    });
  }

  bool _applyGlue(int a, int b) {
    final pa = board[a], pb = board[b];
    if (pa == null || pb == null) return false;
    pa.linkTo = b;
    pb.linkTo = a;
    return true;
  }

  bool _applyArcher(int idx, PieceColor col) {
    final p = board[idx];
    if (p == null || p.color != col || p.type != PieceType.pawn) return false;
    final dir = _dir(col);
    final f = Square.fileOf(idx), r = Square.rankOf(idx);
    int bestIdx = -1, bestVal = -1;
    const val = {
      PieceType.pawn: 1,
      PieceType.knight: 3,
      PieceType.bishop: 3,
      PieceType.rook: 5,
      PieceType.queen: 9,
      PieceType.king: 0,
    };
    for (final df in const [-1, 1]) {
      final nf = f + df, nr = r + dir;
      if (!Square.onBoard(nf, nr)) continue;
      final t = board[Square.of(nf, nr)];
      if (t != null &&
          t.color != col &&
          t.type != PieceType.king &&
          t.resist <= 0) {
        final v = val[t.type]!;
        if (v > bestVal) {
          bestVal = v;
          bestIdx = Square.of(nf, nr);
        }
      }
    }
    if (bestIdx < 0) return false;
    final victim = board[bestIdx]!;
    _breakLink(victim);
    board[bestIdx] = null;
    return true;
  }

  bool _doReinforce(int idx, PieceColor col) {
    final back = -_dir(col); // kendi tarafına doğru
    final f = Square.fileOf(idx), r = Square.rankOf(idx);
    int made = 0;
    for (int s = 1; s <= 3; s++) {
      final nr = r + back * s;
      if (!Square.onBoard(f, nr)) break;
      final ti = Square.of(f, nr);
      if (board[ti] != null) break;
      // Reinforcement is a placement effect: every occupied overlay makes
      // the square non-empty, including a friendly shield or hidden trap.
      if ((blocks[ti] ?? 0) > 0 || traps[ti] != null || shields[ti] != null) {
        break;
      }
      board[ti] = MPiece(col, PieceType.pawn, moved: true);
      made++;
    }
    return made > 0;
  }

  bool _spawnGhosts(PieceColor col) {
    final k = kingIdx(col);
    if (k < 0) return false;
    final dir = _dir(col);
    final kf = Square.fileOf(k), kr = Square.rankOf(k);
    final nr = kr + dir;
    if (!Square.onBoard(kf, nr)) return false;
    int placed = 0;
    for (final cf in [kf, kf - 1, kf + 1]) {
      if (placed >= 2) break;
      if (cf < 0 || cf > 7) continue;
      final ti = Square.of(cf, nr);
      if (board[ti] != null) continue;
      if (shields[ti] != null) continue;
      if ((blocks[ti] ?? 0) > 0 || traps[ti] != null) continue;
      board[ti] = MPiece(
        col,
        PieceType.pawn,
        moved: true,
        ghost: true,
        ghostDur: 3,
      );
      placed++;
    }
    return placed > 0;
  }
}
