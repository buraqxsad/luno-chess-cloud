import 'dart:convert';
import 'dart:math' as math;

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/local_clock.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const pawnDeviationMateFen = 'B6R/2k5/4B3/2KpP3/3r4/8/8/8 w - d6 0 10';
const pawnDeviationBaseFen = '4k3/p7/8/8/3PP3/8/8/4K3 w - - 37 10';

int pawnSquare(PieceColor side, int whiteSquare) =>
    side.isWhite ? whiteSquare : 63 - whiteSquare;

String pawnUci(PieceColor side, String whiteUci) {
  if (side.isWhite) return whiteUci;
  int index(int offset) =>
      whiteUci.codeUnitAt(offset) -
      97 +
      8 * (int.parse(whiteUci[offset + 1]) - 1);
  return '${Square.algebraic(63 - index(0))}'
      '${Square.algebraic(63 - index(2))}'
      '${whiteUci.substring(4)}';
}

Board pawnBoard(String whiteFen, PieceColor side) {
  final board = Board.fromFen(whiteFen);
  if (side.isWhite) return board;
  return Board(
    squares:
        board.squares.reversed
            .map((p) => p?.copyWith(color: p.color.opposite))
            .toList(),
    turn: PieceColor.black,
    castling: 0,
    enPassant: board.enPassant == null ? null : 63 - board.enPassant!,
    halfmoveClock: board.halfmoveClock,
    fullmoveNumber: board.fullmoveNumber,
  );
}

AuthoritativeBattleState pawnFixture({
  PieceColor side = PieceColor.white,
  String fen = pawnDeviationBaseFen,
  int mana = 6,
  List<CardId>? deck,
  Board? board,
}) {
  final cards =
      deck ??
      [
        CardId.pawnDeviation,
        CardId.radar,
        CardId.prophecy,
        ...CardId.values
            .where(
              (c) =>
                  !const [
                    CardId.pawnDeviation,
                    CardId.radar,
                    CardId.prophecy,
                  ].contains(c),
            )
            .take(7),
      ];
  final initial = DeckManager.newBattle(
    board: board ?? pawnBoard(fen, side),
    white: cards,
    black: cards,
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
        ..ownTurns[side] = 2
        ..ownTurns[side.opposite] = 2
        ..mana[side] = mana
        ..effectSequence = 100;
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}

AuthoritativeBattleState pawnEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

ActivePieceEffect pawnPieceEffect(
  AuthoritativeBattleState state,
  PieceEffectType type, {
  int whiteSquare = 27,
  String id = 'v223-piece',
  EffectDuration? duration,
  PieceColor? owner,
  PieceColor? responseSide,
}) {
  final side = state.rules.board.turn;
  return ActivePieceEffect(
    id: id,
    type: type,
    owner: owner ?? side.opposite,
    pieceId: state.rules.pieceIds[pawnSquare(side, whiteSquare)]!,
    responseSide: responseSide ?? side,
    duration:
        duration ??
        (type == PieceEffectType.mineDebuff
            ? EffectDuration.pieceMove
            : EffectDuration.move),
  );
}

BoardEffectInstance pawnBoardEffect(
  AuthoritativeBattleState state,
  BoardEffectType type,
  List<int> whiteSquares, {
  String id = 'v223-board',
  PieceColor? owner,
  EffectDuration? duration,
}) {
  final side = state.rules.board.turn;
  return BoardEffectInstance(
    id: id,
    type: type,
    owner: owner ?? side.opposite,
    squares: whiteSquares.map((s) => pawnSquare(side, s)).toList(),
    responseSide: side,
    duration:
        duration ??
        (type == BoardEffectType.mine
            ? EffectDuration.persistent
            : EffectDuration.move),
  );
}

AuthoritativeBattleState pawnCast(
  AuthoritativeBattleState state, {
  int whiteFrom = 27,
}) => DeckManager.apply(
  state,
  PlayCardAction(
    CardId.pawnDeviation,
    target: pawnSquare(state.rules.board.turn, whiteFrom),
  ),
);

AuthoritativeBattleState pawnMove(AuthoritativeBattleState state, String uci) =>
    DeckManager.apply(
      state,
      ChessMoveAction(pawnUci(state.rules.board.turn, uci)),
    );

// Quiet relocation and attack geometry are independent of MoveGen/Board.apply.
bool pawnOracleAttacked(List<Piece?> board, int target, PieceColor attacker) {
  for (var from = 0; from < 64; from++) {
    final piece = board[from];
    if (piece == null || piece.color != attacker || from == target) continue;
    final df = target % 8 - from % 8, dr = target ~/ 8 - from ~/ 8;
    switch (piece.type) {
      case PieceType.pawn:
        if (df.abs() == 1 && dr == (attacker.isWhite ? 1 : -1)) return true;
      case PieceType.knight:
        if (df.abs() * dr.abs() == 2) return true;
      case PieceType.king:
        if (math.max(df.abs(), dr.abs()) == 1) return true;
      case PieceType.rook:
      case PieceType.bishop:
      case PieceType.queen:
        final straight = df == 0 || dr == 0;
        final diagonal = df.abs() == dr.abs();
        if (piece.type == PieceType.rook && !straight ||
            piece.type == PieceType.bishop && !diagonal ||
            piece.type == PieceType.queen && !straight && !diagonal) {
          continue;
        }
        final step = df.sign + 8 * dr.sign;
        var blocked = false;
        for (var at = from + step; at != target; at += step) {
          if (board[at] != null) {
            blocked = true;
            break;
          }
        }
        if (!blocked) return true;
    }
  }
  return false;
}

List<String> pawnOracleMoves(RuleState rules, int from, PieceColor side) {
  if (from < 0 || from >= 64) return const [];
  final piece = rules.board.squares[from];
  if (piece?.color != side || piece?.type != PieceType.pawn) return const [];
  final rank = from ~/ 8 + (side.isWhite ? 1 : -1);
  if (rank < 1 ||
      rank > 6 ||
      rules.pieceEffects.any(
        (e) =>
            e.pieceId == rules.pieceIds[from] &&
            e.type == PieceEffectType.freeze,
      )) {
    return const [];
  }
  final king = rules.board.squares.indexWhere(
    (p) => p?.color == side && p?.type == PieceType.king,
  );
  if (king < 0) throw StateError('oracle-missing-king');
  final result = <String>[];
  for (final file in [from % 8 - 1, from % 8 + 1]) {
    if (file < 0 || file > 7) continue;
    final to = rank * 8 + file;
    if (rules.board.squares[to] != null ||
        rules.boardEffects.any(
          (e) =>
              e.owner != side &&
              (e.type == BoardEffectType.lockedSquare ||
                  e.type == BoardEffectType.boardSeal) &&
              e.squares.contains(to),
        )) {
      continue;
    }
    final after = [...rules.board.squares]..[from] = null;
    after[to] = piece;
    if (!pawnOracleAttacked(after, king, side.opposite)) {
      result.add(Square.algebraic(from) + Square.algebraic(to));
    }
  }
  return result..sort();
}

void pawnRequire(bool value, String message) {
  if (!value) throw StateError(message);
}

void pawnEqual(Object? actual, Object? expected, String label) => pawnRequire(
  jsonEncode(actual) == jsonEncode(expected),
  '$label: expected ${jsonEncode(expected)}, actual ${jsonEncode(actual)}',
);

void pawnRejected(AuthoritativeBattleState state, BattleAction action) {
  final frozen = jsonEncode(state.toJson());
  pawnRequire(
    !BattleRulesCore.isLegalAction(state.view(state.rules.board.turn), action),
    'action unexpectedly admitted',
  );
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    pawnEqual(error.message, 'illegal-action', 'rejection kind');
    rejected = true;
  }
  pawnRequire(rejected, 'action unexpectedly applied');
  pawnEqual(jsonEncode(state.toJson()), frozen, 'rejected input immutability');
}

