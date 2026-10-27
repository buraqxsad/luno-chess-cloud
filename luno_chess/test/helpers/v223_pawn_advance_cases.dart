import 'dart:convert';

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

const pawnAdvanceDeck = <CardId>[
  CardId.pawnAdvance,
  CardId.prophecy,
  CardId.purify,
  CardId.radar,
  CardId.chain,
  CardId.slow,
  CardId.shelter,
  CardId.lockedSquare,
  CardId.freeze,
  CardId.mine,
];

const pawnAdvanceBaseFens = <PieceColor, String>{
  PieceColor.white: '6k1/7p/8/8/2P5/8/P7/4K3 w - - 83 19',
  PieceColor.black: '4k3/p7/8/2p5/8/8/7P/6K1 b - - 83 19',
};
const pawnAdvanceMateFens = <PieceColor, String>{
  PieceColor.white: '1kN4R/8/1K6/2PB4/8/8/8/8 w - - 7 19',
  PieceColor.black: '8/8/8/8/2pb4/1k6/8/1Kn4r b - - 7 19',
};
const pawnAdvanceStalemateFens = <PieceColor, String>{
  PieceColor.white: 'k7/2K5/8/8/1P6/8/8/8 w - - 44 19',
  PieceColor.black: '8/8/8/1p6/8/8/2k5/K7 b - - 44 19',
};

int advanceSquare(String square) =>
    square.codeUnitAt(0) - 97 + 8 * (int.parse(square[1]) - 1);

String advanceFrom(PieceColor side) => side.isWhite ? 'c4' : 'c5';
String advanceUci(PieceColor side) => side.isWhite ? 'c4c6' : 'c5c3';

void advanceRequire(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void advanceEqual(Object? actual, Object? expected, String label) {
  final actualJson = jsonEncode(canonicalObject(actual));
  final expectedJson = jsonEncode(canonicalObject(expected));
  advanceRequire(
    actualJson == expectedJson,
    '$label: expected $expectedJson, actual $actualJson',
  );
}

AuthoritativeBattleState advanceFixture({
  PieceColor side = PieceColor.white,
  String? fen,
  int mana = 6,
}) {
  final initial = DeckManager.newBattle(
    board: Board.fromFen(fen ?? pawnAdvanceBaseFens[side]!),
    white: pawnAdvanceDeck,
    black: pawnAdvanceDeck,
  );
  advanceRequire(
    initial.rules.terminal == null,
    'fixture is initially terminal',
  );
  advanceRequire(initial.rules.board.turn == side, 'fixture active color');
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
        ..ownTurns[side] = 3
        ..ownTurns[side.opposite] = 3
        ..mana[side] = mana
        ..mana[side.opposite] = 3
        ..effectSequence = 300
        ..ply = 38
        ..repetitions.clear();
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}

AuthoritativeBattleState advanceEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState advanceCast(
  AuthoritativeBattleState state, {
  String? from,
}) => DeckManager.apply(
  state,
  PlayCardAction(
    CardId.pawnAdvance,
    target: advanceSquare(from ?? advanceFrom(state.rules.board.turn)),
  ),
);

List<String> advanceChessActions(AuthoritativeBattleState state) =>
    BattleRulesCore.legalActions(
        state.view(state.rules.board.turn),
      ).whereType<ChessMoveAction>().map((a) => a.uci).toList()
      ..sort();

void advanceRejected(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(canonicalObject(state.toJson()));
  advanceRequire(
    !BattleRulesCore.isLegalAction(state.view(state.rules.board.turn), action),
    'illegal action admitted',
  );
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    advanceEqual(error.message, 'illegal-action', 'rejection reason');
    rejected = true;
  }
  advanceRequire(rejected, 'illegal action applied');
  advanceEqual(
    jsonEncode(canonicalObject(state.toJson())),
    before,
    'rejection preserves authority and hidden state',
  );
}

void advanceInventory(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    advanceEqual(
      state.hidden.hands[side]!.length,
      state.rules.handCounts[side],
      'hand count',
    );
    advanceEqual(
      state.hidden.decks[side]!.length,
      state.rules.deckCounts[side],
      'deck count',
    );
    final inventory =
        [
            ...state.hidden.hands[side]!,
            ...state.hidden.decks[side]!,
            ...state.rules.used[side]!,
            ...state.rules.discarded[side]!,
          ].map((c) => c.wire).toList()
          ..sort();
    final expected = pawnAdvanceDeck.map((c) => c.wire).toList()..sort();
    advanceEqual(inventory, expected, 'exactly ten distinct inventory cards');
    advanceRequire(
      state.rules.mana[side]! >= 0 && state.rules.mana[side]! <= 6,
      'bounded mana',
    );
  }
  advanceEqual(
    AuthoritativeBattleState.fromJson(state.toJson()).toJson(),
    state.toJson(),
    'authority JSON round trip',
  );
}

ActivePieceEffect advancePieceEffect(
  AuthoritativeBattleState state,
  PieceEffectType type, {
  String? square,
  String? id,
}) {
  final side = state.rules.board.turn;
  return ActivePieceEffect(
    id: id ?? 'advance-${type.name}',
    type: type,
    owner: type == PieceEffectType.shelter ? side : side.opposite,
    pieceId: state.rules.pieceIds[advanceSquare(square ?? advanceFrom(side))]!,
    responseSide: type == PieceEffectType.shelter ? side.opposite : side,
    duration:
        type == PieceEffectType.shelter
            ? EffectDuration.card
            : type == PieceEffectType.mineDebuff
            ? EffectDuration.pieceMove
            : EffectDuration.move,
  );
}

