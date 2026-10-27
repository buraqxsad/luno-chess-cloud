import 'dart:convert';
import 'dart:io';

import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const chainWhite = PieceColor.white;
const chainBlack = PieceColor.black;

int chainSquare(String text) =>
    Square.of(text.codeUnitAt(0) - 97, text.codeUnitAt(1) - 49);

int chainReflectSquare(int square) => square ^ 56;

String chainReflectMove(String uci) =>
    '${Square.algebraic(chainReflectSquare(chainSquare(uci.substring(0, 2))))}'
    '${Square.algebraic(chainReflectSquare(chainSquare(uci.substring(2, 4))))}'
    '${uci.length == 5 ? uci[4] : ''}';

Board chainReflectBoard(Board board) => Board(
  squares: [
    for (var square = 0; square < 64; square++)
      board.squares[chainReflectSquare(square)]?.copyWith(
        color: board.squares[chainReflectSquare(square)]!.color.opposite,
      ),
  ],
  turn: board.turn.opposite,
  castling: ((board.castling & 3) << 2) | ((board.castling & 12) >> 2),
  enPassant:
      board.enPassant == null ? null : chainReflectSquare(board.enPassant!),
  halfmoveClock: board.halfmoveClock,
  fullmoveNumber: board.fullmoveNumber,
);

List<CardId> _deck(List<CardId> hand) {
  if (hand.length != 3 || hand.toSet().length != 3) {
    throw ArgumentError('Chain fixtures require exactly three unique cards');
  }
  return [
    ...hand,
    ...CardId.values.where((card) => !hand.contains(card)).take(7),
  ];
}

AuthoritativeBattleState chainPosition(
  String fen, {
  bool reflect = false,
  BattlePhase phase = BattlePhase.chess,
  List<CardId> whiteHand = const [CardId.chain, CardId.purify, CardId.angryN],
  List<CardId> blackHand = const [CardId.chain, CardId.purify, CardId.angryN],
}) {
  final board = Board.fromFen(fen);
  final state = DeckManager.newBattle(
    board: reflect ? chainReflectBoard(board) : board,
    white: _deck(reflect ? blackHand : whiteHand),
    black: _deck(reflect ? whiteHand : blackHand),
  );
  if (state.rules.terminal != null) {
    throw ArgumentError('Unexpected terminal Chain fixture: $fen');
  }
  return chainEdit(state, (draft) {
    draft.phase = phase;
    draft.ownTurns = {chainWhite: 2, chainBlack: 2};
    draft.mana = {chainWhite: 6, chainBlack: 6};
    draft.repetitions = {};
  });
}

AuthoritativeBattleState chainEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState chainAddEffect(
  AuthoritativeBattleState state,
  int square, {
  String id = 'v223-chain',
  PieceEffectType type = PieceEffectType.chain,
  EffectDuration duration = EffectDuration.move,
}) => chainEdit(state, (draft) {
  final side = state.rules.board.pieceAt(square)!.color;
  draft.pieceEffects.add(
    ActivePieceEffect(
      id: id,
      type: type,
      owner: side.opposite,
      pieceId: draft.pieceIds[square]!,
      responseSide: side,
      duration: duration,
    ),
  );
});

AuthoritativeBattleState chainRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

void chainRequire(bool condition, String detail) {
  if (!condition) throw StateError('V223 Chain: $detail');
}

void chainEqual(Object? actual, Object? expected, String detail) {
  Object encode(Object? value) {
    if (value is Enum) return '${value.runtimeType}.${value.name}';
    throw ArgumentError('Unexpected Chain assertion value: $value');
  }

  chainRequire(
    jsonEncode(canonicalObject(actual), toEncodable: encode) ==
        jsonEncode(canonicalObject(expected), toEncodable: encode),
    '$detail; expected=$expected actual=$actual',
  );
}

Set<String> chainMoves(AuthoritativeBattleState state) =>
    BattleRulesCore.legalActions(
      state.view(state.rules.board.turn),
    ).whereType<ChessMoveAction>().map((action) => action.uci).toSet();

void chainRejects(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(state.toJson());
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    rejected = error.message == 'illegal-action';
  }
  chainRequire(rejected, 'must reject ${action.toJson()} as illegal-action');
  chainEqual(jsonEncode(state.toJson()), before, 'rejection is atomic');
}

class ChainCoreCase {
  final String name;
  final void Function() run;
  const ChainCoreCase(this.name, this.run);
}

