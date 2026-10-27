import 'dart:convert';
import 'dart:math' as math;
import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/move_gen.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import 'model.dart';

Board _forSide(Board b, PieceColor side) => Board(
  squares: b.squares,
  turn: side,
  castling: b.castling,
  enPassant: side == b.turn ? b.enPassant : null,
  halfmoveClock: b.halfmoveClock,
  fullmoveNumber: b.fullmoveNumber,
);
Board _withoutEp(Board b) => Board(
  squares: b.squares,
  turn: b.turn,
  castling: b.castling,
  enPassant: null,
  halfmoveClock: b.halfmoveClock,
  fullmoveNumber: b.fullmoveNumber,
);
List<int> boardZone(int anchor) =>
    anchor < 0 ||
            anchor >= 64 ||
            Square.fileOf(anchor) == 7 ||
            Square.rankOf(anchor) == 7
        ? []
        : [anchor, anchor + 1, anchor + 8, anchor + 9];
List<List<T>> _permutations<T>(List<T> items) {
  if (items.isEmpty) return [[]];
  return [
    for (var i = 0; i < items.length; i++)
      for (final rest in _permutations([
        for (var j = 0; j < items.length; j++)
          if (j != i) items[j],
      ]))
        [items[i], ...rest],
  ];
}

/// Legality and public transitions only. There is no hidden hand/deck parameter.
class BattleRulesCore {
  static bool _restrictions(RuleState s, Move move, PieceColor side) {
    final board = s.board.squares, piece = board[move.from];
    if (piece == null || piece.color != side) return false;
    final relocations = [(move.from, move.to)];
    if (move.isCastle) {
      final rank = Square.rankOf(move.from) * 8,
          k = Square.fileOf(move.to) == 6;
      relocations.add((rank + (k ? 7 : 0), rank + (k ? 5 : 3)));
    }
    for (final (from, to) in relocations) {
      final p = board[from];
      if (p == null) return false;
      if (p.type == PieceType.king) continue;
      final id = s.pieceIds[from],
          capture =
              from == move.from && (board[to] != null || move.isEnPassant);
      for (final e in s.pieceEffects.where((e) => e.pieceId == id)) {
        if (e.type == PieceEffectType.freeze) return false;
        if ((e.type == PieceEffectType.chain ||
                e.type == PieceEffectType.mineDebuff) &&
            capture) {
          return false;
        }
        if (e.type == PieceEffectType.slow &&
            math.max(
                  (Square.fileOf(to) - Square.fileOf(from)).abs(),
                  (Square.rankOf(to) - Square.rankOf(from)).abs(),
                ) >
                2) {
          return false;
        }
      }
      if (board[to] == null &&
          s.boardEffects.any(
            (e) =>
                e.owner != side &&
                (e.type == BoardEffectType.lockedSquare ||
                    e.type == BoardEffectType.boardSeal) &&
                e.squares.contains(to),
          )) {
        return false;
      }
    }
    return true;
  }

  static List<Move> legalMoves(
    RuleState s,
    PieceColor side, {
    SpecialMoveAuthorization? authorization,
  }) {
    if (authorization != null) {
      return specialMoves(
        s,
        authorization.card,
        authorization.from,
        side,
      ).where((m) => authorization.moves.contains(m.uci)).toList();
    }
    return MoveGen.legal(_forSide(s.board, side))
        .where(
          (m) =>
              !(s.board.squares[m.from]?.type == PieceType.pawn &&
                  (m.to - m.from).abs() == 16 &&
                  s.movedPawns.contains(s.pieceIds[m.from])) &&
              _restrictions(s, m, side),
        )
        .toList();
  }

