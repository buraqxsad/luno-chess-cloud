import 'dart:math';

import 'board.dart';
import 'move.dart';
import 'move_gen.dart';
import 'piece.dart';

/// Bir Luno eğitmeni (zorluk seviyesi). HTML sürümüyle birebir.
class AiLevel {
  final String id;
  final String name;
  final String desc;
  final int depth; // arama derinliği
  final double errorRate; // rastgele hata olasılığı (yüksek = kolay)
  final int power; // ~kupa gücü (gösterim)
  final double rewardMult; // galibiyet ödül çarpanı
  final double cardUseRate; // kart kullanma eğilimi
  final int thinkBudgetMs; // UI'yi bloklamamak için üst düşünme bütçesi
  final String
  persona; // davranış profili; ekonomi veya ödül hesabında kullanılmaz

  const AiLevel({
    required this.id,
    required this.name,
    required this.desc,
    required this.depth,
    required this.errorRate,
    required this.power,
    required this.rewardMult,
    this.cardUseRate = .45,
    this.thinkBudgetMs = 80,
    this.persona = 'Dengeli',
  });
}

const List<AiLevel> aiLevels = [
  AiLevel(
    id: 'bebek',
    name: 'Bebek Luno',
    desc: 'Yeni öğreniyor, ara sıra hata yapar',
    depth: 2,
    errorRate: 0.30,
    power: 100,
    rewardMult: 0.4,
    cardUseRate: .28,
    thinkBudgetMs: 30,
    persona: 'Meraklı',
  ),
  AiLevel(
    id: 'comez',
    name: 'Çömez Luno',
    desc: 'Hevesli ama acemi',
    depth: 2,
    errorRate: 0.18,
    power: 400,
    rewardMult: 0.6,
    cardUseRate: .34,
    thinkBudgetMs: 40,
    persona: 'Cesur',
  ),
  AiLevel(
    id: 'sovalye',
    name: 'Şövalye Luno',
    desc: 'Dengeli ve disiplinli',
    depth: 3,
    errorRate: 0.08,
    power: 900,
    rewardMult: 1.0,
    cardUseRate: .42,
    thinkBudgetMs: 60,
    persona: 'Dengeli',
  ),
  AiLevel(
    id: 'bilge',
    name: 'Bilge Luno',
    desc: 'Planlı oynar, hatası azdır',
    depth: 3,
    errorRate: 0.03,
    power: 1600,
    rewardMult: 1.5,
    cardUseRate: .50,
    thinkBudgetMs: 85,
    persona: 'Planlı',
  ),
  AiLevel(
    id: 'usta',
    name: 'Usta Luno',
    desc: 'Sıkı strateji, yenmesi zor',
    depth: 4,
    errorRate: 0.01,
    power: 2600,
    rewardMult: 2.0,
    cardUseRate: .58,
    thinkBudgetMs: 120,
    persona: 'Taktikçi',
  ),
  AiLevel(
    id: 'efsane',
    name: 'Efsane Luno',
    desc: 'Krallığın en güçlüsü, acımasız',
    depth: 4,
    errorRate: 0.0,
    power: 4200,
    rewardMult: 2.8,
    cardUseRate: .65,
    thinkBudgetMs: 160,
    persona: 'Acımasız',
  ),
];

/// Negamax + alpha-beta satranç AI'ı. Saf Dart — test edilebilir.
/// Değer ve piece-square tabloları HTML sürümünden birebir alındı,
/// böylece AI gücü doğrulanmış davranışla aynıdır.
class AiEngine {
  static const Map<PieceType, int> _pval = {
    PieceType.pawn: 100,
    PieceType.knight: 320,
    PieceType.bishop: 330,
    PieceType.rook: 500,
    PieceType.queen: 900,
    PieceType.king: 0,
  };

