import 'dart:convert';

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

int lockedSquareIndex(String square) {
  if (!RegExp(r'^[a-h][1-8]$').hasMatch(square)) {
    throw ArgumentError.value(square, 'square');
  }
  return square.codeUnitAt(0) - 97 + 8 * (square.codeUnitAt(1) - 49);
}

String lockedSquareText(int square) =>
    '${String.fromCharCode(97 + square % 8)}${square ~/ 8 + 1}';

int lockedSquareReflect(int square) => square ^ 56;

String lockedSquareReflectMove(String uci) =>
    '${lockedSquareText(lockedSquareReflect(lockedSquareIndex(uci.substring(0, 2))))}'
    '${lockedSquareText(lockedSquareReflect(lockedSquareIndex(uci.substring(2, 4))))}'
    '${uci.length == 5 ? uci[4] : ''}';

Board _reflectBoard(Board board) => Board(
  squares: [
    for (var square = 0; square < 64; square++)
      board.squares[lockedSquareReflect(square)]?.copyWith(
        color: board.squares[lockedSquareReflect(square)]!.color.opposite,
      ),
  ],
  turn: board.turn.opposite,
  castling: ((board.castling & 3) << 2) | ((board.castling & 12) >> 2),
  enPassant:
      board.enPassant == null ? null : lockedSquareReflect(board.enPassant!),
  halfmoveClock: board.halfmoveClock,
  fullmoveNumber: board.fullmoveNumber,
);

List<CardId> _deck(List<CardId> hand) {
  if (hand.length != 3 || hand.toSet().length != 3) {
    throw ArgumentError('Locked Square fixtures need three unique hand cards');
  }
  return [
    ...hand,
    ...CardId.values.where((card) => !hand.contains(card)).take(7),
  ];
}

AuthoritativeBattleState lockedSquarePosition(
  String fen, {
  bool reflect = false,
  BattlePhase phase = BattlePhase.chess,
  List<CardId> whiteHand = const [
    CardId.lockedSquare,
    CardId.breakSeal,
    CardId.purify,
  ],
  List<CardId> blackHand = const [
    CardId.lockedSquare,
    CardId.breakSeal,
    CardId.purify,
  ],
}) {
  final board = Board.fromFen(fen);
  final initial = DeckManager.newBattle(
    board: reflect ? _reflectBoard(board) : board,
    white: _deck(reflect ? blackHand : whiteHand),
    black: _deck(reflect ? whiteHand : blackHand),
  );
  if (initial.rules.terminal != null) {
    throw ArgumentError('Unexpected terminal Locked Square fixture: $fen');
  }
  return lockedSquareEdit(initial, (draft) {
    draft.phase = phase;
    draft.ownTurns = {PieceColor.white: 2, PieceColor.black: 2};
    draft.mana = {PieceColor.white: 6, PieceColor.black: 6};
    draft.effectSequence = 100;
    draft.repetitions = {};
  });
}

AuthoritativeBattleState lockedSquareEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

BoardEffectInstance lockedSquareEffect(
  String id,
  List<int> squares,
  PieceColor owner, {
  BoardEffectType type = BoardEffectType.lockedSquare,
  EffectDuration duration = EffectDuration.move,
  PieceColor? responseSide,
}) => BoardEffectInstance(
  id: id,
  type: type,
  owner: owner,
  squares: squares,
  responseSide: responseSide ?? owner.opposite,
  duration: duration,
);

AuthoritativeBattleState lockedSquareOn(
  AuthoritativeBattleState state,
  int square, {
  String id = 'v223-lock',
  PieceColor? owner,
}) => lockedSquareEdit(state, (draft) {
  draft.boardEffects.add(
    lockedSquareEffect(id, [square], owner ?? state.rules.board.turn.opposite),
  );
});

String lockedSquareEncoded(Object? value) => jsonEncode(
  value,
  toEncodable: (object) {
    if (object is Enum) return '${object.runtimeType}.${object.name}';
    throw ArgumentError.value(object, 'object');
  },
);

void lockedSquareRequire(bool value, String message) {
  if (!value) throw StateError('V223 Locked Square: $message');
}

void lockedSquareEqual(Object? actual, Object? expected, String message) {
  lockedSquareRequire(
    lockedSquareEncoded(actual) == lockedSquareEncoded(expected),
    '$message; expected=$expected; actual=$actual',
  );
}

Set<String> lockedSquareMoves(AuthoritativeBattleState state, {int? from}) =>
    BattleRulesCore.legalMoves(
          state.rules,
          state.rules.board.turn,
          authorization: state.rules.special,
        )
        .where((move) => from == null || move.from == from)
        .map((m) => m.uci)
        .toSet();

void lockedSquareExpectMoves(
  AuthoritativeBattleState state,
  Iterable<String> expected, {
  int? from,
  String context = '',
}) {
  final actual = lockedSquareMoves(state, from: from).toList()..sort();
  final wanted = expected.toList()..sort();
  lockedSquareEqual(actual, wanted, '$context complete move set from $from');
}

void lockedSquareRejects(AuthoritativeBattleState state, BattleAction action) {
  final before = lockedSquareEncoded(state.toJson());
  final view = state.view(state.rules.board.turn);
  lockedSquareRequire(
    !BattleRulesCore.isLegalAction(view, action),
    'illegal request admitted: ${action.toJson()}',
  );
  for (final apply in <void Function()>[
    () {
      BattleRulesCore.transition(view, action);
    },
    () {
      DeckManager.apply(state, action);
    },
  ]) {
    var rejected = false;
    try {
      apply();
    } on StateError catch (error) {
      rejected = error.message == 'illegal-action';
    }
    lockedSquareRequire(rejected, 'must reject ${action.toJson()} atomically');
    lockedSquareEqual(
      lockedSquareEncoded(state.toJson()),
      before,
      'rejected request changed the authoritative input',
    );
  }
}

AuthoritativeBattleState lockedSquareRoundTrip(
  AuthoritativeBattleState state,
) => AuthoritativeBattleState.fromJson(
  jsonDecode(jsonEncode(state.toJson())) as Map,
);

class LockedSquareAuditCase {
  final String name;
  final void Function() run;
  const LockedSquareAuditCase(this.name, this.run);
}

