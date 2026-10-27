import 'dart:isolate';
import 'dart:math';

import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../engine/ai.dart';
import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import 'match_state.dart';

List<int> _searchAiMoveInIsolate(Map<String, dynamic> payload) {
  final board = Board.fromFen(payload['fen'] as String);
  final rawMoves = payload['moves'] as List;
  final moves = <Move>[
    for (final raw in rawMoves)
      () {
        final values =
            (raw as List).map((value) => (value as num).toInt()).toList();
        final promotionIndex = values[2];
        return Move(
          values[0],
          values[1],
          promotion:
              promotionIndex < 0 ? null : PieceType.values[promotionIndex],
          isEnPassant: values[3] == 1,
          isCastle: values[4] == 1,
        );
      }(),
  ];
  if (moves.isEmpty) throw StateError('Yasal hamle yok');

  final level = AiLevel(
    id: 'isolate-search',
    name: 'isolate-search',
    desc: '',
    depth: (payload['depth'] as num).toInt(),
    errorRate: (payload['errorRate'] as num).toDouble(),
    power: 0,
    rewardMult: 1,
    thinkBudgetMs: (payload['budgetMs'] as num).toInt(),
  );
  final best = AiEngine().pickAmong(
    board,
    moves,
    level,
    Random((payload['seed'] as num).toInt()),
    budget: Duration(milliseconds: level.thinkBudgetMs),
  );
  return [best.from, best.to];
}

class _CardPlan {
  final String key;
  final int? target;
  final int? secondaryTarget;
  final int score;

  const _CardPlan(this.key, this.target, this.secondaryTarget, this.score);
}

/// Maçta AI rakibin kart + hamle kararları.
class MatchAi {
  final Random rng;
  final AiEngine engine = AiEngine();

  MatchAi([Random? r]) : rng = r ?? Random();

  static const Map<PieceType, int> _val = {
    PieceType.pawn: 1,
    PieceType.knight: 3,
    PieceType.bishop: 3,
    PieceType.rook: 5,
    PieceType.queen: 9,
    PieceType.king: 0,
  };