class PawnDeviationCase {
  final String name;
  final void Function() run;
  const PawnDeviationCase(this.name, this.run);
}

List<PawnDeviationCase> pawnDeviationCases() {
  final cases = <PawnDeviationCase>[];
  for (final side in PieceColor.values) {
    void add(String label, void Function() run) =>
        cases.add(PawnDeviationCase('${side.name}: $label', run));

    for (final position
        in <({String label, String fen, int from, List<String> expected})>[
          (
            label: 'both quiet diagonals',
            fen: pawnDeviationBaseFen,
            from: 27,
            expected: ['d4c5', 'd4e5'],
          ),
          (
            label: 'occupied diagonals of both colors',
            fen: '4k3/8/8/2n1B3/3P4/8/8/4K3 w - - 0 10',
            from: 27,
            expected: [],
          ),
          (
            label: 'rook absolute pin',
            fen: '4r1k1/8/8/8/4P3/8/8/4K3 w - - 0 10',
            from: 28,
            expected: [],
          ),
          (
            label: 'bishop pin allows continuing on its line',
            fen: '7k/6b1/8/4P3/3K4/8/8/8 w - - 0 10',
            from: 36,
            expected: ['e5f6'],
          ),
          (
            label: 'check can be answered by quiet diagonal interposition',
            fen: '4r2k/8/8/8/8/8/3P4/4K3 w - - 0 10',
            from: 11,
            expected: ['d2e3'],
          ),
          (
            label: 'unanswered knight check',
            fen: '7k/8/8/8/3P4/5n2/8/4K3 w - - 0 10',
            from: 27,
            expected: [],
          ),
          (
            label: 'double check cannot be answered by unrelated pawn',
            fen: '4r2k/8/8/8/1b1P4/8/8/4K3 w - - 0 10',
            from: 27,
            expected: [],
          ),
          (
            label: 'ep checker is not removed by deviation',
            fen: '7k/8/8/3pP3/4K3/8/8/8 w - d6 0 10',
            from: 36,
            expected: [],
          ),
          (
            label: 'quiet ep-square landing preserves the rook blocker',
            fen: '7k/8/8/4KPpr/8/8/8/8 w - g6 0 10',
            from: 37,
            expected: ['f5e6', 'f5g6'],
          ),
          (
            label: 'a-file cannot wrap',
            fen: '4k3/8/8/8/P7/8/8/4K3 w - - 0 10',
            from: 24,
            expected: ['a4b5'],
          ),
          (
            label: 'h-file cannot wrap',
            fen: '4k3/8/8/8/7P/8/8/4K3 w - - 0 10',
            from: 31,
            expected: ['h4g5'],
          ),
          (
            label: 'penultimate rank cannot promote',
            fen: '4k3/P6P/8/8/8/8/8/4K3 w - - 0 10',
            from: 48,
            expected: [],
          ),
          (
            label: 'rank six can land on rank seven',
            fen: '4k3/8/P7/8/8/8/8/4K3 w - - 0 10',
            from: 40,
            expected: ['a6b7'],
          ),
        ]) {
      add(position.label, () {
        final state = pawnFixture(side: side, fen: position.fen);
        final from = pawnSquare(side, position.from);
        final wanted =
            position.expected.map((u) => pawnUci(side, u)).toList()..sort();
        pawnEqual(
          pawnOracleMoves(state.rules, from, side),
          wanted,
          'independent expectation',
        );
        final moves = BattleRulesCore.specialMoves(
          state.rules,
          CardId.pawnDeviation,
          from,
          side,
        );
        pawnEqual(
          moves.map((m) => m.uci).toList()..sort(),
          wanted,
          'special geometry',
        );
        pawnRequire(
          moves.every(
            (m) => !m.isEnPassant && !m.isCastle && m.promotion == null,
          ),
          'deviation must be a quiet non-promotion move',
        );
        final admitted = BattleRulesCore.legalActions(state.view(side))
            .whereType<PlayCardAction>()
            .any((a) => a.card == CardId.pawnDeviation && a.target == from);
        pawnEqual(admitted, wanted.isNotEmpty, 'target admission');
        if (wanted.isEmpty) {
          pawnRejected(
            state,
            PlayCardAction(CardId.pawnDeviation, target: from),
          );
        }
      });
    }

    add(
      'wrong target runtime types and out-of-range squares reject atomically',
      () {
        final state = pawnFixture(side: side);
        for (final target in <Object?>[
          null,
          '${pawnSquare(side, 27)}',
          pawnSquare(side, 27).toDouble(),
          true,
          [],
          {},
          -1,
          64,
          pawnSquare(side, 4),
          pawnSquare(side, 60),
          pawnSquare(side, 35),
        ]) {
          pawnRejected(
            state,
            PlayCardAction(CardId.pawnDeviation, target: target),
          );
        }
        pawnRejected(
          state,
          PlayCardAction(
            CardId.pawnDeviation,
            target: pawnSquare(side, 27),
            sacrifice: CardId.radar,
          ),
        );
      },
    );

    for (final type in PieceEffectType.values) {
      add('${type.name} overlap obeys quiet-move restriction', () {
        final initial = pawnFixture(side: side);
        final state = pawnEdit(
          initial,
          (d) => d.pieceEffects.add(pawnPieceEffect(initial, type)),
        );
        final wanted =
            type == PieceEffectType.freeze
                  ? <String>[]
                  : ['d4c5', 'd4e5'].map((u) => pawnUci(side, u)).toList()
              ..sort();
        pawnEqual(
          BattleRulesCore.specialMoves(
              state.rules,
              CardId.pawnDeviation,
              pawnSquare(side, 27),
              side,
            ).map((m) => m.uci).toList()
            ..sort(),
          wanted,
          'overlap geometry',
        );
      });
    }

    for (final type in BoardEffectType.values) {
      for (final own in [false, true]) {
        add('${type.name} ${own ? 'own' : 'enemy'} diagonal overlap', () {
          final initial = pawnFixture(side: side);
          final state = pawnEdit(
            initial,
            (d) => d.boardEffects.add(
              pawnBoardEffect(initial, type, [
                34,
              ], owner: own ? side : side.opposite),
            ),
          );
          final blocks =
              !own &&
              (type == BoardEffectType.lockedSquare ||
                  type == BoardEffectType.boardSeal);
          final wanted =
              [
                  if (!blocks) 'd4c5',
                  'd4e5',
                ].map((u) => pawnUci(side, u)).toList()
                ..sort();
          pawnEqual(
            pawnOracleMoves(state.rules, pawnSquare(side, 27), side),
            wanted,
            'board oracle',
          );
          pawnEqual(
            BattleRulesCore.specialMoves(
                state.rules,
                CardId.pawnDeviation,
                pawnSquare(side, 27),
                side,
              ).map((m) => m.uci).toList()
              ..sort(),
            wanted,
            'board restrictions',
          );
        });
      }
    }

    add(
      'authorization reserves exactly one pawn and replaces the normal move',
      () {
        final state = pawnFixture(side: side);
        final before = jsonEncode(state.toJson());
        final cast = pawnCast(state);
        pawnEqual(cast.rules.fen, state.rules.fen, 'cast board');
        pawnEqual(cast.rules.phase.name, 'chess', 'cast phase');
        pawnEqual(cast.rules.ply, 0, 'cast ply');
        pawnEqual(cast.rules.mana[side], 4, 'cast cost');
        pawnEqual(cast.rules.handCounts[side], 2, 'cast hand count');
        pawnEqual(cast.rules.deckCounts[side], 7, 'cast does not draw');
        pawnEqual(cast.rules.drawCounts[side], 3, 'cast cumulative draw');
        pawnEqual(cast.rules.special?.from, pawnSquare(side, 27), 'bound pawn');
        pawnRequire(
          cast.rules.pending == null,
          'movement must not create pending',
        );
        pawnRequire(
          !cast.hidden.hands[side]!.contains(CardId.pawnDeviation),
          'card must leave hidden hand once',
        );
        pawnEqual(
          BattleRulesCore.legalActions(
              cast.view(side),
            ).whereType<ChessMoveAction>().map((a) => a.uci).toList()
            ..sort(),
          ['d4c5', 'd4e5'].map((u) => pawnUci(side, u)).toList()..sort(),
          'bound action set',
        );
        for (final action in <BattleAction>[
          const PassAction(),
          const DiscardAction(CardId.radar),
          const PlayCardAction(CardId.prophecy),
          ResolveAction([]),
          ChessMoveAction(pawnUci(side, 'e1d1')),
          ChessMoveAction(pawnUci(side, 'd4d5')),
          ChessMoveAction(pawnUci(side, 'e4d5')),
          ChessMoveAction(pawnUci(side, 'd4c5q')),
        ]) {
          pawnRejected(cast, action);
        }
        final moved = pawnMove(cast, 'd4c5');
        pawnRequire(
          moved.rules.special == null,
          'authorization must be consumed',
        );
        pawnRequire(
          moved.rules.board.turn == side.opposite,
          'turn must advance',
        );
        pawnEqual(moved.rules.ply, 1, 'one completed move');
        pawnEqual(moved.rules.board.halfmoveClock, 0, 'pawn resets clock');
        pawnEqual(
          moved.rules.board.fullmoveNumber,
          side.isWhite ? 10 : 11,
          'fullmove increments on black only',
        );
        pawnRequire(moved.rules.board.enPassant == null, 'no new ep right');
        pawnEqual(moved.rules.handCounts[side], 3, 'one end-move draw');
        pawnEqual(
          moved.rules.deckCounts[side],
          6,
          'one card removed from deck',
        );
        pawnEqual(moved.rules.drawCounts[side], 4, 'one cumulative draw');
        pawnEqual(
          moved.rules.ownTurns[side.opposite],
          3,
          'enemy turn increment',
        );
        pawnEqual(moved.rules.movedPawns, [
          state.rules.pieceIds[pawnSquare(side, 27)]!,
        ], 'pawn move history');
        pawnEqual(
          moved.rules.board.squares.where((p) => p != null).length,
          5,
          'no capture',
        );
        pawnEqual(
          BattleRulesCore.legalActions(moved.view(side)).length,
          0,
          'no extra move',
        );
        pawnEqual(
          jsonEncode(state.toJson()),
          before,
          'accepted input immutability',
        );
      },
    );

    add('authorization list is not an alternate source of geometry', () {
      final cast = pawnCast(pawnFixture(side: side));
      final forged = pawnEdit(
        cast,
        (d) =>
            d.special = SpecialMoveAuthorization(
              CardId.pawnDeviation,
              pawnSquare(side, 27),
              ['d4c5', 'd4d5', 'e1d1'].map((u) => pawnUci(side, u)).toList(),
            ),
      );
      pawnEqual(
        BattleRulesCore.legalActions(
          forged.view(side),
        ).whereType<ChessMoveAction>().map((a) => a.uci).toList(),
        [pawnUci(side, 'd4c5')],
        'recomputed intersection',
      );
      pawnRejected(forged, ChessMoveAction(pawnUci(side, 'd4d5')));
      final blocked = pawnEdit(
        cast,
        (d) =>
            d.pieceEffects.add(pawnPieceEffect(cast, PieceEffectType.freeze)),
      );
      pawnEqual(
        BattleRulesCore.legalActions(blocked.view(side)).length,
        0,
        'stale authorization cannot bypass new freeze',
      );
    });

    for (final mana in [0, 1, 2, 3, 6]) {
      add('base admission with mana $mana', () {
        final state = pawnFixture(side: side, mana: mana);
        final cast = PlayCardAction(
          CardId.pawnDeviation,
          target: pawnSquare(side, 27),
        );
        pawnEqual(
          BattleRulesCore.isLegalAction(state.view(side), cast),
          mana >= 2,
          'affordability',
        );
        if (mana < 2) pawnRejected(state, cast);
      });
    }

    for (final type in ModifierType.values) {
      add('${type.name} targets only current card window', () {
        final initial = pawnFixture(side: side, mana: 2);
        final state = pawnEdit(
          initial,
          (d) => d.modifiers.add(
            PendingModifier(
              id: 'v223-modifier',
              type: type,
              owner: side.opposite,
              responseSide: side,
              targetCard: CardId.pawnDeviation,
              ownTurn: 2,
            ),
          ),
        );
        final cost =
            type == ModifierType.manaSabotage
                ? 3
                : type == ModifierType.discount
                ? 1
                : 2;
        pawnEqual(
          BattleRulesCore.effectiveCost(
            state.rules,
            side,
            CardId.pawnDeviation,
          ),
          cost,
          'effective cost',
        );
        final admitted = type != ModifierType.cardBlock && cost <= 2;
        pawnEqual(
          BattleRulesCore.isLegalAction(
            state.view(side),
            PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
          ),
          admitted,
          'modified admission',
        );
        pawnRequire(
          BattleRulesCore.isLegalAction(
            state.view(side),
            const DiscardAction(CardId.pawnDeviation),
          ),
          'block must allow discard',
        );
        if (admitted) {
          final cast = pawnCast(state);
          pawnEqual(cast.rules.mana[side], 2 - cost, 'modified mana charge');
          pawnEqual(
            cast.rules.mana[side.opposite],
            type == ModifierType.echo ? 3 : 1,
            'echo payoff at cast',
          );
          pawnRequire(cast.rules.modifiers.isEmpty, 'current modifier expires');
        }
      });
    }

    add('sabotage discount echo combine and future block remains dormant', () {
      final initial = pawnFixture(side: side, mana: 1);
      final state = pawnEdit(initial, (d) {
        d.mana[side.opposite] = 5;
        for (final type in [
          ModifierType.manaSabotage,
          ModifierType.discount,
          ModifierType.echo,
          ModifierType.cardBlock,
        ]) {
          d.modifiers.add(
            PendingModifier(
              id: 'v223-${type.name}',
              type: type,
              owner: side.opposite,
              responseSide: side,
              targetCard: CardId.pawnDeviation,
              ownTurn: type == ModifierType.cardBlock ? 3 : 2,
            ),
          );
        }
      });
      final cast = pawnCast(state);
      pawnEqual(cast.rules.mana[side], 0, 'floor-one charge');
      pawnEqual(cast.rules.mana[side.opposite], 6, 'echo cap');
      pawnEqual(cast.rules.modifiers.map((m) => m.id).toList(), [
        'v223-cardBlock',
      ], 'future modifier retained');
    });

    add('old mine debuff consumed while fresh entry debuff survives', () {
      final initial = pawnFixture(side: side);
      final state = pawnEdit(initial, (d) {
        d.pieceEffects.addAll([
          pawnPieceEffect(
            initial,
            PieceEffectType.mineDebuff,
            id: 'old-moving',
          ),
          pawnPieceEffect(
            initial,
            PieceEffectType.mineDebuff,
            whiteSquare: 28,
            id: 'old-stationary',
          ),
          pawnPieceEffect(initial, PieceEffectType.chain, id: 'old-chain'),
          pawnPieceEffect(
            initial,
            PieceEffectType.freeze,
            whiteSquare: 28,
            id: 'old-freeze',
          ),
          pawnPieceEffect(
            initial,
            PieceEffectType.shelter,
            id: 'own-shelter',
            owner: side,
            responseSide: side.opposite,
            duration: EffectDuration.card,
          ),
        ]);
        d.boardEffects.addAll([
          pawnBoardEffect(initial, BoardEffectType.mine, [
            34,
          ], id: 'enemy-mine'),
          pawnBoardEffect(
            initial,
            BoardEffectType.mine,
            [36],
            id: 'own-mine',
            owner: side,
          ),
          pawnBoardEffect(initial, BoardEffectType.lockedSquare, [
            36,
          ], id: 'expired-lock'),
          pawnBoardEffect(
            initial,
            BoardEffectType.fog,
            [34],
            id: 'expired-fog',
            duration: EffectDuration.card,
          ),
        ]);
      });
      final cast = pawnCast(state);
      pawnRequire(
        !cast.rules.boardEffects.any((e) => e.id == 'expired-fog'),
        'fog expires when card window closes',
      );
      pawnRequire(
        cast.rules.pieceEffects.any((e) => e.id == 'old-chain'),
        'move effects cannot expire at cast',
      );
      final moved = pawnMove(cast, 'd4c5');
      final ids = moved.rules.pieceEffects.map((e) => e.id).toSet();
      pawnRequire(
        !ids.contains('old-moving') &&
            !ids.contains('old-chain') &&
            !ids.contains('old-freeze'),
        'completed move consumes old effects',
      );
      pawnRequire(
        ids.contains('old-stationary') && ids.contains('own-shelter'),
        'unmoved piece debuff and opponent-window shelter remain',
      );
      final fresh = moved.rules.pieceEffects.singleWhere(
        (e) => e.type == PieceEffectType.mineDebuff && e.id != 'old-stationary',
      );
      pawnEqual(
        fresh.pieceId,
        state.rules.pieceIds[pawnSquare(side, 27)],
        'fresh mine follows mover identity',
      );
      pawnEqual(fresh.duration.name, 'pieceMove', 'fresh duration');
      pawnEqual(moved.rules.boardEffects.map((e) => e.id).toList(), [
        'own-mine',
      ], 'entry mine consumed; unused own mine preserved');
    });

    add('failed destination does not consume board or piece durations', () {
      final initial = pawnFixture(side: side);
      final state = pawnEdit(initial, (d) {
        d.boardEffects.add(
          pawnBoardEffect(initial, BoardEffectType.lockedSquare, [34]),
        );
        d.pieceEffects.add(pawnPieceEffect(initial, PieceEffectType.chain));
      });
      final cast = pawnCast(state);
      pawnRejected(cast, ChessMoveAction(pawnUci(side, 'd4c5')));
      pawnRequire(
        cast.rules.special != null,
        'rejection retains authorization',
      );
      pawnEqual(cast.rules.pieceEffects.length, 1, 'rejection retains chain');
      pawnEqual(cast.rules.boardEffects.length, 1, 'rejection retains lock');
      final moved = pawnMove(cast, 'd4e5');
      pawnRequire(
        moved.rules.pieceEffects.isEmpty && moved.rules.boardEffects.isEmpty,
        'successful move expires both',
      );
    });

    add(
      'watch payoff uses final square while hunt does not invent capture',
      () {
        final initial = pawnFixture(side: side);
        final state = pawnEdit(
          initial,
          (d) => d.vows.addAll([
            VowState(
              id: 'enemy-watch',
              type: VowType.watch,
              owner: side.opposite,
              pieceId: null,
              square: pawnSquare(side, 34),
              remainingMoves: 1,
            ),
            VowState(
              id: 'own-hunt',
              type: VowType.hunt,
              owner: side,
              pieceId: initial.rules.pieceIds[pawnSquare(side, 48)],
              square: null,
              remainingMoves: 2,
            ),
          ]),
        );
        final cast = pawnCast(state);
        pawnEqual(cast.rules.mana[side.opposite], 1, 'no watch reward at cast');
        final moved = pawnMove(cast, 'd4c5');
        pawnEqual(moved.rules.mana[side], 4, 'quiet move has no hunt reward');
        pawnEqual(
          moved.rules.mana[side.opposite],
          4,
          'watch plus next-turn regeneration',
        );
        pawnEqual(moved.rules.vows.length, 1, 'watch is consumed');
        pawnEqual(moved.rules.vows.single.remainingMoves, 1, 'hunt ticks once');
      },
    );

    add(
      'pending prophecy prohibits cast and resolve cannot replace bound move',
      () {
        final state = pawnFixture(side: side);
        final pending = DeckManager.apply(
          state,
          const PlayCardAction(CardId.prophecy),
        );
        pawnRejected(
          pending,
          PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
        );
        pawnRequire(
          pending.view(side.opposite).knowledge.pendingCards.isEmpty,
          'opponent must not see inspected cards',
        );
        final resolved = DeckManager.apply(
          pending,
          BattleRulesCore.legalActions(
            pending.view(side),
          ).whereType<ResolveAction>().first,
        );
        pawnRejected(
          resolved,
          PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
        );
        pawnRejected(pawnCast(state), ResolveAction([]));
      },
    );

    add(
      'opponent hidden partitions cannot alter cast legality or own projection',
      () {
        final state = pawnFixture(side: side);
        final enemy = side.opposite;
        final hand = [...state.hidden.hands[enemy]!];
        final deck = [...state.hidden.decks[enemy]!];
        final saved = hand[1];
        hand[1] = deck[0];
        deck[0] = saved;
        final alternative = AuthoritativeBattleState(
          state.rules,
          AuthoritativeHiddenState(
            hands: {...state.hidden.hands, enemy: hand},
            decks: {...state.hidden.decks, enemy: deck},
            knowledge: state.hidden.knowledge,
          ),
        );
        pawnEqual(
          state.view(side).toJson(),
          alternative.view(side).toJson(),
          'same redacted input',
        );
        pawnEqual(
          BattleRulesCore.legalActions(
            state.view(side),
          ).map((a) => a.key).toList(),
          BattleRulesCore.legalActions(
            alternative.view(side),
          ).map((a) => a.key).toList(),
          'same redacted actions',
        );
        final first = pawnMove(pawnCast(state), 'd4c5');
        final second = pawnMove(pawnCast(alternative), 'd4c5');
        pawnEqual(
          first.view(side).toJson(),
          second.view(side).toJson(),
          'same redacted result',
        );
        pawnEqual(
          second.hidden.hands[enemy]!.map((c) => c.wire).toList(),
          hand.map((c) => c.wire).toList(),
          'enemy hand unchanged',
        );
        pawnEqual(
          second.hidden.decks[enemy]!.map((c) => c.wire).toList(),
          deck.map((c) => c.wire).toList(),
          'enemy deck unchanged',
        );
      },
    );

    add('first turn and non-active viewer cannot play movement cards', () {
      final state = pawnFixture(side: side);
      final firstCard = pawnEdit(state, (d) => d.ownTurns[side] = 1);
      pawnRejected(
        firstCard,
        PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
      );
      final firstChess = pawnEdit(
        firstCard,
        (d) => d.phase = BattlePhase.chess,
      );
      pawnRejected(
        firstChess,
        PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
      );
      pawnEqual(
        BattleRulesCore.legalActions(state.view(side.opposite)).length,
        0,
        'off-turn actions',
      );
    });

    add('discard spends no mana and creates no authorization', () {
      final state = pawnFixture(side: side);
      final discarded = DeckManager.apply(
        state,
        const DiscardAction(CardId.pawnDeviation),
      );
      pawnEqual(discarded.rules.mana[side], 6, 'discard mana');
      pawnEqual(discarded.rules.fen, state.rules.fen, 'discard board');
      pawnEqual(discarded.rules.ply, 0, 'discard ply');
      pawnEqual(discarded.rules.phase.name, 'chess', 'discard closes window');
      pawnRequire(
        discarded.rules.special == null && discarded.rules.pending == null,
        'discard creates no permission',
      );
      pawnRequire(
        discarded.rules.discarded[side]!.contains(CardId.pawnDeviation),
        'discard is public',
      );
      pawnRequire(
        !discarded.rules.used[side]!.contains(CardId.pawnDeviation),
        'discard is not an accepted cast',
      );
      pawnRejected(
        discarded,
        PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
      );
    });

    add('full hand still draws exactly one replacement after special move', () {
      final initial = pawnFixture(side: side);
      final hands = {
        for (final c in PieceColor.values) c: [...initial.hidden.hands[c]!],
      };
      final decks = {
        for (final c in PieceColor.values) c: [...initial.hidden.decks[c]!],
      };
      hands[side]!.add(decks[side]!.removeAt(0));
      final draft =
          RuleDraft(initial.rules)
            ..handCounts[side] = 4
            ..deckCounts[side] = 6
            ..drawCounts[side] = 4;
      final state = AuthoritativeBattleState(
        draft.freeze(),
        AuthoritativeHiddenState(
          hands: hands,
          decks: decks,
          knowledge: initial.hidden.knowledge,
        ),
      );
      final moved = pawnMove(pawnCast(state), 'd4c5');
      pawnEqual(moved.rules.handCounts[side], 4, 'full hand replacement');
      pawnEqual(moved.rules.deckCounts[side], 5, 'one replacement from deck');
      pawnEqual(moved.rules.drawCounts[side], 5, 'one replacement acquisition');
    });

    add('exhausted deck does not invent a replacement card', () {
      final initial = pawnFixture(side: side);
      final draft =
          RuleDraft(initial.rules)
            ..deckCounts[side] = 0
            ..drawCounts[side] = 10;
      draft.discarded[side]!.addAll(initial.hidden.decks[side]!);
      draft.discarded[side]!.sort((a, b) => a.wire.compareTo(b.wire));
      final state = AuthoritativeBattleState(
        draft.freeze(),
        AuthoritativeHiddenState(
          hands: initial.hidden.hands,
          decks: {...initial.hidden.decks, side: []},
          knowledge: initial.hidden.knowledge,
        ),
      );
      final moved = pawnMove(pawnCast(state), 'd4c5');
      pawnEqual(moved.rules.handCounts[side], 2, 'no invented hand card');
      pawnEqual(moved.rules.deckCounts[side], 0, 'no negative deck count');
      pawnEqual(moved.rules.drawCounts[side], 10, 'no invented acquisition');
    });

    add('pawn deviation preserves real king and rook castling rights', () {
      final board = Board.fromFen(
        side.isWhite
            ? 'r3k2r/8/8/8/3P4/8/8/R3K2R w KQkq - 37 10'
            : 'r3k2r/8/8/4p3/8/8/8/R3K2R b KQkq - 37 10',
      );
      final state = pawnFixture(side: side, board: board);
      final moved = pawnMove(pawnCast(state), 'd4c5');
      pawnEqual(
        moved.rules.board.castling,
        board.castling,
        'unmoved home kings and rooks retain rights',
      );
    });

    add('Fate-acquired deviation waits for the next own card window', () {
      final ordered = [
        CardId.fateExchange,
        CardId.radar,
        CardId.prophecy,
        CardId.pawnDeviation,
        ...CardId.values
            .where(
              (c) =>
                  !const [
                    CardId.fateExchange,
                    CardId.radar,
                    CardId.prophecy,
                    CardId.pawnDeviation,
                  ].contains(c),
            )
            .take(6),
      ];
      final state = pawnFixture(side: side, deck: ordered);
      final pending = DeckManager.apply(
        state,
        const PlayCardAction(CardId.fateExchange, sacrifice: CardId.radar),
      );
      final choice = BattleRulesCore.legalActions(pending.view(side))
          .whereType<ResolveAction>()
          .firstWhere((a) => a.selected == CardId.pawnDeviation);
      final acquired = DeckManager.apply(pending, choice);
      pawnRequire(
        acquired.view(side).ownHand.contains(CardId.pawnDeviation),
        'Fate selection must acquire card',
      );
      pawnRejected(
        acquired,
        PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
      );
      final ownMoved = DeckManager.apply(
        acquired,
        ChessMoveAction(pawnUci(side, 'e1d1')),
      );
      final enemyPassed = DeckManager.apply(ownMoved, const PassAction());
      final nextTurn = DeckManager.apply(
        enemyPassed,
        ChessMoveAction(pawnUci(side, 'e8d8')),
      );
      pawnRequire(
        nextTurn.rules.board.turn == side &&
            nextTurn.rules.phase == BattlePhase.card,
        'next own card window must be reached',
      );
      pawnEqual(
        pawnCast(nextTurn).rules.special?.card.wire,
        'pawn_deviation',
        'acquired card is playable only now',
      );
    });

    add('existing en passant right expires without capture', () {
      final state = pawnFixture(
        side: side,
        fen: '7k/8/8/3pP3/8/8/8/4K3 w - d6 41 10',
      );
      final cast = pawnCast(state, whiteFrom: 36);
      pawnEqual(
        cast.rules.board.enPassant,
        pawnSquare(side, 43),
        'casting is not a chess move',
      );
      final moved = pawnMove(cast, 'e5d6');
      pawnRequire(moved.rules.board.enPassant == null, 'right expires on move');
      pawnEqual(
        moved.rules.pieceIds[pawnSquare(side, 35)],
        state.rules.pieceIds[pawnSquare(side, 35)],
        'adjacent enemy identity stays',
      );
      pawnEqual(
        moved.rules.board.squares.where((p) => p != null).length,
        4,
        'en passant square does not imply capture',
      );
    });

    add('terminal snapshot refuses card cast without spending anything', () {
      final state = pawnEdit(pawnFixture(side: side), (d) {
        d.phase = BattlePhase.terminal;
        d.terminal = const TerminalState('timeout');
      });
      pawnRejected(
        state,
        PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
      );
    });

    add(
      'card stage charges time but only completed chess move gets increment',
      () {
        var now = 0;
        final clock = BattleV1LocalClock(now: () => now);
        if (!side.isWhite) clock.advance(side, chessMove: false);
        final state = pawnFixture(side: side);
        now = 700;
        final cast = pawnCast(state);
        clock.advance(cast.rules.board.turn, chessMove: false);
        pawnEqual(clock.active.name, side.name, 'cast retains clock owner');
        pawnEqual(clock.remaining(side), 299300, 'no cast increment');
        now = 1800;
        final moved = pawnMove(cast, 'd4c5');
        clock.advance(moved.rules.board.turn, chessMove: true);
        pawnEqual(clock.active.name, side.opposite.name, 'move switches clock');
        pawnEqual(clock.remaining(side), 300200, 'one chess increment');
        now = 2300;
        pawnEqual(clock.remaining(side), 300200, 'old side clock stopped');
        pawnEqual(
          clock.remaining(side.opposite),
          299500,
          'enemy clock running',
        );
      },
    );

    add(
      'timeout while bound forbids moving without inventing card rollback',
      () {
        final cast = pawnCast(pawnFixture(side: side));
        final timeout = pawnEdit(cast, (d) {
          d.phase = BattlePhase.terminal;
          d.terminal = TerminalState('timeout', winner: side.opposite);
        });
        pawnRejected(timeout, ChessMoveAction(pawnUci(side, 'd4c5')));
        pawnEqual(timeout.rules.mana[side], 4, 'accepted cost is not refunded');
        pawnEqual(
          timeout.rules.handCounts[side],
          2,
          'accepted card stays consumed',
        );
        pawnEqual(timeout.rules.ply, 0, 'timeout completes no chess move');
        pawnEqual(timeout.rules.drawCounts[side], 3, 'timeout draws no card');
      },
    );

    add(
      'quiet deviation stalemate has no winner, special-mate flag or draw',
      () {
        final state = pawnFixture(
          side: side,
          fen: 'k7/2Q5/2K5/8/3P4/8/8/8 w - - 37 10',
        );
        final moved = pawnMove(pawnCast(state), 'd4c5');
        pawnEqual(moved.rules.terminal?.reason, 'stalemate', 'quiet stalemate');
        pawnRequire(
          moved.rules.terminal?.winner == null,
          'stalemate has no winner',
        );
        pawnEqual(
          moved.rules.terminal?.mateBySpecialMove,
          false,
          'stalemate is not special checkmate',
        );
        pawnEqual(
          moved.rules.terminal?.stalemateByRestriction,
          false,
          'ordinary geometric stalemate',
        );
        pawnEqual(moved.rules.phase.name, 'terminal', 'terminal phase');
        pawnEqual(
          moved.rules.handCounts[side],
          2,
          'terminal has no replacement',
        );
        pawnEqual(moved.rules.deckCounts[side], 7, 'terminal retains deck');
        pawnRequire(
          moved.rules.special == null,
          'terminal consumes authorization',
        );
      },
    );

    add('quiet deviation checkmate without ep alias is marked special', () {
      final state = pawnFixture(
        side: side,
        fen: 'B6R/2k5/4B3/2KpP3/3r4/8/8/8 w - - 0 10',
      );
      final moved = pawnMove(pawnCast(state, whiteFrom: 36), 'e5d6');
      pawnEqual(moved.rules.terminal?.reason, 'checkmate', 'quiet checkmate');
      pawnEqual(
        moved.rules.terminal?.mateBySpecialMove,
        true,
        'non-aliased special mate control',
      );
      pawnEqual(
        moved.rules.terminal?.mateByRestriction,
        false,
        'no restriction caused this mate',
      );
    });

    for (final effect in [PieceEffectType.chain, PieceEffectType.mineDebuff]) {
      add(
        'V223-PD-01 ${effect.name} forbids ep capture, not quiet alias mate',
        () {
          final initial = pawnFixture(side: side, fen: pawnDeviationMateFen);
          final state = pawnEdit(
            initial,
            (d) => d.pieceEffects.add(
              pawnPieceEffect(initial, effect, whiteSquare: 36),
            ),
          );
          pawnRequire(
            !BattleRulesCore.legalMoves(
              state.rules,
              side,
            ).any((m) => m.uci == pawnUci(side, 'e5d6')),
            'restricted ordinary en passant must be unavailable',
          );
          final moved = pawnMove(pawnCast(state, whiteFrom: 36), 'e5d6');
          pawnEqual(
            moved.rules.terminal?.reason,
            'checkmate',
            'quiet alias still mates',
          );
          pawnEqual(
            moved.rules.terminal?.mateBySpecialMove,
            true,
            'V223-PD-01: a forbidden capture alias cannot mark this ordinary',
          );
        },
      );
    }

    add('V223-PD-01 ep UCI alias cannot hide special-move checkmate', () {
      final state = pawnFixture(side: side, fen: pawnDeviationMateFen);
      final ep = MoveGen.legal(
        state.rules.board,
      ).singleWhere((m) => m.uci == pawnUci(side, 'e5d6'));
      pawnRequire(ep.isEnPassant, 'orthodox alias must be an ep capture');
      final normal = state.rules.board.apply(ep);
      pawnRequire(
        MoveGen.legal(normal).any((m) => m.uci == pawnUci(side, 'd4d6')),
        'ordinary ep must allow rook defense',
      );
      final cast = pawnCast(state, whiteFrom: 36);
      final special = BattleRulesCore.legalMoves(
        cast.rules,
        side,
        authorization: cast.rules.special,
      ).singleWhere((m) => m.uci == ep.uci);
      pawnRequire(!special.isEnPassant, 'card alias must not capture');
      final moved = pawnMove(cast, 'e5d6');
      pawnEqual(
        moved.rules.board.squares[pawnSquare(side, 35)]?.type.name,
        'pawn',
        'd5 blocker survives',
      );
      pawnEqual(moved.rules.terminal?.reason, 'checkmate', 'quiet alias mates');
      pawnEqual(moved.rules.terminal?.winner?.name, side.name, 'mate winner');
      pawnEqual(
        moved.rules.terminal?.mateBySpecialMove,
        true,
        'V223-PD-01: compare move semantics, not only UCI',
      );
      pawnEqual(moved.rules.handCounts[side], 2, 'terminal move must not draw');
    });
  }
  return cases;
}