class _MovementReference {
  final String name, fen, from;
  final List<String> destinations;
  final bool king;
  const _MovementReference(
    this.name,
    this.fen,
    this.from,
    this.destinations, {
    this.king = false,
  });
}

// These sets are hand-enumerated board geometry, not MoveGen/core output.
const _references = [
  _MovementReference('rook', '8/7k/8/8/3R4/8/8/K7 w - - 0 31', 'd4', [
    'a4',
    'b4',
    'c4',
    'e4',
    'f4',
    'g4',
    'h4',
    'd1',
    'd2',
    'd3',
    'd5',
    'd6',
    'd7',
    'd8',
  ]),
  _MovementReference('bishop', '8/7k/8/8/3B4/8/8/K7 w - - 0 31', 'd4', [
    'c3',
    'b2',
    'e3',
    'f2',
    'g1',
    'c5',
    'b6',
    'a7',
    'e5',
    'f6',
    'g7',
    'h8',
  ]),
  _MovementReference('queen', '8/7k/8/8/3Q4/8/8/K7 w - - 0 31', 'd4', [
    'a4',
    'b4',
    'c4',
    'e4',
    'f4',
    'g4',
    'h4',
    'd1',
    'd2',
    'd3',
    'd5',
    'd6',
    'd7',
    'd8',
    'c3',
    'b2',
    'e3',
    'f2',
    'g1',
    'c5',
    'b6',
    'a7',
    'e5',
    'f6',
    'g7',
    'h8',
  ]),
  _MovementReference('knight', '8/7k/8/8/3N4/8/8/K7 w - - 0 31', 'd4', [
    'b3',
    'b5',
    'c2',
    'c6',
    'e2',
    'e6',
    'f3',
    'f5',
  ]),
  _MovementReference('pawn', '8/7k/8/8/3P4/8/8/K7 w - - 0 31', 'd4', ['d5']),
  _MovementReference('king', '8/7k/8/8/3K4/8/8/8 w - - 0 31', 'd4', [
    'c3',
    'd3',
    'e3',
    'c4',
    'e4',
    'c5',
    'd5',
    'e5',
  ], king: true),
];

