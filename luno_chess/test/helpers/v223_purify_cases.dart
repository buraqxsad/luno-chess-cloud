import 'dart:convert';

import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const purifyWhite = PieceColor.white;
const purifyBlack = PieceColor.black;

int purifySquare(String text) =>
    Square.of(text.codeUnitAt(0) - 97, text.codeUnitAt(1) - 49);

List<CardId> _deck(List<CardId> hand) {
  if (hand.length != 3 || hand.toSet().length != 3) {
    throw ArgumentError('Purify fixtures need three distinct starting cards');
  }
  return [
    ...hand,
    ...CardId.values.where((card) => !hand.contains(card)).take(7),
  ];
}

AuthoritativeBattleState purifyPosition(
  String fen, {
  BattlePhase phase = BattlePhase.card,
  List<CardId> hand = const [CardId.purify, CardId.prophecy, CardId.shelter],
  List<CardId>? enemyHand,
}) {
  final board = Board.fromFen(fen);
  final own = _deck(hand), enemy = _deck(enemyHand ?? hand);
  final state = DeckManager.newBattle(
    board: board,
    white: board.turn == purifyWhite ? own : enemy,
    black: board.turn == purifyBlack ? own : enemy,
  );
  if (state.rules.terminal != null) {
    throw ArgumentError('Unexpected terminal Purify fixture: $fen');
  }
  return purifyEdit(state, (draft) {
    draft.phase = phase;
    draft.ownTurns = {purifyWhite: 2, purifyBlack: 2};
    draft.mana = {purifyWhite: 6, purifyBlack: 6};
    draft.effectSequence = 100;
    draft.repetitions = {};
  });
}

AuthoritativeBattleState purifyEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState purifyAddEffect(
  AuthoritativeBattleState state,
  int square,
  PieceEffectType type, {
  String id = 'v223-purify-target',
}) => purifyEdit(state, (draft) {
  final victim = state.rules.board.pieceAt(square)!.color;
  draft.pieceEffects.add(
    ActivePieceEffect(
      id: id,
      type: type,
      owner: type == PieceEffectType.shelter ? victim : victim.opposite,
      pieceId: draft.pieceIds[square]!,
      responseSide: type == PieceEffectType.shelter ? victim.opposite : victim,
      duration:
          type == PieceEffectType.shelter
              ? EffectDuration.card
              : type == PieceEffectType.mineDebuff
              ? EffectDuration.pieceMove
              : EffectDuration.move,
    ),
  );
});

AuthoritativeBattleState purifyRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

void purifyRequire(bool value, String detail) {
  if (!value) throw StateError('V223 Purify: $detail');
}

void purifyEqual(Object? actual, Object? expected, String detail) {
  Object encode(Object? value) {
    if (value is Enum) return '${value.runtimeType}.${value.name}';
    throw ArgumentError('Unexpected Purify assertion value: $value');
  }

  purifyRequire(
    jsonEncode(canonicalObject(actual), toEncodable: encode) ==
        jsonEncode(canonicalObject(expected), toEncodable: encode),
    '$detail; expected=$expected actual=$actual',
  );
}

List<String> purifyMoves(AuthoritativeBattleState state, {String? from}) =>
    (BattleRulesCore.legalActions(state.view(state.rules.board.turn))
        .whereType<ChessMoveAction>()
        .map((action) => action.uci)
        .where((uci) => from == null || uci.startsWith(from))
        .toList()
      ..sort());

List<String> _ruleMoves(AuthoritativeBattleState state, {String? from}) =>
    (BattleRulesCore.legalMoves(state.rules, state.rules.board.turn)
        .map((move) => move.uci)
        .where((uci) => from == null || uci.startsWith(from))
        .toList()
      ..sort());

List<PlayCardAction> _plays(
  AuthoritativeBattleState state, {
  PieceColor? side,
}) =>
    BattleRulesCore.legalActions(state.view(side ?? state.rules.board.turn))
        .whereType<PlayCardAction>()
        .where((action) => action.card == CardId.purify)
        .toList();

void purifyRejects(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(state.toJson());
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    rejected = error.message == 'illegal-action';
  }
  purifyRequire(rejected, 'reject ${action.toJson()} as illegal-action');
  purifyEqual(jsonEncode(state.toJson()), before, 'rejection is atomic');
}

void _inventory(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final hand = state.hidden.hands[side]!, deck = state.hidden.decks[side]!;
    final all = [
      ...hand,
      ...deck,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    purifyEqual(hand.length, state.rules.handCounts[side], 'public hand count');
    purifyEqual(deck.length, state.rules.deckCounts[side], 'public deck count');
    purifyEqual(all.length, 10, 'inventory size');
    purifyEqual(all.toSet().length, 10, 'no duplicate card');
    purifyRequire(hand.length <= 4, 'hand cap');
    purifyRequire(
      state.rules.mana[side]! >= 0 && state.rules.mana[side]! <= 6,
      'mana range',
    );
    BattleRulesCore.legalActions(state.view(side));
  }
  purifyEqual(
    purifyRoundTrip(state).toJson(),
    state.toJson(),
    'wire round trip',
  );
}

class PurifyAuditCase {
  final String name;
  final void Function() run;
  const PurifyAuditCase(this.name, this.run);
}