  static List<Move> specialMoves(
    RuleState s,
    CardId card,
    int from,
    PieceColor side,
  ) {
    if (from < 0 || from >= 64) return [];
    final board = s.board.squares, piece = board[from];
    if (piece == null || piece.color != side) return [];
    final f = Square.fileOf(from),
        r = Square.rankOf(from),
        dir = side == PieceColor.white ? 1 : -1;
    final targets = <int>[];
    void add(int nf, int nr, {bool capture = false}) {
      if (!Square.onBoard(nf, nr)) return;
      final to = Square.of(nf, nr), target = board[to];
      if (target == null ||
          (capture && target.color != side && target.type != PieceType.king)) {
        targets.add(to);
      }
    }

    switch (card) {
      case CardId.pawnDeviation:
        if (piece.type == PieceType.pawn && r + dir != 0 && r + dir != 7) {
          add(f - 1, r + dir);
          add(f + 1, r + dir);
        }
      case CardId.pawnAdvance:
        if (piece.type == PieceType.pawn &&
            r + 2 * dir > 0 &&
            r + 2 * dir < 7 &&
            board[from + 8 * dir] == null) {
          add(f, r + 2 * dir);
        }
      case CardId.rookBend:
        if (piece.type == PieceType.rook) {
          for (final df in [-1, 1]) {
            for (final dr in [-1, 1]) {
              add(f + df, r + dr);
            }
          }
        }
      case CardId.angryN:
        if (piece.type == PieceType.knight) {
          for (final d in const [
            [1, 0],
            [-1, 0],
            [0, 1],
            [0, -1],
          ]) {
            add(f + d[0], r + d[1], capture: true);
          }
        }
      case CardId.shadowPass:
        if (piece.type != PieceType.bishop && piece.type != PieceType.rook) {
          break;
        }
        final dirs =
            piece.type == PieceType.bishop
                ? const [
                  [1, 1],
                  [1, -1],
                  [-1, 1],
                  [-1, -1],
                ]
                : const [
                  [1, 0],
                  [-1, 0],
                  [0, 1],
                  [0, -1],
                ];
        for (final d in dirs) {
          var nf = f + d[0], nr = r + d[1], crossed = 0;
          while (Square.onBoard(nf, nr)) {
            final to = Square.of(nf, nr), target = board[to];
            if (target != null) {
              if (target.color != side ||
                  target.type == PieceType.king ||
                  ++crossed > 1) {
                break;
              }
            } else if (crossed == 1) {
              targets.add(to);
            }
            nf += d[0];
            nr += d[1];
          }
        }
      default:
        break;
    }
    if (targets.isEmpty) {
      return [];
    }
    final normal =
        card == CardId.pawnAdvance
            ? MoveGen.legal(_forSide(s.board, side)).map((m) => m.uci).toSet()
            : <String>{};
    return targets.map((to) => Move(from, to)).where((m) {
      if (!_restrictions(s, m, side)) return false;
      var after = _forSide(s.board, side).apply(m);
      if (card == CardId.pawnAdvance &&
          (!normal.contains(m.uci) ||
              s.movedPawns.contains(s.pieceIds[from]))) {
        after = _withoutEp(after);
      }
      return !MoveGen.inCheck(after, side);
    }).toList();
  }

  static bool _protected(RuleState s, int target, PieceColor attacker) =>
      s.pieceEffects.any(
        (e) =>
            e.type == PieceEffectType.shelter &&
            e.owner != attacker &&
            e.pieceId == s.pieceIds[target],
      ) ||
      s.boardEffects.any(
        (e) =>
            e.type == BoardEffectType.fog &&
            e.owner != attacker &&
            e.squares.contains(target),
      );
  static int effectiveCost(RuleState s, PieceColor side, CardId card) {
    var cost = cardDefinitions[card]!.cost;
    for (final m in s.modifiers.where(
      (m) => m.responseSide == side && m.ownTurn == s.ownTurns[side],
    )) {
      if (m.type == ModifierType.manaSabotage && m.targetCard == card) cost++;
      if (m.type == ModifierType.discount) cost -= 2;
    }
    return math.max(1, cost);
  }