List<LockedSquareAuditCase> lockedSquareCoreCases() {
  final cases = <LockedSquareAuditCase>[];
  for (final reflect in [false, true]) {
    final side = reflect ? PieceColor.black : PieceColor.white;
    final enemy = side.opposite;
    final label = side.name;
    int square(String value) => lockedSquareIndex(value) ^ (reflect ? 56 : 0);
    String move(String value) =>
        reflect ? lockedSquareReflectMove(value) : value;
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.chess,
      List<CardId> hand = const [
        CardId.lockedSquare,
        CardId.breakSeal,
        CardId.purify,
      ],
    }) => lockedSquarePosition(
      fen,
      reflect: reflect,
      phase: phase,
      whiteHand: hand,
    );

    for (final reference in _references) {
      cases.add(
        LockedSquareAuditCase(
          '$label ${reference.name}: all 64 own/enemy lock locations',
          () {
            final initial = position(reference.fen);
            final from = square(reference.from);
            final base =
                reference.destinations
                    .map((to) => move('${reference.from}$to'))
                    .toSet();
            lockedSquareExpectMoves(initial, base, from: from);
            for (var target = 0; target < 64; target++) {
              for (final owner in [side, enemy]) {
                final state = lockedSquareOn(initial, target, owner: owner);
                final expected = base.where(
                  (uci) =>
                      reference.king ||
                      owner == side ||
                      lockedSquareIndex(uci.substring(2, 4)) != target,
                );
                lockedSquareExpectMoves(
                  state,
                  expected,
                  from: from,
                  context:
                      '$label ${reference.name} owner=$owner target=$target',
                );
              }
            }
          },
        ),
      );
    }

    cases.add(
      LockedSquareAuditCase('$label all empty targets and edges cast once', () {
        final initial = position(
          '8/7k/8/8/3R4/8/8/K7 w - - 0 31',
          phase: BattlePhase.card,
        );
        final occupied = {square('a1'), square('d4'), square('h7')};
        final expected = [
          for (var i = 0; i < 64; i++)
            if (!occupied.contains(i)) i,
        ];
        lockedSquareEqual(
          BattleRulesCore.cardTargets(initial.view(side), CardId.lockedSquare),
          expected,
          'all 61 empty squares, including edges and corners, are targets',
        );
        final plays =
            BattleRulesCore.legalActions(initial.view(side))
                .whereType<PlayCardAction>()
                .where((a) => a.card == CardId.lockedSquare)
                .toList();
        lockedSquareEqual(plays.length, 61, 'one play per empty target');
        final before = lockedSquareEncoded(initial.toJson());
        for (final target in expected) {
          final action = PlayCardAction(CardId.lockedSquare, target: target);
          final after = DeckManager.apply(initial, action);
          lockedSquareEqual(after.rules.boardEffects.single.toJson(), {
            'id': 'e101',
            'type': 'locked_square',
            'owner': sideWire(side),
            'squares': [target],
            'responseSide': sideWire(enemy),
            'duration': 'move',
          }, 'exact new lock metadata');
          lockedSquareEqual(after.rules.mana[side], 4, 'cost is two');
          lockedSquareEqual(after.rules.handCounts[side], 2, 'one card spent');
          lockedSquareEqual(after.rules.used[side], [
            CardId.lockedSquare,
          ], 'used once');
          lockedSquareEqual(
            after.rules.phase,
            BattlePhase.chess,
            'card window closed',
          );
          lockedSquareEqual(
            after.rules.fen,
            initial.rules.fen,
            'cast never moves a piece',
          );
          lockedSquareEqual(after.rules.ply, 0, 'cast is not a chess ply');
          lockedSquareEqual(
            after.rules.effectSequence,
            101,
            'one fresh effect id',
          );
          for (final color in PieceColor.values) {
            lockedSquareEqual(
              after.hidden.decks[color],
              initial.hidden.decks[color],
              'no cast-time draw',
            );
          }
          lockedSquareEqual(
            lockedSquareEncoded(lockedSquareRoundTrip(after).toJson()),
            lockedSquareEncoded(after.toJson()),
            'cast survives JSON round trip',
          );
          lockedSquareRejects(after, action);
          lockedSquareEqual(
            lockedSquareEncoded(initial.toJson()),
            before,
            'cast input immutable',
          );
        }
        for (final target in occupied) {
          lockedSquareRejects(
            initial,
            PlayCardAction(CardId.lockedSquare, target: target),
          );
        }
      }),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label malformed targets cannot alias integer action keys',
        () {
          final state = position(
            '7k/8/8/8/8/8/8/K7 w - - 0 32',
            phase: BattlePhase.card,
          );
          final valid = square('d4');
          final targets = <Object?>[
            null,
            -1,
            64,
            1000000,
            valid + .5,
            '$valid',
            'd4',
            '',
            true,
            false,
            [valid],
            {'square': valid},
            double.nan,
            double.infinity,
            -double.infinity,
          ];
          for (final target in targets) {
            lockedSquareRejects(
              state,
              PlayCardAction(CardId.lockedSquare, target: target),
            );
            lockedSquareRejects(
              state,
              BattleAction.fromJson({
                'type': 'play',
                'card': 'locked_square',
                'target': target,
              }),
            );
          }
          lockedSquareRejects(
            state,
            PlayCardAction(CardId.lockedSquare, target: valid.toDouble()),
          );
          lockedSquareRejects(
            state,
            PlayCardAction(
              CardId.lockedSquare,
              target: valid,
              sacrifice: CardId.purify,
            ),
          );
          final integer = BattleAction.fromJson({
            'type': 'play',
            'card': 'locked_square',
            'target': valid,
            'ignoredClientField': [1, 2, 3],
          });
          final after = DeckManager.apply(state, integer);
          lockedSquareEqual(after.rules.boardEffects.single.squares, [
            valid,
          ], 'integer wire action accepted');
          lockedSquareEqual(
            after.rules.boardEffects.length,
            1,
            'unknown field cannot add effects',
          );
          final before = lockedSquareEncoded(state.toJson());
          final expected =
              DeckManager.apply(
                state,
                PlayCardAction(CardId.lockedSquare, target: valid),
              ).toJson();
          lockedSquareEqual(
            after.toJson(),
            expected,
            'integer wire action preserves the complete typed integer state',
          );
          for (final number in ['$valid', '$valid.0', '${valid}e0']) {
            final parsed = BattleAction.fromJson(
              jsonDecode(
                    '{"type":"play","card":"locked_square","target":$number}',
                  )
                  as Map,
            );
            lockedSquareRequire(
              (parsed as PlayCardAction).target is int,
              'whole JSON number normalizes to an integer target',
            );
            lockedSquareEqual(
              DeckManager.apply(state, parsed).toJson(),
              expected,
              'equivalent JSON integer spelling preserves the complete lock state',
            );
            lockedSquareEqual(
              lockedSquareEncoded(state.toJson()),
              before,
              'accepted wire action changed the authoritative input',
            );
          }
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label mana, first-turn, phase and hidden-hand admission',
        () {
          final initial = position(
            '7k/8/8/8/8/8/8/K7 w - - 0 33',
            phase: BattlePhase.card,
          );
          final action = PlayCardAction(
            CardId.lockedSquare,
            target: square('d4'),
          );
          for (final mana in [0, 1]) {
            lockedSquareRejects(
              lockedSquareEdit(initial, (d) => d.mana[side] = mana),
              action,
            );
          }
          final exact = DeckManager.apply(
            lockedSquareEdit(initial, (d) => d.mana[side] = 2),
            action,
          );
          lockedSquareEqual(
            exact.rules.mana[side],
            0,
            'exact mana is sufficient',
          );
          lockedSquareRejects(
            lockedSquareEdit(initial, (d) => d.ownTurns[side] = 1),
            action,
          );
          lockedSquareRejects(
            lockedSquareEdit(initial, (d) => d.phase = BattlePhase.chess),
            action,
          );
          lockedSquareRejects(
            lockedSquareEdit(initial, (d) {
              d.phase = BattlePhase.terminal;
              d.terminal = TerminalState('checkmate', winner: enemy);
            }),
            action,
          );
          final unavailable = position(
            '7k/8/8/8/8/8/8/K7 w - - 0 33',
            phase: BattlePhase.card,
            hand: const [CardId.radar, CardId.breakSeal, CardId.purify],
          );
          lockedSquareRejects(unavailable, action);
          final otherView = initial.view(enemy);
          lockedSquareEqual(
            BattleRulesCore.legalActions(otherView),
            [],
            'off-turn player has no actions',
          );
          var rejected = false;
          try {
            BattleRulesCore.transition(otherView, action);
          } on StateError catch (error) {
            rejected = error.message == 'illegal-action';
          }
          lockedSquareRequire(rejected, 'off-turn cast must be rejected');
          final pending = DeckManager.apply(
            position(
              '7k/8/8/8/8/8/8/K7 w - - 0 33',
              phase: BattlePhase.card,
              hand: const [CardId.lockedSquare, CardId.prophecy, CardId.radar],
            ),
            const PlayCardAction(CardId.prophecy),
          );
          lockedSquareRejects(pending, action);
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label pawn double may cross but not land on a lock',
        () {
          final initial = position('7k/8/8/8/8/8/4P3/K7 w - - 0 34');
          lockedSquareExpectMoves(initial, [
            move('e2e3'),
            move('e2e4'),
          ], from: square('e2'));
          final intermediate = lockedSquareOn(initial, square('e3'));
          lockedSquareExpectMoves(intermediate, [
            move('e2e4'),
          ], from: square('e2'));
          final destination = lockedSquareOn(initial, square('e4'));
          lockedSquareExpectMoves(destination, [
            move('e2e3'),
          ], from: square('e2'));
          lockedSquareRejects(destination, ChessMoveAction(move('e2e4')));
          final after = DeckManager.apply(
            intermediate,
            ChessMoveAction(move('e2e4')),
          );
          lockedSquareEqual(
            after.rules.board.enPassant,
            square('e3'),
            'orthodox EP target is retained',
          );
          lockedSquareEqual(
            after.rules.boardEffects,
            [],
            'response move expires intermediate lock',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label en passant destination, victim and origin are distinct',
        () {
          final initial = position('7k/8/8/3pP3/8/8/8/K7 w - d6 0 35');
          lockedSquareExpectMoves(initial, [
            move('e5e6'),
            move('e5d6'),
          ], from: square('e5'));
          final blocked = lockedSquareOn(initial, square('d6'));
          lockedSquareExpectMoves(blocked, [move('e5e6')], from: square('e5'));
          lockedSquareRejects(blocked, ChessMoveAction(move('e5d6')));
          for (final target in ['d5', 'e5']) {
            final state = lockedSquareOn(initial, square(target));
            lockedSquareExpectMoves(state, [
              move('e5e6'),
              move('e5d6'),
            ], from: square('e5'));
            final mover = state.rules.pieceIds[square('e5')];
            final victim = state.rules.pieceIds[square('d5')];
            final after = DeckManager.apply(
              state,
              ChessMoveAction(move('e5d6')),
            );
            lockedSquareEqual(
              after.rules.pieceIds[square('d6')],
              mover,
              'EP mover id follows pawn',
            );
            lockedSquareEqual(
              after.rules.board.squares[square('d5')],
              null,
              'EP victim square emptied',
            );
            lockedSquareRequire(
              !after.rules.pieceIds.contains(victim),
              'EP victim identity removed',
            );
            lockedSquareEqual(
              after.rules.boardEffects,
              [],
              'lock expires on successful EP',
            );
            lockedSquareEqual(
              after.rules.board.enPassant,
              null,
              'EP rights consumed',
            );
          }
          final own = lockedSquareOn(initial, square('d6'), owner: side);
          lockedSquareExpectMoves(own, [
            move('e5e6'),
            move('e5d6'),
          ], from: square('e5'));
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label all four quiet/capture promotions respect destination occupancy',
        () {
          final initial = position('k6r/6P1/8/8/8/8/8/4K3 w - - 0 36');
          final quiet = [
            for (final suffix in ['q', 'r', 'b', 'n']) move('g7g8$suffix'),
          ];
          final captures = [
            for (final suffix in ['q', 'r', 'b', 'n']) move('g7h8$suffix'),
          ];
          lockedSquareExpectMoves(initial, [
            ...quiet,
            ...captures,
          ], from: square('g7'));
          final blocked = lockedSquareOn(initial, square('g8'));
          lockedSquareExpectMoves(blocked, captures, from: square('g7'));
          for (final uci in quiet) {
            lockedSquareRejects(blocked, ChessMoveAction(uci));
          }
          final captureLock = lockedSquareOn(
            blocked,
            square('h8'),
            id: 'capture-lock',
          );
          lockedSquareExpectMoves(captureLock, captures, from: square('g7'));
          final types = [
            PieceType.queen,
            PieceType.rook,
            PieceType.bishop,
            PieceType.knight,
          ];
          for (var index = 0; index < captures.length; index++) {
            final mover = initial.rules.pieceIds[square('g7')];
            final victim = initial.rules.pieceIds[square('h8')];
            final after = DeckManager.apply(
              captureLock,
              ChessMoveAction(captures[index]),
            );
            lockedSquareEqual(
              after.rules.board.squares[square('h8')]?.type,
              types[index],
              'promotion type',
            );
            lockedSquareEqual(
              after.rules.board.squares[square('h8')]?.color,
              side,
              'promotion color',
            );
            lockedSquareEqual(
              after.rules.pieceIds[square('h8')],
              mover,
              'promotion keeps mover identity',
            );
            lockedSquareRequire(
              !after.rules.pieceIds.contains(victim),
              'captured rook id removed',
            );
            lockedSquareEqual(
              after.rules.board.halfmoveClock,
              0,
              'capture/pawn resets clock',
            );
            lockedSquareEqual(
              after.rules.boardEffects,
              [],
              'all responding locks expire after promotion',
            );
          }
          final own = lockedSquareOn(initial, square('g8'), owner: side);
          lockedSquareExpectMoves(own, [
            ...quiet,
            ...captures,
          ], from: square('g7'));
        },
      ),
    );

    for (final capture in const [
      ('rook', '8/7k/3n4/8/3R4/8/8/K7 w - - 0 37', 'd4d6', PieceType.rook),
      ('bishop', '8/7k/5n2/8/3B4/8/8/K7 w - - 0 37', 'd4f6', PieceType.bishop),
      ('queen', '8/7k/8/8/1n1Q4/8/8/K7 w - - 0 37', 'd4b4', PieceType.queen),
      ('knight', '8/7k/8/5p2/3N4/8/8/K7 w - - 0 37', 'd4f5', PieceType.knight),
      ('pawn', '8/7k/8/2r5/3P4/8/8/K7 w - - 0 37', 'd4c5', PieceType.pawn),
      ('king', '7k/8/8/4r3/3K4/8/8/8 w - - 0 37', 'd4e5', PieceType.king),
    ]) {
      cases.add(
        LockedSquareAuditCase(
          '$label ${capture.$1} captures occupied locked destination',
          () {
            final from = square(capture.$3.substring(0, 2));
            final to = square(capture.$3.substring(2, 4));
            final state = lockedSquareOn(position(capture.$2), to);
            final mover = state.rules.pieceIds[from];
            final victim = state.rules.pieceIds[to];
            lockedSquareRequire(
              lockedSquareMoves(state).contains(move(capture.$3)),
              'fixed capture must be legal',
            );
            final before = lockedSquareEncoded(state.toJson());
            final after = DeckManager.apply(
              state,
              ChessMoveAction(move(capture.$3)),
            );
            lockedSquareEqual(
              after.rules.board.squares[to]?.type,
              capture.$4,
              'capturer type',
            );
            lockedSquareEqual(
              after.rules.board.squares[to]?.color,
              side,
              'capturer color',
            );
            lockedSquareEqual(
              after.rules.pieceIds[to],
              mover,
              'capturer identity',
            );
            lockedSquareEqual(
              after.rules.pieceIds[from],
              null,
              'origin vacated',
            );
            lockedSquareRequire(
              !after.rules.pieceIds.contains(victim),
              'victim identity removed',
            );
            lockedSquareEqual(
              after.rules.boardEffects,
              [],
              'capture consumes response window',
            );
            lockedSquareEqual(
              lockedSquareEncoded(state.toJson()),
              before,
              'successful capture input immutable',
            );
          },
        ),
      );
    }

    cases.add(
      LockedSquareAuditCase(
        '$label friendly occupancy is not a capture exception or a ghost wall',
        () {
          final state = lockedSquareOn(
            position('8/7k/3N4/8/3R4/8/8/K7 w - - 0 38'),
            square('d6'),
          );
          lockedSquareExpectMoves(state, [
            for (final to in [
              'a4',
              'b4',
              'c4',
              'e4',
              'f4',
              'g4',
              'h4',
              'd1',
              'd2',
              'd3',
              'd5',
            ])
              move('d4$to'),
          ], from: square('d4'));
          lockedSquareRejects(state, ChessMoveAction(move('d4d6')));
          lockedSquareRejects(state, ChessMoveAction(move('d4d7')));
          final occupiedEnemy = lockedSquareOn(
            position('8/7k/3n4/8/3R4/8/8/K7 w - - 0 38'),
            square('d5'),
          );
          lockedSquareExpectMoves(occupiedEnemy, [
            for (final to in [
              'a4',
              'b4',
              'c4',
              'e4',
              'f4',
              'g4',
              'h4',
              'd1',
              'd2',
              'd3',
              'd6',
            ])
              move('d4$to'),
          ], from: square('d4'));
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label a real cast can be filled by its owner then captured',
        () {
          final initial = position(
            '3r3k/8/8/8/3R4/8/8/K7 w - - 0 39',
            phase: BattlePhase.card,
          );
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('d5')),
          );
          final ownerMove = DeckManager.apply(
            cast,
            ChessMoveAction(move('d4d5')),
          );
          lockedSquareEqual(ownerMove.rules.boardEffects.single.squares, [
            square('d5'),
          ], 'owner move does not expire lock');
          lockedSquareEqual(
            ownerMove.rules.boardEffects.single.responseSide,
            enemy,
            'response still belongs to opponent',
          );
          final response = DeckManager.apply(ownerMove, const PassAction());
          lockedSquareRequire(
            lockedSquareMoves(response).contains(move('d8d5')),
            'occupied lock permits real opponent capture',
          );
          final after = DeckManager.apply(
            response,
            ChessMoveAction(move('d8d5')),
          );
          lockedSquareEqual(
            after.rules.board.squares[square('d5')]?.color,
            enemy,
            'opponent takes owner on lock',
          );
          lockedSquareEqual(
            after.rules.boardEffects,
            [],
            'completed response expires lock',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label pass/discard/play/pending/resolve do not expire move lock',
        () {
          final initial = lockedSquarePosition(
            '6nk/8/8/8/8/8/8/KN6 w - - 0 40',
            reflect: reflect,
            phase: BattlePhase.card,
            blackHand: const [CardId.prophecy, CardId.radar, CardId.purify],
          );
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('f6')),
          );
          final ownerMove = DeckManager.apply(
            cast,
            ChessMoveAction(move('b1c3')),
          );
          final expectedEffect = cast.rules.boardEffects.single.toJson();
          for (final action in <BattleAction>[
            const PassAction(),
            const DiscardAction(CardId.radar),
            const PlayCardAction(CardId.radar, target: 'purify'),
            const PlayCardAction(CardId.prophecy),
          ]) {
            var response = DeckManager.apply(ownerMove, action);
            lockedSquareEqual(
              response.rules.boardEffects.single.toJson(),
              expectedEffect,
              'card response preserves move lock',
            );
            if (action is PlayCardAction && action.card == CardId.prophecy) {
              lockedSquareEqual(
                response.rules.phase,
                BattlePhase.pending,
                'real pending window',
              );
              lockedSquareEqual(
                response.hidden.knowledge[enemy]!.pendingCards,
                [CardId.shelter, CardId.chain],
                'independent explicit deck prefix',
              );
              lockedSquareRejects(response, ChessMoveAction(move('g8h6')));
              response = DeckManager.apply(
                response,
                ResolveAction(const [CardId.shelter, CardId.chain]),
              );
              lockedSquareEqual(
                response.rules.boardEffects.single.toJson(),
                expectedEffect,
                'resolve preserves move lock',
              );
            }
            lockedSquareExpectMoves(response, [
              move('g8h6'),
              move('g8e7'),
            ], from: square('g8'));
            lockedSquareRejects(response, ChessMoveAction(move('g8f6')));
            lockedSquareEqual(
              response.rules.boardEffects.single.toJson(),
              expectedEffect,
              'rejected move does not tick expiry',
            );
            final after = DeckManager.apply(
              response,
              ChessMoveAction(move('g8h6')),
            );
            lockedSquareEqual(
              after.rules.boardEffects,
              [],
              'unrelated completed chess move ends lock',
            );
          }
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label alternating real locks on one square have separate windows',
        () {
          final initial = position(
            '6nk/8/8/8/8/8/8/KN6 w - - 0 41',
            phase: BattlePhase.card,
          );
          var state = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('d5')),
          );
          state = DeckManager.apply(state, ChessMoveAction(move('b1c3')));
          state = DeckManager.apply(
            state,
            PlayCardAction(CardId.lockedSquare, target: square('d5')),
          );
          lockedSquareEqual(
            state.rules.boardEffects.map((e) => e.id).toList(),
            ['e101', 'e102'],
            'overlap creates distinct ids',
          );
          state = DeckManager.apply(state, ChessMoveAction(move('g8f6')));
          lockedSquareEqual(
            state.rules.boardEffects.map((e) => e.id).toList(),
            ['e102'],
            'only first response window expires',
          );
          lockedSquareEqual(
            state.rules.boardEffects.single.owner,
            enemy,
            'second caster owns surviving lock',
          );
          state = DeckManager.apply(state, const PassAction());
          lockedSquareRejects(state, ChessMoveAction(move('c3d5')));
          state = DeckManager.apply(state, ChessMoveAction(move('a1a2')));
          lockedSquareEqual(
            state.rules.boardEffects,
            [],
            'second lock expires after its response',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label all four castles distinguish king/path from rook destination',
        () {
          final initial = position('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 42');
          for (var target = 0; target < 64; target++) {
            for (final owner in [side, enemy]) {
              final state = lockedSquareOn(initial, target, owner: owner);
              final moves = lockedSquareMoves(state);
              lockedSquareEqual(
                moves.contains(move('e1g1')),
                owner == side || target != square('f1'),
                'kingside rook destination target=$target owner=$owner',
              );
              lockedSquareEqual(
                moves.contains(move('e1c1')),
                owner == side || target != square('d1'),
                'queenside rook destination target=$target owner=$owner',
              );
            }
          }
          for (final castle in [
            ('e1g1', 'h1', 'f1', 'g1'),
            ('e1c1', 'a1', 'd1', 'c1'),
          ]) {
            final state = lockedSquareOn(initial, square(castle.$4));
            final rookId = state.rules.pieceIds[square(castle.$2)];
            final kingId = state.rules.pieceIds[square('e1')];
            final after = DeckManager.apply(
              state,
              ChessMoveAction(move(castle.$1)),
            );
            lockedSquareEqual(
              after.rules.pieceIds[square(castle.$3)],
              rookId,
              'castling rook id relocated',
            );
            lockedSquareEqual(
              after.rules.pieceIds[square(castle.$4)],
              kingId,
              'castling king id relocated',
            );
            lockedSquareEqual(
              after.rules.board.squares[square(castle.$3)]?.type,
              PieceType.rook,
              'rook relocated',
            );
            lockedSquareEqual(
              after.rules.board.squares[square(castle.$4)]?.type,
              PieceType.king,
              'king relocated',
            );
            lockedSquareEqual(
              after.rules.board.castling,
              0,
              'both castling rights consumed',
            );
            lockedSquareEqual(
              after.rules.boardEffects,
              [],
              'castling completes response window',
            );
            lockedSquareEqual(
              after.rules.board.enPassant,
              null,
              'castling has no EP right',
            );
          }
          for (final castle in [('e1g1', 'f1'), ('e1c1', 'd1')]) {
            lockedSquareRejects(
              lockedSquareOn(initial, square(castle.$2)),
              ChessMoveAction(move(castle.$1)),
            );
          }
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label a locked ray never shields a king or licenses castling through attack',
        () {
          final check = position('k3r3/8/8/8/8/8/8/4K3 w - - 0 43');
          for (final target in ['e2', 'e4', 'd1']) {
            for (final owner in [side, enemy]) {
              final state = lockedSquareOn(check, square(target), owner: owner);
              lockedSquareExpectMoves(state, [
                move('e1d1'),
                move('e1f1'),
                move('e1d2'),
                move('e1f2'),
              ], from: square('e1'));
              lockedSquareRejects(state, ChessMoveAction(move('e1e2')));
            }
          }
          final castle = position('4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 43');
          for (final owner in [side, enemy]) {
            final state = lockedSquareOn(castle, square('g1'), owner: owner);
            lockedSquareRejects(state, ChessMoveAction(move('e1g1')));
            lockedSquareRequire(
              lockedSquareMoves(state).contains(move('e1c1')),
              'unattacked opposite castle survives',
            );
          }
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label pins, interposition, capture and EP safety remain orthodox',
        () {
          final pinned = lockedSquareOn(
            position('k3r3/8/8/8/8/8/4R3/4K3 w - - 0 44'),
            square('e3'),
          );
          lockedSquareExpectMoves(pinned, [
            for (final rank in ['4', '5', '6', '7', '8']) move('e2e$rank'),
          ], from: square('e2'));
          lockedSquareRejects(pinned, ChessMoveAction(move('e2f2')));
          final interpose = position('k3r3/8/8/8/8/2B5/8/4K3 w - - 0 44');
          lockedSquareExpectMoves(interpose, [
            move('c3e5'),
          ], from: square('c3'));
          lockedSquareExpectMoves(lockedSquareOn(interpose, square('d4')), [
            move('c3e5'),
          ], from: square('c3'));
          lockedSquareExpectMoves(
            lockedSquareOn(interpose, square('e5')),
            [],
            from: square('c3'),
          );
          final captureChecker = lockedSquareOn(
            position('k3r3/8/8/1B6/8/8/8/4K3 w - - 0 44'),
            square('e2'),
          );
          lockedSquareExpectMoves(captureChecker, [
            move('b5e8'),
          ], from: square('b5'));
          final unsafeEp = position('k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 44');
          for (final owner in [side, enemy]) {
            lockedSquareRejects(
              lockedSquareOn(unsafeEp, square('d6'), owner: owner),
              ChessMoveAction(move('e5d6')),
            );
          }
          final unsafePromotion = lockedSquareOn(
            position('k5rn/6P1/8/8/8/8/8/6K1 w - - 0 44'),
            square('h8'),
          );
          lockedSquareExpectMoves(unsafePromotion, [], from: square('g7'));
          for (final suffix in ['q', 'r', 'b', 'n']) {
            lockedSquareRejects(
              unsafePromotion,
              ChessMoveAction(move('g7h8$suffix')),
            );
          }
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label break-seal selects one instance; overlaps and own lock remain',
        () {
          final initial = lockedSquareEdit(
            position(
              '7k/8/8/8/3R4/8/8/KN6 w - - 0 45',
              phase: BattlePhase.card,
            ),
            (draft) {
              draft.boardEffects.addAll([
                lockedSquareEffect('lock-one', [square('d5')], enemy),
                lockedSquareEffect('lock-two', [square('d5')], enemy),
                lockedSquareEffect(
                  'seal',
                  [square('d5'), square('e5'), square('d6'), square('e6')],
                  enemy,
                  type: BoardEffectType.boardSeal,
                ),
                lockedSquareEffect(
                  'mine',
                  [square('d5')],
                  enemy,
                  type: BoardEffectType.mine,
                  duration: EffectDuration.persistent,
                ),
                lockedSquareEffect('own-lock', [square('d5')], side),
              ]);
            },
          );
          lockedSquareEqual(
            BattleRulesCore.cardTargets(initial.view(side), CardId.breakSeal),
            ['lock-one', 'lock-two', 'seal', 'mine'],
            'removal targets instance ids, not square or owner effect',
          );
          lockedSquareEqual(
            BattleRulesCore.cardTargets(initial.view(side), CardId.purify),
            [],
            'purify cannot remove board lock',
          );
          for (final action in [
            const PlayCardAction(CardId.breakSeal, target: 'own-lock'),
            PlayCardAction(CardId.breakSeal, target: square('d5')),
            const PlayCardAction(CardId.breakSeal, target: 'missing'),
            const PlayCardAction(CardId.purify, target: 'lock-one'),
          ]) {
            lockedSquareRejects(initial, action);
          }
          for (final selected in ['lock-one', 'lock-two', 'seal', 'mine']) {
            final after = DeckManager.apply(
              initial,
              PlayCardAction(CardId.breakSeal, target: selected),
            );
            lockedSquareEqual(
              after.rules.boardEffects.map((e) => e.id).toList(),
              [
                'lock-one',
                'lock-two',
                'seal',
                'mine',
                'own-lock',
              ].where((id) => id != selected).toList(),
              'only selected instance removed',
            );
            lockedSquareRejects(after, ChessMoveAction(move('d4d5')));
          }
          final removed = DeckManager.apply(
            initial,
            const PlayCardAction(CardId.breakSeal, target: 'lock-one'),
          );
          final moved = DeckManager.apply(
            removed,
            ChessMoveAction(move('a1a2')),
          );
          lockedSquareEqual(
            moved.rules.boardEffects.map((e) => e.id).toList(),
            ['mine', 'own-lock'],
            'response expiry preserves persistent mine and opposite response window',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label lock overlaps mine without triggering on a rejected arrival',
        () {
          final initial = lockedSquareEdit(
            position('7k/8/8/8/3R4/8/8/K7 w - - 0 46'),
            (draft) {
              draft.boardEffects.addAll([
                lockedSquareEffect('lock', [square('d5')], enemy),
                lockedSquareEffect(
                  'mine',
                  [square('d5')],
                  enemy,
                  type: BoardEffectType.mine,
                  duration: EffectDuration.persistent,
                ),
              ]);
            },
          );
          lockedSquareRejects(initial, ChessMoveAction(move('d4d5')));
          lockedSquareEqual(
            initial.rules.pieceEffects,
            [],
            'illegal arrival creates no debuff',
          );
          final moved = DeckManager.apply(
            initial,
            ChessMoveAction(move('d4e4')),
          );
          lockedSquareEqual(
            moved.rules.boardEffects.map((e) => e.id).toList(),
            ['mine'],
            'unentered mine survives expired lock',
          );
          lockedSquareEqual(
            moved.rules.pieceEffects,
            [],
            'unrelated move does not enter mine',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label real cast on a mine, owner arrival and enemy capture compose',
        () {
          final initial = lockedSquareEdit(
            position(
              '3r3k/8/8/8/3R4/8/8/K7 w - - 0 47',
              phase: BattlePhase.card,
            ),
            (draft) => draft.boardEffects.add(
              lockedSquareEffect(
                'mine',
                [square('d5')],
                enemy,
                type: BoardEffectType.mine,
                duration: EffectDuration.persistent,
              ),
            ),
          );
          lockedSquareRequire(
            BattleRulesCore.cardTargets(
              initial.view(side),
              CardId.lockedSquare,
            ).contains(square('d5')),
            'existing mine does not forbid empty lock target',
          );
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('d5')),
          );
          final ownerMove = DeckManager.apply(
            cast,
            ChessMoveAction(move('d4d5')),
          );
          lockedSquareEqual(
            ownerMove.rules.boardEffects.map((e) => e.id).toList(),
            ['e101'],
            'mine triggered, lock survives owner move',
          );
          lockedSquareEqual(
            ownerMove.rules.pieceEffects.single.type,
            PieceEffectType.mineDebuff,
            'owner arrival still triggers opposing mine',
          );
          final response = DeckManager.apply(ownerMove, const PassAction());
          final after = DeckManager.apply(
            response,
            ChessMoveAction(move('d8d5')),
          );
          lockedSquareEqual(
            after.rules.boardEffects,
            [],
            'capture ends lock response window',
          );
          lockedSquareEqual(
            after.rules.pieceEffects,
            [],
            'captured owner effect is not orphaned',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label restriction mate has one independently known interposition',
        () {
          final initial = position(
            '5b1k/5K2/8/8/8/8/8/6R1 w - - 0 48',
            phase: BattlePhase.card,
          );
          final plain = DeckManager.apply(
            DeckManager.apply(initial, const PassAction()),
            ChessMoveAction(move('g1h1')),
          );
          lockedSquareEqual(
            plain.rules.terminal,
            null,
            'orthodox interposition prevents mate',
          );
          lockedSquareExpectMoves(plain, [move('f8h6')]);
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('h6')),
          );
          final after = DeckManager.apply(cast, ChessMoveAction(move('g1h1')));
          lockedSquareEqual(after.rules.terminal?.toJson(), {
            'reason': 'checkmate',
            'winner': sideWire(side),
            'mateByRestriction': true,
            'mateBySpecialMove': false,
            'stalemateByRestriction': false,
          }, 'lock removes sole bishop interposition');
          lockedSquareEqual(
            after.rules.phase,
            BattlePhase.terminal,
            'terminal phase',
          );
          lockedSquareEqual(
            after.rules.handCounts[side],
            cast.rules.handCounts[side],
            'terminal move draws no card',
          );
          lockedSquareEqual(
            after.rules.drawCounts[side],
            cast.rules.drawCounts[side],
            'terminal draw count unchanged',
          );
          lockedSquareEqual(
            after.rules.boardEffects.single.id,
            'e101',
            'unanswered lock remains in terminal snapshot',
          );
          for (final viewer in PieceColor.values) {
            lockedSquareEqual(
              BattleRulesCore.legalActions(after.view(viewer)),
              [],
              'terminal has no card rescue action',
            );
          }
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label restriction stalemate has one independently known pawn move',
        () {
          final initial = position(
            '7k/5K2/p7/8/8/3B4/8/8 w - - 0 49',
            phase: BattlePhase.card,
          );
          final plain = DeckManager.apply(
            DeckManager.apply(initial, const PassAction()),
            ChessMoveAction(move('d3e4')),
          );
          lockedSquareEqual(
            plain.rules.terminal,
            null,
            'pawn move prevents ordinary stalemate',
          );
          lockedSquareExpectMoves(plain, [move('a6a5')]);
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('a5')),
          );
          final after = DeckManager.apply(cast, ChessMoveAction(move('d3e4')));
          lockedSquareEqual(after.rules.terminal?.toJson(), {
            'reason': 'stalemate',
            'winner': null,
            'mateByRestriction': false,
            'mateBySpecialMove': false,
            'stalemateByRestriction': true,
          }, 'lock removes sole non-king quiet move');
          lockedSquareEqual(
            after.rules.handCounts[side],
            cast.rules.handCounts[side],
            'stalemate draws no card',
          );
          lockedSquareEqual(
            after.rules.boardEffects.single.id,
            'e101',
            'stalemate does not pre-expire unanswered lock',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label king-only escape cannot become restriction mate',
        () {
          final initial = position(
            '7k/8/5K2/8/2B5/8/8/6R1 w - - 0 50',
            phase: BattlePhase.card,
          );
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.lockedSquare, target: square('h7')),
          );
          final after = DeckManager.apply(cast, ChessMoveAction(move('g1g8')));
          lockedSquareEqual(
            after.rules.terminal,
            null,
            'safe king escape survives lock',
          );
          lockedSquareExpectMoves(after, [move('h8h7')]);
          final response = DeckManager.apply(after, const PassAction());
          final escaped = DeckManager.apply(
            response,
            ChessMoveAction(move('h8h7')),
          );
          lockedSquareEqual(
            escaped.rules.boardEffects,
            [],
            'king response also expires lock',
          );
        },
      ),
    );

    for (final special in const [
      (
        CardId.pawnDeviation,
        '7k/8/8/8/3P4/8/8/K7 w - - 0 51',
        'd4',
        ['d4c5', 'd4e5'],
        'c5',
      ),
      (
        CardId.pawnAdvance,
        '7k/8/8/8/8/4P3/8/K7 w - - 0 51',
        'e3',
        ['e3e5'],
        'e5',
      ),
      (
        CardId.rookBend,
        '7k/8/8/8/3R4/8/8/K7 w - - 0 51',
        'd4',
        ['d4c3', 'd4e3', 'd4c5', 'd4e5'],
        'c5',
      ),
      (
        CardId.angryN,
        '7k/8/8/8/3N4/8/8/K7 w - - 0 51',
        'd4',
        ['d4c4', 'd4e4', 'd4d3', 'd4d5'],
        'd5',
      ),
      (
        CardId.shadowPass,
        '7k/8/8/8/8/P7/8/R3K3 w - - 0 51',
        'a1',
        ['a1a4', 'a1a5', 'a1a6', 'a1a7', 'a1a8'],
        'a5',
      ),
    ]) {
      cases.add(
        LockedSquareAuditCase(
          '$label lock intersects ${special.$1.wire} without widening authorization',
          () {
            final initial = position(
              special.$2,
              phase: BattlePhase.card,
              hand: [special.$1, CardId.lockedSquare, CardId.purify],
            );
            final state = lockedSquareOn(initial, square(special.$5));
            final expected =
                special.$4
                    .where((uci) => uci.substring(2, 4) != special.$5)
                    .map(move)
                    .toList();
            final actual =
                BattleRulesCore.specialMoves(
                    state.rules,
                    special.$1,
                    square(special.$3),
                    side,
                  ).map((m) => m.uci).toList()
                  ..sort();
            lockedSquareEqual(
              actual,
              [...expected]..sort(),
              'hand-authored special destination set',
            );
            if (expected.isNotEmpty) {
              final cast = DeckManager.apply(
                state,
                PlayCardAction(special.$1, target: square(special.$3)),
              );
              lockedSquareExpectMoves(cast, expected);
              lockedSquareRejects(
                cast,
                ChessMoveAction(move('${special.$3}${special.$5}')),
              );
              final after = DeckManager.apply(
                cast,
                ChessMoveAction(expected.first),
              );
              lockedSquareEqual(
                after.rules.boardEffects,
                [],
                'special response move also expires lock',
              );
            } else {
              lockedSquareRejects(
                state,
                PlayCardAction(special.$1, target: square(special.$3)),
              );
            }
            final allBlocked = lockedSquareEdit(initial, (draft) {
              for (var index = 0; index < special.$4.length; index++) {
                draft.boardEffects.add(
                  lockedSquareEffect('special-lock-$index', [
                    square(special.$4[index].substring(2, 4)),
                  ], enemy),
                );
              }
            });
            lockedSquareRequire(
              !BattleRulesCore.cardTargets(
                allBlocked.view(side),
                special.$1,
              ).contains(square(special.$3)),
              'no special target when all destinations locked',
            );
            lockedSquareRejects(
              allBlocked,
              PlayCardAction(special.$1, target: square(special.$3)),
            );
          },
        ),
      );
    }

    cases.add(
      LockedSquareAuditCase(
        '$label special pawn double crosses locked intermediate square',
        () {
          final initial = position(
            '7k/8/8/8/8/4P3/8/K7 w - - 0 52',
            phase: BattlePhase.card,
            hand: const [
              CardId.pawnAdvance,
              CardId.lockedSquare,
              CardId.purify,
            ],
          );
          final state = lockedSquareOn(initial, square('e4'));
          final cast = DeckManager.apply(
            state,
            PlayCardAction(CardId.pawnAdvance, target: square('e3')),
          );
          lockedSquareExpectMoves(cast, [move('e3e5')]);
          final after = DeckManager.apply(cast, ChessMoveAction(move('e3e5')));
          lockedSquareEqual(
            after.rules.board.enPassant,
            null,
            'nonstandard double creates no EP right',
          );
          lockedSquareEqual(
            after.rules.boardEffects,
            [],
            'special double completes response',
          );
        },
      ),
    );

    cases.add(
      LockedSquareAuditCase(
        '$label occupied capture exception cannot override Chain or Freeze',
        () {
          final initial = lockedSquareOn(
            position('8/7k/3n4/8/3R4/8/8/K7 w - - 0 53'),
            square('d6'),
          );
          for (final type in [
            PieceEffectType.chain,
            PieceEffectType.freeze,
            PieceEffectType.mineDebuff,
          ]) {
            final state = lockedSquareEdit(
              initial,
              (draft) => draft.pieceEffects.add(
                ActivePieceEffect(
                  id: 'overlap-${type.name}',
                  type: type,
                  owner: enemy,
                  pieceId: draft.pieceIds[square('d4')]!,
                  responseSide: side,
                  duration:
                      type == PieceEffectType.mineDebuff
                          ? EffectDuration.pieceMove
                          : EffectDuration.move,
                ),
              ),
            );
            lockedSquareRejects(state, ChessMoveAction(move('d4d6')));
            if (type == PieceEffectType.freeze) {
              lockedSquareExpectMoves(state, [], from: square('d4'));
            } else {
              lockedSquareRequire(
                lockedSquareMoves(state).contains(move('d4e4')),
                'noncapture remains available',
              );
            }
          }
        },
      ),
    );
  }
  return cases;
}