List<ChainCoreCase> chainCoreCases() {
  final cases = <ChainCoreCase>[];
  for (final reflected in [false, true]) {
    final side = reflected ? chainBlack : chainWhite;
    final prefix = sideWire(side);
    int square(String text) =>
        reflected ? chainReflectSquare(chainSquare(text)) : chainSquare(text);
    String uci(String text) => reflected ? chainReflectMove(text) : text;
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.chess,
    }) => chainPosition(fen, reflect: reflected, phase: phase);

    cases.add(
      ChainCoreCase('$prefix paired en passant after card pass', () {
        final baseline = position('7k/8/8/2PpP3/8/8/8/4K3 w - d6 0 10');
        chainRequire(chainMoves(baseline).contains(uci('e5d6')), 'baseline EP');
        chainRequire(chainMoves(baseline).contains(uci('c5d6')), 'paired EP');
        final chained = chainAddEffect(baseline, square('e5'));
        final card = chainEdit(
          chained,
          (draft) => draft.phase = BattlePhase.card,
        );
        final passed = DeckManager.apply(card, const PassAction());
        chainEqual(
          passed.rules.board.enPassant,
          square('d6'),
          'pass retains EP',
        );
        chainRequire(
          !chainMoves(passed).contains(uci('e5d6')),
          'chained EP denied',
        );
        chainRequire(
          chainMoves(passed).contains(uci('c5d6')),
          'other EP retained',
        );
        chainRequire(
          chainMoves(passed).contains(uci('e5e6')),
          'quiet pawn retained',
        );
        chainRejects(passed, ChessMoveAction(uci('e5d6')));
        final victimId = passed.rules.pieceIds[square('d5')];
        final after = DeckManager.apply(passed, ChessMoveAction(uci('c5d6')));
        chainRequire(
          !after.rules.pieceIds.contains(victimId),
          'EP victim removed',
        );
        chainRequire(
          after.rules.pieceEffects.isEmpty,
          'other-piece EP expires Chain',
        );
        chainEqual(
          after.rules.board.halfmoveClock,
          0,
          'EP resets halfmove clock',
        );
      }),
    );

    cases.add(
      ChainCoreCase('$prefix Purify restores EP and entry Mine survives', () {
        var state = chainAddEffect(
          position(
            '7k/8/8/3pP3/8/8/8/4K3 w - d6 0 10',
            phase: BattlePhase.card,
          ),
          square('e5'),
        );
        state = chainEdit(state, (draft) {
          draft.boardEffects.add(
            BoardEffectInstance(
              id: 'v223-ep-mine',
              type: BoardEffectType.mine,
              owner: side.opposite,
              squares: [square('d6')],
              responseSide: side,
              duration: EffectDuration.persistent,
            ),
          );
        });
        final pawnId = state.rules.pieceIds[square('e5')];
        final before = jsonEncode(state.toJson());
        final purified = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-chain'),
        );
        chainRequire(
          chainMoves(purified).contains(uci('e5d6')),
          'Purify restores EP',
        );
        chainEqual(
          purified.rules.board.enPassant,
          square('d6'),
          'Purify retains EP',
        );
        final after = DeckManager.apply(purified, ChessMoveAction(uci('e5d6')));
        chainEqual(
          after.rules.pieceEffects.single.type,
          PieceEffectType.mineDebuff,
          'fresh entry Mine remains',
        );
        chainEqual(
          after.rules.pieceEffects.single.pieceId,
          pawnId,
          'Mine follows EP mover',
        );
        chainEqual(
          after.rules.pieceEffects.single.duration,
          EffectDuration.pieceMove,
          'Mine uses piece lifetime',
        );
        chainRequire(
          after.rules.boardEffects.isEmpty,
          'Mine consumed on EP arrival',
        );
        chainEqual(jsonEncode(state.toJson()), before, 'input not mutated');
      }),
    );

    cases.add(
      ChainCoreCase('$prefix chained victim can still be taken en passant', () {
        final state = chainAddEffect(
          position('7k/8/8/3pP3/8/8/8/4K3 w - d6 0 10'),
          square('d5'),
        );
        final victim = state.rules.pieceIds[square('d5')];
        final after = DeckManager.apply(state, ChessMoveAction(uci('e5d6')));
        chainRequire(
          !after.rules.pieceIds.contains(victim),
          'victim identity gone',
        );
        chainRequire(
          after.rules.pieceEffects.isEmpty,
          'captured victim Chain removed',
        );
      }),
    );

    cases.add(
      ChainCoreCase('$prefix Purify cannot legalize discovered-check EP', () {
        final state = chainAddEffect(
          position('k7/8/8/r4pPK/8/8/8/8 w - f6 0 10', phase: BattlePhase.card),
          square('g5'),
        );
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'v223-chain'),
        );
        chainRequire(
          !chainMoves(after).contains(uci('g5f6')),
          'discovered check remains illegal',
        );
        chainRequire(
          chainMoves(after).contains(uci('g5g6')),
          'safe quiet remains',
        );
        chainRejects(after, ChessMoveAction(uci('g5f6')));
      }),
    );

    cases.add(
      ChainCoreCase(
        '$prefix Angry Knight captures filtered before authorization',
        () {
          final original = position(
            '7k/8/8/3p4/2BNp3/8/8/4K3 w - - 0 10',
            phase: BattlePhase.card,
          );
          final state = chainAddEffect(original, square('d4'));
          final normal =
              BattleRulesCore.specialMoves(
                original.rules,
                CardId.angryN,
                square('d4'),
                side,
              ).map((move) => move.uci).toSet();
          chainRequire(
            normal.containsAll([uci('d4d5'), uci('d4e4')]),
            'baseline special captures',
          );
          final expected = {uci('d4d3')};
          final actual =
              BattleRulesCore.specialMoves(
                state.rules,
                CardId.angryN,
                square('d4'),
                side,
              ).map((move) => move.uci).toSet();
          chainEqual(
            actual.toList()..sort(),
            expected.toList()..sort(),
            'only empty special destination',
          );
          final authorized = DeckManager.apply(
            state,
            PlayCardAction(CardId.angryN, target: square('d4')),
          );
          chainEqual(
            chainMoves(authorized).toList(),
            expected.toList(),
            'authorization preserves restriction',
          );
          chainRejects(authorized, ChessMoveAction(uci('d4e4')));
          chainRejects(authorized, ChessMoveAction(uci('e1f1')));
          final after = DeckManager.apply(
            authorized,
            ChessMoveAction(uci('d4d3')),
          );
          chainRequire(after.rules.special == null, 'special consumed');
          chainRequire(
            after.rules.pieceEffects.isEmpty,
            'quiet special consumes Chain',
          );
          chainEqual(
            after.rules.ply,
            state.rules.ply + 1,
            'one chess move only',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix capture-only Angry Knight check escape is not offered',
        () {
          final original = position(
            'k7/8/8/8/8/8/3Nr3/4K3 w - - 0 10',
            phase: BattlePhase.card,
          );
          final state = chainAddEffect(original, square('d2'));
          chainRequire(
            MoveGen.inCheck(state.rules.board, side),
            'starts in check',
          );
          chainEqual(
            BattleRulesCore.specialMoves(
              original.rules,
              CardId.angryN,
              square('d2'),
              side,
            ).map((move) => move.uci).toList(),
            [uci('d2e2')],
            'baseline special capture escape',
          );
          chainRequire(
            BattleRulesCore.cardTargets(
              state.view(side),
              CardId.angryN,
            ).isEmpty,
            'unusable mandatory movement card not offered',
          );
          chainRejects(
            state,
            PlayCardAction(CardId.angryN, target: square('d2')),
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix check escape requires legal noncapture by other piece',
        () {
          final original = position('7k/8/8/8/1b6/8/8/1RB1K3 w - - 0 10');
          chainRequire(
            chainMoves(original).contains(uci('b1b4')),
            'baseline capture escape',
          );
          final state = chainAddEffect(original, square('b1'));
          chainRequire(
            !chainMoves(state).contains(uci('b1b4')),
            'capture escape blocked',
          );
          chainRequire(
            !chainMoves(state).contains(uci('b1b2')),
            'quiet move cannot ignore check',
          );
          chainRequire(
            chainMoves(state).contains(uci('c1d2')),
            'other piece interposition allowed',
          );
          final after = DeckManager.apply(state, ChessMoveAction(uci('c1d2')));
          chainRequire(
            !MoveGen.inCheck(after.rules.board, side),
            'king safe after block',
          );
          chainRequire(
            after.rules.pieceEffects.isEmpty,
            'interposition expires Chain',
          );
        },
      ),
    );

    for (final promotion in ['q', 'r', 'b', 'n']) {
      cases.add(
        ChainCoreCase(
          '$prefix promotion $promotion capture denied, quiet Mine accepted',
          () {
            final original = position('k6r/6P1/8/8/8/8/8/4K3 w - - 0 10');
            final state = chainEdit(chainAddEffect(original, square('g7')), (
              draft,
            ) {
              draft.boardEffects.add(
                BoardEffectInstance(
                  id: 'v223-promotion-mine',
                  type: BoardEffectType.mine,
                  owner: side.opposite,
                  squares: [square('g8')],
                  responseSide: side,
                  duration: EffectDuration.persistent,
                ),
              );
            });
            final pawnId = state.rules.pieceIds[square('g7')];
            chainRequire(
              chainMoves(original).contains(uci('g7h8$promotion')),
              'baseline promotion capture',
            );
            chainRejects(state, ChessMoveAction(uci('g7h8$promotion')));
            final after = DeckManager.apply(
              state,
              ChessMoveAction(uci('g7g8$promotion')),
            );
            chainEqual(
              after.rules.pieceIds[square('g8')],
              pawnId,
              'promotion retains identity',
            );
            chainEqual(
              after.rules.pieceEffects.single.pieceId,
              pawnId,
              'Mine follows promoted piece',
            );
            chainEqual(
              after.rules.pieceEffects.single.type,
              PieceEffectType.mineDebuff,
              'fresh Mine replaces expired Chain',
            );
            chainEqual(
              after.rules.board.pieceAt(square('g8'))!.type,
              {
                'q': PieceType.queen,
                'r': PieceType.rook,
                'b': PieceType.bishop,
                'n': PieceType.knight,
              }[promotion],
              'correct promotion type',
            );
          },
        ),
      );
    }

    cases.add(
      ChainCoreCase(
        '$prefix chained castling rook consumes old Mine but triggers fresh Mine',
        () {
          var state = chainAddEffect(
            position('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 10'),
            square('h1'),
          );
          state = chainAddEffect(
            state,
            square('h1'),
            id: 'v223-old-mine',
            type: PieceEffectType.mineDebuff,
            duration: EffectDuration.pieceMove,
          );
          state = chainAddEffect(state, square('a8'), id: 'v223-enemy-chain');
          state = chainEdit(state, (draft) {
            draft.boardEffects.add(
              BoardEffectInstance(
                id: 'v223-castle-mine',
                type: BoardEffectType.mine,
                owner: side.opposite,
                squares: [square('f1')],
                responseSide: side,
                duration: EffectDuration.persistent,
              ),
            );
          });
          chainRequire(
            chainMoves(state).contains(uci('e1g1')),
            'Chain does not ban castling',
          );
          final rookId = state.rules.pieceIds[square('h1')];
          final after = DeckManager.apply(state, ChessMoveAction(uci('e1g1')));
          chainEqual(
            after.rules.pieceIds[square('f1')],
            rookId,
            'castling rook identity',
          );
          chainRequire(
            after.rules.pieceEffects.any(
              (effect) => effect.id == 'v223-enemy-chain',
            ),
            'other side response survives',
          );
          chainRequire(
            !after.rules.pieceEffects.any(
              (effect) => effect.id == 'v223-old-mine',
            ),
            'old Mine consumed by rook relocation',
          );
          final fresh =
              after.rules.pieceEffects
                  .where((effect) => effect.pieceId == rookId)
                  .single;
          chainEqual(
            fresh.type,
            PieceEffectType.mineDebuff,
            'new Mine survives castling',
          );
          chainRequire(fresh.id != 'v223-old-mine', 'fresh effect identity');
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix Chain does not erase enemy attacks for castling',
        () {
          final state = chainAddEffect(
            position('4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 10'),
            square('f8'),
          );
          chainRequire(
            MoveGen.isSquareAttacked(
              state.rules.board,
              square('f1'),
              side.opposite,
            ),
            'geometric attack survives Chain',
          );
          chainRequire(
            !chainMoves(state).contains(uci('e1g1')),
            'cannot castle through attacked f-file',
          );
          chainRequire(
            chainMoves(state).contains(uci('e1c1')),
            'safe opposite castling remains',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix Chain target selection and exact-once card lifecycle',
        () {
          final initial = position(
            '7k/8/8/8/3r4/8/8/R3K3 w - - 0 10',
            phase: BattlePhase.card,
          );
          final view = initial.view(side);
          final actions = BattleRulesCore.legalActions(view);
          final selection = BattleInteraction()..select(CardId.chain, actions);
          chainEqual(selection.targets(view, actions).toList(), [
            square('d4'),
          ], 'only opposing rook');
          chainRequire(
            selection.tap(square('d4'), view, actions).isEmpty,
            'target does not submit',
          );
          chainEqual(selection.preview().toList(), [
            square('d4'),
          ], 'preview matches target');
          final play = selection.play!;
          final afterCard = DeckManager.apply(initial, play);
          chainEqual(afterCard.rules.mana[side], 4, 'Chain costs two');
          chainEqual(
            afterCard.rules.phase,
            BattlePhase.chess,
            'card ends own card window',
          );
          chainEqual(afterCard.rules.used[side], [
            CardId.chain,
          ], 'one used card');
          chainEqual(
            afterCard.hidden.hands[side]!.length,
            2,
            'one hidden card consumed',
          );
          chainEqual(
            afterCard.rules.pieceEffects.single.responseSide,
            side.opposite,
            'enemy response side',
          );
          chainRejects(afterCard, play);
          final ownMove = DeckManager.apply(
            afterCard,
            ChessMoveAction(uci('a1a2')),
          );
          chainEqual(
            ownMove.rules.pieceEffects.length,
            1,
            'caster move does not expire effect',
          );
          final enemyPass = DeckManager.apply(ownMove, const PassAction());
          chainEqual(
            enemyPass.rules.pieceEffects.length,
            1,
            'enemy card pass does not expire effect',
          );
          final enemyMove = DeckManager.apply(
            enemyPass,
            ChessMoveAction(uci('h8g8')),
          );
          chainRequire(
            enemyMove.rules.pieceEffects.isEmpty,
            'different-piece move expires effect',
          );
          selection.synchronize(afterCard.view(side), 1);
          chainRequire(
            selection.card == null && selection.play == null,
            'accepted version clears selection',
          );
        },
      ),
    );

    for (final removed in ['v223-chain', 'v223-old-mine']) {
      cases.add(
        ChainCoreCase(
          '$prefix Purify $removed leaves the other capture ban',
          () {
            var state = chainAddEffect(
              position(
                '7k/8/8/8/Rp6/8/8/4K3 w - - 0 10',
                phase: BattlePhase.card,
              ),
              square('a4'),
            );
            state = chainAddEffect(
              state,
              square('a4'),
              id: 'v223-old-mine',
              type: PieceEffectType.mineDebuff,
              duration: EffectDuration.pieceMove,
            );
            final view = state.view(side),
                actions = BattleRulesCore.legalActions(state.view(side));
            final selection =
                BattleInteraction()..select(CardId.purify, actions);
            final choices = selection.tap(square('a4'), view, actions);
            chainEqual(
              choices
                  .map((action) => (action as PlayCardAction).target)
                  .toList()
                ..sort(),
              ['v223-chain', 'v223-old-mine'],
              'both effect IDs offered at one piece',
            );
            chainRequire(
              selection.play == null,
              'overlap requires explicit choice',
            );
            selection.play = choices.whereType<PlayCardAction>().singleWhere(
              (action) => action.target == removed,
            );
            chainEqual(selection.preview().toList(), [
              square('a4'),
            ], 'chosen effect previews correct piece');
            final after = DeckManager.apply(state, selection.play!);
            chainEqual(
              after.rules.pieceEffects.length,
              1,
              'only one effect removed',
            );
            chainRequire(
              !after.rules.pieceEffects.any((effect) => effect.id == removed),
              'selected ID removed',
            );
            chainRejects(after, ChessMoveAction(uci('a4b4')));
            final moved = DeckManager.apply(
              after,
              ChessMoveAction(uci('a4a5')),
            );
            chainRequire(
              moved.rules.pieceEffects.isEmpty,
              'quiet affected-piece move clears remaining restriction',
            );
          },
        ),
      );
    }

    cases.add(
      ChainCoreCase(
        '$prefix different-piece move expires Chain but not stacked Mine',
        () {
          var state = chainAddEffect(
            position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
            square('a4'),
          );
          state = chainAddEffect(
            state,
            square('a4'),
            id: 'v223-old-mine',
            type: PieceEffectType.mineDebuff,
            duration: EffectDuration.pieceMove,
          );
          final after = DeckManager.apply(
            chainRoundTrip(state),
            ChessMoveAction(uci('e1f1')),
          );
          chainEqual(
            after.rules.pieceEffects.single.id,
            'v223-old-mine',
            'piece-bound Mine remains',
          );
          chainEqual(
            after.rules.pieceIds[square('a4')],
            state.rules.pieceIds[square('a4')],
            'target stayed put',
          );
          chainEqual(
            chainRoundTrip(after).toJson(),
            after.toJson(),
            'projection preserves exact lifetime',
          );
        },
      ),
    );
  }
  cases.addAll(chainIndependentGeometryCases());
  cases.addAll(chainLifecycleCases());
  return cases;
}

List<ChainCoreCase> chainIndependentGeometryCases() {
  final corpus =
      jsonDecode(File('qa/v223/chain/geometry_cases.json').readAsStringSync())
          as List;
  return [
    for (final reflect in [false, true])
      for (final raw in corpus)
        ChainCoreCase(
          '${reflect ? 'b' : 'w'} independent geometry ${raw['id']}',
          () {
            final fixture = raw as Map;
            final side = reflect ? chainBlack : chainWhite;
            final special =
                fixture['special'] == null
                    ? null
                    : CardId.parse(fixture['special'] as String);
            final from =
                chainSquare(fixture['from'] as String) ^ (reflect ? 56 : 0);
            final hand = [
              special ?? CardId.angryN,
              CardId.chain,
              CardId.purify,
            ];
            var state = chainPosition(
              fixture['fen'] as String,
              reflect: reflect,
              whiteHand: hand,
              blackHand: hand,
            );
            if (fixture['movedPawn'] == true) {
              state = chainEdit(
                state,
                (draft) => draft.movedPawns.add(draft.pieceIds[from]!),
              );
            }
            state = chainAddEffect(state, from);
            final expected = [
              for (final move in fixture['expected'] as List)
                reflect ? chainReflectMove(move as String) : move as String,
            ]..sort();
            final actual =
                special == null
                    ? BattleRulesCore.legalMoves(
                      state.rules,
                      side,
                    ).where((move) => move.from == from).toList()
                    : BattleRulesCore.specialMoves(
                      state.rules,
                      special,
                      from,
                      side,
                    );
            chainEqual(
              actual.map((move) => move.uci).toList()..sort(),
              expected,
              'hand-authored complete move set for ${fixture['id']}',
            );
            if (special != null) {
              final cardWindow = chainEdit(
                state,
                (draft) => draft.phase = BattlePhase.card,
              );
              final offered = BattleRulesCore.legalActions(
                cardWindow.view(side),
              ).whereType<PlayCardAction>().any(
                (action) => action.card == special && action.target == from,
              );
              chainEqual(
                offered,
                expected.isNotEmpty,
                'mandatory card only offered with a legal destination',
              );
              if (expected.isNotEmpty) {
                state = DeckManager.apply(
                  cardWindow,
                  PlayCardAction(special, target: from),
                );
                chainEqual(
                  chainMoves(state).toList()..sort(),
                  expected,
                  'authorization cannot add a capture',
                );
              }
            }
            final before = jsonEncode(state.toJson());
            for (final move in expected) {
              final after = DeckManager.apply(state, ChessMoveAction(move));
              chainRequire(
                !after.rules.pieceEffects.any(
                  (effect) => effect.id == 'v223-chain',
                ),
                'response completion expires Chain',
              );
              chainEqual(after.rules.ply, 1, 'one completed move');
              chainEqual(after.rules.special, null, 'authorization consumed');
              chainEqual(
                jsonEncode(state.toJson()),
                before,
                'input snapshot unchanged',
              );
            }
          },
        ),
  ];
}

List<ChainCoreCase> chainLifecycleCases() {
  final cases = <ChainCoreCase>[];
  for (final reflect in [false, true]) {
    final side = reflect ? chainBlack : chainWhite;
    final enemy = side.opposite;
    final prefix = sideWire(side);
    int square(String value) => chainSquare(value) ^ (reflect ? 56 : 0);
    String move(String value) => reflect ? chainReflectMove(value) : value;
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.card,
      List<CardId> hand = const [CardId.chain, CardId.purify, CardId.shelter],
    }) => chainPosition(
      fen,
      reflect: reflect,
      phase: phase,
      whiteHand: hand,
      blackHand: hand,
    );

    cases.add(
      ChainCoreCase('$prefix new Shelter does not cleanse old Chain', () {
        final initial = chainAddEffect(
          position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
          square('a4'),
        );
        final guarded = DeckManager.apply(
          initial,
          PlayCardAction(CardId.shelter, target: square('a4')),
        );
        chainEqual(
          guarded.rules.pieceEffects.length,
          2,
          'both effects coexist',
        );
        chainRejects(guarded, ChessMoveAction(move('a4b4')));
        chainRequire(
          chainMoves(guarded).contains(move('a4a5')),
          'quiet remains',
        );
        final moved = DeckManager.apply(guarded, ChessMoveAction(move('a4a5')));
        chainEqual(
          moved.rules.pieceEffects.single.type,
          PieceEffectType.shelter,
          'own response expires only Chain',
        );
        chainEqual(
          moved.rules.pieceEffects.single.pieceId,
          initial.rules.pieceIds[square('a4')],
          'protection follows identity',
        );
        final passed = DeckManager.apply(moved, const PassAction());
        chainRequire(
          passed.rules.pieceEffects.isEmpty,
          'enemy card-window closure expires Shelter',
        );
      }),
    );

    cases.add(
      ChainCoreCase('$prefix new Fog does not cleanse old Chain', () {
        final initial = chainAddEffect(
          position(
            '7k/8/8/8/Rp6/8/8/4K3 w - - 0 10',
            hand: const [CardId.fog, CardId.purify, CardId.chain],
          ),
          square('a4'),
        );
        final guarded = DeckManager.apply(
          initial,
          PlayCardAction(CardId.fog, target: square('a4')),
        );
        chainRejects(guarded, ChessMoveAction(move('a4b4')));
        final moved = DeckManager.apply(guarded, ChessMoveAction(move('e1f1')));
        chainRequire(
          moved.rules.pieceEffects.isEmpty,
          'other-piece response expires Chain',
        );
        chainEqual(
          moved.rules.boardEffects.single.type,
          BoardEffectType.fog,
          'own move does not expire protection response',
        );
        chainRequire(
          DeckManager.apply(
            moved,
            const PassAction(),
          ).rules.boardEffects.isEmpty,
          'enemy pass closes Fog lifetime',
        );
      }),
    );

    cases.add(
      ChainCoreCase('$prefix opposing response lifetimes stay independent', () {
        var initial = chainAddEffect(
          position(
            '7k/8/7r/8/Rp6/8/8/4K3 w - - 0 10',
            phase: BattlePhase.chess,
          ),
          square('a4'),
        );
        initial = chainAddEffect(
          initial,
          square('h6'),
          id: 'v223-opposing-chain',
        );
        final ownMove = DeckManager.apply(
          initial,
          ChessMoveAction(move('e1f1')),
        );
        chainEqual(
          ownMove.rules.pieceEffects.single.id,
          'v223-opposing-chain',
          'only current response consumed',
        );
        final passed = DeckManager.apply(ownMove, const PassAction());
        chainEqual(
          passed.rules.pieceEffects.single.id,
          'v223-opposing-chain',
          'pass is not a completed chess move',
        );
        final enemyMove = DeckManager.apply(
          passed,
          ChessMoveAction(move('h8g8')),
        );
        chainRequire(
          enemyMove.rules.pieceEffects.isEmpty,
          'other side completion expires its Chain',
        );
      }),
    );

    cases.add(
      ChainCoreCase('$prefix captured target cannot poison its old square', () {
        final initial = position('1r5k/8/8/8/Rr6/8/8/4K3 w - - 0 10');
        final target = initial.rules.pieceIds[square('b4')];
        final otherRook = initial.rules.pieceIds[square('b8')];
        final cast = DeckManager.apply(
          initial,
          PlayCardAction(CardId.chain, target: square('b4')),
        );
        final taken = DeckManager.apply(cast, ChessMoveAction(move('a4b4')));
        chainRequire(
          !taken.rules.pieceIds.contains(target),
          'target identity removed',
        );
        chainRequire(
          taken.rules.pieceEffects.isEmpty,
          'target capture cleans effect early',
        );
        final response = DeckManager.apply(taken, const PassAction());
        chainRequire(
          chainMoves(response).contains(move('b8b4')),
          'new piece can capture onto old target square',
        );
        final retaken = DeckManager.apply(
          response,
          ChessMoveAction(move('b8b4')),
        );
        chainEqual(
          retaken.rules.pieceIds[square('b4')],
          otherRook,
          'unaffected replacement identity',
        );
        chainRequire(
          retaken.rules.pieceEffects.isEmpty,
          'no orphan resurrection',
        );
      }),
    );

    for (final card in [CardId.prophecy, CardId.fateExchange]) {
      cases.add(
        ChainCoreCase(
          '$prefix Chain survives ${card.wire} inspect and every resolution',
          () {
            final initial = chainAddEffect(
              position(
                '7k/8/8/8/Rp6/8/8/4K3 w - - 0 10',
                hand: [card, CardId.chain, CardId.purify],
              ),
              square('a4'),
            );
            final pending = DeckManager.apply(
              initial,
              PlayCardAction(
                card,
                sacrifice: card == CardId.fateExchange ? CardId.chain : null,
              ),
            );
            chainEqual(
              pending.rules.phase,
              BattlePhase.pending,
              'private choice pending',
            );
            chainEqual(
              pending.rules.pieceEffects.single.id,
              'v223-chain',
              'inspection retains effect',
            );
            chainEqual(pending.rules.ply, 0, 'inspection is not a move');
            chainRequire(
              pending.view(enemy).knowledge.pendingCards.isEmpty,
              'opponent projection does not learn inspected cards',
            );
            chainRequire(
              pending.view(enemy).knowledge.knownUpcomingCards.isEmpty,
              'opponent projection does not learn deck order',
            );
            chainEqual(
              pending.view(enemy).rules.pieceEffects.single.toJson(),
              pending.view(side).rules.pieceEffects.single.toJson(),
              'Chain is public',
            );
            final resolutions =
                BattleRulesCore.legalActions(
                  pending.view(side),
                ).whereType<ResolveAction>().toList();
            chainEqual(
              resolutions.length,
              card == CardId.prophecy ? 2 : 6,
              'independent count of bounded choices',
            );
            for (final resolution in resolutions) {
              final resolved = DeckManager.apply(
                chainRoundTrip(pending),
                resolution,
              );
              chainEqual(
                resolved.rules.pieceEffects.single.id,
                'v223-chain',
                'resolution retains effect despite card sacrifice',
              );
              chainEqual(resolved.rules.ply, 0, 'resolution is not a move');
              chainRejects(resolved, ChessMoveAction(move('a4b4')));
              chainRequire(
                chainMoves(resolved).contains(move('a4a5')),
                'quiet remains',
              );
              final moved = DeckManager.apply(
                resolved,
                ChessMoveAction(move('a4a5')),
              );
              chainRequire(
                moved.rules.pieceEffects.isEmpty,
                'only chess completion expires effect',
              );
              chainEqual(
                moved.rules.ply,
                1,
                'no extra turn from pending resolution',
              );
            }
          },
        ),
      );
    }

    cases.add(
      ChainCoreCase(
        '$prefix discarding own Chain card does not cleanse hostile Chain',
        () {
          final initial = chainAddEffect(
            position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
            square('a4'),
          );
          final discarded = DeckManager.apply(
            initial,
            const DiscardAction(CardId.chain),
          );
          chainEqual(discarded.rules.discarded[side], [
            CardId.chain,
          ], 'own card discarded');
          chainEqual(
            discarded.rules.pieceEffects.single.id,
            'v223-chain',
            'hostile effect remains',
          );
          chainRejects(discarded, ChessMoveAction(move('a4b4')));
          final moved = DeckManager.apply(
            discarded,
            ChessMoveAction(move('e1f1')),
          );
          chainRequire(
            moved.rules.pieceEffects.isEmpty,
            'different piece expires hostile effect',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix Purify Chain leaves an independent sealed destination',
        () {
          var initial = chainAddEffect(
            position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
            square('a4'),
          );
          initial = chainEdit(
            initial,
            (draft) => draft.boardEffects.add(
              BoardEffectInstance(
                id: 'v223-seal',
                type: BoardEffectType.boardSeal,
                owner: enemy,
                squares: [
                  square('a5'),
                  square('b5'),
                  square('a6'),
                  square('b6'),
                ],
                responseSide: side,
                duration: EffectDuration.move,
              ),
            ),
          );
          final purified = DeckManager.apply(
            initial,
            const PlayCardAction(CardId.purify, target: 'v223-chain'),
          );
          chainRequire(
            chainMoves(purified).contains(move('a4b4')),
            'capture restored',
          );
          chainRejects(purified, ChessMoveAction(move('a4a5')));
          chainEqual(
            purified.rules.boardEffects.single.id,
            'v223-seal',
            'Seal not removed by Purify',
          );
          final captured = DeckManager.apply(
            purified,
            ChessMoveAction(move('a4b4')),
          );
          chainRequire(
            captured.rules.boardEffects.isEmpty,
            'completed response consumes Seal',
          );
        },
      ),
    );

    for (final removed in ['v223-chain', 'v223-freeze']) {
      cases.add(
        ChainCoreCase(
          '$prefix Purify $removed respects stacked Freeze and Slow',
          () {
            var initial = chainAddEffect(
              position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
              square('a4'),
            );
            initial = chainAddEffect(
              initial,
              square('a4'),
              id: 'v223-freeze',
              type: PieceEffectType.freeze,
            );
            initial = chainAddEffect(
              initial,
              square('a4'),
              id: 'v223-slow',
              type: PieceEffectType.slow,
            );
            final actions = BattleRulesCore.legalActions(initial.view(side));
            final selection =
                BattleInteraction()..select(CardId.purify, actions);
            final options = selection.tap(
              square('a4'),
              initial.view(side),
              actions,
            );
            chainEqual(
              options
                  .whereType<PlayCardAction>()
                  .map((action) => action.target)
                  .toList()
                ..sort(),
              ['v223-chain', 'v223-freeze', 'v223-slow'],
              'effect-specific choices',
            );
            chainEqual(selection.play, null, 'no implicit cleanse selection');
            final purified = DeckManager.apply(
              initial,
              PlayCardAction(CardId.purify, target: removed),
            );
            chainEqual(
              purified.rules.pieceEffects.length,
              2,
              'only chosen effect removed',
            );
            chainRejects(purified, ChessMoveAction(move('a4b4')));
            if (removed == 'v223-chain') {
              chainRejects(purified, ChessMoveAction(move('a4a5')));
            } else {
              chainRequire(
                chainMoves(purified).contains(move('a4a5')),
                'short quiet restored',
              );
              chainRejects(purified, ChessMoveAction(move('a4a7')));
            }
            final moved = DeckManager.apply(
              purified,
              ChessMoveAction(move('e1f1')),
            );
            chainRequire(
              moved.rules.pieceEffects.isEmpty,
              'all move-duration responses end together',
            );
          },
        ),
      );
    }

    cases.add(
      ChainCoreCase(
        '$prefix Chain assists mate only by removing the sole capture defense',
        () {
          final initial = position('k7/7r/1QK5/8/8/8/8/8 w - - 0 10');
          final baseline = DeckManager.apply(
            DeckManager.apply(initial, const PassAction()),
            ChessMoveAction(move('b6b7')),
          );
          chainEqual(
            baseline.rules.terminal,
            null,
            'rook capture prevents ordinary mate',
          );
          final defense = DeckManager.apply(baseline, const PassAction());
          chainEqual(chainMoves(defense).toList(), [
            move('h7b7'),
          ], 'sole ordinary defense');
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.chain, target: square('h7')),
          );
          final mate = DeckManager.apply(cast, ChessMoveAction(move('b6b7')));
          chainEqual(
            mate.rules.terminal?.reason,
            'checkmate',
            'restriction-assisted mate',
          );
          chainEqual(mate.rules.terminal?.winner, side, 'caster wins');
          chainEqual(
            mate.rules.terminal?.mateByRestriction,
            true,
            'real eliminated capture',
          );
          chainEqual(
            mate.rules.terminal?.mateBySpecialMove,
            false,
            'ordinary queen move',
          );
          chainEqual(
            mate.rules.handCounts[side],
            2,
            'terminal move draws no replacement card',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix irrelevant Chain is not credited for ordinary mate',
        () {
          final initial = position('k7/7p/1QK5/8/8/8/8/8 w - - 0 10');
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.chain, target: square('h7')),
          );
          final mate = DeckManager.apply(cast, ChessMoveAction(move('b6b7')));
          chainEqual(
            mate.rules.terminal?.reason,
            'checkmate',
            'ordinary mate remains',
          );
          chainEqual(
            mate.rules.terminal?.mateByRestriction,
            false,
            'irrelevant effect not credited',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix Chain assists stalemate by removing the sole pawn capture',
        () {
          final initial = position('k7/8/2K4p/1Q4BR/8/8/8/8 w - - 0 10');
          final baseline = DeckManager.apply(
            DeckManager.apply(initial, const PassAction()),
            ChessMoveAction(move('b5b6')),
          );
          chainEqual(
            baseline.rules.terminal,
            null,
            'pawn capture prevents ordinary stalemate',
          );
          final defense = DeckManager.apply(baseline, const PassAction());
          chainEqual(chainMoves(defense).toList(), [
            move('h6g5'),
          ], 'sole ordinary capture');
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.chain, target: square('h6')),
          );
          final stale = DeckManager.apply(cast, ChessMoveAction(move('b5b6')));
          chainEqual(
            stale.rules.terminal?.reason,
            'stalemate',
            'no check, no legal response',
          );
          chainEqual(stale.rules.terminal?.winner, null, 'stalemate is draw');
          chainEqual(
            stale.rules.terminal?.stalemateByRestriction,
            true,
            'real eliminated pawn capture',
          );
          chainEqual(
            stale.rules.terminal?.mateByRestriction,
            false,
            'not mate attribution',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase(
        '$prefix response expiry precedes automatic 75-move draw',
        () {
          final initial = chainAddEffect(
            position(
              '7k/8/8/8/Rp6/8/8/4K3 w - - 149 10',
              phase: BattlePhase.chess,
            ),
            square('a4'),
          );
          final ended = DeckManager.apply(
            initial,
            ChessMoveAction(move('e1f1')),
          );
          chainEqual(
            ended.rules.terminal?.reason,
            'seventy_five_moves',
            'automatic draw boundary',
          );
          chainRequire(
            ended.rules.pieceEffects.isEmpty,
            'completed response still consumes Chain',
          );
          chainEqual(
            ended.rules.handCounts[side],
            3,
            'terminal move draws no card',
          );
          chainEqual(
            ended.rules.deckCounts[side],
            7,
            'terminal move preserves deck',
          );
          chainEqual(
            ended.rules.ply,
            1,
            'draw is completed after one chess move',
          );
        },
      ),
    );

    cases.add(
      ChainCoreCase('$prefix Pawn Deviation to EP square is not a capture', () {
        final initial = chainAddEffect(
          position(
            '7k/8/8/3pP3/8/8/8/4K3 w - d6 0 10',
            hand: const [CardId.pawnDeviation, CardId.chain, CardId.purify],
          ),
          square('e5'),
        );
        final victim = initial.rules.pieceIds[square('d5')];
        final special = BattleRulesCore.specialMoves(
          initial.rules,
          CardId.pawnDeviation,
          square('e5'),
          side,
        );
        chainEqual(
          special.map((value) => value.uci).toList()..sort(),
          [move('e5d6'), move('e5f6')]..sort(),
          'empty special destinations',
        );
        chainRequire(
          special.every((value) => !value.isEnPassant),
          'same square, different movement semantics',
        );
        final authorized = DeckManager.apply(
          initial,
          PlayCardAction(CardId.pawnDeviation, target: square('e5')),
        );
        final moved = DeckManager.apply(
          authorized,
          ChessMoveAction(move('e5d6')),
        );
        chainEqual(
          moved.rules.pieceIds[square('d5')],
          victim,
          'no capture: victim survives',
        );
        chainRequire(
          moved.rules.pieceEffects.isEmpty,
          'quiet special expires Chain',
        );
        chainEqual(moved.rules.special, null, 'special consumed');
      }),
    );
  }
  return cases;
}
