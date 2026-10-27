import 'dart:convert';

import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const mineWhite = PieceColor.white;
const mineBlack = PieceColor.black;
const mineCaptureFen = '1k6/8/6b1/8/8/3P4/4R3/1K6 w - - 14 46';
const mineCastleFen = '1k6/3p4/8/8/8/8/5P2/R3K2R w KQ - 5 38';

int mineSquare(String text) =>
    Square.of(text.codeUnitAt(0) - 97, text.codeUnitAt(1) - 49);

String mineReflectMove(String uci) =>
    '${Square.algebraic(mineSquare(uci.substring(0, 2)) ^ 56)}'
    '${Square.algebraic(mineSquare(uci.substring(2, 4)) ^ 56)}'
    '${uci.length == 5 ? uci[4] : ''}';

Board mineReflectBoard(Board board) => Board(
  squares: [
    for (var i = 0; i < 64; i++)
      board.squares[i ^ 56]?.copyWith(
        color: board.squares[i ^ 56]!.color.opposite,
      ),
  ],
  turn: board.turn.opposite,
  castling: ((board.castling & 3) << 2) | ((board.castling & 12) >> 2),
  enPassant: board.enPassant == null ? null : board.enPassant! ^ 56,
  halfmoveClock: board.halfmoveClock,
  fullmoveNumber: board.fullmoveNumber,
);

List<CardId> _mineDeck(List<CardId> hand) {
  if (hand.length != 3 || hand.toSet().length != 3) {
    throw ArgumentError('Mine fixtures require three distinct initial cards');
  }
  return [
    ...hand,
    ...CardId.values.where((card) => !hand.contains(card)).take(7),
  ];
}

AuthoritativeBattleState minePosition(
  String fen, {
  bool reflect = false,
  BattlePhase phase = BattlePhase.chess,
  List<CardId> hand = const [CardId.mine, CardId.purify, CardId.breakSeal],
}) {
  final board = Board.fromFen(fen);
  final state = DeckManager.newBattle(
    board: reflect ? mineReflectBoard(board) : board,
    white: _mineDeck(hand),
    black: _mineDeck(hand),
  );
  mineRequire(state.rules.terminal == null, 'nonterminal fixture: $fen');
  return mineEdit(state, (draft) {
    draft.phase = phase;
    draft.ownTurns = {mineWhite: 2, mineBlack: 2};
    draft.mana = {mineWhite: 6, mineBlack: 6};
    draft.repetitions = {};
  });
}

AuthoritativeBattleState mineEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState mineBoardEffect(
  AuthoritativeBattleState state,
  int square,
  PieceColor owner, {
  String id = 'v223-mine-board',
  BoardEffectType type = BoardEffectType.mine,
  EffectDuration duration = EffectDuration.persistent,
  List<int>? squares,
}) => mineEdit(state, (draft) {
  draft.boardEffects.add(
    BoardEffectInstance(
      id: id,
      type: type,
      owner: owner,
      squares: squares ?? [square],
      responseSide: owner.opposite,
      duration: duration,
    ),
  );
});

AuthoritativeBattleState minePieceEffect(
  AuthoritativeBattleState state,
  int square, {
  String id = 'v223-mine-old',
  PieceEffectType type = PieceEffectType.mineDebuff,
  EffectDuration duration = EffectDuration.pieceMove,
}) => mineEdit(state, (draft) {
  final affected = state.rules.board.pieceAt(square)!.color;
  draft.pieceEffects.add(
    ActivePieceEffect(
      id: id,
      type: type,
      owner: type == PieceEffectType.shelter ? affected : affected.opposite,
      pieceId: draft.pieceIds[square]!,
      responseSide:
          type == PieceEffectType.shelter ? affected.opposite : affected,
      duration: duration,
    ),
  );
});

AuthoritativeBattleState mineRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

void mineRequire(bool condition, String detail) {
  if (!condition) throw StateError('V223 Mine: $detail');
}

void mineEqual(Object? actual, Object? expected, String detail) {
  Object encode(Object? value) {
    if (value is Enum) return '${value.runtimeType}.${value.name}';
    throw ArgumentError('Unexpected Mine assertion value: $value');
  }

  mineRequire(
    jsonEncode(canonicalObject(actual), toEncodable: encode) ==
        jsonEncode(canonicalObject(expected), toEncodable: encode),
    '$detail; expected=$expected actual=$actual',
  );
}

Set<String> mineMoves(AuthoritativeBattleState state, {PieceColor? side}) =>
    BattleRulesCore.legalMoves(
      state.rules,
      side ?? state.rules.board.turn,
      authorization: state.rules.special,
    ).map((move) => move.uci).toSet();