  static List<Object?> cardTargets(PlayerView view, CardId card) {
    final s = view.rules,
        side = view.viewer,
        enemy = side.opposite,
        board = s.board.squares,
        definition = cardDefinitions[card]!;
    if (definition.category == CardCategory.movement) {
      return [
        for (var i = 0; i < 64; i++)
          if (specialMoves(s, card, i, side).isNotEmpty) i,
      ];
    }
    if (definition.category == CardCategory.vow &&
        s.vows.any((v) => v.owner == side)) {
      return [];
    }
    switch (definition.target) {
      case CardTargetType.opponentCard:
        return s.arsenals[enemy]!
            .where(
              (c) =>
                  !s.used[enemy]!.contains(c) &&
                  !s.discarded[enemy]!.contains(c),
            )
            .map((c) => c.wire)
            .toList();
      case CardTargetType.ownPiece:
        return [
          for (var i = 0; i < 64; i++)
            if (board[i] != null &&
                board[i]!.color == side &&
                board[i]!.type != PieceType.king)
              i,
        ];
      case CardTargetType.opponentPiece:
      case CardTargetType.opponentSlider:
        return [
          for (var i = 0; i < 64; i++)
            if (board[i] != null &&
                board[i]!.color == enemy &&
                board[i]!.type != PieceType.king &&
                (definition.target != CardTargetType.opponentSlider ||
                    [
                      PieceType.rook,
                      PieceType.bishop,
                      PieceType.queen,
                    ].contains(board[i]!.type)) &&
                !_protected(s, i, side))
              i,
        ];
      case CardTargetType.emptySquare:
        if (card == CardId.mine &&
            s.boardEffects.any(
              (e) => e.type == BoardEffectType.mine && e.owner == side,
            )) {
          return [];
        }
        return [
          for (var i = 0; i < 64; i++)
            if (board[i] == null &&
                (card != CardId.mine ||
                    !s.boardEffects.any(
                      (e) =>
                          e.type == BoardEffectType.mine &&
                          e.squares.contains(i),
                    )))
              i,
        ];
      case CardTargetType.zone:
        return [
          for (var i = 0; i < 64; i++)
            if (boardZone(i).length == 4 &&
                (card != CardId.boardSeal ||
                    boardZone(i).any((q) => board[q] == null)))
              i,
        ];
      case CardTargetType.ownPieceEffect:
        return s.pieceEffects
            .where(
              (e) =>
                  e.type != PieceEffectType.shelter &&
                  s.pieceEffects.where((other) => other.id == e.id).length ==
                      1 &&
                  [
                    for (var i = 0; i < 64; i++)
                      if (s.pieceIds[i] == e.pieceId && board[i]?.color == side)
                        i,
                  ].isNotEmpty,
            )
            .map((e) => e.id)
            .toList();
      case CardTargetType.opponentBoardEffect:
        return s.boardEffects
            .where(
              (e) =>
                  e.owner == enemy &&
                  s.boardEffects.where((other) => other.id == e.id).length == 1,
            )
            .map((e) => e.id)
            .toList();
      case CardTargetType.none:
        return card == CardId.prophecy && s.deckCounts[side]! < 1 ? [] : [null];
      case CardTargetType.sacrifice:
        return view.ownHand.any((c) => c != card) &&
                (card != CardId.fateExchange || s.deckCounts[side]! >= 1)
            ? [null]
            : [];
      default:
        return [];
    }
  }

  static void _checkView(PlayerView view) {
    final s = view.rules, side = view.viewer;
    if (view.ownHand.length != s.handCounts[side] ||
        view.ownHand.toSet().length != view.ownHand.length ||
        view.ownHand.any(
          (c) =>
              !s.arsenals[side]!.contains(c) ||
              s.used[side]!.contains(c) ||
              s.discarded[side]!.contains(c),
        )) {
      throw StateError('invalid-player-view');
    }
    bool validKnown(List<CardId> items, int limit) =>
        items.length <= limit &&
        items.toSet().length == items.length &&
        items.every(
          (c) =>
              s.arsenals[side]!.contains(c) &&
              !view.ownHand.contains(c) &&
              !s.used[side]!.contains(c) &&
              !s.discarded[side]!.contains(c),
        );
    final pendingLimit =
        s.phase == BattlePhase.pending && s.pending?.owner == side
            ? math.min(
              s.deckCounts[side]!,
              s.pending!.card == CardId.prophecy ? 2 : 3,
            )
            : 0;
    if (!validKnown(view.knowledge.pendingCards, pendingLimit) ||
        view.knowledge.pendingCards.length != pendingLimit ||
        !validKnown(
          view.knowledge.knownUpcomingCards,
          math.min(2, s.deckCounts[side]!),
        )) {
      throw StateError('invalid-player-knowledge');
    }
  }

