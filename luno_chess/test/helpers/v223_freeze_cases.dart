import 'dart:convert';

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

class FreezeAuditCase {
  final String name;
  final void Function() run;
  const FreezeAuditCase(this.name, this.run);
}

int freezeSquare(String text) =>
    text.codeUnitAt(0) - 97 + (text.codeUnitAt(1) - 49) * 8;

String freezeReflectMove(String uci) =>
    '${uci[0]}${9 - int.parse(uci[1])}'
    '${uci[2]}${9 - int.parse(uci[3])}${uci.substring(4)}';

List<CardId> _deck(List<CardId> first) =>
    [
      ...first,
      ...CardId.values.where((card) => !first.contains(card)),
    ].take(10).toList();

AuthoritativeBattleState freezePosition(
  String fen, {
  bool reflect = false,
  BattlePhase phase = BattlePhase.card,
  List<CardId> actorHand = const [
    CardId.freeze,
    CardId.purify,
    CardId.prophecy,
  ],
  List<CardId> otherHand = const [
    CardId.purify,
    CardId.shelter,
    CardId.prophecy,
  ],
  int mana = 6,
}) {
  final original = Board.fromFen(fen);
  final board =
      reflect
          ? Board(
            squares: [
              for (var i = 0; i < 64; i++)
                original.squares[i ^ 56]?.copyWith(
                  color: original.squares[i ^ 56]!.color.opposite,
                ),
            ],
            turn: original.turn.opposite,
            castling:
                ((original.castling & 3) << 2) |
                ((original.castling & 12) >> 2),
            enPassant:
                original.enPassant == null ? null : original.enPassant! ^ 56,
            halfmoveClock: original.halfmoveClock,
            fullmoveNumber: original.fullmoveNumber,
          )
          : original;
  final actor = board.turn;
  final initial = DeckManager.newBattle(
    board: board,
    white: _deck(actor == PieceColor.white ? actorHand : otherHand),
    black: _deck(actor == PieceColor.black ? actorHand : otherHand),
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = phase
        ..ownTurns = {for (final side in PieceColor.values) side: 4}
        ..mana = {for (final side in PieceColor.values) side: mana}
        ..effectSequence = 200
        ..repetitions = {};
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}

AuthoritativeBattleState freezeEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

ActivePieceEffect freezeEffect(
  RuleState rules,
  int square, {
  PieceEffectType type = PieceEffectType.freeze,
  String id = 'v223-freeze',
}) {
  final side = rules.board.squares[square]!.color;
  return ActivePieceEffect(
    id: id,
    type: type,
    owner: side.opposite,
    pieceId: rules.pieceIds[square]!,
    responseSide: side,
    duration:
        type == PieceEffectType.mineDebuff
            ? EffectDuration.pieceMove
            : EffectDuration.move,
  );
}

AuthoritativeBattleState freezeOn(
  AuthoritativeBattleState state,
  int square, {
  PieceEffectType type = PieceEffectType.freeze,
  String id = 'v223-freeze',
}) => freezeEdit(state, (draft) {
  draft.pieceEffects.add(freezeEffect(state.rules, square, type: type, id: id));
});

Set<String> freezeMoves(AuthoritativeBattleState state, PieceColor side) =>
    BattleRulesCore.legalMoves(
      state.rules,
      side,
      authorization: state.rules.special,
    ).map((move) => move.uci).toSet();

String freezeEncoded(Object? value) => jsonEncode(
  canonicalObject(value),
  toEncodable: (value) {
    if (value is Enum) return '${value.runtimeType}.${value.name}';
    throw ArgumentError('Unexpected Freeze assertion value: $value');
  },
);

void freezeRequire(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

void freezeEqual(Object? actual, Object? expected, String reason) {
  if (freezeEncoded(actual) != freezeEncoded(expected)) {
    throw StateError(
      '$reason: expected ${freezeEncoded(expected)}, '
      'got ${freezeEncoded(actual)}',
    );
  }
}

void freezeExactMoves(
  AuthoritativeBattleState state,
  PieceColor side,
  Iterable<String> expected,
  String reason,
) {
  final actual = freezeMoves(state, side).toList()..sort();
  final wanted = expected.toList()..sort();
  freezeEqual(actual, wanted, reason);
}

void freezeReject(AuthoritativeBattleState state, BattleAction action) {
  final before = freezeEncoded(state.toJson());
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    rejected = error.message == 'illegal-action';
  }
  freezeRequire(rejected, 'Expected atomic illegal-action for ${action.key}');
  freezeEqual(freezeEncoded(state.toJson()), before, 'Rejected input mutated');
}

void freezeInventory(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final inventory = [
      ...state.hidden.hands[side]!,
      ...state.hidden.decks[side]!,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    freezeRequire(
      inventory.length == 10 && inventory.toSet().length == 10,
      'Card conservation failed for $side',
    );
    freezeEqual(
      state.hidden.hands[side]!.length,
      state.rules.handCounts[side],
      'Private/public hand count',
    );
    freezeEqual(
      state.hidden.decks[side]!.length,
      state.rules.deckCounts[side],
      'Private/public deck count',
    );
    freezeRequire(
      state.rules.mana[side]! >= 0 && state.rules.mana[side]! <= 6,
      'Mana out of bounds for $side',
    );
  }
  freezeEqual(
    AuthoritativeBattleState.fromJson(state.toJson()).toJson(),
    state.toJson(),
    'Authority round trip',
  );
}

Iterable<FreezeAuditCase> freezeCoreCases() sync* {
  for (final reflected in [false, true]) {
    final side = reflected ? PieceColor.black : PieceColor.white;
    final enemy = side.opposite;
    final label = side.name;
    int square(String text) => freezeSquare(text) ^ (reflected ? 56 : 0);
    String move(String text) => reflected ? freezeReflectMove(text) : text;
    Iterable<String> moves(Iterable<String> text) => text.map(move);
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.card,
      List<CardId> actorHand = const [
        CardId.freeze,
        CardId.purify,
        CardId.prophecy,
      ],
      List<CardId> otherHand = const [
        CardId.purify,
        CardId.shelter,
        CardId.prophecy,
      ],
      int mana = 6,
    }) => freezePosition(
      fen,
      reflect: reflected,
      phase: phase,
      actorHand: actorHand,
      otherHand: otherHand,
      mana: mana,
    );

    yield FreezeAuditCase('$label target types and protection ownership', () {
      var state = position('2k5/1q3br1/3p1n2/8/8/2P1N3/1B3RQ1/5K2 w - - 7 23');
      final expected =
          ['b7', 'f7', 'g7', 'd6', 'f6'].map(square).toList()..sort();
      final actual =
          BattleRulesCore.cardTargets(
              state.view(side),
              CardId.freeze,
            ).cast<int>().toList()
            ..sort();
      freezeEqual(
        actual,
        expected,
        'All five opposing non-king types eligible',
      );
      state = freezeEdit(state, (draft) {
        draft.pieceEffects.add(
          ActivePieceEffect(
            id: 'v223-shelter',
            type: PieceEffectType.shelter,
            owner: enemy,
            pieceId: draft.pieceIds[square('d6')]!,
            responseSide: side,
            duration: EffectDuration.card,
          ),
        );
        draft.boardEffects.add(
          BoardEffectInstance(
            id: 'v223-fog',
            type: BoardEffectType.fog,
            owner: enemy,
            squares: ['e6', 'f6', 'e7', 'f7'].map(square).toList(),
            responseSide: side,
            duration: EffectDuration.card,
          ),
        );
        draft.boardEffects.add(
          BoardEffectInstance(
            id: 'v223-own-fog',
            type: BoardEffectType.fog,
            owner: side,
            squares: ['a7', 'b7', 'a8', 'b8'].map(square).toList(),
            responseSide: enemy,
            duration: EffectDuration.card,
          ),
        );
      });
      final protectedTargets =
          BattleRulesCore.cardTargets(
              state.view(side),
              CardId.freeze,
            ).cast<int>().toList()
            ..sort();
      final wanted = ['b7', 'g7'].map(square).toList()..sort();
      freezeEqual(
        protectedTargets,
        wanted,
        'Only opposing protection excludes',
      );
      for (final target in <Object?>[
        square('c8'),
        square('e3'),
        square('a4'),
        square('d6'),
        square('f7'),
        square('f6'),
        -1,
        64,
        null,
      ]) {
        freezeReject(state, PlayCardAction(CardId.freeze, target: target));
      }
      freezeInventory(state);
    });

    yield FreezeAuditCase('$label exact frozen rook legal set and expiry', () {
      var state = position('7k/8/8/8/3R4/8/8/K7 w - - 0 18');
      freezeExactMoves(
        state,
        side,
        moves([
          'a1b1',
          'a1a2',
          'a1b2',
          'd4a4',
          'd4b4',
          'd4c4',
          'd4e4',
          'd4f4',
          'd4g4',
          'd4h4',
          'd4d1',
          'd4d2',
          'd4d3',
          'd4d5',
          'd4d6',
          'd4d7',
          'd4d8',
        ]),
        'Independent unrestricted oracle',
      );
      state = freezeOn(state, square('d4'));
      freezeExactMoves(
        state,
        side,
        moves(['a1b1', 'a1a2', 'a1b2']),
        'Freeze removes every rook move, no king move',
      );
      final closed = DeckManager.apply(state, const PassAction());
      freezeEqual(closed.rules.pieceEffects.length, 1, 'Pass does not thaw');
      freezeReject(closed, ChessMoveAction(move('d4d5')));
      final after = DeckManager.apply(closed, ChessMoveAction(move('a1b1')));
      freezeEqual(after.rules.pieceEffects.length, 0, 'Other-piece move thaws');
      freezeEqual(
        after.rules.pieceIds[square('d4')],
        state.rules.pieceIds[square('d4')],
        'Frozen rook did not relocate',
      );
      freezeInventory(after);
    });

    yield FreezeAuditCase(
      '$label cast retains the chess move and response window',
      () {
        final state = position('6k1/8/8/8/2r5/8/8/5K2 w - - 9 24');
        final before = freezeEncoded(state.toJson());
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('c4')),
        );
        freezeEqual(
          cast.rules.fen,
          state.rules.fen,
          'Casting is not a chess move',
        );
        freezeEqual(cast.rules.ply, state.rules.ply, 'No extra ply');
        freezeEqual(
          cast.rules.phase.name,
          'chess',
          'No pending Freeze chooser',
        );
        freezeEqual(cast.rules.mana[side], 2, 'Exact base cost four');
        freezeEqual(
          cast.hidden.hands[side]!.length,
          2,
          'Cast consumes one card',
        );
        freezeEqual(
          cast.hidden.decks[side],
          state.hidden.decks[side],
          'Casting cannot draw',
        );
        final effect = cast.rules.pieceEffects.single;
        freezeEqual(effect.type.name, 'freeze', 'Effect type');
        freezeEqual(effect.owner.name, side.name, 'Caster owns effect');
        freezeEqual(effect.responseSide.name, enemy.name, 'Opponent response');
        freezeEqual(
          effect.duration.name,
          'move',
          'Move duration, not pieceMove',
        );
        freezeEqual(
          effect.pieceId,
          state.rules.pieceIds[square('c4')],
          'Target binds to identity',
        );
        final moved = DeckManager.apply(cast, ChessMoveAction(move('f1e1')));
        freezeEqual(
          moved.rules.pieceEffects.single.id,
          effect.id,
          'Caster chess move cannot consume enemy response',
        );
        freezeEqual(moved.rules.phase.name, 'card', 'Opponent gets card phase');
        final passed = DeckManager.apply(moved, const PassAction());
        freezeEqual(
          passed.rules.pieceEffects.single.id,
          effect.id,
          'Opponent card phase does not consume move duration',
        );
        freezeReject(passed, ChessMoveAction(move('c4c5')));
        final response = DeckManager.apply(
          passed,
          ChessMoveAction(move('g8f8')),
        );
        freezeEqual(response.rules.pieceEffects.length, 0, 'Response consumes');
        freezeEqual(
          freezeEncoded(state.toJson()),
          before,
          'Cast input immutable',
        );
        freezeInventory(response);
      },
    );

    yield FreezeAuditCase(
      '$label frozen attacker still checks and guards squares',
      () {
        final state = position('7k/8/8/3n4/8/2K5/8/8 w - - 0 21');
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('d5')),
        );
        freezeExactMoves(
          cast,
          side,
          moves(['c3b2', 'c3c2', 'c3d2', 'c3b3', 'c3d3', 'c3c4', 'c3d4']),
          'Frozen knight attack on b4 remains',
        );
        freezeReject(cast, ChessMoveAction(move('c3b4')));
        final escaped = DeckManager.apply(cast, ChessMoveAction(move('c3c4')));
        freezeEqual(
          escaped.rules.pieceEffects.length,
          1,
          'Escaping check is still the caster move',
        );
        freezeRequire(escaped.rules.terminal == null, 'Must not false-mate');
      },
    );

    yield FreezeAuditCase(
      '$label Purify restores only pin-respecting moves',
      () {
        var state = position('3r3k/8/8/8/8/3R4/8/3K4 w - - 0 31');
        state = freezeOn(state, square('d3'));
        freezeExactMoves(
          state,
          side,
          moves(['d1c1', 'd1e1', 'd1c2', 'd1d2', 'd1e2']),
          'Frozen pinned rook has no move',
        );
        final clean = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-freeze'),
        );
        freezeExactMoves(
          clean,
          side,
          moves([
            'd1c1',
            'd1e1',
            'd1c2',
            'd1d2',
            'd1e2',
            'd3d2',
            'd3d4',
            'd3d5',
            'd3d6',
            'd3d7',
            'd3d8',
          ]),
          'Purify is not a king-safety exemption',
        );
        freezeReject(clean, ChessMoveAction(move('d3c3')));
        freezeInventory(
          DeckManager.apply(clean, ChessMoveAction(move('d3d8'))),
        );
      },
    );

    yield FreezeAuditCase(
      '$label frozen EP mover and exact Purify restoration',
      () {
        var state = position('7k/8/8/2pP4/8/8/8/K7 w - c6 0 27');
        state = freezeOn(state, square('d5'));
        freezeExactMoves(
          state,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Neither pawn advance nor EP bypasses Freeze',
        );
        final passed = DeckManager.apply(state, const PassAction());
        freezeEqual(
          passed.rules.board.enPassant,
          square('c6'),
          'Card pass preserves EP window',
        );
        freezeReject(passed, ChessMoveAction(move('d5c6')));
        final clean = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-freeze'),
        );
        freezeExactMoves(
          clean,
          side,
          moves(['a1b1', 'a1a2', 'a1b2', 'd5d6', 'd5c6']),
          'Purify restores both independent pawn options',
        );
        final after = DeckManager.apply(clean, ChessMoveAction(move('d5c6')));
        freezeRequire(
          after.rules.board.squares[square('c5')] == null,
          'EP victim must leave c5',
        );
        freezeEqual(
          after.rules.pieceIds[square('c6')],
          state.rules.pieceIds[square('d5')],
          'EP mover identity',
        );
        freezeInventory(after);
      },
    );

    yield FreezeAuditCase('$label EP can capture the frozen victim', () {
      final state = position('7k/8/8/2pP4/8/8/8/K7 w - c6 0 28');
      final cast = DeckManager.apply(
        state,
        PlayCardAction(CardId.freeze, target: square('c5')),
      );
      freezeExactMoves(
        cast,
        side,
        moves(['a1b1', 'a1a2', 'a1b2', 'd5d6', 'd5c6']),
        'Freeze is not capture immunity',
      );
      final after = DeckManager.apply(cast, ChessMoveAction(move('d5c6')));
      freezeEqual(
        after.rules.pieceEffects.length,
        0,
        'Off-destination EP victim effect removed immediately',
      );
      freezeRequire(
        !after.rules.pieceIds.contains(state.rules.pieceIds[square('c5')]),
        'EP victim identity removed',
      );
      freezeInventory(after);
    });

    yield FreezeAuditCase(
      '$label frozen rook still forbids discovered-check EP',
      () {
        final state = position('7k/8/8/r2pP2K/8/8/8/8 w - d6 0 29');
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('a5')),
        );
        freezeExactMoves(
          cast,
          side,
          moves(['h5g4', 'h5h4', 'h5g5', 'h5g6', 'h5h6', 'e5e6']),
          'Frozen rook retains the exposed fifth-rank attack',
        );
        freezeReject(cast, ChessMoveAction(move('e5d6')));
        freezeInventory(DeckManager.apply(cast, ChessMoveAction(move('e5e6'))));
      },
    );

    for (final rook in ['a1', 'h1']) {
      yield FreezeAuditCase('$label frozen $rook blocks only its castle', () {
        var state = position('4k3/7p/8/8/8/8/P7/R3K2R w KQ - 0 35');
        state = freezeOn(state, square(rook));
        final actual = freezeMoves(state, side);
        final blocked = move(rook == 'h1' ? 'e1g1' : 'e1c1');
        final allowed = move(rook == 'h1' ? 'e1c1' : 'e1g1');
        freezeRequire(!actual.contains(blocked), 'Frozen rook cannot castle');
        freezeRequire(actual.contains(allowed), 'Other rook can still castle');
        final passed = DeckManager.apply(state, const PassAction());
        freezeReject(passed, ChessMoveAction(blocked));
        final after = DeckManager.apply(passed, ChessMoveAction(allowed));
        freezeEqual(
          after.rules.pieceEffects.length,
          0,
          'Other-side castle consumes the response move',
        );
        freezeEqual(
          after.rules.pieceIds[square(rook)],
          state.rules.pieceIds[square(rook)],
          'Frozen rook stays put',
        );
        freezeInventory(after);
      });
    }

    yield FreezeAuditCase(
      '$label frozen attacker still forbids castling transit',
      () {
        final state = position('4k3/8/8/8/8/5r2/8/4K2R w K - 0 36');
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('f3')),
        );
        freezeRequire(
          !freezeMoves(cast, side).contains(move('e1g1')),
          'Frozen rook attacks f1 transit',
        );
        freezeReject(cast, ChessMoveAction(move('e1g1')));
        freezeInventory(DeckManager.apply(cast, ChessMoveAction(move('e1d1'))));
      },
    );

    yield FreezeAuditCase(
      '$label frozen promotion pawn has no promotion choice',
      () {
        var state = position('6k1/1P6/8/8/8/8/7p/K7 w - - 0 41');
        state = freezeOn(state, square('b7'));
        freezeExactMoves(
          state,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Freeze blocks all four promotions',
        );
        final clean = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-freeze'),
        );
        freezeExactMoves(
          clean,
          side,
          moves(['a1b1', 'a1a2', 'a1b2', 'b7b8q', 'b7b8r', 'b7b8b', 'b7b8n']),
          'Purify restores all promotion types',
        );
        for (final suffix in ['q', 'r', 'b', 'n']) {
          final after = DeckManager.apply(
            clean,
            ChessMoveAction(move('b7b8$suffix')),
          );
          freezeEqual(
            after.rules.pieceIds[square('b8')],
            state.rules.pieceIds[square('b7')],
            'Promotion keeps pawn identity',
          );
          freezeEqual(after.rules.pieceEffects.length, 0, 'No ghost Freeze');
          freezeInventory(after);
        }
      },
    );

    yield FreezeAuditCase(
      '$label promotion capture removes frozen target only',
      () {
        final state = position('r5k1/1P6/8/8/8/8/7p/K7 w - - 0 42');
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('a8')),
        );
        for (final suffix in ['q', 'r', 'b', 'n']) {
          final after = DeckManager.apply(
            cast,
            ChessMoveAction(move('b7a8$suffix')),
          );
          freezeEqual(
            after.rules.pieceEffects.length,
            0,
            'Captured Freeze removed',
          );
          freezeEqual(
            after.rules.pieceIds[square('a8')],
            state.rules.pieceIds[square('b7')],
            'Not the frozen rook identity',
          );
          freezeInventory(after);
        }
      },
    );

    yield FreezeAuditCase(
      '$label Purify one overlapping Freeze/Mine instance',
      () {
        var state = position('7k/8/8/8/3R1p2/8/8/K7 w - - 0 47');
        state = freezeOn(state, square('d4'));
        state = freezeOn(
          state,
          square('d4'),
          type: PieceEffectType.mineDebuff,
          id: 'v223-old-mine',
        );
        final cleanFreeze = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-freeze'),
        );
        freezeEqual(
          cleanFreeze.rules.pieceEffects.single.id,
          'v223-old-mine',
          'Removing Freeze preserves old Mine debuff',
        );
        freezeRequire(
          freezeMoves(cleanFreeze, side).contains(move('d4e4')),
          'Quiet rook move restored',
        );
        freezeReject(cleanFreeze, ChessMoveAction(move('d4f4')));
        final other = DeckManager.apply(
          cleanFreeze,
          ChessMoveAction(move('a1b1')),
        );
        freezeEqual(
          other.rules.pieceEffects.single.id,
          'v223-old-mine',
          'Other-piece move cannot consume pieceMove Mine',
        );
        final cleanMine = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-old-mine'),
        );
        freezeExactMoves(
          cleanMine,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Removing Mine does not remove Freeze',
        );
        freezeInventory(other);
      },
    );

    yield FreezeAuditCase(
      '$label own Shelter cannot cleanse existing Freeze',
      () {
        var state = position(
          '7k/8/8/8/3R4/8/8/K7 w - - 0 49',
          actorHand: [CardId.shelter, CardId.purify, CardId.freeze],
        );
        state = freezeOn(state, square('d4'));
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: square('d4')),
        );
        freezeExactMoves(
          cast,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Own Shelter does not override Freeze',
        );
        freezeEqual(cast.rules.pieceEffects.length, 2, 'Both effects remain');
        final after = DeckManager.apply(cast, ChessMoveAction(move('a1b1')));
        freezeEqual(
          after.rules.pieceEffects.single.type.name,
          'shelter',
          'Only response-window Freeze expires',
        );
        freezeInventory(after);
      },
    );

    yield FreezeAuditCase(
      '$label Purify restores check interpositions, not unsafe moves',
      () {
        var state = position('3r3k/8/8/8/2B5/8/8/3K4 w - - 0 51');
        state = freezeOn(state, square('c4'));
        freezeExactMoves(
          state,
          side,
          moves(['d1c1', 'd1c2', 'd1e1', 'd1e2']),
          'Frozen bishop cannot interpose',
        );
        final clean = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-freeze'),
        );
        freezeExactMoves(
          clean,
          side,
          moves(['d1c1', 'd1c2', 'd1e1', 'd1e2', 'c4d3', 'c4d5']),
          'Only two safe bishop interpositions restored',
        );
        freezeReject(clean, ChessMoveAction(move('c4b5')));
        freezeInventory(
          DeckManager.apply(clean, ChessMoveAction(move('c4d5'))),
        );
      },
    );

    yield FreezeAuditCase(
      '$label restriction mate terminates instead of empty live turn',
      () {
        final state = position('1k6/pppr4/8/8/8/8/6K1/4R3 w - - 0 53');
        final normal = DeckManager.apply(
          DeckManager.apply(state, const PassAction()),
          ChessMoveAction(move('e1e8')),
        );
        freezeRequire(normal.rules.terminal == null, 'Without Freeze not mate');
        freezeExactMoves(
          normal,
          enemy,
          moves(['d7d8']),
          'Independent sole rook interposition',
        );
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('d7')),
        );
        final after = DeckManager.apply(cast, ChessMoveAction(move('e1e8')));
        final terminal = after.rules.terminal;
        freezeRequire(
          terminal != null &&
              terminal.reason == 'checkmate' &&
              terminal.winner == side &&
              terminal.mateByRestriction &&
              !terminal.mateBySpecialMove &&
              !terminal.stalemateByRestriction,
          'Freeze must produce classified restriction mate',
        );
        freezeEqual(after.rules.phase.name, 'terminal', 'No live softlock');
        freezeEqual(
          after.hidden.decks[side],
          cast.hidden.decks[side],
          'Terminal move does not draw',
        );
        freezeEqual(
          BattleRulesCore.legalActions(after.view(side)).length,
          0,
          'No post-terminal caster action',
        );
        freezeEqual(
          BattleRulesCore.legalActions(after.view(enemy)).length,
          0,
          'No post-terminal opponent action',
        );
        freezeReject(after, const PassAction());
        freezeInventory(after);
      },
    );

    yield FreezeAuditCase(
      '$label restriction stalemate is a draw, not a hang',
      () {
        final state = position('k7/4r3/2K5/2Q5/8/8/8/8 w - - 0 57');
        final normal = DeckManager.apply(
          DeckManager.apply(state, const PassAction()),
          ChessMoveAction(move('c5b6')),
        );
        freezeRequire(
          normal.rules.terminal == null &&
              freezeMoves(normal, enemy).contains(move('e7e8')),
          'Unfrozen rook has at least explicit e7e8',
        );
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.freeze, target: square('e7')),
        );
        final after = DeckManager.apply(cast, ChessMoveAction(move('c5b6')));
        final terminal = after.rules.terminal;
        freezeRequire(
          terminal != null &&
              terminal.reason == 'stalemate' &&
              terminal.winner == null &&
              terminal.stalemateByRestriction &&
              !terminal.mateByRestriction &&
              !terminal.mateBySpecialMove,
          'Freeze must classify restriction stalemate',
        );
        freezeEqual(after.rules.phase.name, 'terminal', 'No empty live phase');
        freezeInventory(after);
      },
    );

    yield FreezeAuditCase(
      '$label pending Prophecy does not tick Freeze lifetime',
      () {
        var state = position(
          '7k/8/8/8/3R4/8/8/K7 w - - 0 61',
          actorHand: [CardId.prophecy, CardId.purify, CardId.freeze],
        );
        state = freezeOn(state, square('d4'));
        final pending = DeckManager.apply(
          state,
          const PlayCardAction(CardId.prophecy),
        );
        freezeEqual(
          pending.rules.phase.name,
          'pending',
          'Prophecy choice pending',
        );
        freezeEqual(
          pending.rules.pieceEffects.single.id,
          'v223-freeze',
          'Inspection is not a response move',
        );
        freezeReject(pending, ChessMoveAction(move('a1b1')));
        freezeReject(pending, const PassAction());
        freezeReject(
          pending,
          PlayCardAction(CardId.freeze, target: square('h8')),
        );
        final order =
            pending.hidden.knowledge[side]!.pendingCards.reversed.toList();
        final resolved = DeckManager.apply(pending, ResolveAction(order));
        freezeExactMoves(
          resolved,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Resolution retains Freeze for chess move',
        );
        final after = DeckManager.apply(
          resolved,
          ChessMoveAction(move('a1b1')),
        );
        freezeEqual(
          after.rules.pieceEffects.length,
          0,
          'Chess response finally ticks',
        );
        freezeInventory(after);
      },
    );

    yield FreezeAuditCase(
      '$label blocked/poor Freeze can be discarded without effect',
      () {
        var state = position('6k1/8/8/8/2r5/8/8/5K2 w - - 0 63', mana: 3);
        state = freezeEdit(state, (draft) {
          draft.modifiers.add(
            PendingModifier(
              id: 'v223-card-block',
              type: ModifierType.cardBlock,
              owner: enemy,
              responseSide: side,
              targetCard: CardId.freeze,
              ownTurn: draft.ownTurns[side]!,
            ),
          );
        });
        freezeReject(
          state,
          PlayCardAction(CardId.freeze, target: square('c4')),
        );
        final after = DeckManager.apply(
          state,
          const DiscardAction(CardId.freeze),
        );
        freezeEqual(
          after.rules.phase.name,
          'chess',
          'Discard preserves chess turn',
        );
        freezeEqual(after.rules.mana[side], 3, 'Discard charges no mana');
        freezeEqual(after.rules.pieceEffects.length, 0, 'No discard Freeze');
        freezeEqual(after.rules.used[side]!.length, 0, 'Discard is not use');
        freezeEqual(
          after.rules.discarded[side]!.map((card) => card.wire).toList(),
          ['freeze'],
          'Discard ledger',
        );
        freezeInventory(
          DeckManager.apply(after, ChessMoveAction(move('f1e1'))),
        );
      },
    );

    yield FreezeAuditCase(
      '$label second Freeze cannot be replayed in chess phase',
      () {
        final state = position('6k1/8/8/8/2r1n3/8/8/5K2 w - - 0 65');
        final action = PlayCardAction(CardId.freeze, target: square('c4'));
        final cast = DeckManager.apply(state, action);
        freezeReject(cast, action);
        freezeReject(cast, PlayCardAction(CardId.freeze, target: square('e4')));
        freezeReject(cast, const DiscardAction(CardId.freeze));
        freezeEqual(
          cast.rules.effectSequence,
          state.rules.effectSequence + 1,
          'One accepted cast creates one effect',
        );
        freezeInventory(cast);
      },
    );

    for (final symbol in ['P', 'N', 'B', 'R', 'Q']) {
      yield FreezeAuditCase('$label $symbol movement is fully frozen', () {
        var state = position('8/7k/8/8/3${symbol}4/8/8/K7 w - - 0 71');
        state = freezeOn(state, square('d4'));
        freezeExactMoves(
          state,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Every ordinary move of $symbol is blocked',
        );
        final after = DeckManager.apply(
          DeckManager.apply(state, const PassAction()),
          ChessMoveAction(move('a1a2')),
        );
        freezeEqual(
          after.rules.pieceEffects.length,
          0,
          'All piece types expire',
        );
        freezeInventory(after);
      });
    }

    for (final row in <({CardId card, String fen, List<String> expected})>[
      (
        card: CardId.pawnDeviation,
        fen: '8/7k/8/8/3P4/8/8/K7 w - - 0 73',
        expected: ['d4c5', 'd4e5'],
      ),
      (
        card: CardId.pawnAdvance,
        fen: '8/7k/8/8/3P4/8/8/K7 w - - 0 74',
        expected: ['d4d6'],
      ),
      (
        card: CardId.rookBend,
        fen: '8/7k/8/8/3R4/8/8/K7 w - - 0 75',
        expected: ['d4c3', 'd4c5', 'd4e3', 'd4e5'],
      ),
      (
        card: CardId.angryN,
        fen: '8/7k/8/8/3N4/8/8/K7 w - - 0 76',
        expected: ['d4c4', 'd4d3', 'd4d5', 'd4e4'],
      ),
      (
        card: CardId.shadowPass,
        fen: '8/7k/8/8/3R4/3P4/8/K7 w - - 0 77',
        expected: ['d4d2', 'd4d1'],
      ),
    ]) {
      yield FreezeAuditCase('$label ${row.card.wire} cannot bypass Freeze', () {
        final root = position(
          row.fen,
          actorHand: [row.card, CardId.purify, CardId.freeze],
        );
        final normal =
            BattleRulesCore.specialMoves(
                root.rules,
                row.card,
                square('d4'),
                side,
              ).map((candidate) => candidate.uci).toList()
              ..sort();
        final expected = moves(row.expected).toList()..sort();
        freezeEqual(normal, expected, 'Independent special-move control');
        final frozen = freezeOn(root, square('d4'));
        freezeEqual(
          BattleRulesCore.specialMoves(
            frozen.rules,
            row.card,
            square('d4'),
            side,
          ).length,
          0,
          'Freeze blocks special geometry',
        );
        freezeRequire(
          !BattleRulesCore.cardTargets(
            frozen.view(side),
            row.card,
          ).contains(square('d4')),
          'No unfulfillable bound card authorization',
        );
        freezeReject(frozen, PlayCardAction(row.card, target: square('d4')));
        freezeInventory(frozen);
      });
    }

    yield FreezeAuditCase(
      '$label duplicate effect fixture removes exactly one instance',
      () {
        var state = position('8/7k/8/8/3R4/8/8/K7 w - - 0 79');
        state = freezeOn(state, square('d4'), id: 'v223-freeze-1');
        state = freezeOn(state, square('d4'), id: 'v223-freeze-2');
        final clean = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-freeze-1'),
        );
        freezeEqual(
          clean.rules.pieceEffects.single.id,
          'v223-freeze-2',
          'Synthetic duplicate is not an all-effect cleanse',
        );
        freezeExactMoves(
          clean,
          side,
          moves(['a1b1', 'a1a2', 'a1b2']),
          'Remaining Freeze is independently active',
        );
        final after = DeckManager.apply(clean, ChessMoveAction(move('a1b1')));
        freezeEqual(
          after.rules.pieceEffects.length,
          0,
          'Remaining instance expires',
        );
        freezeInventory(after);
      },
    );

    yield FreezeAuditCase(
      '$label hidden permutations do not affect Freeze legality',
      () {
        final root = position('6k1/8/8/8/2r1n3/8/8/5K2 w - - 0 81');
        final alternative = AuthoritativeBattleState(
          root.rules,
          AuthoritativeHiddenState(
            hands: {
              side: root.hidden.hands[side]!,
              enemy: root.hidden.hands[enemy]!.reversed.toList(),
            },
            decks: {
              side: root.hidden.decks[side]!,
              enemy: root.hidden.decks[enemy]!.reversed.toList(),
            },
            knowledge: {
              side: root.hidden.knowledge[side]!,
              enemy: PlayerKnowledgeState(
                knownUpcomingCards:
                    root.hidden.decks[enemy]!.reversed.take(2).toList(),
              ),
            },
          ),
        );
        freezeEqual(
          root.view(side).toJson(),
          alternative.view(side).toJson(),
          'Opponent hand/deck/knowledge never enters caster PlayerView',
        );
        final rootActions =
            BattleRulesCore.legalActions(
              root.view(side),
            ).map((action) => action.toJson()).toList();
        final otherActions =
            BattleRulesCore.legalActions(
              alternative.view(side),
            ).map((action) => action.toJson()).toList();
        freezeEqual(
          rootActions,
          otherActions,
          'No hidden-state targeting oracle',
        );
        final action = PlayCardAction(CardId.freeze, target: square('c4'));
        final first = DeckManager.apply(root, action);
        final second = DeckManager.apply(alternative, action);
        freezeEqual(
          first.rules.toJson(),
          second.rules.toJson(),
          'Same public Freeze effect under secret permutations',
        );
        freezeEqual(
          first.hidden.hands[enemy],
          root.hidden.hands[enemy],
          'Freeze never changes enemy cards',
        );
        freezeEqual(
          second.hidden.decks[enemy],
          alternative.hidden.decks[enemy],
          'Freeze never inspects or reorders enemy deck',
        );
        freezeInventory(first);
        freezeInventory(second);
      },
    );

    for (final row in <({int mana, bool sabotage, bool discount, int cost})>[
      (mana: 3, sabotage: false, discount: false, cost: 4),
      (mana: 4, sabotage: false, discount: false, cost: 4),
      (mana: 4, sabotage: true, discount: false, cost: 5),
      (mana: 5, sabotage: true, discount: false, cost: 5),
      (mana: 1, sabotage: false, discount: true, cost: 2),
      (mana: 2, sabotage: false, discount: true, cost: 2),
      (mana: 2, sabotage: true, discount: true, cost: 3),
      (mana: 3, sabotage: true, discount: true, cost: 3),
    ]) {
      yield FreezeAuditCase('$label cost boundary $row', () {
        var state = position(
          '6k1/8/8/8/2r5/8/8/5K2 w - - 0 67',
          mana: row.mana,
        );
        state = freezeEdit(state, (draft) {
          if (row.sabotage) {
            draft.modifiers.add(
              PendingModifier(
                id: 'v223-sabotage',
                type: ModifierType.manaSabotage,
                owner: enemy,
                responseSide: side,
                targetCard: CardId.freeze,
                ownTurn: draft.ownTurns[side]!,
              ),
            );
          }
          if (row.discount) {
            draft.modifiers.add(
              PendingModifier(
                id: 'v223-discount',
                type: ModifierType.discount,
                owner: side,
                responseSide: side,
                targetCard: null,
                ownTurn: draft.ownTurns[side]!,
              ),
            );
          }
        });
        freezeEqual(
          BattleRulesCore.effectiveCost(state.rules, side, CardId.freeze),
          row.cost,
          'Explicit cost contract',
        );
        final action = PlayCardAction(CardId.freeze, target: square('c4'));
        if (row.mana < row.cost) {
          freezeReject(state, action);
        } else {
          final after = DeckManager.apply(state, action);
          freezeEqual(
            after.rules.mana[side],
            row.mana - row.cost,
            'Charge calculated before modifier window closes',
          );
          freezeEqual(after.rules.pieceEffects.length, 1, 'One effect');
          freezeEqual(
            after.rules.modifiers.length,
            0,
            'Own cost window consumed',
          );
          freezeInventory(after);
        }
      });
    }
  }
}