void mineRejects(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(state.toJson());
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    rejected = error.message == 'illegal-action';
  }
  mineRequire(rejected, 'illegal-action required for ${action.toJson()}');
  mineEqual(jsonEncode(state.toJson()), before, 'atomic rejection');
}

void mineInvariants(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final hand = state.hidden.hands[side]!, deck = state.hidden.decks[side]!;
    mineEqual(hand.length, state.rules.handCounts[side], 'public hand count');
    mineEqual(deck.length, state.rules.deckCounts[side], 'public deck count');
    final inventory = [
      ...hand,
      ...deck,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    mineEqual(inventory.length, 10, 'finite deck inventory');
    mineEqual(inventory.toSet().length, 10, 'no duplicate card inventory');
    mineRequire(
      state.rules.mana[side]! >= 0 && state.rules.mana[side]! <= 6,
      'mana remains in bounds',
    );
    mineRequire(
      state.rules.boardEffects
              .where(
                (effect) =>
                    effect.type == BoardEffectType.mine && effect.owner == side,
              )
              .length <=
          1,
      'one dormant Mine per side',
    );
  }
  final ids = state.rules.pieceIds.whereType<String>().toList();
  mineEqual(ids.toSet().length, ids.length, 'unique live piece identities');
  for (var square = 0; square < 64; square++) {
    mineEqual(
      state.rules.pieceIds[square] == null,
      state.rules.board.pieceAt(square) == null,
      'piece identity occupancy',
    );
  }
  mineRequire(
    state.rules.pieceEffects.every((effect) => ids.contains(effect.pieceId)),
    'no orphaned piece effect',
  );
  mineEqual(
    mineRoundTrip(state).toJson(),
    state.toJson(),
    'authority round trip',
  );
}

AuthoritativeBattleState mineApply(
  AuthoritativeBattleState state,
  BattleAction action,
) {
  final before = jsonEncode(state.toJson());
  final next = DeckManager.apply(state, action);
  mineEqual(jsonEncode(state.toJson()), before, 'accepted input is immutable');
  mineInvariants(next);
  return next;
}

AuthoritativeBattleState mineMove(AuthoritativeBattleState state, String uci) {
  if (state.rules.phase == BattlePhase.card) {
    state = mineApply(state, const PassAction());
  }
  return mineApply(state, ChessMoveAction(uci));
}

void mineFreshEffect(
  AuthoritativeBattleState state,
  String pieceId,
  PieceColor owner,
) {
  final effects = state.rules.pieceEffects.where(
    (effect) =>
        effect.type == PieceEffectType.mineDebuff && effect.pieceId == pieceId,
  );
  mineEqual(effects.length, 1, 'exactly one fresh Mine debuff on arrival');
  final effect = effects.single;
  mineEqual(effect.owner, owner, 'Mine caster owns triggered debuff');
  mineEqual(effect.responseSide, owner.opposite, 'affected side response');
  mineEqual(
    effect.duration,
    EffectDuration.pieceMove,
    'piece-specific lifetime',
  );
  mineRequire(effect.id != 'v223-mine-old', 'fresh effect has new identity');
}

class MineCase {
  final String name;
  final void Function() run;
  const MineCase(this.name, this.run);
}

List<MineCase> mineOracleCases(List<dynamic> oracles) => [
  for (final raw in oracles)
    for (final reflect in [false, true])
      MineCase('${reflect ? 'b' : 'w'} oracle ${raw['id']}', () {
        final row = raw as Map;
        int sq(String value) => mineSquare(value) ^ (reflect ? 56 : 0);
        String uci(String value) => reflect ? mineReflectMove(value) : value;
        var state = minePosition(row['fen'] as String, reflect: reflect);
        if (row['debuff'] != null) {
          state = minePieceEffect(state, sq(row['debuff'] as String));
        }
        final from = sq(row['from'] as String);
        final actual =
            mineMoves(state)
                .where((move) => move.startsWith(Square.algebraic(from)))
                .toList()
              ..sort();
        final expected = [
          for (final move in row['expected'] as List) uci(move as String),
        ]..sort();
        mineEqual(actual, expected, row['reason'] as String);
        for (final denied in row['denied'] as List) {
          mineRejects(state, ChessMoveAction(uci(denied as String)));
        }
        for (final move in expected) {
          final next = mineApply(state, ChessMoveAction(move));
          final affected =
              row['debuff'] == row['from'] ||
              (row['debuff'] == 'h1' && move == uci('e1g1')) ||
              (row['debuff'] == 'a1' && move == uci('e1c1'));
          mineEqual(
            next.rules.pieceEffects.any((e) => e.id == 'v223-mine-old'),
            row['debuff'] != null && !affected,
            'only affected identity movement consumes old Mine',
          );
        }
        mineInvariants(state);
      }),
];