  static void initializeTerminal(RuleDraft d) {
    final s = d.freeze(),
        side = s.board.turn,
        check = MoveGen.inCheck(s.board, side);
    if (legalMoves(s, side).isEmpty) {
      d.terminal = TerminalState(
        check ? 'checkmate' : 'stalemate',
        winner: check ? side.opposite : null,
      );
    } else if (s.board.halfmoveClock >= 150) {
      d.terminal = const TerminalState('seventy_five_moves');
    }
    if (d.terminal != null) {
      d.phase = BattlePhase.terminal;
    } else {
      recordRepetition(d);
    }
  }

  static List<BattleAction> legalActions(PlayerView view) {
    _checkView(view);
    final s = view.rules, side = view.viewer;
    if (s.board.turn != side || s.phase == BattlePhase.terminal) return [];
    if (s.phase == BattlePhase.pending) {
      if (s.pending?.owner != side) return [];
      final inspected = view.knowledge.pendingCards;
      if (inspected.isEmpty) return [];
      if (s.pending!.card == CardId.prophecy) {
        return _permutations(
          inspected,
        ).map((order) => ResolveAction(order)).toList();
      }
      return [
        for (final selected in inspected)
          for (final order in _permutations(
            inspected.where((c) => c != selected).toList(),
          ))
            ResolveAction(order, selected: selected),
      ];
    }
    if (s.phase == BattlePhase.chess) {
      return legalMoves(
        s,
        side,
        authorization: s.special,
      ).map((m) => ChessMoveAction(m.uci)).toList();
    }
    if (s.ownTurns[side]! < 2) return [];
    final actions = <BattleAction>[
      const PassAction(),
      ...view.ownHand.map(DiscardAction.new),
    ];
    for (final card in view.ownHand) {
      if (s.mana[side]! < effectiveCost(s, side, card) ||
          s.modifiers.any(
            (m) =>
                m.type == ModifierType.cardBlock &&
                m.responseSide == side &&
                m.ownTurn == s.ownTurns[side] &&
                m.targetCard == card,
          )) {
        continue;
      }
      for (final target in cardTargets(view, card)) {
        if (card == CardId.fateExchange || card == CardId.shadowContract) {
          for (final sacrifice in view.ownHand.where((c) => c != card)) {
            actions.add(
              PlayCardAction(card, target: target, sacrifice: sacrifice),
            );
          }
        } else {
          actions.add(PlayCardAction(card, target: target));
        }
      }
    }
    actions.sort((a, b) => a.key.compareTo(b.key));
    return actions;
  }

  static void _closeCardWindow(RuleDraft d, PieceColor side) {
    d.pieceEffects.removeWhere(
      (e) => e.duration == EffectDuration.card && e.responseSide == side,
    );
    d.boardEffects.removeWhere(
      (e) => e.duration == EffectDuration.card && e.responseSide == side,
    );
    d.modifiers.removeWhere(
      (m) => m.responseSide == side && m.ownTurn <= d.ownTurns[side]!,
    );
    d.phase = BattlePhase.chess;
  }