List<PurifyAuditCase> purifyAuditCases() {
  final cases = <PurifyAuditCase>[];
  for (final side in PieceColor.values) {
    final enemy = side.opposite, tag = sideWire(side);
    String choose(String white, String black) =>
        side == purifyWhite ? white : black;
    int square(String white, String black) =>
        purifySquare(choose(white, black));
    List<String> chooseMoves(List<String> white, List<String> black) =>
        [...(side == purifyWhite ? white : black)]..sort();
    final rook = square('b2', 'b7');
    final rookText = choose('b2', 'b7');
    final ordinaryFen = choose(
      '6k1/8/8/1p6/8/8/1R6/5K2 w - - 17 23',
      '5k2/1r6/8/8/1P6/8/8/6K1 b - - 17 23',
    );
    final fullRookMoves = chooseMoves(
      [
        'b2a2',
        'b2b1',
        'b2b3',
        'b2b4',
        'b2b5',
        'b2c2',
        'b2d2',
        'b2e2',
        'b2f2',
        'b2g2',
        'b2h2',
      ],
      [
        'b7a7',
        'b7b8',
        'b7b6',
        'b7b5',
        'b7b4',
        'b7c7',
        'b7d7',
        'b7e7',
        'b7f7',
        'b7g7',
        'b7h7',
      ],
    );
    final shortRookMoves = chooseMoves(
      ['b2a2', 'b2b1', 'b2b3', 'b2b4', 'b2c2', 'b2d2'],
      ['b7a7', 'b7b8', 'b7b6', 'b7b5', 'b7c7', 'b7d7'],
    );
    final rookCapture = choose('b2b5', 'b7b4');

    for (final type in [
      PieceEffectType.chain,
      PieceEffectType.slow,
      PieceEffectType.freeze,
      PieceEffectType.mineDebuff,
    ]) {
      cases.add(
        PurifyAuditCase('$tag/${type.name}/literal-rook-and-transaction', () {
          final initial = purifyAddEffect(
            purifyPosition(ordinaryFen),
            rook,
            type,
          );
          final before = jsonEncode(initial.toJson());
          final expectedBefore =
              type == PieceEffectType.freeze
                  ? <String>[]
                  : type == PieceEffectType.slow
                  ? shortRookMoves
                  : fullRookMoves.where((uci) => uci != rookCapture).toList();
          purifyEqual(
            _ruleMoves(initial, from: rookText),
            expectedBefore,
            'literal restricted rook moves',
          );
          final after = DeckManager.apply(
            purifyRoundTrip(initial),
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          );
          purifyEqual(
            purifyMoves(after, from: rookText),
            fullRookMoves,
            'all eleven independently listed rook moves restored',
          );
          purifyEqual(
            after.rules.fen,
            ordinaryFen,
            'card does not move board/counters',
          );
          purifyEqual(
            after.rules.pieceIds,
            initial.rules.pieceIds,
            'piece identity',
          );
          purifyEqual(after.rules.mana[side], 5, 'literal base cost one');
          purifyEqual(after.rules.mana[enemy], 6, 'no unearned enemy mana');
          purifyEqual(after.rules.used[side], [CardId.purify], 'one used card');
          purifyEqual(after.rules.discarded[side], [], 'not a discard');
          purifyEqual(after.hidden.hands[side], [
            CardId.prophecy,
            CardId.shelter,
          ], 'one card removed from hidden hand');
          purifyEqual(after.rules.handCounts[side], 2, 'hand after card');
          purifyEqual(after.rules.deckCounts[side], 7, 'no card-stage draw');
          purifyEqual(
            after.rules.drawCounts[side],
            3,
            'no card-stage draw count',
          );
          purifyEqual(
            after.rules.phase,
            BattlePhase.chess,
            'same-turn chess window',
          );
          purifyEqual(after.rules.board.turn, side, 'same actor');
          purifyEqual(after.rules.ply, 0, 'no chess ply consumed');
          purifyEqual(after.rules.ownTurns[side], 2, 'no own turn consumed');
          purifyEqual(
            after.rules.effectSequence,
            100,
            'removal allocates no effect',
          );
          purifyEqual(after.rules.pending, null, 'no private resolution');
          purifyEqual(after.rules.special, null, 'no special authorization');
          purifyEqual(after.rules.terminal, null, 'not terminal');
          purifyRejects(
            after,
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          );
          final moved = DeckManager.apply(
            after,
            ChessMoveAction(choose('b2b3', 'b7b6')),
          );
          purifyEqual(moved.rules.ply, 1, 'card then chess');
          purifyEqual(
            moved.rules.board.turn,
            enemy,
            'turn passes only after chess',
          );
          purifyEqual(moved.rules.handCounts[side], 3, 'one end-move draw');
          purifyEqual(moved.rules.deckCounts[side], 6, 'one deck card drawn');
          purifyEqual(moved.rules.drawCounts[side], 4, 'one draw event');
          purifyEqual(moved.hidden.hands[side], [
            CardId.prophecy,
            CardId.shelter,
            CardId.radar,
          ], 'literal next draw');
          purifyEqual(jsonEncode(initial.toJson()), before, 'input immutable');
          _inventory(after);
          _inventory(moved);
        }),
      );
    }

    for (final sealed in [false, true]) {
      cases.add(
        PurifyAuditCase('$tag/stack-matrix/sealed=$sealed', () {
          const types = [
            PieceEffectType.chain,
            PieceEffectType.slow,
            PieceEffectType.freeze,
            PieceEffectType.mineDebuff,
          ];
          var branches = 0;
          for (var mask = 1; mask < 16; mask++) {
            var initial = purifyPosition(ordinaryFen);
            final present = <PieceEffectType>[];
            for (var i = 0; i < types.length; i++) {
              if ((mask & (1 << i)) == 0) continue;
              present.add(types[i]);
              initial = purifyAddEffect(
                initial,
                rook,
                types[i],
                id: 'stack-$i',
              );
            }
            initial = purifyAddEffect(
              initial,
              rook,
              PieceEffectType.shelter,
              id: 'own-shelter',
            );
            if (sealed) {
              initial = purifyEdit(initial, (draft) {
                draft.boardEffects.addAll([
                  BoardEffectInstance(
                    id: 'lock',
                    type: BoardEffectType.lockedSquare,
                    owner: enemy,
                    responseSide: side,
                    duration: EffectDuration.move,
                    squares: [square('b3', 'b6')],
                  ),
                  BoardEffectInstance(
                    id: 'seal',
                    type: BoardEffectType.boardSeal,
                    owner: enemy,
                    responseSide: side,
                    duration: EffectDuration.move,
                    squares: [
                      square('c2', 'c7'),
                      square('d2', 'd7'),
                      square('c3', 'c6'),
                      square('d3', 'd6'),
                    ],
                  ),
                ]);
              });
            }
            for (var i = 0; i < types.length; i++) {
              if (!present.contains(types[i])) continue;
              final after = DeckManager.apply(
                initial,
                PlayCardAction(CardId.purify, target: 'stack-$i'),
              );
              final remaining =
                  present.where((type) => type != types[i]).toList();
              var expected =
                  remaining.contains(PieceEffectType.freeze)
                      ? <String>[]
                      : remaining.contains(PieceEffectType.slow)
                      ? [...shortRookMoves]
                      : [...fullRookMoves];
              if (remaining.contains(PieceEffectType.chain) ||
                  remaining.contains(PieceEffectType.mineDebuff)) {
                expected.remove(rookCapture);
              }
              if (sealed) {
                expected.removeWhere(
                  [
                    choose('b2b3', 'b7b6'),
                    choose('b2c2', 'b7c7'),
                    choose('b2d2', 'b7d7'),
                  ].contains,
                );
              }
              expected.sort();
              purifyEqual(
                purifyMoves(after, from: rookText),
                expected,
                'literal geometry oracle for mask=$mask removed=$i',
              );
              purifyEqual(
                after.rules.pieceEffects.map((effect) => effect.id).toList(),
                [
                  for (var j = 0; j < types.length; j++)
                    if ((mask & (1 << j)) != 0 && j != i) 'stack-$j',
                  'own-shelter',
                ],
                'remove exactly one ID, preserve Shelter',
              );
              purifyEqual(
                after.rules.boardEffects.map((effect) => effect.id).toList(),
                sealed ? ['lock', 'seal'] : [],
                'Purify is not Break Seal',
              );
              purifyRequire(
                purifyMoves(after).isNotEmpty,
                'unrestricted king preserves a chess continuation',
              );
              final beforeMoves = _ruleMoves(initial).toSet();
              purifyRequire(
                purifyMoves(after).toSet().containsAll(beforeMoves),
                'Purify must not strand a previously legal normal move',
              );
              branches++;
            }
          }
          purifyEqual(
            branches,
            32,
            'all removals of all nonempty four-effect subsets',
          );
        }),
      );
    }

    cases.add(
      PurifyAuditCase('$tag/same-type-stacks-and-effect-choice', () {
        var state = purifyAddEffect(
          purifyPosition(ordinaryFen),
          rook,
          PieceEffectType.chain,
          id: 'chain-a',
        );
        state = purifyAddEffect(
          state,
          rook,
          PieceEffectType.chain,
          id: 'chain-b',
        );
        state = purifyAddEffect(
          state,
          rook,
          PieceEffectType.shelter,
          id: 'shelter',
        );
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(state.view(side));
        final selection =
            BattleInteraction()
              ..synchronize(view, 8)
              ..select(CardId.purify, actions);
        purifyEqual(selection.targets(view, actions).toList(), [
          rook,
        ], 'one live target square');
        final options = selection.tap(rook, view, actions);
        purifyEqual(options.map((action) => action.key).toList(), [
          'play:purify:chain-a:',
          'play:purify:chain-b:',
        ], 'two exact effect choices');
        purifyEqual(
          selection.play,
          null,
          'ambiguous stack must not auto-confirm',
        );
        selection.play = options.last as PlayCardAction;
        purifyEqual(selection.preview().toList(), [
          rook,
        ], 'preview tracks identity');
        final after = DeckManager.apply(state, selection.play!);
        purifyEqual(
          after.rules.pieceEffects.map((effect) => effect.id).toList(),
          ['chain-a', 'shelter'],
          'same-type sibling preserved',
        );
        purifyRequire(
          !purifyMoves(after).contains(rookCapture),
          'remaining Chain still bans capture',
        );
        selection.synchronize(after.view(side), 9);
        purifyEqual(
          selection.play,
          null,
          'accepted version clears stale effect choice',
        );
        purifyEqual(
          selection.card,
          null,
          'accepted version clears selected card',
        );
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/target-identity-and-invalid-retarget', () {
        var state = purifyAddEffect(
          purifyPosition(ordinaryFen),
          rook,
          PieceEffectType.freeze,
          id: '17',
        );
        state = purifyAddEffect(
          state,
          square('b5', 'b4'),
          PieceEffectType.freeze,
          id: 'enemy-effect',
        );
        state = purifyAddEffect(
          state,
          rook,
          PieceEffectType.shelter,
          id: 'own-shelter',
        );
        state = purifyEdit(state, (draft) {
          draft.pieceEffects.add(
            ActivePieceEffect(
              id: 'orphan',
              type: PieceEffectType.chain,
              owner: enemy,
              responseSide: side,
              duration: EffectDuration.move,
              pieceId: 'captured-piece-not-on-board',
            ),
          );
          draft.boardEffects.add(
            BoardEffectInstance(
              id: 'board-mine',
              type: BoardEffectType.mine,
              owner: enemy,
              responseSide: side,
              duration: EffectDuration.persistent,
              squares: [square('c3', 'c6')],
            ),
          );
        });
        purifyEqual(_plays(state).map((action) => action.target).toList(), [
          '17',
        ], 'only a negative effect on a live own identity');
        for (final target in <Object?>[
          17,
          rook,
          null,
          'enemy-effect',
          'own-shelter',
          'orphan',
          'board-mine',
          'missing',
          {'id': '17'},
        ]) {
          purifyRejects(state, PlayCardAction(CardId.purify, target: target));
        }
        purifyRejects(
          state,
          const PlayCardAction(
            CardId.purify,
            target: '17',
            sacrifice: CardId.prophecy,
          ),
        );
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(state.view(side));
        final selection = BattleInteraction()..select(CardId.purify, actions);
        for (final invalid in [
          square('b5', 'b4'),
          square('f1', 'f8'),
          square('a4', 'a5'),
        ]) {
          selection.tap(rook, view, actions);
          purifyEqual(selection.play?.target, '17', 'valid string ID selected');
          selection.tap(invalid, view, actions);
          purifyEqual(
            selection.play,
            null,
            'invalid retarget clears old effect',
          );
          purifyEqual(
            selection.preview().toList(),
            [],
            'invalid retarget clears preview',
          );
          purifyEqual(
            selection.invalidTarget,
            true,
            'invalid target feedback state',
          );
        }
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/absolute-pin-is-not-cleansed', () {
        final state = purifyAddEffect(
          purifyPosition(
            choose(
              '4r1k1/8/8/8/8/4R3/8/4K3 w - - 11 23',
              '4k3/8/4r3/8/8/8/8/4R1K1 b - - 11 23',
            ),
          ),
          square('e3', 'e6'),
          PieceEffectType.freeze,
        );
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          purifyMoves(after, from: choose('e3', 'e6')),
          chooseMoves(
            ['e3e2', 'e3e4', 'e3e5', 'e3e6', 'e3e7', 'e3e8'],
            ['e6e7', 'e6e5', 'e6e4', 'e6e3', 'e6e2', 'e6e1'],
          ),
          'only moves along the pin ray, including capture of pinner',
        );
        purifyRejects(after, ChessMoveAction(choose('e3d3', 'e6d6')));
        final captured = DeckManager.apply(
          after,
          ChessMoveAction(choose('e3e8', 'e6e1')),
        );
        purifyEqual(
          MoveGen.inCheck(captured.rules.board, side),
          false,
          'king safe after pinner capture',
        );
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/check-requires-a-real-interposition', () {
        final state = purifyAddEffect(
          purifyPosition(
            choose(
              '4r1k1/8/8/8/8/2B5/8/4K3 w - - 4 23',
              '4k3/8/2b5/8/8/8/8/4R1K1 b - - 4 23',
            ),
          ),
          square('c3', 'c6'),
          PieceEffectType.freeze,
        );
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          MoveGen.inCheck(after.rules.board, side),
          true,
          'Purify itself does not evade check',
        );
        purifyEqual(purifyMoves(after, from: choose('c3', 'c6')), [
          choose('c3e5', 'c6e4'),
        ], 'only the e-file interposition is legal');
        purifyRejects(after, ChessMoveAction(choose('c3d4', 'c6d5')));
        final moved = DeckManager.apply(
          after,
          ChessMoveAction(choose('c3e5', 'c6e4')),
        );
        purifyEqual(
          MoveGen.inCheck(moved.rules.board, side),
          false,
          'interposition resolves check',
        );
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/checker-capture-and-double-check', () {
        final captureState = purifyAddEffect(
          purifyPosition(
            choose(
              'k7/8/8/8/8/5n2/8/4KR2 w - - 0 23',
              '4kr2/8/5N2/8/8/8/8/K7 b - - 0 23',
            ),
          ),
          square('f1', 'f8'),
          PieceEffectType.chain,
        );
        final captureReady = DeckManager.apply(
          captureState,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(purifyMoves(captureReady, from: choose('f1', 'f8')), [
          choose('f1f3', 'f8f6'),
        ], 'capture the checking knight, no quiet rook evasion');
        final escaped = DeckManager.apply(
          captureReady,
          ChessMoveAction(choose('f1f3', 'f8f6')),
        );
        purifyEqual(
          MoveGen.inCheck(escaped.rules.board, side),
          false,
          'checker removed',
        );
        final doubleState = purifyAddEffect(
          purifyPosition(
            choose(
              '4r1k1/8/8/8/1b6/8/2N5/4K3 w - - 6 23',
              '4k3/2n5/8/1B6/8/8/8/4R1K1 b - - 6 23',
            ),
          ),
          square('c2', 'c7'),
          PieceEffectType.freeze,
        );
        final doubleReady = DeckManager.apply(
          doubleState,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          purifyMoves(doubleReady),
          chooseMoves(['e1d1', 'e1f1', 'e1f2'], ['e8d8', 'e8f8', 'e8f7']),
          'double check permits only the three literal king evasions',
        );
        purifyRejects(doubleReady, ChessMoveAction(choose('c2b4', 'c7b5')));
      }),
    );

    for (final type in [
      PieceEffectType.chain,
      PieceEffectType.freeze,
      PieceEffectType.mineDebuff,
    ]) {
      cases.add(
        PurifyAuditCase('$tag/${type.name}/en-passant-capture-semantics', () {
          final state = purifyAddEffect(
            purifyPosition(
              choose(
                '6k1/8/8/2Pp4/8/8/8/4K3 w - d6 0 23',
                '4k3/8/8/8/2pP4/8/8/6K1 b - d3 0 23',
              ),
            ),
            square('c5', 'c4'),
            type,
          );
          final after = DeckManager.apply(
            state,
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          );
          purifyEqual(
            after.rules.board.enPassant,
            square('d6', 'd3'),
            'card retains EP window',
          );
          purifyEqual(
            purifyMoves(after, from: choose('c5', 'c4')),
            chooseMoves(['c5c6', 'c5d6'], ['c4c3', 'c4d3']),
            'literal quiet and EP moves',
          );
          final moved = DeckManager.apply(
            after,
            ChessMoveAction(choose('c5d6', 'c4d3')),
          );
          purifyEqual(
            moved.rules.board.pieceAt(square('d5', 'd4')),
            null,
            'EP victim actually captured',
          );
          purifyEqual(
            moved.rules.pieceIds[square('d5', 'd4')],
            null,
            'EP victim identity retired',
          );
          purifyEqual(
            moved.rules.pieceIds[square('d6', 'd3')],
            state.rules.pieceIds[square('c5', 'c4')],
            'EP mover identity retained',
          );
          purifyEqual(
            moved.rules.board.enPassant,
            null,
            'EP window consumed by chess',
          );
          purifyEqual(
            moved.rules.board.halfmoveClock,
            0,
            'capture resets clock',
          );
          _inventory(moved);
        }),
      );
    }

    cases.add(
      PurifyAuditCase('$tag/EP-discovered-check-remains-illegal', () {
        final state = purifyAddEffect(
          purifyPosition(
            choose(
              '6k1/8/8/K1Pp3r/8/8/8/8 w - d6 0 23',
              '8/8/8/8/k1pP3R/8/8/6K1 b - d3 0 23',
            ),
          ),
          square('c5', 'c4'),
          PieceEffectType.chain,
        );
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(purifyMoves(after, from: choose('c5', 'c4')), [
          choose('c5c6', 'c4c3'),
        ], 'EP would remove both rook-ray blockers');
        purifyRejects(after, ChessMoveAction(choose('c5d6', 'c4d3')));
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/EP-can-remove-checking-pawn-but-not-a-seal', () {
        final checked = purifyAddEffect(
          purifyPosition(
            choose(
              '6k1/8/8/2Pp4/4K3/8/8/8 w - d6 0 23',
              '8/8/8/4k3/2pP4/8/8/6K1 b - d3 0 23',
            ),
          ),
          square('c5', 'c4'),
          PieceEffectType.freeze,
        );
        final ready = DeckManager.apply(
          checked,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(purifyMoves(ready, from: choose('c5', 'c4')), [
          choose('c5d6', 'c4d3'),
        ], 'EP is the pawn only legal check evasion');
        final moved = DeckManager.apply(
          ready,
          ChessMoveAction(choose('c5d6', 'c4d3')),
        );
        purifyEqual(
          MoveGen.inCheck(moved.rules.board, side),
          false,
          'checking pawn removed',
        );
        final sealed = purifyEdit(checked, (draft) {
          draft.boardEffects.add(
            BoardEffectInstance(
              id: 'ep-lock',
              type: BoardEffectType.lockedSquare,
              owner: enemy,
              responseSide: side,
              duration: EffectDuration.move,
              squares: [square('d6', 'd3')],
            ),
          );
        });
        final sealReady = DeckManager.apply(
          sealed,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          purifyMoves(sealReady, from: choose('c5', 'c4')),
          [],
          'independent empty-square lock remains',
        );
        purifyEqual(
          sealReady.rules.boardEffects.single.id,
          'ep-lock',
          'Purify does not remove lock',
        );
        purifyRequire(
          purifyMoves(sealReady).isNotEmpty,
          'king still has an evasion, not stranded',
        );
      }),
    );

    for (final type in [
      PieceEffectType.chain,
      PieceEffectType.slow,
      PieceEffectType.freeze,
      PieceEffectType.mineDebuff,
    ]) {
      for (final queenSide in [false, true]) {
        cases.add(
          PurifyAuditCase('$tag/${type.name}/castle-rook/queen=$queenSide', () {
            final state = purifyAddEffect(
              purifyPosition(
                choose(
                  '5k2/8/8/8/8/8/8/R3K2R w KQ - 37 23',
                  'r3k2r/8/8/8/8/8/8/5K2 b kq - 37 23',
                ),
              ),
              queenSide ? square('a1', 'a8') : square('h1', 'h8'),
              type,
            );
            final castles = chooseMoves(['e1c1', 'e1g1'], ['e8c8', 'e8g8']);
            final selectedCastle =
                queenSide ? choose('e1c1', 'e8c8') : choose('e1g1', 'e8g8');
            final blocksCastle =
                type == PieceEffectType.freeze ||
                (type == PieceEffectType.slow && queenSide);
            purifyEqual(
              _ruleMoves(state).where(castles.contains).toList(),
              castles
                  .where((uci) => !blocksCastle || uci != selectedCastle)
                  .toList(),
              'literal pre-cleanse castle restriction including auxiliary rook',
            );
            final after = DeckManager.apply(
              state,
              const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
            );
            purifyEqual(
              purifyMoves(after).where(castles.contains).toList(),
              castles,
              'both orthodox castles legal after cleanse',
            );
            purifyEqual(
              after.rules.board.castling,
              side == purifyWhite ? 3 : 12,
              'card leaves castling flags unchanged',
            );
            final moved = DeckManager.apply(
              after,
              ChessMoveAction(selectedCastle),
            );
            final rookFrom =
                queenSide ? square('a1', 'a8') : square('h1', 'h8');
            final rookTo = queenSide ? square('d1', 'd8') : square('f1', 'f8');
            final kingTo = queenSide ? square('c1', 'c8') : square('g1', 'g8');
            purifyEqual(
              moved.rules.pieceIds[rookTo],
              state.rules.pieceIds[rookFrom],
              'rook identity relocates',
            );
            purifyEqual(
              moved.rules.pieceIds[kingTo],
              state.rules.pieceIds[square('e1', 'e8')],
              'king identity relocates',
            );
            purifyEqual(
              moved.rules.pieceIds[rookFrom],
              null,
              'rook source cleared',
            );
            purifyEqual(
              moved.rules.board.castling,
              0,
              'chess consumes castling rights',
            );
            purifyEqual(
              moved.rules.board.halfmoveClock,
              38,
              'only chess advances halfmove clock',
            );
            purifyEqual(
              moved.rules.special,
              null,
              'Purify castle is ordinary, not special',
            );
            _inventory(moved);
          }),
        );
      }
    }

    cases.add(
      PurifyAuditCase(
        '$tag/castle-safety-and-lost-rights-are-not-cleansed',
        () {
          for (final fen in [
            choose(
              '5k2/8/8/8/2b5/8/8/R3K2R w KQ - 12 23',
              'r3k2r/8/8/2B5/8/8/8/5K2 b kq - 12 23',
            ),
            choose(
              '4rk2/8/8/8/8/8/8/R3K2R w KQ - 12 23',
              'r3k2r/8/8/8/8/8/8/4RK2 b kq - 12 23',
            ),
            choose(
              '5k2/8/8/8/8/8/8/R3K2R w - - 12 23',
              'r3k2r/8/8/8/8/8/8/5K2 b - - 12 23',
            ),
          ]) {
            final state = purifyAddEffect(
              purifyPosition(fen),
              square('h1', 'h8'),
              PieceEffectType.freeze,
            );
            final after = DeckManager.apply(
              state,
              const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
            );
            purifyRejects(after, ChessMoveAction(choose('e1g1', 'e8g8')));
            purifyEqual(
              after.rules.board.castling,
              state.rules.board.castling,
              'do not invent rights',
            );
            purifyRequire(
              purifyMoves(after).isNotEmpty,
              'ordinary king/rook action remains',
            );
          }
        },
      ),
    );

    cases.add(
      PurifyAuditCase(
        '$tag/castle-arrival-mine-is-a-new-independent-effect',
        () {
          var state = purifyAddEffect(
            purifyPosition(
              choose(
                '5k2/8/8/8/8/8/8/R3K2R w KQ - 37 23',
                'r3k2r/8/8/8/8/8/8/5K2 b kq - 37 23',
              ),
            ),
            square('h1', 'h8'),
            PieceEffectType.mineDebuff,
          );
          state = purifyEdit(state, (draft) {
            draft.boardEffects.add(
              BoardEffectInstance(
                id: 'arrival-mine',
                type: BoardEffectType.mine,
                owner: enemy,
                responseSide: side,
                duration: EffectDuration.persistent,
                squares: [square('f1', 'f8')],
              ),
            );
          });
          final after = DeckManager.apply(
            state,
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          );
          purifyEqual(
            after.rules.pieceEffects,
            [],
            'old mine punishment removed now',
          );
          purifyEqual(
            after.rules.boardEffects.single.id,
            'arrival-mine',
            'untriggered mine survives',
          );
          final moved = DeckManager.apply(
            after,
            ChessMoveAction(choose('e1g1', 'e8g8')),
          );
          final effect = moved.rules.pieceEffects.single;
          purifyEqual(effect.id, 'e101', 'new arrival effect identity');
          purifyEqual(
            effect.type,
            PieceEffectType.mineDebuff,
            'rook triggers mine',
          );
          purifyEqual(
            effect.pieceId,
            state.rules.pieceIds[square('h1', 'h8')],
            'punish rook, not king',
          );
          purifyEqual(
            effect.duration,
            EffectDuration.pieceMove,
            'new debuff survives triggering move',
          );
          purifyEqual(moved.rules.boardEffects, [], 'mine consumed once');
        },
      ),
    );

    for (final type in [
      PieceEffectType.chain,
      PieceEffectType.freeze,
      PieceEffectType.mineDebuff,
    ]) {
      cases.add(
        PurifyAuditCase(
          '$tag/${type.name}/all-quiet-and-capture-promotions',
          () {
            final state = purifyAddEffect(
              purifyPosition(
                choose(
                  'r5k1/1P6/8/8/8/8/8/4K3 w - - 0 23',
                  '4k3/8/8/8/8/8/1p6/R5K1 b - - 0 23',
                ),
              ),
              square('b7', 'b2'),
              type,
            );
            final after = DeckManager.apply(
              state,
              const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
            );
            final expected = chooseMoves(
              [
                'b7a8b',
                'b7a8n',
                'b7a8q',
                'b7a8r',
                'b7b8b',
                'b7b8n',
                'b7b8q',
                'b7b8r',
              ],
              [
                'b2a1b',
                'b2a1n',
                'b2a1q',
                'b2a1r',
                'b2b1b',
                'b2b1n',
                'b2b1q',
                'b2b1r',
              ],
            );
            purifyEqual(
              purifyMoves(after, from: choose('b7', 'b2')),
              expected,
              'literal eight promotion actions',
            );
            for (final uci in expected) {
              final moved = DeckManager.apply(after, ChessMoveAction(uci));
              final to = purifySquare(uci.substring(2, 4));
              final expectedType =
                  {
                    'q': PieceType.queen,
                    'r': PieceType.rook,
                    'b': PieceType.bishop,
                    'n': PieceType.knight,
                  }[uci[4]];
              purifyEqual(
                moved.rules.board.pieceAt(to)?.type,
                expectedType,
                'literal promotion choice',
              );
              purifyEqual(
                moved.rules.board.pieceAt(to)?.color,
                side,
                'promotion color',
              );
              purifyEqual(
                moved.rules.pieceIds[to],
                state.rules.pieceIds[square('b7', 'b2')],
                'promotion retains pawn identity',
              );
              purifyEqual(
                moved.rules.board.halfmoveClock,
                0,
                'promotion resets halfmove clock',
              );
              purifyEqual(
                moved.rules.pieceEffects,
                [],
                'removed restriction never reattaches',
              );
              purifyRequire(
                moved.rules.terminal != null ||
                    BattleRulesCore.legalActions(moved.view(enemy)).isNotEmpty,
                'next actor is not stranded',
              );
              _inventory(moved);
            }
            purifyRejects(after, ChessMoveAction(choose('b7b8', 'b2b1')));
            purifyRejects(after, ChessMoveAction(choose('b7a8k', 'b2a1k')));
          },
        ),
      );
    }

    cases.add(
      PurifyAuditCase('$tag/does-not-reset-moved-pawn-history', () {
        var state = purifyAddEffect(
          purifyPosition(
            choose(
              '6k1/8/8/8/8/8/6P1/4K3 w - - 5 23',
              '4k3/6p1/8/8/8/8/8/6K1 b - - 5 23',
            ),
          ),
          square('g2', 'g7'),
          PieceEffectType.freeze,
        );
        state = purifyEdit(
          state,
          (draft) => draft.movedPawns.add(draft.pieceIds[square('g2', 'g7')]!),
        );
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          after.rules.movedPawns,
          state.rules.movedPawns,
          'historical movement preserved',
        );
        purifyEqual(purifyMoves(after, from: choose('g2', 'g7')), [
          choose('g2g3', 'g7g6'),
        ], 'no renewed starting-rank double step');
        purifyRejects(after, ChessMoveAction(choose('g2g4', 'g7g5')));
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/cost-countercards-and-no-target-fallback', () {
        final base = purifyAddEffect(
          purifyPosition(ordinaryFen),
          rook,
          PieceEffectType.freeze,
        );
        for (final sample in [
          (sabotage: 0, discount: 0, mana: 1, cost: 1),
          (sabotage: 1, discount: 0, mana: 1, cost: 2),
          (sabotage: 1, discount: 0, mana: 2, cost: 2),
          (sabotage: 2, discount: 0, mana: 3, cost: 3),
          (sabotage: 1, discount: 1, mana: 1, cost: 1),
          (sabotage: 2, discount: 1, mana: 1, cost: 1),
        ]) {
          final state = purifyEdit(base, (draft) {
            draft.mana[side] = sample.mana;
            for (var i = 0; i < sample.sabotage; i++) {
              draft.modifiers.add(
                PendingModifier(
                  id: 'sabotage-$i',
                  type: ModifierType.manaSabotage,
                  owner: enemy,
                  responseSide: side,
                  targetCard: CardId.purify,
                  ownTurn: 2,
                ),
              );
            }
            for (var i = 0; i < sample.discount; i++) {
              draft.modifiers.add(
                PendingModifier(
                  id: 'discount-$i',
                  type: ModifierType.discount,
                  owner: side,
                  responseSide: side,
                  targetCard: null,
                  ownTurn: 2,
                ),
              );
            }
          });
          purifyEqual(
            BattleRulesCore.effectiveCost(state.rules, side, CardId.purify),
            sample.cost,
            'independently authored cost',
          );
          if (sample.mana < sample.cost) {
            purifyEqual(_plays(state), [], 'unaffordable Purify omitted');
            purifyRejects(
              state,
              const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
            );
          } else {
            final after = DeckManager.apply(
              state,
              const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
            );
            purifyEqual(
              after.rules.mana[side],
              sample.mana - sample.cost,
              'exact spend',
            );
            purifyEqual(
              after.rules.modifiers,
              [],
              'current modifiers close after card',
            );
          }
        }
        final blocked = purifyEdit(base, (draft) {
          draft.modifiers.add(
            PendingModifier(
              id: 'block',
              type: ModifierType.cardBlock,
              owner: enemy,
              responseSide: side,
              targetCard: CardId.purify,
              ownTurn: 2,
            ),
          );
        });
        purifyEqual(_plays(blocked), [], 'Card Block prevents Purify');
        purifyRejects(
          blocked,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        final passed = DeckManager.apply(blocked, const PassAction());
        purifyRequire(
          purifyMoves(passed).isNotEmpty,
          'blocked Purify still permits another piece move',
        );
        purifyEqual(
          passed.rules.pieceEffects.single.type,
          PieceEffectType.freeze,
          'pass does not cleanse',
        );
        final empty = purifyPosition(ordinaryFen);
        purifyEqual(_plays(empty), [], 'no useless targetless Purify play');
        final discarded = DeckManager.apply(
          empty,
          const DiscardAction(CardId.purify),
        );
        purifyRequire(
          purifyMoves(discarded).isNotEmpty,
          'targetless card can be discarded without dead end',
        );
        purifyEqual(discarded.rules.mana[side], 6, 'discard is free');
        purifyEqual(discarded.rules.used[side], [], 'discard is not use');
        purifyEqual(discarded.rules.discarded[side], [
          CardId.purify,
        ], 'one discard');
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/echo-scope-and-one-window', () {
        var state = purifyAddEffect(
          purifyPosition(ordinaryFen),
          rook,
          PieceEffectType.freeze,
        );
        state = purifyEdit(state, (draft) {
          draft.mana[enemy] = 3;
          draft.modifiers.addAll([
            PendingModifier(
              id: 'echo',
              type: ModifierType.echo,
              owner: enemy,
              responseSide: side,
              targetCard: CardId.purify,
              ownTurn: 2,
            ),
            PendingModifier(
              id: 'future-sabotage',
              type: ModifierType.manaSabotage,
              owner: enemy,
              responseSide: side,
              targetCard: CardId.purify,
              ownTurn: 3,
            ),
            PendingModifier(
              id: 'expired-block',
              type: ModifierType.cardBlock,
              owner: enemy,
              responseSide: side,
              targetCard: CardId.purify,
              ownTurn: 1,
            ),
            PendingModifier(
              id: 'wrong-card-tax',
              type: ModifierType.manaSabotage,
              owner: enemy,
              responseSide: side,
              targetCard: CardId.shelter,
              ownTurn: 2,
            ),
          ]);
        });
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          after.rules.mana[side],
          5,
          'future/wrong-card modifiers do not tax',
        );
        purifyEqual(after.rules.mana[enemy], 5, 'one Echo reward');
        purifyEqual(
          after.rules.modifiers.map((modifier) => modifier.id).toList(),
          ['future-sabotage'],
          'only future response window survives',
        );
        purifyRejects(after, const PlayCardAction(CardId.shelter, target: 9));
        purifyRejects(after, const PassAction());
        purifyRejects(after, const DiscardAction(CardId.prophecy));
        purifyRejects(
          after,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          after.rules.mana[enemy],
          5,
          'rejected replay grants no Echo mana',
        );
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/pending-and-terminal-do-not-admit-Purify', () {
        final state = purifyAddEffect(
          purifyPosition(ordinaryFen),
          rook,
          PieceEffectType.freeze,
        );
        final pending = DeckManager.apply(
          state,
          const PlayCardAction(CardId.prophecy),
        );
        purifyEqual(
          pending.rules.phase,
          BattlePhase.pending,
          'real Prophecy pending boundary',
        );
        purifyEqual(_plays(pending), [], 'no Purify during private resolution');
        purifyRejects(
          pending,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        final resolves =
            BattleRulesCore.legalActions(
              pending.view(side),
            ).whereType<ResolveAction>().toList();
        purifyEqual(
          resolves.length,
          2,
          'both inspected orderings remain actionable',
        );
        final resolved = DeckManager.apply(pending, resolves.first);
        purifyEqual(resolved.rules.pending, null, 'resolution closes pending');
        purifyEqual(
          resolved.rules.phase,
          BattlePhase.chess,
          'resolution consumes card window',
        );
        purifyEqual(
          resolved.rules.pieceEffects.single.type,
          PieceEffectType.freeze,
          'Prophecy did not cleanse',
        );
        purifyRequire(
          purifyMoves(resolved).isNotEmpty,
          'king continuation remains after resolve',
        );
        purifyRejects(
          resolved,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        final terminal = purifyEdit(state, (draft) {
          draft.phase = BattlePhase.terminal;
          draft.terminal = TerminalState('timeout', winner: enemy);
        });
        for (final viewer in PieceColor.values) {
          purifyEqual(
            BattleRulesCore.legalActions(terminal.view(viewer)),
            [],
            'terminal actor cannot reopen',
          );
        }
        purifyRejects(
          terminal,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        final firstTurn = purifyEdit(state, (draft) {
          draft.phase = BattlePhase.chess;
          draft.ownTurns[side] = 1;
        });
        purifyEqual(_plays(firstTurn), [], 'no first-turn card');
        purifyRejects(
          firstTurn,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          _plays(state, side: enemy),
          [],
          'nonmoving color has no card actions',
        );
      }),
    );

    for (final removed in ['e102', 'e103']) {
      cases.add(
        PurifyAuditCase('$tag/reachable-mine-plus-chain/remove-$removed', () {
          var state = purifyPosition(
            choose(
              '6k1/8/8/1p6/8/8/1R6/5K2 b - - 17 23',
              '5k2/1r6/8/8/1P6/8/8/6K1 w - - 17 23',
            ),
            hand: const [CardId.mine, CardId.chain, CardId.slow],
            enemyHand: const [CardId.purify, CardId.prophecy, CardId.shelter],
          );
          state = DeckManager.apply(
            state,
            PlayCardAction(CardId.mine, target: square('b3', 'b6')),
          );
          state = DeckManager.apply(
            state,
            ChessMoveAction(choose('g8f8', 'g1f1')),
          );
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(choose('b2b3', 'b7b6')),
          );
          purifyEqual(
            state.rules.pieceEffects.single.id,
            'e102',
            'actual Mine trigger identity',
          );
          purifyEqual(
            state.rules.pieceEffects.single.duration,
            EffectDuration.pieceMove,
            'trigger persists',
          );
          state = DeckManager.apply(
            state,
            PlayCardAction(CardId.chain, target: square('b3', 'b6')),
          );
          state = DeckManager.apply(
            state,
            ChessMoveAction(choose('f8g8', 'f1g1')),
          );
          purifyEqual(state.rules.board.turn, side, 'victim response turn');
          purifyEqual(
            state.rules.phase,
            BattlePhase.card,
            'victim can choose a card',
          );
          purifyEqual(
            state.rules.pieceEffects.map((effect) => effect.id).toList(),
            ['e102', 'e103'],
            'old Mine plus fresh Chain after real histories',
          );
          final after = DeckManager.apply(
            purifyRoundTrip(state),
            PlayCardAction(CardId.purify, target: removed),
          );
          purifyEqual(
            after.rules.pieceEffects.single.id,
            removed == 'e102' ? 'e103' : 'e102',
            'only selected effect removed',
          );
          purifyRejects(after, ChessMoveAction(choose('b3b5', 'b6b4')));
          purifyRequire(
            purifyMoves(after).contains(choose('b3b4', 'b6b5')),
            'quiet rook action remains',
          );
          final moved = DeckManager.apply(
            after,
            ChessMoveAction(choose('b3b4', 'b6b5')),
          );
          purifyEqual(
            moved.rules.pieceEffects,
            [],
            'remaining effect consumed by its correct lifetime',
          );
          _inventory(moved);
        }),
      );
    }

    cases.add(
      PurifyAuditCase('$tag/unselected-mine-and-vows-are-not-cleansed', () {
        var state = purifyAddEffect(
          purifyPosition(ordinaryFen),
          rook,
          PieceEffectType.chain,
        );
        state = purifyEdit(state, (draft) {
          draft.mana[side] = 4;
          draft.mana[enemy] = 1;
          draft.boardEffects.add(
            BoardEffectInstance(
              id: 'persistent-mine',
              type: BoardEffectType.mine,
              owner: enemy,
              responseSide: side,
              duration: EffectDuration.persistent,
              squares: [square('h3', 'h6')],
            ),
          );
          draft.vows.addAll([
            VowState(
              id: 'hunt',
              type: VowType.hunt,
              owner: side,
              pieceId: draft.pieceIds[square('b5', 'b4')],
              square: null,
              remainingMoves: 2,
            ),
            VowState(
              id: 'watch',
              type: VowType.watch,
              owner: enemy,
              pieceId: null,
              square: square('b5', 'b4'),
              remainingMoves: 1,
            ),
          ]);
        });
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          after.rules.vows.map((vow) => vow.toJson()).toList(),
          state.rules.vows.map((vow) => vow.toJson()).toList(),
          'both vow contracts survive Purify',
        );
        purifyEqual(
          after.rules.boardEffects.single.id,
          'persistent-mine',
          'untriggered mine survives',
        );
        final moved = DeckManager.apply(after, ChessMoveAction(rookCapture));
        purifyEqual(
          moved.rules.mana[side],
          5,
          '4 - 1 Purify + 2 normal Hunt capture',
        );
        purifyEqual(
          moved.rules.mana[enemy],
          4,
          '1 + 2 Watch arrival + 1 turn income',
        );
        purifyEqual(
          moved.rules.vows,
          [],
          'both vows resolve at chess, not at removal',
        );
        purifyEqual(
          moved.rules.boardEffects.single.id,
          'persistent-mine',
          'remote mine remains persistent',
        );
      }),
    );

    cases.add(
      PurifyAuditCase('$tag/terminal-clock-and-checkmate-precedence', () {
        final quietState = purifyAddEffect(
          purifyPosition(
            choose(
              '6k1/8/8/1p6/8/8/1R6/5K2 w - - 149 23',
              '5k2/1r6/8/8/1P6/8/8/6K1 b - - 149 23',
            ),
          ),
          rook,
          PieceEffectType.freeze,
        );
        final quietReady = DeckManager.apply(
          quietState,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        purifyEqual(
          quietReady.rules.board.halfmoveClock,
          149,
          'card neither resets nor advances clock',
        );
        final quiet = DeckManager.apply(
          quietReady,
          ChessMoveAction(choose('b2b3', 'b7b6')),
        );
        purifyEqual(
          quiet.rules.terminal?.reason,
          'seventy_five_moves',
          'quiet chess reaches 150',
        );
        purifyEqual(
          quiet.rules.phase,
          BattlePhase.terminal,
          'automatic draw terminal',
        );
        purifyEqual(quiet.rules.drawCounts[side], 3, 'no end-match deck draw');
        purifyEqual(
          purifyMoves(quiet),
          [],
          'no stranded action in terminal phase',
        );
        final capture = DeckManager.apply(
          quietReady,
          ChessMoveAction(rookCapture),
        );
        purifyEqual(
          capture.rules.board.halfmoveClock,
          0,
          'restored capture resets 149 counter',
        );
        purifyEqual(
          capture.rules.terminal,
          null,
          'capture avoids automatic draw',
        );
        final mateState = purifyAddEffect(
          purifyPosition(
            choose(
              '7k/8/5KQ1/8/8/8/8/8 w - - 149 23',
              '8/8/8/8/8/5kq1/8/7K b - - 149 23',
            ),
          ),
          square('g6', 'g3'),
          PieceEffectType.freeze,
        );
        final mateReady = DeckManager.apply(
          mateState,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
        final mate = DeckManager.apply(
          mateReady,
          ChessMoveAction(choose('g6g7', 'g3g2')),
        );
        purifyEqual(
          mate.rules.board.halfmoveClock,
          150,
          'quiet mate also reaches draw counter',
        );
        purifyEqual(
          mate.rules.terminal?.toJson(),
          {
            'reason': 'checkmate',
            'winner': sideWire(side),
            'mateByRestriction': false,
            'mateBySpecialMove': false,
            'stalemateByRestriction': false,
          },
          'ordinary checkmate takes precedence, Purify is not special movement',
        );
        purifyEqual(
          mate.rules.drawCounts[side],
          3,
          'no draw after mating move',
        );
        purifyRejects(
          mate,
          const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
        );
      }),
    );

    for (final stalemate in [false, true]) {
      cases.add(
        PurifyAuditCase(
          '$tag/restriction-terminal-is-not-a-Purify-softlock/stalemate=$stalemate',
          () {
            var state = purifyPosition(
              stalemate
                  ? choose(
                    '8/8/8/8/2b5/2k5/7r/KR6 b - - 0 23',
                    'kr6/7R/2K5/2B5/8/8/8/8 w - - 0 23',
                  )
                  : choose(
                    '8/8/8/8/2b5/2k5/1R5r/K7 b - - 0 23',
                    'k7/1r5R/2K5/2B5/8/8/8/8 w - - 0 23',
                  ),
              hand: const [CardId.freeze, CardId.prophecy, CardId.shelter],
              enemyHand: const [CardId.purify, CardId.prophecy, CardId.shelter],
            );
            state = DeckManager.apply(
              state,
              PlayCardAction(
                CardId.freeze,
                target: stalemate ? square('b1', 'b8') : square('b2', 'b7'),
              ),
            );
            final ended = DeckManager.apply(
              state,
              ChessMoveAction(choose('h2h1', 'h7h8')),
            );
            purifyEqual(
              ended.rules.phase,
              BattlePhase.terminal,
              'terminal before victim card window',
            );
            purifyEqual(
              ended.rules.terminal?.toJson(),
              {
                'reason': stalemate ? 'stalemate' : 'checkmate',
                'winner': stalemate ? null : sideWire(enemy),
                'mateByRestriction': !stalemate,
                'mateBySpecialMove': false,
                'stalemateByRestriction': stalemate,
              },
              'intentional restriction terminal, not an active empty-action hang',
            );
            purifyRequire(
              ended.hidden.hands[side]!.contains(CardId.purify),
              'victim still holds Purify',
            );
            purifyEqual(
              BattleRulesCore.legalActions(ended.view(side)),
              [],
              'Purify cannot reopen a terminal match',
            );
            purifyRejects(
              ended,
              const PlayCardAction(CardId.purify, target: 'e101'),
            );
          },
        ),
      );
    }
  }
  return cases;
}