BoardEffectInstance advanceBoardEffect(
  AuthoritativeBattleState state,
  BoardEffectType type,
  String square, {
  bool own = false,
  String? id,
}) {
  final side = state.rules.board.turn;
  return BoardEffectInstance(
    id: id ?? 'advance-${type.name}-$square',
    type: type,
    owner: own ? side : side.opposite,
    squares: [advanceSquare(square)],
    responseSide: own ? side.opposite : side,
    duration:
        type == BoardEffectType.mine
            ? EffectDuration.persistent
            : type == BoardEffectType.fog
            ? EffectDuration.card
            : EffectDuration.move,
  );
}

PendingModifier advanceModifier(
  AuthoritativeBattleState state,
  ModifierType type, {
  CardId? card = CardId.pawnAdvance,
  int turnOffset = 0,
  bool wrongSide = false,
}) {
  final side = state.rules.board.turn;
  return PendingModifier(
    id: 'advance-${type.name}-$turnOffset-$wrongSide',
    type: type,
    owner: side.opposite,
    responseSide: wrongSide ? side.opposite : side,
    targetCard: card,
    ownTurn: state.rules.ownTurns[side]! + turnOffset,
  );
}

class PawnAdvanceCase {
  final String name;
  final void Function() run;
  const PawnAdvanceCase(this.name, this.run);
}

class _Geometry {
  final String name, whiteFen, blackFen, whiteFrom, blackFrom;
  final String? whiteMove, blackMove;
  const _Geometry(
    this.name,
    this.whiteFen,
    this.blackFen,
    this.whiteFrom,
    this.blackFrom,
    this.whiteMove,
    this.blackMove,
  );
}

// Every black FEN and expected UCI is literal, not produced by a mirror or engine.
const _geometry = <_Geometry>[
  _Geometry(
    'non-starting rank',
    '6k1/7p/8/8/2P5/8/P7/4K3 w - - 83 19',
    '4k3/p7/8/2p5/8/8/7P/6K1 b - - 83 19',
    'c4',
    'c5',
    'c4c6',
    'c5c3',
  ),
  _Geometry(
    'a-file edge',
    '6k1/7p/8/8/P7/8/8/4K3 w - - 1 19',
    '4k3/8/8/p7/8/8/7P/6K1 b - - 1 19',
    'a4',
    'a5',
    'a4a6',
    'a5a3',
  ),
  _Geometry(
    'h-file edge',
    '6k1/p7/8/8/7P/8/8/4K3 w - - 2 19',
    '4k3/8/8/7p/8/8/P7/6K1 b - - 2 19',
    'h4',
    'h5',
    'h4h6',
    'h5h3',
  ),
  _Geometry(
    'orthodox starting double alias',
    '6k1/7p/8/8/8/8/2P5/4K3 w - - 3 19',
    '4k3/2p5/8/8/8/8/7P/6K1 b - - 3 19',
    'c2',
    'c7',
    'c2c4',
    'c7c5',
  ),
  _Geometry(
    'last non-promotion landing',
    '6k1/7p/8/2P5/8/8/8/4K3 w - - 4 19',
    '4k3/8/8/8/2p5/8/7P/6K1 b - - 4 19',
    'c5',
    'c4',
    'c5c7',
    'c4c2',
  ),
  _Geometry(
    'final-rank double forbidden',
    '6k1/7p/2P5/8/8/8/8/4K3 w - - 5 19',
    '4k3/8/8/8/8/2p5/7P/6K1 b - - 5 19',
    'c6',
    'c3',
    null,
    null,
  ),
  _Geometry(
    'off-board double forbidden',
    '6k1/2P4p/8/8/8/8/8/4K3 w - - 6 19',
    '4k3/8/8/8/8/8/2p4P/6K1 b - - 6 19',
    'c7',
    'c2',
    null,
    null,
  ),
  _Geometry(
    'friendly intermediate blocker',
    '6k1/7p/8/2N5/2P5/8/8/4K3 w - - 7 19',
    '4k3/8/8/2p5/2n5/8/7P/6K1 b - - 7 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'enemy intermediate blocker',
    '6k1/7p/8/2n5/2P5/8/8/4K3 w - - 8 19',
    '4k3/8/8/2p5/2N5/8/7P/6K1 b - - 8 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'friendly landing blocker',
    '6k1/7p/2N5/8/2P5/8/8/4K3 w - - 9 19',
    '4k3/8/8/2p5/8/2n5/7P/6K1 b - - 9 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'enemy landing cannot be captured',
    '6k1/7p/2n5/8/2P5/8/8/4K3 w - - 10 19',
    '4k3/8/8/2p5/8/2N5/7P/6K1 b - - 10 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'enemy king cannot be captured',
    '8/8/2k5/8/2P5/8/8/4K3 w - - 11 19',
    '4k3/8/8/2p5/8/2K5/8/8 b - - 11 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'rook is not an own pawn',
    '6k1/7p/8/8/2R5/8/8/4K3 w - - 12 19',
    '4k3/8/8/2r5/8/8/7P/6K1 b - - 12 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'enemy pawn is not an own pawn',
    '6k1/7p/8/8/2p5/8/8/4K3 w - - 13 19',
    '4k3/8/8/2P5/8/8/7P/6K1 b - - 13 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'empty origin',
    '6k1/7p/8/8/8/8/P7/4K3 w - - 14 19',
    '4k3/p7/8/8/8/8/7P/6K1 b - - 14 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'file pin remains blocked after advance',
    '2r4k/8/8/8/2P5/8/8/2K5 w - - 15 19',
    '2k5/8/8/2p5/8/8/8/2R4K b - - 15 19',
    'c4',
    'c5',
    'c4c6',
    'c5c3',
  ),
  _Geometry(
    'diagonal absolute pin',
    '7k/5b2/8/8/2P5/1K6/8/8 w - - 16 19',
    '8/8/1k6/2p5/8/8/5B2/7K b - - 16 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'rank absolute pin',
    '7k/8/8/8/K1P4r/8/8/8 w - - 17 19',
    '8/8/8/k1p4R/8/8/8/7K b - - 17 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'double interposition answers check',
    '7k/8/8/8/K6r/8/2P5/8 w - - 18 19',
    '8/2p5/8/k6R/8/8/8/7K b - - 18 19',
    'c2',
    'c7',
    'c2c4',
    'c7c5',
  ),
  _Geometry(
    'one interposition cannot answer double check',
    '7k/3b4/8/8/K6r/8/2P5/8 w - - 19 19',
    '8/2p5/8/k6R/8/8/3B4/7K b - - 19 19',
    'c2',
    'c7',
    null,
    null,
  ),
  _Geometry(
    'unanswered knight check',
    '7k/8/8/8/2P5/5n2/8/4K3 w - - 20 19',
    '4k3/8/5N2/2p5/8/8/8/7K b - - 20 19',
    'c4',
    'c5',
    null,
    null,
  ),
  _Geometry(
    'attacked intermediate is allowed for a pawn',
    '7k/8/8/7r/2P5/8/8/4K3 w - - 21 19',
    '4k3/8/8/2p5/7R/8/8/7K b - - 21 19',
    'c4',
    'c5',
    'c4c6',
    'c5c3',
  ),
  _Geometry(
    'attacked landing is allowed for a pawn',
    '7k/8/8/8/2P5/5b2/8/4K3 w - - 22 19',
    '4k3/8/5B2/2p5/8/8/8/7K b - - 22 19',
    'c4',
    'c5',
    'c4c6',
    'c5c3',
  ),
];