  static String _effectId(RuleDraft d) => 'e${++d.effectSequence}';
  static ({CardId? radar, int inspect}) _applyCard(
    RuleDraft d,
    PlayerView view,
    PlayCardAction a,
  ) {
    final side = view.viewer,
        enemy = side.opposite,
        card = a.card,
        target = a.target;
    d.mana[side] = d.mana[side]! - effectiveCost(d.freeze(), side, card);
    d.handCounts[side] = d.handCounts[side]! - 1;
    d.used[side]!.add(card);
    d.used[side]!.sort((a, b) => a.wire.compareTo(b.wire));
    if (a.sacrifice != null) {
      d.handCounts[side] = d.handCounts[side]! - 1;
      d.discarded[side]!.add(a.sacrifice!);
      d.discarded[side]!.sort((a, b) => a.wire.compareTo(b.wire));
    }
    for (final m in d.modifiers.where(
      (m) =>
          m.type == ModifierType.echo &&
          m.responseSide == side &&
          m.ownTurn == d.ownTurns[side] &&
          m.targetCard == card,
    )) {
      d.mana[m.owner] = math.min(6, d.mana[m.owner]! + 2);
    }
    CardId? radar;
    var inspect = 0;
    if (movementCards.contains(card)) {
      d.special = SpecialMoveAuthorization(
        card,
        target as int,
        specialMoves(d.freeze(), card, target, side).map((m) => m.uci).toList()
          ..sort(),
      );
    } else {
      switch (card) {
        case CardId.radar:
          radar = CardId.parse(target as String);
        case CardId.prophecy:
        case CardId.fateExchange:
          d.pending = PendingResolution(card, side);
          d.phase = BattlePhase.pending;
          inspect = card == CardId.prophecy ? 2 : 3;
        case CardId.shelter:
        case CardId.chain:
        case CardId.slow:
        case CardId.freeze:
          final type = switch (card) {
            CardId.shelter => PieceEffectType.shelter,
            CardId.chain => PieceEffectType.chain,
            CardId.slow => PieceEffectType.slow,
            _ => PieceEffectType.freeze,
          };
          d.pieceEffects.add(
            ActivePieceEffect(
              id: _effectId(d),
              type: type,
              owner: side,
              pieceId: d.pieceIds[target as int]!,
              responseSide: enemy,
              duration:
                  card == CardId.shelter
                      ? EffectDuration.card
                      : EffectDuration.move,
            ),
          );
        case CardId.purify:
          d.pieceEffects.removeWhere((e) => e.id == target);
        case CardId.mine:
        case CardId.lockedSquare:
        case CardId.fog:
        case CardId.boardSeal:
          final type = switch (card) {
            CardId.mine => BoardEffectType.mine,
            CardId.lockedSquare => BoardEffectType.lockedSquare,
            CardId.fog => BoardEffectType.fog,
            _ => BoardEffectType.boardSeal,
          };
          d.boardEffects.add(
            BoardEffectInstance(
              id: _effectId(d),
              type: type,
              owner: side,
              squares:
                  card == CardId.fog || card == CardId.boardSeal
                      ? boardZone(target as int)
                      : [target as int],
              responseSide: enemy,
              duration:
                  card == CardId.mine
                      ? EffectDuration.persistent
                      : card == CardId.fog
                      ? EffectDuration.card
                      : EffectDuration.move,
            ),
          );
        case CardId.breakSeal:
          d.boardEffects.removeWhere((e) => e.id == target);
        case CardId.manaSabotage:
        case CardId.cardBlock:
        case CardId.echo:
          final type = switch (card) {
            CardId.manaSabotage => ModifierType.manaSabotage,
            CardId.cardBlock => ModifierType.cardBlock,
            _ => ModifierType.echo,
          };
          d.modifiers.add(
            PendingModifier(
              id: _effectId(d),
              type: type,
              owner: side,
              responseSide: enemy,
              targetCard: CardId.parse(target as String),
              ownTurn: d.ownTurns[enemy]! + 1,
            ),
          );
        case CardId.shadowContract:
          d.modifiers.add(
            PendingModifier(
              id: _effectId(d),
              type: ModifierType.discount,
              owner: side,
              responseSide: side,
              targetCard: null,
              ownTurn: d.ownTurns[side]! + 1,
            ),
          );
        case CardId.huntVow:
        case CardId.watchVow:
          d.vows.add(
            VowState(
              id: _effectId(d),
              type: card == CardId.huntVow ? VowType.hunt : VowType.watch,
              owner: side,
              pieceId:
                  card == CardId.huntVow ? d.pieceIds[target as int] : null,
              square: card == CardId.watchVow ? target as int : null,
              remainingMoves: card == CardId.huntVow ? 2 : 1,
            ),
          );
        default:
          break;
      }
    }
    if (inspect == 0) _closeCardWindow(d, side);
    return (radar: radar, inspect: inspect);
  }