List<MineCase> mineCoreCases() {
  final cases = <MineCase>[];
  for (final reflect in [false, true]) {
    final side = reflect ? mineBlack : mineWhite, enemy = side.opposite;
    final prefix = sideWire(side);
    int sq(String value) => mineSquare(value) ^ (reflect ? 56 : 0);
    String uci(String value) => reflect ? mineReflectMove(value) : value;
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.chess,
      List<CardId> hand = const [CardId.mine, CardId.purify, CardId.breakSeal],
    }) => minePosition(fen, reflect: reflect, phase: phase, hand: hand);

    cases.add(
      MineCase(
        '$prefix cast, friendly occupancy, capture entry, piece lifetime',
        () {
          final initial = position(mineCaptureFen, phase: BattlePhase.card);
          final rookId = initial.rules.pieceIds[sq('e2')]!;
          final bishopId = initial.rules.pieceIds[sq('g6')]!;
          var state = mineApply(
            initial,
            PlayCardAction(CardId.mine, target: sq('e4')),
          );
          mineEqual(state.rules.mana[side], 4, 'Mine costs exactly two');
          mineEqual(state.rules.used[side], [CardId.mine], 'one cast consumed');
          mineEqual(
            state.rules.fen,
            initial.rules.fen,
            'casting does not move chess',
          );
          mineEqual(state.rules.ply, 0, 'casting does not increment ply');
          mineEqual(
            state.rules.boardEffects.single.duration,
            EffectDuration.persistent,
            'dormant persistent lifetime',
          );
          mineRejects(state, PlayCardAction(CardId.mine, target: sq('f4')));
          state = mineMove(state, uci('e2e4'));
          mineEqual(
            state.rules.pieceIds[sq('e4')],
            rookId,
            'friendly arrival survives',
          );
          mineEqual(
            state.rules.boardEffects.length,
            1,
            'friendly arrival does not trigger',
          );
          state = mineMove(state, uci('g6e4'));
          mineRequire(
            !state.rules.pieceIds.contains(rookId),
            'trigger capture succeeds',
          );
          mineEqual(
            state.rules.pieceIds[sq('e4')],
            bishopId,
            'capturing piece is not destroyed',
          );
          mineRequire(state.rules.boardEffects.isEmpty, 'trap consumed once');
          mineFreshEffect(state, bishopId, side);
          state = mineMove(state, uci('b1a1'));
          mineFreshEffect(state, bishopId, side);
          final passed = mineApply(state, const PassAction());
          mineRejects(passed, ChessMoveAction(uci('e4d3')));
          state = mineMove(passed, uci('e4f5'));
          mineRequire(
            state.rules.pieceEffects.isEmpty,
            'affected quiet move consumes debuff',
          );
          mineEqual(state.rules.ply, 4, 'four chess moves, no extra turns');
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix pinned quiet move consumes old Mine and arms a fresh one',
        () {
          var state = minePieceEffect(
            position('2r5/7k/8/8/8/1pR5/8/2K5 w - - 11 17'),
            sq('c3'),
          );
          final identity = state.rules.pieceIds[sq('c3')]!;
          state = mineBoardEffect(state, sq('c4'), enemy);
          mineRejects(state, ChessMoveAction(uci('c3d3')));
          mineRejects(state, ChessMoveAction(uci('c3c8')));
          final after = mineMove(state, uci('c3c4'));
          mineEqual(
            after.rules.pieceIds[sq('c4')],
            identity,
            'same pinned identity',
          );
          mineRequire(
            !after.rules.pieceEffects.any((e) => e.id == 'v223-mine-old'),
            'old effect consumed',
          );
          mineFreshEffect(after, identity, enemy);
          mineRequire(after.rules.boardEffects.isEmpty, 'new trap consumed');
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix slider path crossing does not trigger, landing does',
        () {
          final base = position('6k1/8/8/8/8/8/3R4/1K6 w - - 4 40');
          final armed = mineBoardEffect(base, sq('d4'), enemy);
          final crossed = mineMove(armed, uci('d2d6'));
          mineEqual(
            crossed.rules.boardEffects.length,
            1,
            'crossed Mine persists',
          );
          mineRequire(
            crossed.rules.pieceEffects.isEmpty,
            'crossing is not arrival',
          );
          final landed = mineMove(armed, uci('d2d4'));
          mineRequire(
            landed.rules.boardEffects.isEmpty,
            'landing consumes Mine',
          );
          mineFreshEffect(landed, base.rules.pieceIds[sq('d2')]!, enemy);
        },
      ),
    );

    for (final rookSide in ['short', 'long']) {
      cases.add(
        MineCase('$prefix $rookSide castle applies Mine to rook, not king', () {
          final short = rookSide == 'short';
          final rookFrom = sq(short ? 'h1' : 'a1');
          final rookTo = sq(short ? 'f1' : 'd1');
          final kingTo = sq(short ? 'g1' : 'c1');
          var state = minePieceEffect(position(mineCastleFen), rookFrom);
          state = mineBoardEffect(state, rookTo, enemy);
          state = mineBoardEffect(
            state,
            kingTo,
            side,
            id: 'v223-friendly-king-mine',
          );
          final rookId = state.rules.pieceIds[rookFrom]!;
          final kingId = state.rules.pieceIds[sq('e1')]!;
          final after = mineMove(state, uci(short ? 'e1g1' : 'e1c1'));
          mineEqual(
            after.rules.pieceIds[rookTo],
            rookId,
            'rook identity relocated',
          );
          mineEqual(
            after.rules.pieceIds[kingTo],
            kingId,
            'king identity relocated',
          );
          mineFreshEffect(after, rookId, enemy);
          mineRequire(
            !after.rules.pieceEffects.any((e) => e.pieceId == kingId),
            'no king debuff',
          );
          mineEqual(
            after.rules.boardEffects.single.id,
            'v223-friendly-king-mine',
            'king-square Mine persists',
          );
          mineEqual(
            after.rules.board.castling & (side.isWhite ? 3 : 12),
            0,
            'both own castling rights removed',
          );
        }),
      );
    }

    cases.add(
      MineCase(
        '$prefix king landing and castle transit do not trigger Mine',
        () {
          final kingTrap = mineBoardEffect(
            position(mineCastleFen),
            sq('g1'),
            enemy,
          );
          final castled = mineMove(kingTrap, uci('e1g1'));
          mineEqual(
            castled.rules.boardEffects.length,
            1,
            'king destination ignored',
          );
          mineRequire(castled.rules.pieceEffects.isEmpty, 'king is immune');
          final transitTrap = mineBoardEffect(
            position(mineCastleFen),
            sq('c1'),
            enemy,
          );
          final long = mineMove(transitTrap, uci('e1c1'));
          mineEqual(
            long.rules.boardEffects.length,
            1,
            'king destination / rook transit ignored',
          );
          mineRequire(
            long.rules.pieceEffects.isEmpty,
            'rook ends on d1, not c1',
          );
        },
      ),
    );

    for (final promotion in ['q', 'r', 'b', 'n']) {
      cases.add(
        MineCase(
          '$prefix promotion $promotion retains fresh Mine across type change',
          () {
            var state = minePieceEffect(
              position('1k2r3/3P4/8/8/8/8/8/6K1 w - - 2 34'),
              sq('d7'),
            );
            state = mineBoardEffect(state, sq('d8'), enemy);
            final pawnId = state.rules.pieceIds[sq('d7')]!;
            mineRejects(state, ChessMoveAction(uci('d7e8$promotion')));
            final after = mineMove(state, uci('d7d8$promotion'));
            mineEqual(
              after.rules.pieceIds[sq('d8')],
              pawnId,
              'promotion keeps identity',
            );
            mineFreshEffect(after, pawnId, enemy);
            mineEqual(
              after.rules.board.pieceAt(sq('d8'))!.type,
              {
                'q': PieceType.queen,
                'r': PieceType.rook,
                'b': PieceType.bishop,
                'n': PieceType.knight,
              }[promotion],
              'correct promoted type',
            );
            mineEqual(
              after.rules.board.halfmoveClock,
              0,
              'promotion resets halfmove',
            );
          },
        ),
      );
    }

    cases.add(
      MineCase(
        '$prefix EP distinguishes arrival square from removed victim square',
        () {
          final base = position(
            '6k1/8/b7/1Pp5/8/8/8/6K1 w - c6 0 29',
            phase: BattlePhase.card,
          );
          final pawnId = base.rules.pieceIds[sq('b5')]!;
          var arrival = minePieceEffect(base, sq('b5'));
          arrival = mineBoardEffect(arrival, sq('c6'), enemy);
          final purified = mineApply(
            arrival,
            const PlayCardAction(CardId.purify, target: 'v223-mine-old'),
          );
          mineEqual(
            purified.rules.board.enPassant,
            sq('c6'),
            'Purify retains EP',
          );
          final after = mineMove(purified, uci('b5c6'));
          mineFreshEffect(after, pawnId, enemy);
          mineRequire(
            after.rules.board.pieceAt(sq('c5')) == null,
            'EP victim removed',
          );
          final victimTrap = mineBoardEffect(base, sq('c5'), enemy);
          final untouched = mineMove(victimTrap, uci('b5c6'));
          mineEqual(untouched.rules.boardEffects.single.squares, [
            sq('c5'),
          ], 'vacating captured pawn square is not an arrival');
          mineRequire(
            untouched.rules.pieceEffects.isEmpty,
            'victim-square Mine does not trigger',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix Purify cannot admit discovered-check EP or trigger its Mine',
        () {
          var state = minePieceEffect(
            position(
              '1r4k1/8/8/1Pp5/8/8/8/1K6 w - c6 0 31',
              phase: BattlePhase.card,
            ),
            sq('b5'),
          );
          state = mineBoardEffect(state, sq('c6'), enemy);
          final after = mineApply(
            state,
            const PlayCardAction(CardId.purify, target: 'v223-mine-old'),
          );
          mineRejects(after, ChessMoveAction(uci('b5c6')));
          mineEqual(
            after.rules.boardEffects.length,
            1,
            'rejected EP cannot detonate Mine',
          );
          mineRequire(
            mineMoves(after).contains(uci('b5b6')),
            'safe pinned quiet remains',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix Freeze response expiry does not expire a stationary Mine debuff',
        () {
          var state = minePieceEffect(
            position('6k1/8/8/8/3R4/8/8/1K6 w - - 10 48'),
            sq('d4'),
          );
          state = minePieceEffect(
            state,
            sq('d4'),
            id: 'v223-freeze',
            type: PieceEffectType.freeze,
            duration: EffectDuration.move,
          );
          mineRejects(state, ChessMoveAction(uci('d4d5')));
          final after = mineMove(state, uci('b1a1'));
          mineEqual(after.rules.pieceEffects.map((e) => e.id).toList(), [
            'v223-mine-old',
          ], 'only response-window Freeze expires');
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix Purify removes one Mine instance and preserves Chain',
        () {
          var state = minePieceEffect(
            position(
              '6k1/8/8/8/3Rp3/8/8/1K6 w - - 10 49',
              phase: BattlePhase.card,
            ),
            sq('d4'),
          );
          state = minePieceEffect(
            state,
            sq('d4'),
            id: 'v223-chain',
            type: PieceEffectType.chain,
            duration: EffectDuration.move,
          );
          final after = mineApply(
            state,
            const PlayCardAction(CardId.purify, target: 'v223-mine-old'),
          );
          mineEqual(
            after.rules.pieceEffects.single.id,
            'v223-chain',
            'Chain preserved',
          );
          mineRejects(after, ChessMoveAction(uci('d4e4')));
          mineRequire(
            mineMoves(after).contains(uci('d4d5')),
            'quiet remains legal',
          );
        },
      ),
    );

    cases.add(
      MineCase('$prefix Shelter and Fog do not suppress square-entry Mine', () {
        var state = position('6k1/8/8/8/8/8/3R4/1K6 w - - 4 50');
        state = mineBoardEffect(state, sq('d4'), enemy);
        state = minePieceEffect(
          state,
          sq('d2'),
          id: 'v223-shelter',
          type: PieceEffectType.shelter,
          duration: EffectDuration.card,
        );
        state = mineBoardEffect(
          state,
          sq('d4'),
          side,
          id: 'v223-friendly-fog',
          type: BoardEffectType.fog,
          duration: EffectDuration.card,
          squares: [sq('d4'), sq('e4'), sq('d5'), sq('e5')],
        );
        final rookId = state.rules.pieceIds[sq('d2')]!;
        final after = mineMove(state, uci('d2d4'));
        mineFreshEffect(after, rookId, enemy);
        mineRequire(
          after.rules.boardEffects.any((e) => e.id == 'v223-friendly-fog'),
          'friendly Fog remains until opposing card window',
        );
        mineRequire(
          after.rules.pieceEffects.any((e) => e.id == 'v223-shelter'),
          'Shelter does not cleanse newly triggered Mine',
        );
      }),
    );

    cases.add(
      MineCase(
        '$prefix locked-square overlap blocks arrival without consuming Mine',
        () {
          var state = position('6k1/8/8/8/8/8/3R4/1K6 w - - 4 51');
          state = mineBoardEffect(state, sq('d4'), enemy);
          state = mineBoardEffect(
            state,
            sq('d4'),
            enemy,
            id: 'v223-locked',
            type: BoardEffectType.lockedSquare,
            duration: EffectDuration.move,
          );
          mineRejects(state, ChessMoveAction(uci('d2d4')));
          final after = mineMove(state, uci('b1a1'));
          mineEqual(
            after.rules.boardEffects.single.type,
            BoardEffectType.mine,
            'restriction expires but dormant Mine persists',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix Break Seal removes dormant Mine only, not overlapping seal',
        () {
          var state = position(
            '6k1/8/8/8/8/8/3R4/1K6 w - - 4 52',
            phase: BattlePhase.card,
          );
          state = mineBoardEffect(state, sq('d4'), enemy);
          state = mineBoardEffect(
            state,
            sq('d4'),
            enemy,
            id: 'v223-zone',
            type: BoardEffectType.boardSeal,
            duration: EffectDuration.move,
            squares: [sq('d4'), sq('e4'), sq('d5'), sq('e5')],
          );
          final after = mineApply(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'v223-mine-board'),
          );
          mineEqual(
            after.rules.boardEffects.single.id,
            'v223-zone',
            'overlapping seal preserved',
          );
          mineRejects(after, ChessMoveAction(uci('d2d4')));
          mineRequire(
            after.rules.pieceEffects.isEmpty,
            'removal cannot create debuff',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix dormant Mine is public while opposing hand/deck stay private',
        () {
          final initial = position(mineCaptureFen, phase: BattlePhase.card);
          final cast = mineApply(
            initial,
            PlayCardAction(CardId.mine, target: sq('e4')),
          );
          final other = AuthoritativeBattleState(
            cast.rules,
            AuthoritativeHiddenState(
              hands: {
                side: cast.hidden.hands[side]!,
                enemy: cast.hidden.hands[enemy]!.reversed.toList(),
              },
              decks: {
                side: cast.hidden.decks[side]!,
                enemy: cast.hidden.decks[enemy]!.reversed.toList(),
              },
              knowledge: cast.hidden.knowledge,
            ),
          );
          mineEqual(
            cast.view(side).toJson(),
            other.view(side).toJson(),
            'enemy private order cannot change own view',
          );
          mineEqual(
            cast.view(side).rules.boardEffects.single.toJson(),
            cast.view(enemy).rules.boardEffects.single.toJson(),
            'Mine equally visible',
          );
          mineEqual(cast.view(side).toJson().keys.toList()..sort(), [
            'knowledge',
            'ownHand',
            'rules',
            'viewer',
          ], 'allowlisted player view');
        },
      ),
    );

    for (final reason in ['checkmate', 'stalemate']) {
      cases.add(
        MineCase(
          '$prefix Mine $reason is terminal, not a live empty chess phase',
          () {
            final mate = reason == 'checkmate';
            final fen =
                mate
                    ? '8/8/8/8/5N2/r7/5k2/7K b - - 12 43'
                    : '8/8/8/6r1/7n/5b1P/5k1K/8 b - - 6 45';
            final affected = sq(mate ? 'f4' : 'h3');
            final move = uci(mate ? 'a3h3' : 'g5g4');
            final base = position(fen);
            final unrestricted = mineMove(base, move);
            final expectedDefense = uci(mate ? 'f4h3' : 'h3g4');
            mineEqual(mineMoves(unrestricted).toList(), [
              expectedDefense,
            ], 'independent sole defense before Mine restriction');
            final state = minePieceEffect(base, affected);
            final after = mineMove(state, move);
            mineEqual(
              after.rules.phase,
              BattlePhase.terminal,
              'terminal phase',
            );
            mineEqual(
              after.rules.terminal!.reason,
              reason,
              'terminal classification',
            );
            mineEqual(
              after.rules.terminal!.winner,
              mate ? enemy : null,
              'winner',
            );
            mineEqual(
              after.rules.terminal!.mateByRestriction,
              mate,
              'mine mate attribution',
            );
            mineEqual(
              after.rules.terminal!.stalemateByRestriction,
              !mate,
              'mine stalemate attribution',
            );
            mineRequire(
              BattleRulesCore.legalActions(after.view(side)).isEmpty,
              'no actions after terminal',
            );
            mineRejects(after, const PassAction());
            mineRejects(after, PlayCardAction(CardId.mine, target: sq('a5')));
          },
        ),
      );
    }
  }
  return cases;
}

List<MineCase> mineBoundaryCases() {
  final cases = <MineCase>[];
  for (final reflect in [false, true]) {
    final side = reflect ? mineBlack : mineWhite, enemy = side.opposite;
    final prefix = sideWire(side);
    int sq(String value) => mineSquare(value) ^ (reflect ? 56 : 0);
    String uci(String value) => reflect ? mineReflectMove(value) : value;

    cases.add(
      MineCase(
        '$prefix target set excludes occupied squares and opposing Mine',
        () {
          var state = minePosition(
            mineCaptureFen,
            reflect: reflect,
            phase: BattlePhase.card,
          );
          state = mineBoardEffect(state, sq('f4'), enemy);
          final view = state.view(side),
              actions = BattleRulesCore.legalActions(state.view(side));
          final selection = BattleInteraction()..select(CardId.mine, actions);
          final expected = {
            for (var square = 0; square < 64; square++)
              if (state.rules.board.pieceAt(square) == null &&
                  square != sq('f4'))
                square,
          };
          mineEqual(
            selection.targets(view, actions).toList()..sort(),
            expected.toList()..sort(),
            'all and only unmined empty squares',
          );
          mineRequire(
            selection.tap(sq('e4'), view, actions).isEmpty,
            'selection alone does not cast',
          );
          mineEqual(
            selection.play!.target,
            sq('e4'),
            'explicit selected square',
          );
          final cast = mineApply(state, selection.play!);
          mineEqual(
            cast.rules.boardEffects.length,
            2,
            'one Mine for each owner',
          );
          mineEqual(
            cast.rules.boardEffects.where((e) => e.owner == enemy).single.id,
            'v223-mine-board',
            'enemy Mine not replaced',
          );
          mineRejects(state, PlayCardAction(CardId.mine, target: sq('f4')));
          mineRejects(state, PlayCardAction(CardId.mine, target: sq('e2')));
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix cast in check preserves the sole quiet rook interposition',
        () {
          var state = minePosition(
            '6r1/k7/8/8/4p3/8/4R3/6K1 w - - 8 21',
            reflect: reflect,
            phase: BattlePhase.card,
          );
          state = minePieceEffect(state, sq('e2'));
          final cast = mineApply(
            state,
            PlayCardAction(CardId.mine, target: sq('h4')),
          );
          final rookMoves =
              mineMoves(
                cast,
              ).where((m) => m.startsWith(Square.algebraic(sq('e2')))).toList();
          mineEqual(rookMoves, [
            uci('e2g2'),
          ], 'Mine cast does not cancel check');
          mineRejects(cast, ChessMoveAction(uci('e2e4')));
          final blocked = mineMove(cast, uci('e2g2'));
          mineRequire(
            blocked.rules.pieceEffects.isEmpty,
            'affected quiet defense consumes old Mine',
          );
          mineEqual(blocked.rules.boardEffects.single.squares, [
            sq('h4'),
          ], 'unrelated newly cast trap persists');
        },
      ),
    );

    for (final costCase in ['base', 'sabotage', 'discount', 'combined']) {
      cases.add(
        MineCase(
          '$prefix $costCase Mine cost is atomic and never paid twice',
          () {
            var state = minePosition(
              mineCaptureFen,
              reflect: reflect,
              phase: BattlePhase.card,
            );
            state = mineEdit(state, (draft) {
              draft.mana[side] = 4;
              if (costCase == 'sabotage' || costCase == 'combined') {
                draft.modifiers.add(
                  PendingModifier(
                    id: 'v223-mana-tax',
                    type: ModifierType.manaSabotage,
                    owner: enemy,
                    responseSide: side,
                    targetCard: CardId.mine,
                    ownTurn: 2,
                  ),
                );
              }
              if (costCase == 'discount' || costCase == 'combined') {
                draft.modifiers.add(
                  PendingModifier(
                    id: 'v223-discount',
                    type: ModifierType.discount,
                    owner: side,
                    responseSide: side,
                    targetCard: null,
                    ownTurn: 2,
                  ),
                );
              }
            });
            final expectedCost =
                costCase == 'base'
                    ? 2
                    : costCase == 'sabotage'
                    ? 3
                    : 1;
            mineEqual(
              BattleRulesCore.effectiveCost(state.rules, side, CardId.mine),
              expectedCost,
              'current contract cost',
            );
            final poor = mineEdit(
              state,
              (draft) => draft.mana[side] = expectedCost - 1,
            );
            final play = PlayCardAction(CardId.mine, target: sq('e4'));
            mineRejects(poor, play);
            final cast = mineApply(state, play);
            mineEqual(
              cast.rules.mana[side],
              4 - expectedCost,
              'one exact debit',
            );
            mineEqual(cast.rules.effectSequence, 1, 'one trap identity');
            mineEqual(cast.rules.used[side], [CardId.mine], 'one used entry');
            mineRejects(cast, play);
          },
        ),
      );
    }

    cases.add(
      MineCase(
        '$prefix blocked Mine can be discarded without clearing existing traps/debuffs',
        () {
          var state = minePosition(
            '6k1/8/8/8/3R4/8/8/1K6 w - - 10 48',
            reflect: reflect,
            phase: BattlePhase.card,
          );
          state = minePieceEffect(state, sq('d4'));
          state = mineBoardEffect(state, sq('e4'), enemy);
          state = mineEdit(state, (draft) {
            draft.mana[side] = 0;
            draft.modifiers.add(
              PendingModifier(
                id: 'v223-mine-block',
                type: ModifierType.cardBlock,
                owner: enemy,
                responseSide: side,
                targetCard: CardId.mine,
                ownTurn: 2,
              ),
            );
          });
          mineRejects(state, PlayCardAction(CardId.mine, target: sq('f4')));
          final discarded = mineApply(state, const DiscardAction(CardId.mine));
          mineEqual(discarded.rules.mana[side], 0, 'discard is free');
          mineEqual(discarded.rules.discarded[side], [
            CardId.mine,
          ], 'permanent discard');
          mineEqual(
            discarded.rules.boardEffects.single.id,
            'v223-mine-board',
            'trap persists',
          );
          mineEqual(
            discarded.rules.pieceEffects.single.id,
            'v223-mine-old',
            'debuff persists',
          );
          final moved = mineMove(discarded, uci('b1a1'));
          mineEqual(
            moved.rules.pieceEffects.single.id,
            'v223-mine-old',
            'different-piece chess continuation does not consume Mine',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix pending private ordering cannot detonate or consume Mine',
        () {
          var state = minePosition(
            '6k1/8/8/8/3R4/8/8/1K6 w - - 10 53',
            reflect: reflect,
            phase: BattlePhase.card,
            hand: [CardId.prophecy, CardId.purify, CardId.mine],
          );
          state = minePieceEffect(state, sq('d4'));
          state = mineBoardEffect(state, sq('e4'), enemy);
          final pending = mineApply(
            state,
            const PlayCardAction(CardId.prophecy),
          );
          mineEqual(
            pending.rules.phase,
            BattlePhase.pending,
            'requires private order',
          );
          mineRejects(pending, PlayCardAction(CardId.mine, target: sq('f4')));
          mineRejects(pending, ChessMoveAction(uci('d4e4')));
          final order =
              pending.hidden.knowledge[side]!.pendingCards.reversed.toList();
          final resolved = mineApply(pending, ResolveAction(order));
          mineEqual(
            resolved.rules.pieceEffects.single.id,
            'v223-mine-old',
            'resolution is not affected-piece movement',
          );
          mineEqual(
            resolved.rules.boardEffects.single.id,
            'v223-mine-board',
            'resolution is not arrival',
          );
          mineEqual(
            resolved.rules.phase,
            BattlePhase.chess,
            'continues to chess',
          );
          mineEqual(
            mineMove(resolved, uci('b1a1')).rules.pieceEffects.single.id,
            'v223-mine-old',
            'other-piece continuation retains debuff',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix special capture can trigger a fresh Mine, not retroactively forbid capture',
        () {
          var state = minePosition(
            '1k6/8/8/2p5/1BN5/8/8/6K1 w - - 0 57',
            reflect: reflect,
            phase: BattlePhase.card,
            hand: [CardId.angryN, CardId.purify, CardId.mine],
          );
          state = mineBoardEffect(state, sq('c5'), enemy);
          final knightId = state.rules.pieceIds[sq('c4')]!;
          final victimId = state.rules.pieceIds[sq('c5')]!;
          final authorized = mineApply(
            state,
            PlayCardAction(CardId.angryN, target: sq('c4')),
          );
          final after = mineMove(authorized, uci('c4c5'));
          mineRequire(
            !after.rules.pieceIds.contains(victimId),
            'special capture completes',
          );
          mineFreshEffect(after, knightId, enemy);
          mineEqual(
            after.rules.special,
            null,
            'special authorization consumed',
          );
          mineRequire(
            after.rules.boardEffects.isEmpty,
            'fresh Mine consumed exactly once',
          );
        },
      ),
    );

    cases.add(
      MineCase(
        '$prefix capturing the affected identity clears only its Mine debuff',
        () {
          var state = minePosition(
            mineCaptureFen,
            reflect: reflect,
            phase: BattlePhase.card,
          );
          state = mineApply(
            state,
            PlayCardAction(CardId.mine, target: sq('e4')),
          );
          state = mineMove(state, uci('e2e4'));
          state = mineMove(state, uci('g6e4'));
          final bishopId = state.rules.pieceIds[sq('e4')]!;
          mineFreshEffect(state, bishopId, side);
          final captured = mineMove(state, uci('d3e4'));
          mineRequire(
            !captured.rules.pieceIds.contains(bishopId),
            'affected identity captured',
          );
          mineRequire(
            captured.rules.pieceEffects.isEmpty,
            'orphan Mine debuff removed',
          );
          mineRequire(
            captured.rules.boardEffects.isEmpty,
            'triggered trap cannot resurrect',
          );
          mineEqual(
            captured.rules.board.pieceAt(sq('e4'))!.type,
            PieceType.pawn,
            'ordinary capturing pawn survives',
          );
        },
      ),
    );
  }
  return cases;
}