List<PawnAdvanceCase> pawnAdvanceCases() {
  final cases = <PawnAdvanceCase>[
    PawnAdvanceCase('literal card definition', () {
      final definition = cardDefinitions[CardId.pawnAdvance]!;
      advanceEqual(definition.cost, 2, 'base cost');
      advanceEqual(definition.category.name, 'movement', 'category');
      advanceEqual(definition.target.name, 'ownPawn', 'target');
    }),
  ];
  for (final side in PieceColor.values) {
    void add(String name, void Function() run) =>
        cases.add(PawnAdvanceCase('${side.name}: $name', run));

    for (final row in _geometry) {
      add('geometry ${row.name}', () {
        final state = advanceFixture(
          side: side,
          fen: side.isWhite ? row.whiteFen : row.blackFen,
        );
        final from = advanceSquare(
          side.isWhite ? row.whiteFrom : row.blackFrom,
        );
        final expectedMove = side.isWhite ? row.whiteMove : row.blackMove;
        final expected = expectedMove == null ? <String>[] : [expectedMove];
        final moves = BattleRulesCore.specialMoves(
          state.rules,
          CardId.pawnAdvance,
          from,
          side,
        );
        advanceEqual(moves.map((m) => m.uci).toList(), expected, row.name);
        advanceRequire(
          moves.every(
            (m) => !m.isEnPassant && !m.isCastle && m.promotion == null,
          ),
          'quiet non-promotion move semantics',
        );
        final action = PlayCardAction(CardId.pawnAdvance, target: from);
        advanceEqual(
          BattleRulesCore.cardTargets(
            state.view(side),
            CardId.pawnAdvance,
          ).contains(from),
          expectedMove != null,
          'target availability matches literal outcome',
        );
        if (expectedMove == null) {
          advanceRejected(state, action);
        } else {
          final cast = DeckManager.apply(state, action);
          advanceEqual(
            advanceChessActions(cast),
            expected,
            'accepted card has a nonempty bound continuation',
          );
          final moved = DeckManager.apply(cast, ChessMoveAction(expectedMove));
          advanceRequire(moved.rules.special == null, 'authorization consumed');
          advanceInventory(moved);
        }
      });
    }

    add('card then chess exact state accounting and no alternate move', () {
      final before = advanceFixture(side: side);
      final input = jsonEncode(canonicalObject(before.toJson()));
      final from = advanceSquare(advanceFrom(side));
      final to = advanceSquare(side.isWhite ? 'c6' : 'c3');
      final identity = before.rules.pieceIds[from];
      final cast = advanceCast(before);
      advanceEqual(cast.rules.phase.name, 'chess', 'phase after card');
      advanceEqual(
        cast.rules.fen,
        pawnAdvanceBaseFens[side],
        'card is not a move',
      );
      advanceEqual(cast.rules.ply, 38, 'card does not advance ply');
      advanceEqual(cast.rules.mana[side], 4, 'one cost payment');
      advanceEqual(
        cast.rules.mana[side.opposite],
        3,
        'no enemy regeneration yet',
      );
      advanceEqual(cast.rules.handCounts[side], 2, 'one hand removal');
      advanceEqual(cast.rules.deckCounts[side], 7, 'no card-stage draw');
      advanceEqual(cast.rules.drawCounts[side], 3, 'no card-stage draw count');
      advanceEqual(cast.rules.used[side]!.map((c) => c.wire).toList(), [
        'pawn_advance',
      ], 'one used entry');
      advanceEqual(cast.rules.special!.toJson(), {
        'card': 'pawn_advance',
        'from': from,
        'moves': [advanceUci(side)],
      }, 'literal authorization');
      advanceRequire(cast.rules.pending == null, 'movement creates no choice');
      advanceEqual(
        BattleRulesCore.legalActions(
          cast.view(side),
        ).map((a) => a.key).toList(),
        ['move:${advanceUci(side)}'],
        'only selected pawn double is legal',
      );
      for (final forbidden in <BattleAction>[
        const PassAction(),
        const DiscardAction(CardId.prophecy),
        const PlayCardAction(CardId.prophecy),
        PlayCardAction(CardId.pawnAdvance, target: from),
        ChessMoveAction(side.isWhite ? 'c4c5' : 'c5c4'),
        ChessMoveAction(side.isWhite ? 'e1f1' : 'e8f8'),
      ]) {
        advanceRejected(cast, forbidden);
      }
      final moved = DeckManager.apply(cast, ChessMoveAction(advanceUci(side)));
      advanceEqual(
        moved.rules.fen,
        side.isWhite
            ? '6k1/7p/2P5/8/8/8/P7/4K3 b - - 0 19'
            : '4k3/p7/8/8/8/2p5/7P/6K1 w - - 0 20',
        'literal resulting FEN',
      );
      advanceEqual(moved.rules.ply, 39, 'one chess ply');
      advanceEqual(moved.rules.phase.name, 'card', 'enemy card window');
      advanceEqual(moved.rules.ownTurns[side], 3, 'no extra own turn');
      advanceEqual(moved.rules.ownTurns[side.opposite], 4, 'one enemy turn');
      advanceEqual(moved.rules.mana[side], 4, 'no extra card charge');
      advanceEqual(moved.rules.mana[side.opposite], 4, 'one regeneration');
      advanceEqual(moved.rules.handCounts[side], 3, 'one draw');
      advanceEqual(moved.rules.deckCounts[side], 6, 'one deck removal');
      advanceEqual(moved.rules.drawCounts[side], 4, 'one cumulative draw');
      advanceEqual(moved.hidden.hands[side]!.map((c) => c.wire).toList(), [
        'prophecy',
        'purify',
        'radar',
      ], 'literal post-move hand');
      advanceEqual(moved.rules.pieceIds[from], null, 'source identity vacated');
      advanceEqual(moved.rules.pieceIds[to], identity, 'same pawn identity');
      advanceEqual(moved.rules.movedPawns, [identity], 'one moved-pawn record');
      advanceEqual(moved.rules.effectSequence, 300, 'no fabricated effect');
      advanceEqual(
        jsonEncode(canonicalObject(before.toJson())),
        input,
        'accepted transition preserves input',
      );
      advanceRejected(moved, ChessMoveAction(advanceUci(side)));
      advanceInventory(cast);
      advanceInventory(moved);
    });

    for (var mana = 0; mana <= 6; mana++) {
      add('literal affordability at mana $mana', () {
        final state = advanceFixture(side: side, mana: mana);
        final action = PlayCardAction(
          CardId.pawnAdvance,
          target: advanceSquare(advanceFrom(side)),
        );
        advanceEqual(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.pawnAdvance),
          2,
          'unmodified cost',
        );
        if (mana < 2) {
          advanceRejected(state, action);
          advanceRequire(
            BattleRulesCore.isLegalAction(state.view(side), const PassAction()),
            'unaffordable card does not strand pass',
          );
        } else {
          advanceEqual(
            DeckManager.apply(state, action).rules.mana[side],
            mana - 2,
            'literal remaining mana',
          );
        }
      });
    }

    for (final spec in <({String name, List<ModifierType> types, int cost})>[
      (name: 'sabotage', types: [ModifierType.manaSabotage], cost: 3),
      (name: 'discount floor', types: [ModifierType.discount], cost: 1),
      (
        name: 'sabotage plus discount',
        types: [ModifierType.manaSabotage, ModifierType.discount],
        cost: 1,
      ),
    ]) {
      add('current ${spec.name} payment and expiry', () {
        var state = advanceFixture(side: side, mana: spec.cost);
        state = advanceEdit(
          state,
          (d) => d.modifiers.addAll([
            for (final type in spec.types) advanceModifier(state, type),
          ]),
        );
        advanceEqual(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.pawnAdvance),
          spec.cost,
          'independent modifier cost',
        );
        final cast = advanceCast(state);
        advanceEqual(cast.rules.mana[side], 0, 'exact modified debit');
        advanceEqual(cast.rules.modifiers.length, 0, 'card-window expiry');
        advanceEqual(advanceChessActions(cast), [
          advanceUci(side),
        ], 'cost expiry preserves continuation');
      });
    }

    for (final type in [ModifierType.manaSabotage, ModifierType.cardBlock]) {
      for (final mode in ['expired', 'future', 'other side', 'other card']) {
        add('${type.name} $mode does not block or tax', () {
          var state = advanceFixture(side: side, mana: 2);
          state = advanceEdit(
            state,
            (d) => d.modifiers.add(
              advanceModifier(
                state,
                type,
                turnOffset:
                    mode == 'expired'
                        ? -1
                        : mode == 'future'
                        ? 1
                        : 0,
                wrongSide: mode == 'other side',
                card:
                    mode == 'other card' ? CardId.prophecy : CardId.pawnAdvance,
              ),
            ),
          );
          advanceEqual(
            BattleRulesCore.effectiveCost(
              state.rules,
              side,
              CardId.pawnAdvance,
            ),
            2,
            'non-applicable cost',
          );
          final cast = advanceCast(state);
          advanceEqual(cast.rules.mana[side], 0, 'base debit');
          advanceEqual(
            cast.rules.modifiers.length,
            mode == 'future' || mode == 'other side' ? 1 : 0,
            'only closing-side elapsed modifiers expire',
          );
        });
      }
    }

    add('current card block rejects cast but preserves discard and chess', () {
      var state = advanceFixture(side: side);
      state = advanceEdit(
        state,
        (d) => d.modifiers.add(advanceModifier(state, ModifierType.cardBlock)),
      );
      advanceRejected(
        state,
        PlayCardAction(
          CardId.pawnAdvance,
          target: advanceSquare(advanceFrom(side)),
        ),
      );
      final discarded = DeckManager.apply(
        state,
        const DiscardAction(CardId.pawnAdvance),
      );
      advanceEqual(discarded.rules.mana[side], 6, 'discard has no charge');
      advanceEqual(
        discarded.rules.discarded[side]!.map((c) => c.wire).toList(),
        ['pawn_advance'],
        'discard consumes card once',
      );
      advanceRequire(
        advanceChessActions(discarded).contains(side.isWhite ? 'c4c5' : 'c5c4'),
        'ordinary continuation remains',
      );
      advanceEqual(discarded.rules.modifiers.length, 0, 'block expires');
    });

    add('echo pays opponent once at cast, not again at chess', () {
      var state = advanceFixture(side: side);
      state = advanceEdit(
        state,
        (d) => d.modifiers.add(advanceModifier(state, ModifierType.echo)),
      );
      final cast = advanceCast(state);
      advanceEqual(cast.rules.mana[side.opposite], 5, 'one echo credit');
      final moved = DeckManager.apply(cast, ChessMoveAction(advanceUci(side)));
      advanceEqual(
        moved.rules.mana[side.opposite],
        6,
        'one capped regeneration',
      );
      advanceEqual(moved.rules.modifiers.length, 0, 'echo retired');
    });

    for (var mask = 0; mask < 16; mask++) {
      add('piece restriction combination $mask', () {
        var state = advanceFixture(side: side);
        const types = [
          PieceEffectType.freeze,
          PieceEffectType.chain,
          PieceEffectType.mineDebuff,
          PieceEffectType.shelter,
        ];
        state = advanceEdit(
          state,
          (d) => d.pieceEffects.addAll([
            for (var i = 0; i < types.length; i++)
              if ((mask & (1 << i)) != 0) advancePieceEffect(state, types[i]),
          ]),
        );
        final action = PlayCardAction(
          CardId.pawnAdvance,
          target: advanceSquare(advanceFrom(side)),
        );
        if ((mask & 1) != 0) {
          advanceRejected(state, action);
          final passed = DeckManager.apply(state, const PassAction());
          advanceRequire(
            advanceChessActions(
              passed,
            ).contains(side.isWhite ? 'e1f1' : 'e8f8'),
            'freeze leaves king continuation',
          );
        } else {
          final cast = DeckManager.apply(state, action);
          advanceEqual(
            cast.rules.pieceEffects.length,
            state.rules.pieceEffects.length,
            'cast does not consume move debuff',
          );
          final moved = DeckManager.apply(
            cast,
            ChessMoveAction(advanceUci(side)),
          );
          advanceEqual(
            moved.rules.pieceEffects.map((e) => e.type.name).toList(),
            (mask & 8) != 0 ? ['shelter'] : <String>[],
            'quiet double consumes old chain/mine, keeps own shelter',
          );
          advanceInventory(moved);
        }
      });
    }

    for (final type in BoardEffectType.values) {
      for (final landing in [false, true]) {
        for (final own in [false, true]) {
          add('${type.name} ${landing ? 'landing' : 'intermediate'} '
              '${own ? 'own' : 'enemy'} effect', () {
            var state = advanceFixture(side: side);
            final square =
                side.isWhite
                    ? (landing ? 'c6' : 'c5')
                    : (landing ? 'c3' : 'c4');
            state = advanceEdit(
              state,
              (d) => d.boardEffects.add(
                advanceBoardEffect(state, type, square, own: own),
              ),
            );
            final blocked =
                landing &&
                !own &&
                (type == BoardEffectType.lockedSquare ||
                    type == BoardEffectType.boardSeal);
            if (blocked) {
              advanceRejected(
                state,
                PlayCardAction(
                  CardId.pawnAdvance,
                  target: advanceSquare(advanceFrom(side)),
                ),
              );
              advanceRequire(
                BattleRulesCore.isLegalAction(
                  state.view(side),
                  const PassAction(),
                ),
                'blocked landing leaves pass',
              );
            } else {
              final cast = advanceCast(state);
              final moved = DeckManager.apply(
                cast,
                ChessMoveAction(advanceUci(side)),
              );
              final triggered = type == BoardEffectType.mine && landing && !own;
              advanceEqual(
                moved.rules.pieceEffects.map((e) => e.type.name).toList(),
                triggered ? ['mineDebuff'] : <String>[],
                'only enemy landing mine triggers',
              );
              advanceEqual(
                moved.rules.effectSequence,
                triggered ? 301 : 300,
                'exact mine trigger count',
              );
              advanceEqual(
                moved.rules.boardEffects.length,
                own || (type == BoardEffectType.mine && !triggered) ? 1 : 0,
                'entry-only mine and response-side lifetimes',
              );
              if (triggered) {
                advanceEqual(
                  moved.rules.pieceEffects.single.pieceId,
                  moved.rules.pieceIds[advanceSquare(square)],
                  'new debuff follows arriving pawn',
                );
              }
              advanceInventory(moved);
            }
          });
        }
      }
    }

    add('existing EP expires without moving or capturing either EP pawn', () {
      final state = advanceFixture(
        side: side,
        fen:
            side.isWhite
                ? '6k1/7p/8/3pP3/2P5/8/8/4K3 w - d6 0 19'
                : '4k3/8/8/2p5/3Pp3/8/7P/6K1 b - d3 0 19',
      );
      final ep = side.isWhite ? 'e5d6' : 'e4d3';
      advanceRequire(
        BattleRulesCore.legalMoves(
          state.rules,
          side,
        ).any((m) => m.uci == ep && m.isEnPassant),
        'real EP exists before card',
      );
      final cast = advanceCast(state);
      advanceEqual(
        cast.rules.board.enPassant,
        side.isWhite ? 43 : 19,
        'card stage retains original EP field',
      );
      advanceRejected(cast, ChessMoveAction(ep));
      final moved = DeckManager.apply(cast, ChessMoveAction(advanceUci(side)));
      advanceEqual(
        moved.rules.fen,
        side.isWhite
            ? '6k1/7p/2P5/3pP3/8/8/8/4K3 b - - 0 19'
            : '4k3/8/8/8/3Pp3/2p5/7P/6K1 w - - 0 20',
        'old EP removed, bystander pawns preserved',
      );
    });

    for (final alreadyMoved in [false, true]) {
      add(
        'starting double EP ${alreadyMoved ? 'history suppresses' : 'orthodox preserves'}',
        () {
          var state = advanceFixture(
            side: side,
            fen:
                side.isWhite
                    ? '6k1/7p/8/8/3p4/8/2P5/4K3 w - - 91 19'
                    : '4k3/2p5/8/3P4/8/8/7P/6K1 b - - 91 19',
          );
          final from = side.isWhite ? 'c2' : 'c7';
          final move = side.isWhite ? 'c2c4' : 'c7c5';
          if (alreadyMoved) {
            // Synthetic imported history: a pawn ID marked moved on its home rank.
            state = advanceEdit(
              state,
              (d) => d.movedPawns.add(d.pieceIds[advanceSquare(from)]!),
            );
          }
          advanceEqual(
            BattleRulesCore.legalMoves(
              state.rules,
              side,
            ).any((m) => m.uci == move),
            !alreadyMoved,
            'ordinary double history gate',
          );
          final cast = advanceCast(state, from: from);
          final moved = DeckManager.apply(cast, ChessMoveAction(move));
          advanceEqual(
            moved.rules.fen,
            side.isWhite
                ? '6k1/7p/8/8/2Pp4/8/8/4K3 b - ${alreadyMoved ? '-' : 'c3'} 0 19'
                : '4k3/8/8/2pP4/8/8/7P/6K1 w - ${alreadyMoved ? '-' : 'c6'} 0 20',
            'literal EP/fullmove result',
          );
          final reply = DeckManager.apply(moved, const PassAction());
          final capture = side.isWhite ? 'd4c3' : 'd5c6';
          advanceEqual(
            advanceChessActions(reply).contains(capture),
            !alreadyMoved,
            'opponent EP action availability',
          );
          if (!alreadyMoved) {
            final taken = DeckManager.apply(reply, ChessMoveAction(capture));
            advanceEqual(
              taken.rules.pieceIds[advanceSquare(side.isWhite ? 'c4' : 'c5')],
              null,
              'EP removes advanced pawn',
            );
            advanceEqual(
              taken.rules.board.squares
                  .where((p) => p?.type == PieceType.pawn)
                  .length,
              2,
              'one actual EP capture',
            );
            advanceInventory(taken);
          } else {
            advanceRejected(reply, ChessMoveAction(capture));
          }
        },
      );
    }

    add('off-home double never creates a capturable phantom EP', () {
      final state = advanceFixture(
        side: side,
        fen:
            side.isWhite
                ? '6k1/7p/3p4/8/2P5/8/8/4K3 w - - 23 19'
                : '4k3/8/8/2p5/8/3P4/7P/6K1 b - - 23 19',
      );
      final moved = DeckManager.apply(
        advanceCast(state),
        ChessMoveAction(advanceUci(side)),
      );
      advanceEqual(
        moved.rules.fen,
        side.isWhite
            ? '6k1/7p/2Pp4/8/8/8/8/4K3 b - - 0 19'
            : '4k3/8/8/8/8/2pP4/7P/6K1 w - - 0 20',
        'nonstandard double has no EP',
      );
      final reply = DeckManager.apply(moved, const PassAction());
      advanceRejected(reply, ChessMoveAction(side.isWhite ? 'd6c5' : 'd3c4'));
    });

    for (final promotion
        in <String, PieceType>{
          'q': PieceType.queen,
          'r': PieceType.rook,
          'b': PieceType.bishop,
          'n': PieceType.knight,
        }.entries) {
      add('advance then later orthodox ${promotion.key} promotion', () {
        final state = advanceFixture(
          side: side,
          fen:
              side.isWhite
                  ? '6k1/7p/8/2P5/8/8/8/4K3 w - - 12 19'
                  : '4k3/8/8/8/2p5/8/7P/6K1 b - - 12 19',
        );
        final from = side.isWhite ? 'c5' : 'c4';
        final double = side.isWhite ? 'c5c7' : 'c4c2';
        var next = DeckManager.apply(
          advanceCast(state, from: from),
          ChessMoveAction(double),
        );
        next = DeckManager.apply(next, const PassAction());
        next = DeckManager.apply(
          next,
          ChessMoveAction(side.isWhite ? 'h7h6' : 'h2h3'),
        );
        next = DeckManager.apply(next, const PassAction());
        final prefix = side.isWhite ? 'c7c8' : 'c2c1';
        final expected = [
          '${prefix}b',
          '${prefix}n',
          '${prefix}q',
          '${prefix}r',
        ];
        advanceEqual(
          advanceChessActions(next).where((m) => m.startsWith(prefix)).toList(),
          expected,
          'four literal promotion choices',
        );
        advanceRejected(next, ChessMoveAction(prefix));
        final promoted = DeckManager.apply(
          next,
          ChessMoveAction('$prefix${promotion.key}'),
        );
        final at = advanceSquare(side.isWhite ? 'c8' : 'c1');
        advanceRequire(
          promoted.rules.board.squares[at] == Piece(side, promotion.value),
          'requested promotion type and color',
        );
        advanceRequire(
          promoted.rules.special == null,
          'old card never authorizes promotion',
        );
        advanceInventory(promoted);
      });
    }

    for (final kingSide in [false, true]) {
      add(
        'card-bound move excludes castles, later opponent castle remains legal '
        '${kingSide ? 'king' : 'queen'} side',
        () {
          final state = advanceFixture(
            side: side,
            fen:
                side.isWhite
                    ? 'r3k2r/7p/8/8/2P5/8/P7/R3K2R w KQkq - 0 19'
                    : 'r3k2r/p7/8/2p5/8/8/7P/R3K2R b KQkq - 0 19',
          );
          final cast = advanceCast(state);
          advanceEqual(
            cast.rules.board.castling,
            15,
            'card preserves all rights',
          );
          advanceRejected(
            cast,
            ChessMoveAction(side.isWhite ? 'e1g1' : 'e8g8'),
          );
          final moved = DeckManager.apply(
            cast,
            ChessMoveAction(advanceUci(side)),
          );
          advanceEqual(
            moved.rules.board.castling,
            15,
            'pawn double preserves all rights',
          );
          final reply = DeckManager.apply(moved, const PassAction());
          final castle =
              side.isWhite
                  ? (kingSide ? 'e8g8' : 'e8c8')
                  : (kingSide ? 'e1g1' : 'e1c1');
          advanceRequire(
            advanceChessActions(reply).contains(castle),
            'opponent castle legal',
          );
          final after = DeckManager.apply(reply, ChessMoveAction(castle));
          final rookTo =
              side.isWhite
                  ? (kingSide ? 'f8' : 'd8')
                  : (kingSide ? 'f1' : 'd1');
          advanceRequire(
            after.rules.board.squares[advanceSquare(rookTo)] ==
                Piece(side.opposite, PieceType.rook),
            'orthodox rook relocation',
          );
          advanceEqual(
            after.rules.board.castling,
            side.isWhite ? 3 : 12,
            'only castling side loses rights',
          );
          advanceInventory(after);
        },
      );
    }

    add('149 halfmoves: cast preserves counter and pawn move resets it', () {
      final state = advanceFixture(
        side: side,
        fen: pawnAdvanceBaseFens[side]!.replaceFirst('83 19', '149 19'),
      );
      final cast = advanceCast(state);
      advanceEqual(cast.rules.board.halfmoveClock, 149, 'no cast clock reset');
      final after = DeckManager.apply(cast, ChessMoveAction(advanceUci(side)));
      advanceEqual(after.rules.board.halfmoveClock, 0, 'pawn resets counter');
      advanceRequire(after.rules.terminal == null, 'no spurious 75-move draw');
    });

    for (final mate in [false, true]) {
      add(
        'literal ${mate ? 'checkmate' : 'stalemate'} after special double',
        () {
          final state = advanceFixture(
            side: side,
            fen: (mate ? pawnAdvanceMateFens : pawnAdvanceStalemateFens)[side],
          );
          final from =
              side.isWhite ? (mate ? 'c5' : 'b4') : (mate ? 'c4' : 'b5');
          final move =
              side.isWhite
                  ? (mate ? 'c5c7' : 'b4b6')
                  : (mate ? 'c4c2' : 'b5b3');
          final cast = advanceCast(state, from: from);
          advanceEqual(advanceChessActions(cast), [
            move,
          ], 'nonempty terminal-bound move');
          final ended = DeckManager.apply(cast, ChessMoveAction(move));
          advanceEqual(ended.rules.terminal!.toJson(), {
            'reason': mate ? 'checkmate' : 'stalemate',
            'winner': mate ? sideWire(side) : null,
            'mateByRestriction': false,
            'mateBySpecialMove': mate,
            'stalemateByRestriction': false,
          }, 'independent terminal reason and provenance');
          advanceEqual(ended.rules.phase.name, 'terminal', 'terminal phase');
          advanceEqual(ended.rules.ply, 39, 'terminal move counts once');
          advanceEqual(
            ended.rules.handCounts[side],
            2,
            'no post-terminal draw',
          );
          advanceEqual(ended.rules.deckCounts[side], 7, 'terminal keeps deck');
          advanceEqual(
            ended.rules.drawCounts[side],
            3,
            'terminal keeps cumulative draws',
          );
          advanceEqual(
            ended.rules.ownTurns[side.opposite],
            3,
            'no next turn after terminal',
          );
          advanceEqual(
            ended.rules.mana[side.opposite],
            3,
            'no terminal regeneration',
          );
          advanceRequire(
            ended.rules.special == null && ended.rules.pending == null,
            'no stranded authorization or pending choice',
          );
          for (final viewer in PieceColor.values) {
            advanceEqual(
              BattleRulesCore.legalActions(ended.view(viewer)).length,
              0,
              'no actions for either color after terminal',
            );
          }
          advanceRejected(ended, const PassAction());
          advanceRejected(ended, ChessMoveAction(move));
          advanceInventory(ended);
        },
      );
    }

    add('pending prophecy cannot be bypassed by pawn advance', () {
      final state = advanceFixture(side: side);
      final pending = DeckManager.apply(
        state,
        const PlayCardAction(CardId.prophecy),
      );
      advanceEqual(pending.rules.phase.name, 'pending', 'real pending state');
      advanceEqual(
        pending.hidden.knowledge[side]!.pendingCards
            .map((c) => c.wire)
            .toList(),
        ['radar', 'chain'],
        'literal inspected cards',
      );
      advanceRejected(
        pending,
        PlayCardAction(
          CardId.pawnAdvance,
          target: advanceSquare(advanceFrom(side)),
        ),
      );
      advanceRejected(pending, const PassAction());
      advanceRejected(pending, ChessMoveAction(advanceUci(side)));
      final resolved = DeckManager.apply(
        pending,
        ResolveAction([CardId.chain, CardId.radar]),
      );
      advanceEqual(
        resolved.rules.phase.name,
        'chess',
        'resolve closes card window',
      );
      advanceRequire(
        resolved.rules.special == null,
        'no authorization sneaked through pending',
      );
      advanceRejected(
        resolved,
        PlayCardAction(
          CardId.pawnAdvance,
          target: advanceSquare(advanceFrom(side)),
        ),
      );
      advanceRequire(
        advanceChessActions(resolved).contains(side.isWhite ? 'c4c5' : 'c5c4'),
        'pending resolution leaves ordinary legal move',
      );
      advanceInventory(resolved);
    });

    add(
      'strict target types and surplus sacrifice are rejected atomically',
      () {
        final state = advanceFixture(side: side);
        for (final target in <Object?>[
          null,
          advanceFrom(side),
          advanceSquare(advanceFrom(side)).toDouble(),
          -1,
          64,
          true,
          <int>[advanceSquare(advanceFrom(side))],
        ]) {
          advanceRejected(
            state,
            PlayCardAction(CardId.pawnAdvance, target: target),
          );
        }
        advanceRejected(
          state,
          PlayCardAction(
            CardId.pawnAdvance,
            target: advanceSquare(advanceFrom(side)),
            sacrifice: CardId.prophecy,
          ),
        );
        advanceEqual(advanceChessActions(advanceCast(state)), [
          advanceUci(side),
        ], 'invalid attempts do not poison subsequent valid cast');
      },
    );

    add('first turn, chess phase, wrong viewer and terminal cannot cast', () {
      final state = advanceFixture(side: side);
      final castAction = PlayCardAction(
        CardId.pawnAdvance,
        target: advanceSquare(advanceFrom(side)),
      );
      final firstTurn = advanceEdit(state, (d) {
        d.phase = BattlePhase.chess;
        d.ownTurns[side] = 1;
      });
      advanceRejected(firstTurn, castAction);
      final chess = DeckManager.apply(state, const PassAction());
      advanceRejected(chess, castAction);
      advanceEqual(
        BattleRulesCore.legalActions(state.view(side.opposite)).length,
        0,
        'wrong viewer never receives actions',
      );
      final terminal = advanceEdit(advanceCast(state), (d) {
        d.phase = BattlePhase.terminal;
        d.terminal = TerminalState('timeout', winner: side.opposite);
      });
      advanceRejected(terminal, ChessMoveAction(advanceUci(side)));
      advanceRejected(terminal, castAction);
      advanceEqual(
        BattleRulesCore.legalActions(terminal.view(side)).length,
        0,
        'stale authorization cannot bypass terminal',
      );
    });
  }
  return cases;
}