  static List<Move> _counterfactualDefenses(RuleState s, PieceColor side) {
    final d = RuleDraft(s);
    d.pieceEffects.removeWhere(
      (e) =>
          e.type != PieceEffectType.shelter &&
          [
            for (var i = 0; i < 64; i++)
              if (s.pieceIds[i] == e.pieceId &&
                  s.board.squares[i]?.color == side)
                i,
          ].isNotEmpty,
    );
    d.boardEffects.removeWhere(
      (e) =>
          e.owner != side &&
          (e.type == BoardEffectType.lockedSquare ||
              e.type == BoardEffectType.boardSeal),
    );
    return legalMoves(d.freeze(), side);
  }

  static PieceColor? _resolveMove(RuleDraft d, Move move, PieceColor side) {
    final before = d.board,
        enemy = side.opposite,
        isSpecial = d.special != null;
    // A quiet card move and en passant can share UCI but not move semantics.
    final normal = MoveGen.legal(before).contains(move);
    final moverId = d.pieceIds[move.from]!,
        captureSquare =
            move.isEnPassant
                ? move.to + (side == PieceColor.white ? -8 : 8)
                : move.to;
    final capturedId =
        before.squares[captureSquare] != null
            ? d.pieceIds[captureSquare]
            : null;
    final movingIds = [moverId],
        relocations = [move.to],
        oldEffects = d.pieceEffects.map((e) => e.id).toSet();
    d.pieceIds[move.from] = null;
    if (capturedId != null) d.pieceIds[captureSquare] = null;
    d.pieceIds[move.to] = moverId;
    if (move.isCastle) {
      final rank = Square.rankOf(move.from) * 8,
          k = Square.fileOf(move.to) == 6,
          rf = rank + (k ? 7 : 0),
          rt = rank + (k ? 5 : 3);
      movingIds.add(d.pieceIds[rf]!);
      d.pieceIds[rt] = d.pieceIds[rf];
      d.pieceIds[rf] = null;
      relocations.add(rt);
    }
    final cardDouble =
        d.special?.card == CardId.pawnAdvance &&
        (!normal || d.movedPawns.contains(moverId));
    d.board = before.apply(move);
    if (cardDouble) d.board = _withoutEp(d.board);
    d.ply++;
    if (before.squares[move.from]!.type == PieceType.pawn &&
        !d.movedPawns.contains(moverId)) {
      d.movedPawns.add(moverId);
      d.movedPawns.sort();
    }
    final retainedVows = <VowState>[];
    for (var v in d.vows) {
      if (v.type != VowType.hunt) {
        retainedVows.add(v);
        continue;
      }
      if (v.pieceId == capturedId) {
        if (v.owner == side && !isSpecial) {
          d.mana[side] = math.min(6, d.mana[side]! + 2);
        }
        continue;
      }
      if (v.owner == side) v = v.tick();
      if (v.remainingMoves > 0) retainedVows.add(v);
    }
    d.vows = retainedVows;
    // Existing debuffs are consumed later; freshly triggered Mines survive.
    final retainedBoard = <BoardEffectInstance>[];
    for (final e in d.boardEffects) {
      if (e.type != BoardEffectType.mine || e.owner == side) {
        retainedBoard.add(e);
        continue;
      }
      final arrivals =
          relocations
              .where(
                (to) =>
                    e.squares.contains(to) &&
                    d.board.squares[to] != null &&
                    d.board.squares[to]!.type != PieceType.king,
              )
              .toList();
      if (arrivals.isEmpty) {
        retainedBoard.add(e);
        continue;
      }
      d.pieceEffects.add(
        ActivePieceEffect(
          id: _effectId(d),
          type: PieceEffectType.mineDebuff,
          owner: e.owner,
          pieceId: d.pieceIds[arrivals.first]!,
          responseSide: side,
          duration: EffectDuration.pieceMove,
        ),
      );
    }
    d.boardEffects = retainedBoard;
    d.vows.removeWhere((v) {
      if (v.type != VowType.watch || v.owner == side) return false;
      if (v.square != null && d.board.squares[v.square!]?.color == side) {
        d.mana[v.owner] = math.min(6, d.mana[v.owner]! + 2);
      }
      return true;
    });
    d.pieceEffects.removeWhere(
      (e) =>
          !d.pieceIds.contains(e.pieceId) ||
          (e.duration == EffectDuration.move && e.responseSide == side) ||
          (e.duration == EffectDuration.pieceMove &&
              oldEffects.contains(e.id) &&
              movingIds.contains(e.pieceId)),
    );
    d.boardEffects.removeWhere(
      (e) => e.duration == EffectDuration.move && e.responseSide == side,
    );
    d.special = null;
    final state = d.freeze(),
        defense = legalMoves(state, enemy),
        check = MoveGen.inCheck(d.board, enemy);
    if (defense.isEmpty) {
      final restricted = _counterfactualDefenses(state, enemy).isNotEmpty;
      d.terminal = TerminalState(
        check ? 'checkmate' : 'stalemate',
        winner: check ? side : null,
        mateByRestriction: check && restricted,
        mateBySpecialMove: check && isSpecial && !normal,
        stalemateByRestriction: !check && restricted,
      );
    } else if (d.board.isSeventyFiveMoveRule) {
      d.terminal = const TerminalState('seventy_five_moves');
    }
    if (d.terminal != null) {
      d.phase = BattlePhase.terminal;
      return null;
    }
    PieceColor? draw;
    if (d.handCounts[side]! < 4 && d.deckCounts[side]! > 0) {
      d.handCounts[side] = d.handCounts[side]! + 1;
      d.deckCounts[side] = d.deckCounts[side]! - 1;
      d.drawCounts[side] = d.drawCounts[side]! + 1;
      draw = side;
    }
    d.ownTurns[enemy] = d.ownTurns[enemy]! + 1;
    if (d.ownTurns[enemy]! > 1) d.mana[enemy] = math.min(6, d.mana[enemy]! + 1);
    d.phase = d.ownTurns[enemy] == 1 ? BattlePhase.chess : BattlePhase.card;
    recordRepetition(d);
    return draw;
  }