  // PST: siyah taş idx ile, beyaz taş aynalanmış (idx^56) okur.
  static const Map<PieceType, List<int>> _pst = {
    PieceType.pawn: [
      0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, //
      10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5, //
      0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, //
      5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0,
    ],
    PieceType.knight: [
      -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, //
      -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30, //
      -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, //
      -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50,
    ],
    PieceType.bishop: [
      -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, //
      -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10, //
      -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, //
      -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20,
    ],
    PieceType.rook: [
      0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, //
      -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, //
      -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, //
      -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0,
    ],
    PieceType.queen: [
      -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, //
      -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5, //
      0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, //
      -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20,
    ],
    PieceType.king: [
      -30,
      -40,
      -40,
      -50,
      -50,
      -40,
      -40,
      -30,
      -30,
      -40,
      -40,
      -50,
      -50,
      -40,
      -40,
      -30, //
      -30,
      -40,
      -40,
      -50,
      -50,
      -40,
      -40,
      -30,
      -30,
      -40,
      -40,
      -50,
      -50,
      -40,
      -40,
      -30, //
      -20,
      -30,
      -30,
      -40,
      -40,
      -30,
      -30,
      -20,
      -10,
      -20,
      -20,
      -20,
      -20,
      -20,
      -20,
      -10, //
      20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20,
    ],
  };

  static const int _inf = 1 << 30;
  static const int _mate = 900000;
  static const int _nodeCap = 400000;

  int _nodes = 0;
  Stopwatch? _watch;
  Duration? _budget;
  bool _stopped = false;

  void _beginSearch(Duration? budget) {
    _nodes = 0;
    _stopped = false;
    _watch = budget == null ? null : (Stopwatch()..start());
    _budget = budget;
  }

  bool _shouldStop() {
    if (_stopped) return true;
    if (_nodes >= _nodeCap) return _stopped = true;
    final budget = _budget;
    final watch = _watch;
    // Avoid reading the clock for every node while still enforcing a tight
    // bound often enough for the mobile UI.
    if (budget == null || watch == null || (_nodes & 127) != 0) return false;
    return _stopped = watch.elapsed >= budget;
  }

  int _pstVal(Piece p, int idx) =>
      _pst[p.type]![p.color == PieceColor.white ? idx ^ 56 : idx];

  /// Beyaz açısından statik değerlendirme (beyaz pozitif).
  int evaluateWhite(Board b) {
    int s = 0;
    for (int i = 0; i < 64; i++) {
      final p = b.squares[i];
      if (p == null) continue;
      final v = _pval[p.type]! + _pstVal(p, i);
      s += p.color == PieceColor.white ? v : -v;
    }
    return s;
  }

  int _evalStm(Board b) =>
      b.turn == PieceColor.white ? evaluateWhite(b) : -evaluateWhite(b);

  int _mvvLva(Board b, Move m) {
    final victim = b.squares[m.to];
    if (victim == null) return m.isEnPassant ? 90 : 0;
    final att = b.squares[m.from]!;
    return _pval[victim.type]! - (_pval[att.type]! ~/ 10);
  }

