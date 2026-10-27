import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
int _square(int white, PieceColor side) => side.isWhite ? white : white ^ 56;
String _uci(String white, PieceColor side) =>
    side.isWhite
        ? white
        : '${white[0]}${9 - int.parse(white[1])}${white[2]}${9 - int.parse(white[3])}${white.substring(4)}';

AuthoritativeBattleState _ready(
  CardId card,
  PieceColor side, {
  String fen = _initialFen,
  int mana = 6,
  List<CardId>? hand,
}) {
  final first = hand ?? [card, CardId.radar, CardId.prophecy];
  final deck =
      [
        ...first,
        ...CardId.values.where((c) => !first.contains(c)),
      ].take(10).toList();
  final white = Board.fromFen(fen);
  final board =
      side.isWhite
          ? white
          : Board(
            squares: [
              for (var i = 0; i < 64; i++)
                white.squares[i ^ 56]?.copyWith(
                  color: white.squares[i ^ 56]!.color.opposite,
                ),
            ],
            turn: side,
            castling:
                ((white.castling & 3) << 2) | ((white.castling & 12) >> 2),
            enPassant: white.enPassant == null ? null : white.enPassant! ^ 56,
            halfmoveClock: white.halfmoveClock,
            fullmoveNumber: white.fullmoveNumber,
          );
  final root = DeckManager.newBattle(board: board, white: deck, black: deck);
  final draft =
      RuleDraft(root.rules)
        ..phase = BattlePhase.card
        ..ownTurns = {PieceColor.white: 2, PieceColor.black: 2}
        ..mana = {side: mana, side.opposite: 6}
        ..repetitions = {};
  return AuthoritativeBattleState(draft.freeze(), root.hidden);
}

List<List<T>> _orders<T>(List<T> items) =>
    items.isEmpty
        ? [[]]
        : [
          for (var i = 0; i < items.length; i++)
            for (final rest in _orders([
              for (var j = 0; j < items.length; j++)
                if (i != j) items[j],
            ]))
              [items[i], ...rest],
        ];