  static String publicFingerprint(RuleState s) {
    if (!(s.phase == BattlePhase.card && s.ownTurns[s.board.turn]! >= 2) &&
        !(s.phase == BattlePhase.chess && s.ownTurns[s.board.turn] == 1)) {
      throw StateError('not-stable-boundary');
    }
    final json = s.toJson(), fen = s.fen.split(' ');
    if (!legalMoves(s, s.board.turn).any((m) => m.isEnPassant)) fen[3] = '-';
    final data = <String, Object?>{
      'fen': fen.take(4).join(' '),
      'phase': s.phase.name,
      'firstTurns': {
        'w': s.ownTurns[PieceColor.white]! <= 1,
        'b': s.ownTurns[PieceColor.black]! <= 1,
      },
      for (final key in [
        'mana',
        'handCounts',
        'deckCounts',
        'drawCounts',
        'arsenals',
        'used',
        'discarded',
        'pieceIds',
        'movedPawns',
        'pieceEffects',
        'boardEffects',
        'vows',
        'special',
      ])
        key: json[key],
      'modifiers':
          s.modifiers
              .map(
                (m) => {
                  ...m.toJson(),
                  'ownTurn': m.ownTurn - s.ownTurns[m.responseSide]!,
                },
              )
              .toList(),
    };
    return jsonEncode(canonicalObject(data));
  }