  int _negamax(Board b, int depth, int alpha, int beta, int ply) {
    if (_shouldStop()) return 0;
    _nodes++;
    final moves = MoveGen.legal(b);
    if (moves.isEmpty) {
      // Mate scores include distance from the root: an earlier mate is
      // always preferred over a later mate, regardless of remaining depth.
      return MoveGen.inCheck(b, b.turn) ? -(_mate - ply) : 0;
    }
    if (depth <= 0) return _evalStm(b);
    moves.sort((a, c) => _mvvLva(b, c) - _mvvLva(b, a));
    int best = -_inf;
    for (final m in moves) {
      final sc = -_negamax(b.apply(m), depth - 1, -beta, -alpha, ply + 1);
      // An interrupted subtree has no comparable score. Unwind to the root
      // without replacing the last completely searched legal candidate.
      if (_stopped) return 0;
      if (sc > best) best = sc;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  }

  /// Sıradaki taraf için en iyi hamle (deterministik, gürültüsüz).
  Move search(Board b, int depth, {Duration? budget}) {
    if (depth < 1) {
      throw ArgumentError.value(depth, 'depth', 'Must be positive');
    }
    _beginSearch(budget);
    final moves = MoveGen.legal(b);
    if (moves.isEmpty) {
      throw StateError('Yasal hamle yok');
    }
    moves.sort((a, c) => _mvvLva(b, c) - _mvvLva(b, a));
    Move best = moves.first;
    int bestSc = -_inf, alpha = -_inf;
    const beta = _inf;
    for (final m in moves) {
      if (_shouldStop()) break;
      final sc = -_negamax(b.apply(m), depth - 1, -beta, -alpha, 1);
      if (_stopped) break;
      if (sc > bestSc) {
        bestSc = sc;
        best = m;
      }
      if (sc > alpha) alpha = sc;
      if (_shouldStop()) break;
    }
    return best;
  }

  int _clampDepth(int d) => d < 2 ? 2 : (d > 4 ? 4 : d);

  /// Verilen kök hamleler arasından seç (kart efektleriyle filtrelenmiş
  /// yasal hamleler dışarıdan gelir; alt ağaç saf satranç aranır).
  Move pickAmong(
    Board b,
    List<Move> moves,
    AiLevel level,
    Random rng, {
    Duration? budget,
  }) {
    if (moves.isEmpty) throw StateError('Yasal hamle yok');
    if (rng.nextDouble() < level.errorRate) {
      return moves[rng.nextInt(moves.length)];
    }
    final noise = level.errorRate * 8;
    final depth = _clampDepth(level.depth);
    _beginSearch(budget);
    final ordered = List<Move>.of(moves)
      ..sort((a, c) => _mvvLva(b, c) - _mvvLva(b, a));
    Move best = ordered.first;
    double bestSc = -1e18;
    int alpha = -_inf;
    const beta = _inf;
    for (final m in ordered) {
      if (_shouldStop()) break;
      final raw = -_negamax(b.apply(m), depth - 1, -beta, -alpha, 1);
      if (_stopped) break;
      final sc = raw + (noise > 0 ? rng.nextDouble() * noise : 0.0);
      if (sc > bestSc) {
        bestSc = sc;
        best = m;
      }
      if (raw > alpha) alpha = raw;
      if (_shouldStop()) break;
    }
    return best;
  }

  /// Zorluk seviyesine göre hamle seç (rastgele hata + arama gürültüsü dahil).
  Move pickMove(Board b, AiLevel level, Random rng, {Duration? budget}) {
    final moves = MoveGen.legal(b);
    if (moves.isEmpty) throw StateError('Yasal hamle yok');

    // Zayıf eğitmenler bilerek hata yapar (rastgele hamle).
    if (rng.nextDouble() < level.errorRate) {
      return moves[rng.nextInt(moves.length)];
    }

    final noise = level.errorRate * 8;
    final depth = _clampDepth(level.depth);
    if (noise <= 0) return search(b, depth, budget: budget);

    // Gürültülü: eşit hamlelerde çeşitlilik için köke küçük rastgelelik ekle.
    _beginSearch(budget);
    moves.sort((a, c) => _mvvLva(b, c) - _mvvLva(b, a));
    Move best = moves.first;
    double bestSc = -1e18;
    int alpha = -_inf;
    const beta = _inf;
    for (final m in moves) {
      if (_shouldStop()) break;
      final raw = -_negamax(b.apply(m), depth - 1, -beta, -alpha, 1);
      if (_stopped) break;
      final sc = raw + rng.nextDouble() * noise;
      if (sc > bestSc) {
        bestSc = sc;
        best = m;
      }
      if (raw > alpha) alpha = raw;
      if (_shouldStop()) break;
    }
    return best;
  }
}