void main() {
  for (final side in PieceColor.values) {
    test(
      '${side.name}: Knight Revolt grants only one orthogonal step and no Hunt payoff',
      () {
        final root = _ready(
          CardId.angryN,
          side,
          fen: '8/7k/8/3r4/3N4/8/8/K7 w - - 0 10',
        );
        final draft = RuleDraft(root.rules)
          ..vows.add(
            VowState(
              id: 'hunt',
              type: VowType.hunt,
              owner: side,
              pieceId: root.rules.pieceIds[_square(35, side)],
              square: null,
              remainingMoves: 1,
            ),
          );
        final before = AuthoritativeBattleState(draft.freeze(), root.hidden);
        final expected =
            ['d4c4', 'd4d3', 'd4d5', 'd4e4'].map((m) => _uci(m, side)).toSet();
        expect(
          BattleRulesCore.specialMoves(
            before.rules,
            CardId.angryN,
            _square(27, side),
            side,
          ).map((m) => m.uci).toSet(),
          expected,
        );
        final cast = DeckManager.apply(
          before,
          PlayCardAction(CardId.angryN, target: _square(27, side)),
        );
        expect(
          BattleRulesCore.legalActions(
            cast.view(side),
          ).whereType<ChessMoveAction>().map((m) => m.uci).toSet(),
          expected,
        );
        expect(
          () => DeckManager.apply(cast, ChessMoveAction(_uci('d4e6', side))),
          throwsStateError,
        );
        final after = DeckManager.apply(
          cast,
          ChessMoveAction(_uci('d4d5', side)),
        );
        expect(
          after.rules.mana[side],
          3,
          reason: 'The special capture does not pay Hunt Vow.',
        );
        expect(after.rules.vows, isEmpty);
        expect(after.rules.special, isNull);
        expect(
          after.rules.pieceIds[_square(35, side)],
          before.rules.pieceIds[_square(27, side)],
        );
      },
    );

    for (final bishop in [false, true]) {
      test(
        '${side.name}: Shadow Pass crosses exactly one friendly non-king, ${bishop ? 'bishop' : 'rook'}',
        () {
          final root = _ready(
            CardId.shadowPass,
            side,
            fen:
                bishop
                    ? '7k/8/8/4P3/3B4/8/8/K7 w - - 0 10'
                    : '7k/8/8/8/3R4/3P4/8/K7 w - - 0 10',
          );
          final expected =
              (bishop ? ['d4f6', 'd4g7'] : ['d4d1', 'd4d2'])
                  .map((m) => _uci(m, side))
                  .toSet();
          expect(
            BattleRulesCore.specialMoves(
              root.rules,
              CardId.shadowPass,
              _square(27, side),
              side,
            ).map((m) => m.uci).toSet(),
            expected,
          );
          final cast = DeckManager.apply(
            root,
            PlayCardAction(CardId.shadowPass, target: _square(27, side)),
          );
          for (final move in expected) {
            final after = DeckManager.apply(cast, ChessMoveAction(move));
            expect(
              after.rules.pieceIds.whereType<String>().length,
              root.rules.pieceIds.whereType<String>().length,
            );
            expect(after.rules.special, isNull);
            expect(after.rules.board.turn, side.opposite);
          }
          final blocked = _ready(
            CardId.shadowPass,
            side,
            fen: '7k/8/8/8/3R4/3K4/8/8 w - - 0 10',
          );
          expect(
            BattleRulesCore.cardTargets(blocked.view(side), CardId.shadowPass),
            isEmpty,
          );
          expect(
            BattleRulesCore.isLegalAction(
              blocked.view(side),
              const DiscardAction(CardId.shadowPass),
            ),
            isTrue,
          );
        },
      );
    }

    for (final path in ['immediate', 'second', 'expire']) {
      test('${side.name}: Hunt Vow $path has exact two-own-move window', () {
        var state = _ready(
          CardId.huntVow,
          side,
          mana: 3,
          fen: '8/7k/8/3r4/3Q4/8/8/K7 w - - 0 10',
        );
        state = DeckManager.apply(
          state,
          PlayCardAction(CardId.huntVow, target: _square(35, side)),
        );
        expect(state.rules.mana[side], 1);
        if (path == 'immediate') {
          state = DeckManager.apply(state, ChessMoveAction(_uci('d4d5', side)));
          expect(state.rules.mana[side], 3);
        } else {
          state = DeckManager.apply(state, ChessMoveAction(_uci('d4d3', side)));
          expect(state.rules.vows.single.remainingMoves, 1);
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(state, ChessMoveAction(_uci('h7h6', side)));
          expect(state.rules.vows.single.remainingMoves, 1);
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(_uci(path == 'second' ? 'd3d5' : 'd3c3', side)),
          );
          expect(state.rules.mana[side], path == 'second' ? 4 : 2);
        }
        expect(state.rules.vows, isEmpty);
      });
    }

    for (final success in [false, true]) {
      test(
        '${side.name}: Watch Vow ${success ? 'king arrival pays' : 'empty expiry pays nothing'}',
        () {
          var state = _ready(
            CardId.watchVow,
            side,
            mana: 3,
            fen: '8/8/8/5k2/8/8/4P3/K7 w - - 0 10',
          );
          state = DeckManager.apply(
            state,
            PlayCardAction(CardId.watchVow, target: _square(36, side)),
          );
          state = DeckManager.apply(state, ChessMoveAction(_uci('e2e3', side)));
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(_uci(success ? 'f5e5' : 'f5g5', side)),
          );
          expect(state.rules.mana[side], success ? 4 : 2);
          expect(state.rules.vows, isEmpty);
        },
      );
    }

    for (final target in CardId.values) {
      test(
        '${side.name}: Echo rewards actual ${target.wire} play, not discard or pass',
        () {
          final root = cardScenario(target, side.opposite);
          final draft =
              RuleDraft(root.rules)
                ..mana[side] = 1
                ..modifiers.add(
                  PendingModifier(
                    id: 'echo-window',
                    type: ModifierType.echo,
                    owner: side,
                    responseSide: side.opposite,
                    targetCard: target,
                    ownTurn: root.rules.ownTurns[side.opposite]!,
                  ),
                );
          final before = AuthoritativeBattleState(draft.freeze(), root.hidden);
          final action = BattleRulesCore.legalActions(
            before.view(side.opposite),
          ).whereType<PlayCardAction>().firstWhere((a) => a.card == target);
          final played = DeckManager.apply(before, action);
          expect(played.rules.mana[side], 3);
          final discarded = DeckManager.apply(before, DiscardAction(target));
          final passed = DeckManager.apply(before, const PassAction());
          expect(discarded.rules.mana[side], 1);
          expect(passed.rules.mana[side], 1);
          expect(
            discarded.rules.modifiers.where((m) => m.id == 'echo-window'),
            isEmpty,
          );
          expect(
            passed.rules.modifiers.where((m) => m.id == 'echo-window'),
            isEmpty,
          );
        },
      );
    }

    for (var remaining = 1; remaining <= 7; remaining++) {
      test(
        '${side.name}: Fate Exchange deck $remaining preserves every choice and order',
        () {
          final root = _ready(CardId.fateExchange, side);
          final cards = root.hidden.decks[side]!;
          final draft =
              RuleDraft(root.rules)
                ..deckCounts[side] = remaining
                ..drawCounts[side] = 10 - remaining
                ..discarded[side] = cards.skip(remaining).toList();
          final before = AuthoritativeBattleState(
            draft.freeze(),
            AuthoritativeHiddenState(
              hands: root.hidden.hands,
              decks: {
                ...root.hidden.decks,
                side: cards.take(remaining).toList(),
              },
              knowledge: root.hidden.knowledge,
            ),
          );
          final frozen = jsonEncode(before.toJson());
          final pending = DeckManager.apply(
            before,
            const PlayCardAction(CardId.fateExchange, sacrifice: CardId.radar),
          );
          final inspected = cards.take(math.min(3, remaining)).toList();
          expect(pending.hidden.knowledge[side]!.pendingCards, inspected);
          expect(pending.rules.phase, BattlePhase.pending);
          expect(pending.hidden.hands[side], [CardId.prophecy]);
          for (final taken in inspected) {
            for (final order in _orders(
              inspected.where((c) => c != taken).toList(),
            )) {
              final resolve = ResolveAction(order, selected: taken);
              final after = DeckManager.apply(pending, resolve);
              expect(after.hidden.hands[side], [CardId.prophecy, taken]);
              expect(after.hidden.decks[side], [
                ...order,
                ...cards.take(remaining).skip(inspected.length),
              ]);
              expect(after.hidden.knowledge[side]!.knownUpcomingCards, order);
              expect(after.hidden.knowledge[side]!.pendingCards, isEmpty);
              expect(after.rules.phase, BattlePhase.chess);
              expect(
                BattleRulesCore.legalActions(
                  after.view(side),
                ).whereType<PlayCardAction>(),
                isEmpty,
              );
              expect(() => DeckManager.apply(after, resolve), throwsStateError);
            }
          }
          expect(jsonEncode(before.toJson()), frozen);
        },
      );
    }

    for (final closeWith in ['pass', 'play']) {
      test(
        '${side.name}: Shadow Contract waits one own turn and expires after $closeWith',
        () {
          var state = _ready(CardId.shadowContract, side);
          state = DeckManager.apply(
            state,
            const PlayCardAction(
              CardId.shadowContract,
              sacrifice: CardId.radar,
            ),
          );
          expect(state.rules.mana[side], 5);
          expect(state.rules.modifiers.single.ownTurn, 3);
          expect(
            BattleRulesCore.effectiveCost(state.rules, side, CardId.freeze),
            4,
          );
          state = DeckManager.apply(state, ChessMoveAction(_uci('e2e4', side)));
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(state, ChessMoveAction(_uci('d7d5', side)));
          for (final card in CardId.values) {
            expect(
              BattleRulesCore.effectiveCost(state.rules, side, card),
              math.max(1, cardDefinitions[card]!.cost - 2),
            );
          }
          final beforeMana = state.rules.mana[side]!;
          state = DeckManager.apply(
            state,
            closeWith == 'pass'
                ? const PassAction()
                : const PlayCardAction(CardId.prophecy),
          );
          if (state.rules.phase == BattlePhase.pending) {
            expect(state.rules.modifiers, hasLength(1));
            state = DeckManager.apply(
              state,
              ResolveAction(state.hidden.knowledge[side]!.pendingCards),
            );
            expect(state.rules.mana[side], beforeMana - 1);
          } else {
            expect(state.rules.mana[side], beforeMana);
          }
          expect(state.rules.modifiers, isEmpty);
          expect(
            BattleRulesCore.effectiveCost(state.rules, side, CardId.freeze),
            4,
          );
        },
      );
    }

    for (var rank = 0; rank < 7; rank++) {
      for (var file = 0; file < 7; file++) {
        final anchor = rank * 8 + file;
        test(
          '${side.name}: Board Seal anchor $anchor has exact empty-landing and response-move bounds',
          () {
            final root = _ready(CardId.boardSeal, side);
            final target = _square(anchor, side);
            // A reflected lower-left anchor remains the lower-left of the zone.
            final adjusted = side.isWhite ? target : target - 8;
            final zone = [adjusted, adjusted + 1, adjusted + 8, adjusted + 9];
            final action = PlayCardAction(CardId.boardSeal, target: adjusted);
            if (zone.every((s) => root.rules.board.squares[s] != null)) {
              expect(() => DeckManager.apply(root, action), throwsStateError);
              return;
            }
            var state = DeckManager.apply(root, action);
            expect(state.rules.boardEffects.single.squares, zone);
            expect(state.rules.mana[side], 1);
            state = DeckManager.apply(
              state,
              ChessMoveAction(_uci('e2e4', side)),
            );
            state = DeckManager.apply(state, const PassAction());
            expect(state.rules.boardEffects, hasLength(1));
            final board = state.rules.board;
            final expected =
                MoveGen.legal(board)
                    .where(
                      (move) =>
                          board.squares[move.from]!.type == PieceType.king ||
                          board.squares[move.to] != null ||
                          !zone.contains(move.to),
                    )
                    .map((m) => m.uci)
                    .toSet();
            final moves =
                BattleRulesCore.legalActions(
                  state.view(side.opposite),
                ).whereType<ChessMoveAction>().toList();
            expect(moves.map((m) => m.uci).toSet(), expected);
            expect(moves, isNotEmpty);
            state = DeckManager.apply(state, moves.first);
            expect(state.rules.boardEffects, isEmpty);
          },
        );
      }
    }
  }
}