  static void recordRepetition(RuleDraft d) {
    final key = publicFingerprint(d.freeze()),
        count = (d.repetitions[key] ?? 0) + 1;
    d.repetitions[key] = count;
    if (count >= 5) {
      d.phase = BattlePhase.terminal;
      d.terminal = const TerminalState('fivefold');
    }
  }

  static bool _matchesAction(BattleAction requested, BattleAction canonical) {
    switch (canonical) {
      case PassAction():
        return requested is PassAction;
      case ChessMoveAction():
        return requested is ChessMoveAction && requested.uci == canonical.uci;
      case DiscardAction():
        return requested is DiscardAction && requested.card == canonical.card;
      case PlayCardAction():
        if (requested is! PlayCardAction ||
            requested.card != canonical.card ||
            requested.sacrifice != canonical.sacrifice) {
          return false;
        }
        final target = canonical.target;
        return target == null
            ? requested.target == null
            : target is int
            ? requested.target is int && requested.target == target
            : requested.target is String && requested.target == target;
      case ResolveAction():
        return requested is ResolveAction &&
            requested.selected == canonical.selected &&
            requested.order.length == canonical.order.length &&
            List.generate(
              canonical.order.length,
              (i) => requested.order[i] == canonical.order[i],
            ).every((same) => same);
    }
  }

  static bool isLegalAction(PlayerView view, BattleAction requested) =>
      legalActions(view).any((action) => _matchesAction(requested, action));

  static RuleTransition transition(PlayerView view, BattleAction requested) {
    final matches =
        legalActions(view).where((a) => _matchesAction(requested, a)).toList();
    if (matches.isEmpty) throw StateError('illegal-action');
    final action = matches.first, d = RuleDraft(view.rules), side = view.viewer;
    PieceColor? draw;
    CardId? radar;
    var inspect = 0;
    switch (action) {
      case PassAction():
        _closeCardWindow(d, side);
      case DiscardAction():
        d.handCounts[side] = d.handCounts[side]! - 1;
        d.discarded[side]!.add(action.card);
        d.discarded[side]!.sort((a, b) => a.wire.compareTo(b.wire));
        _closeCardWindow(d, side);
      case PlayCardAction():
        final result = _applyCard(d, view, action);
        radar = result.radar;
        inspect = result.inspect;
      case ResolveAction():
        if (d.pending!.card == CardId.fateExchange) {
          d.handCounts[side] = d.handCounts[side]! + 1;
          d.deckCounts[side] = d.deckCounts[side]! - 1;
          d.drawCounts[side] = d.drawCounts[side]! + 1;
        }
        d.pending = null;
        _closeCardWindow(d, side);
      case ChessMoveAction():
        draw = _resolveMove(
          d,
          legalMoves(
            view.rules,
            side,
            authorization: view.rules.special,
          ).firstWhere((m) => m.uci == action.uci),
          side,
        );
    }
    return RuleTransition(
      d.freeze(),
      draw: draw,
      radar: radar,
      inspect: inspect,
    );
  }

  static BattleAction? chooseBotAction(PlayerView view) {
    final actions = legalActions(view);
    if (actions.isEmpty) return null;
    int score(BattleAction action) => switch (action) {
      ChessMoveAction() =>
        10 +
            (view.rules.board.squares[(action.uci.codeUnitAt(2) - 97) +
                        8 * (int.parse(action.uci[3]) - 1)] !=
                    null
                ? 10
                : 0),
      PlayCardAction() => 30,
      ResolveAction() => 40,
      PassAction() => 1,
      DiscardAction() => 0,
    };
    actions.sort((a, b) {
      final rank = score(b).compareTo(score(a));
      return rank == 0 ? a.key.compareTo(b.key) : rank;
    });
    return actions.first;
  }
}

Object? canonicalObject(Object? value) {
  if (value is List) return value.map(canonicalObject).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalObject(value[key])};
  }
  return value;
}