  /// AI uygun bir kart oynamaya karar verirse oynar; oynanan kartın
  /// anahtarını döndürür (yoksa null). Hamleden ÖNCE çağrılır.
  String? maybeCard(MatchState m, AiLevel level) {
    if (m.over || m.cardUsed) return null;
    final col = m.turn;
    if ((m.cardBlock[col] ?? 0) > 0) return null;
    final playChance = level.cardUseRate.clamp(0.0, 1.0).toDouble();
    if (rng.nextDouble() > playChance) return null;

    final candidates = <_CardPlan>[];
    for (final heldKey in m.handOf(col)) {
      final key = _affordableKey(m, heldKey, col);
      if (key == null) continue;
      final plan = _planFor(m, key, level, col);
      if (plan != null) candidates.add(plan);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // A failed plan must never consume mana or end the turn. Try the next
    // validated plan as a defensive fallback for stale UI/state snapshots.
    for (final plan in candidates) {
      final ok = m.playCard(
        plan.key,
        idx: plan.target,
        idx2: plan.secondaryTarget,
      );
      if (ok) return plan.key;
    }
    return null;
  }

  String? _affordableKey(MatchState m, String heldKey, PieceColor color) {
    final held = kCards[heldKey];
    final family =
        held?.family.isNotEmpty == true
            ? held!.family
            : _familyFromKey(heldKey);
    if (held == null && family == null) return null;
    if (held != null && !held.upgradeable) {
      return m.manaOf(color) >= held.mana ? heldKey : null;
    }
    final startLevel = held?.level ?? 1;
    for (var level = startLevel; level >= 1; level--) {
      final key = familyKeyAtLevel(family!, level);
      final definition = key == null ? null : kCards[key];
      if (key != null &&
          definition != null &&
          m.manaOf(color) >= definition.mana) {
        return key;
      }
    }
    return null;
  }

  String? _familyFromKey(String key) {
    for (final family in const [
      'trap',
      'radar',
      'resist',
      'shield',
      'deploy',
    ]) {
      if (key == family || key.startsWith(family)) return family;
    }
    return null;
  }

  _CardPlan? _planFor(MatchState m, String key, AiLevel level, PieceColor col) {
    final c = kCards[key];
    if (c == null || c.skipMove && m.inCheck(col)) return null;

    if (key == 'glue') {
      final pair = _pawnPair(m, col);
      if (pair == null) return null;
      return _CardPlan(key, pair[0], pair[1], _score(c, level, 24));
    }
    if (key == 'archer') {
      final target = _archerPawn(m, col);
      if (target == null) return null;
      return _CardPlan(key, target, null, _score(c, level, 34));
    }
    if (key == 'reinforce') {
      final target = _reinforcePawn(m, col);
      if (target == null) return null;
      return _CardPlan(key, target, null, _score(c, level, 18));
    }
    if (key == 'ghosts' && !_hasGhostSlot(m, col)) return null;

    if (c.target == CardTarget.none) {
      return _CardPlan(key, null, null, _score(c, level, 12));
    }

    final targets = m.cardTargets(key);
    if (targets.isEmpty) return null;
    final target = _bestTarget(m, c, targets, col);
    return _CardPlan(
      key,
      target,
      null,
      _score(c, level, _targetValue(m, c, target)),
    );
  }

  int _score(CardDef card, AiLevel level, int tacticalValue) {
    final personaBias = switch (level.persona) {
      'Meraklı' => card.mana <= 3 ? 14 : 0,
      'Cesur' => card.target == CardTarget.enemy ? 12 : 4,
      'Planlı' => card.target == CardTarget.none ? 10 : 6,
      'Taktikçi' => tacticalValue,
      'Acımasız' =>
        card.target == CardTarget.enemy || card.target == CardTarget.enemyQueen
            ? 18
            : 5,
      _ => 8,
    };
    return tacticalValue + card.mana * 3 + personaBias;
  }

  int _targetValue(MatchState m, CardDef card, int idx) {
    final piece = m.board[idx];
    final value = piece == null ? 0 : (_val[piece.type] ?? 0);
    if (card.target == CardTarget.enemy ||
        card.target == CardTarget.enemyQueen) {
      return 18 + value * 12;
    }
    if (card.target == CardTarget.empty || card.target == CardTarget.emptyOwn) {
      final file = Square.fileOf(idx), rank = Square.rankOf(idx);
      return 10 - ((file - 3).abs() + (rank - 3).abs());
    }
    return 12 + value * 4;
  }

  int _bestTarget(
    MatchState m,
    CardDef card,
    List<int> targets,
    PieceColor col,
  ) {
    var best = targets.first;
    var bestValue = -1 << 30;
    for (final target in targets) {
      final value = _targetValue(m, card, target);
      if (value > bestValue) {
        bestValue = value;
        best = target;
      }
    }
    return best;
  }

  /// Hamleyi seçer (uygulamaz) — [from, to]. Yasal hamle yoksa null.
  List<int>? chooseMove(MatchState m, AiLevel level) {
    final legal = m.allLegal(m.turn);
    if (legal.isEmpty) return null;
    final b = m.pureBoard();
    final moves = legal.map((ft) => m.asMove(ft[0], ft[1])).toList();
    final best = engine.pickAmong(
      b,
      moves,
      level,
      rng,
      budget: Duration(milliseconds: level.thinkBudgetMs.clamp(10, 500)),
    );
    final isLegal = moves.any(
      (move) =>
          move.from == best.from &&
          move.to == best.to &&
          move.promotion == best.promotion,
    );
    final selected = isLegal ? best : moves.first;
    return [selected.from, selected.to];
  }

  /// Satranç aramasını UI isolate'ından çıkarır. Kart katmanı yasal kök
  /// hamleleri ana isolate'ta üretir; ayrı isolate yalnızca saf minimax
  /// aramasını yapar. Böylece zor AI seviyeleri tahtayı dondurmaz.
  Future<List<int>?> chooseMoveAsync(MatchState m, AiLevel level) async {
    final legal = m.allLegal(m.turn);
    if (legal.isEmpty) return null;
    final moves = legal.map((ft) => m.asMove(ft[0], ft[1])).toList();
    final payload = <String, dynamic>{
      'fen': m.pureBoard().positionKey(),
      'moves': [
        for (final move in moves)
          [
            move.from,
            move.to,
            move.promotion?.index ?? -1,
            move.isEnPassant ? 1 : 0,
            move.isCastle ? 1 : 0,
          ],
      ],
      'depth': level.depth,
      'errorRate': level.errorRate,
      'budgetMs': level.thinkBudgetMs.clamp(10, 500),
      'seed': rng.nextInt(1 << 32),
    };

    try {
      final selected = await Isolate.run(() => _searchAiMoveInIsolate(payload));
      if (selected.length != 2) return [moves.first.from, moves.first.to];
      final isLegal = moves.any(
        (move) => move.from == selected[0] && move.to == selected[1],
      );
      return isLegal ? selected : [moves.first.from, moves.first.to];
    } catch (_) {
      // Keep non-Android/test platforms functional if isolate creation is
      // unavailable. The existing bounded search remains the safe fallback.
      return chooseMove(m, level);
    }
  }

  int? _archerPawn(MatchState m, PieceColor col) {
    int? best;
    var bestValue = -1;
    final dir = col == PieceColor.white ? 1 : -1;
    for (var idx = 0; idx < 64; idx++) {
      final pawn = m.board[idx];
      if (pawn == null || pawn.color != col || pawn.type != PieceType.pawn) {
        continue;
      }
      final f = Square.fileOf(idx), r = Square.rankOf(idx);
      for (final df in const [-1, 1]) {
        final nf = f + df, nr = r + dir;
        if (!Square.onBoard(nf, nr)) continue;
        final target = m.board[Square.of(nf, nr)];
        if (target == null ||
            target.color == col ||
            target.type == PieceType.king ||
            target.resist > 0) {
          continue;
        }
        final value = _val[target.type] ?? 0;
        if (value > bestValue) {
          bestValue = value;
          best = idx;
        }
      }
    }
    return best;
  }

  int? _reinforcePawn(MatchState m, PieceColor col) {
    for (var idx = 0; idx < 64; idx++) {
      final pawn = m.board[idx];
      if (pawn == null || pawn.color != col || pawn.type != PieceType.pawn) {
        continue;
      }
      final dir = col == PieceColor.white ? -1 : 1;
      final file = Square.fileOf(idx), rank = Square.rankOf(idx);
      for (final step in const [1, 2, 3]) {
        final nextRank = rank + dir * step;
        if (!Square.onBoard(file, nextRank)) break;
        final target = Square.of(file, nextRank);
        if (m.board[target] != null ||
            m.traps[target] != null ||
            m.shields[target] != null ||
            (m.blocks[target] ?? 0) > 0) {
          break;
        }
        return idx;
      }
    }
    return null;
  }

  bool _hasGhostSlot(MatchState m, PieceColor col) {
    final king = m.kingIdx(col);
    if (king < 0) return false;
    final dir = col == PieceColor.white ? 1 : -1;
    final rank = Square.rankOf(king) + dir;
    if (rank < 0 || rank > 7) return false;
    final file = Square.fileOf(king);
    for (final candidate in [file, file - 1, file + 1]) {
      if (candidate < 0 || candidate > 7) continue;
      final target = Square.of(candidate, rank);
      if (m.board[target] == null &&
          m.traps[target] == null &&
          m.shields[target] == null &&
          (m.blocks[target] ?? 0) == 0) {
        return true;
      }
    }
    return false;
  }

  List<int>? _pawnPair(MatchState m, PieceColor col) {
    final pawns = <int>[];
    for (int i = 0; i < 64; i++) {
      final p = m.board[i];
      if (p != null && p.color == col && p.type == PieceType.pawn) pawns.add(i);
    }
    for (final a in pawns) {
      for (final b in pawns) {
        if (a == b) continue;
        if (m.board[a]?.linkTo == null &&
            m.board[b]?.linkTo == null &&
            Square.rankOf(a) == Square.rankOf(b) &&
            (Square.fileOf(a) - Square.fileOf(b)).abs() == 1) {
          return [a, b];
        }
      }
    }
    return null;
  }
}
