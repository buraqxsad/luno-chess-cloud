import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const _effectsFen = '4k3/8/2r1b3/3q1p2/2R1BN2/3P4/8/4K3 w - - 0 10';

int _square(String text, PieceColor owner) {
  final square = Square.of(text.codeUnitAt(0) - 97, int.parse(text[1]) - 1);
  return owner.isWhite ? square : square ^ 56;
}

String _uci(String text, PieceColor owner) =>
    owner.isWhite
        ? text
        : '${text[0]}${9 - int.parse(text[1])}'
            '${text[2]}${9 - int.parse(text[3])}${text.substring(4)}';

List<CardId> _deck(List<CardId> first) =>
    [
      ...first,
      ...CardId.values.where((card) => !first.contains(card)),
    ].take(10).toList();

AuthoritativeBattleState _root(
  PieceColor owner,
  List<CardId> own, {
  List<CardId> enemy = const [CardId.radar, CardId.prophecy, CardId.purify],
  String fen = _effectsFen,
  int mana = 6,
}) {
  final original = Board.fromFen(fen);
  final board =
      owner.isWhite
          ? original
          : Board(
            squares: [
              for (var i = 0; i < 64; i++)
                original.squares[i ^ 56]?.copyWith(
                  color: original.squares[i ^ 56]!.color.opposite,
                ),
            ],
            turn: owner,
            castling:
                ((original.castling & 3) << 2) |
                ((original.castling & 12) >> 2),
            enPassant:
                original.enPassant == null ? null : original.enPassant! ^ 56,
            halfmoveClock: original.halfmoveClock,
            fullmoveNumber: original.fullmoveNumber,
          );
  final state = DeckManager.newBattle(
    board: board,
    white: _deck(owner.isWhite ? own : enemy),
    black: _deck(owner.isWhite ? enemy : own),
  );
  final rules =
      RuleDraft(state.rules)
        ..phase = BattlePhase.card
        ..ownTurns = {owner: 10, owner.opposite: 10}
        ..mana = {owner: mana, owner.opposite: 6}
        ..repetitions = {};
  return AuthoritativeBattleState(rules.freeze(), state.hidden);
}

AuthoritativeBattleState _cast(
  AuthoritativeBattleState state,
  CardId card, {
  Object? target,
}) => DeckManager.apply(state, PlayCardAction(card, target: target));

AuthoritativeBattleState _move(
  AuthoritativeBattleState state,
  String text,
  PieceColor owner,
) => DeckManager.apply(state, ChessMoveAction(_uci(text, owner)));

AuthoritativeBattleState _pass(AuthoritativeBattleState state) =>
    DeckManager.apply(state, const PassAction());

// Ordinary chess moves are filtered by literal card rules, without calling the
// card core's move, target, restriction or cost helpers for the expected set.
List<Move> _expectedMoves(RuleState rules) =>
    MoveGen.legal(rules.board).where((move) {
      final relocations = [(move.from, move.to)];
      if (move.isCastle) {
        final rank = Square.rankOf(move.from) * 8;
        final kingside = Square.fileOf(move.to) == 6;
        relocations.add((rank + (kingside ? 7 : 0), rank + (kingside ? 5 : 3)));
      }
      for (final (from, to) in relocations) {
        final piece = rules.board.squares[from]!;
        if (piece.type == PieceType.king) continue;
        final capture =
            from == move.from &&
            (rules.board.squares[to] != null || move.isEnPassant);
        for (final effect in rules.pieceEffects.where(
          (effect) => effect.pieceId == rules.pieceIds[from],
        )) {
          if (effect.type == PieceEffectType.freeze) return false;
          if ((effect.type == PieceEffectType.chain ||
                  effect.type == PieceEffectType.mineDebuff) &&
              capture) {
            return false;
          }
          if (effect.type == PieceEffectType.slow &&
              ((Square.fileOf(from) - Square.fileOf(to)).abs() > 2 ||
                  (Square.rankOf(from) - Square.rankOf(to)).abs() > 2)) {
            return false;
          }
        }
        if (rules.board.squares[to] == null &&
            rules.boardEffects.any(
              (effect) =>
                  effect.owner != piece.color &&
                  (effect.type == BoardEffectType.lockedSquare ||
                      effect.type == BoardEffectType.boardSeal) &&
                  effect.squares.contains(to),
            )) {
          return false;
        }
      }
      return true;
    }).toList();

List<String> _actualMoves(AuthoritativeBattleState state) =>
    BattleRulesCore.legalActions(
        state.view(state.rules.board.turn),
      ).whereType<ChessMoveAction>().map((move) => move.uci).toList()
      ..sort();

void _expectLiteralMoves(AuthoritativeBattleState state) {
  expect(state.rules.phase, BattlePhase.chess);
  expect(state.rules.special, isNull);
  final expected =
      _expectedMoves(state.rules).map((move) => move.uci).toList()..sort();
  expect(_actualMoves(state), expected);
}

void main() {
  for (final owner in PieceColor.values) {
    for (final card in [CardId.chain, CardId.freeze, CardId.slow]) {
      for (final target in ['c6', 'e6', 'd5', if (card != CardId.slow) 'f5']) {
        test(
          '${owner.name} ${card.wire} literal moves and exact expiry on $target',
          () {
            final root = _root(owner, [card]);
            final rootJson = jsonEncode(root.toJson());
            final cast = _cast(root, card, target: _square(target, owner));
            final affectedId = root.rules.pieceIds[_square(target, owner)];
            expect(cast.rules.pieceEffects, hasLength(1));
            expect(cast.rules.pieceEffects.single.pieceId, affectedId);
            expect(cast.rules.pieceEffects.single.type, switch (card) {
              CardId.chain => PieceEffectType.chain,
              CardId.slow => PieceEffectType.slow,
              _ => PieceEffectType.freeze,
            });
            expect(cast.rules.pieceEffects.single.owner, owner);
            expect(cast.rules.pieceEffects.single.responseSide, owner.opposite);
            expect(
              cast.rules.pieceEffects.single.duration,
              EffectDuration.move,
            );
            final response = _pass(_move(cast, 'd3d4', owner));
            _expectLiteralMoves(response);
            final moves = _actualMoves(response);
            expect(moves, isNotEmpty);
            final responseJson = jsonEncode(response.toJson());
            for (final uci in moves) {
              final after = DeckManager.apply(response, ChessMoveAction(uci));
              expect(after.rules.pieceEffects, isEmpty);
              expect(after.rules.used[owner], [card]);
              expect(jsonEncode(response.toJson()), responseJson);
            }
            expect(jsonEncode(root.toJson()), rootJson);
          },
        );
      }
    }

    for (final card in [CardId.lockedSquare, CardId.boardSeal]) {
      test(
        '${owner.name} ${card.wire}: ordinary landing and king immunity',
        () {
          final cast = _cast(
            _root(owner, [card]),
            card,
            target: _square('d7', owner),
          );
          expect(
            cast.rules.boardEffects.single.type,
            card == CardId.lockedSquare
                ? BoardEffectType.lockedSquare
                : BoardEffectType.boardSeal,
          );
          expect(
            cast.rules.boardEffects.single.squares,
            card == CardId.lockedSquare
                ? [_square('d7', owner)]
                : owner.isWhite
                ? [51, 52, 59, 60]
                : [11, 12, 19, 20],
          );
          final response = _pass(_move(cast, 'd3d4', owner));
          _expectLiteralMoves(response);
          expect(_actualMoves(response), contains(_uci('e8d7', owner)));
          expect(_actualMoves(response), isNot(contains(_uci('d5d7', owner))));
          for (final uci in _actualMoves(response)) {
            final after = DeckManager.apply(response, ChessMoveAction(uci));
            expect(after.rules.boardEffects, isEmpty);
          }
        },
      );
    }

    for (final card in [CardId.chain, CardId.slow, CardId.freeze]) {
      for (final purifyMine in [false, true]) {
        test(
          '${owner.name} Mine + ${card.wire}: Purify mine=$purifyMine removes exactly one',
          () {
            final root = _root(
              owner,
              [CardId.mine, card],
              enemy: [CardId.purify],
            );
            final mined = _cast(
              root,
              CardId.mine,
              target: _square('c5', owner),
            );
            final entered = _move(
              _pass(_move(mined, 'd3d4', owner)),
              'c6c5',
              owner,
            );
            expect(entered.rules.boardEffects, isEmpty);
            expect(
              entered.rules.pieceEffects.single.type,
              PieceEffectType.mineDebuff,
            );
            final restricted = _cast(
              entered,
              card,
              target: _square('c5', owner),
            );
            final response = _move(restricted, 'e4d3', owner);
            expect(response.rules.pieceEffects, hasLength(2));
            final mine = response.rules.pieceEffects.singleWhere(
              (effect) => effect.type == PieceEffectType.mineDebuff,
            );
            final second = response.rules.pieceEffects.singleWhere(
              (effect) => effect.type != PieceEffectType.mineDebuff,
            );
            expect(second.pieceId, mine.pieceId);
            final purified = _cast(
              response,
              CardId.purify,
              target: purifyMine ? mine.id : second.id,
            );
            final survivor = purifyMine ? second : mine;
            expect(
              purified.rules.pieceEffects.map((effect) => effect.toJson()),
              [survivor.toJson()],
            );
            _expectLiteralMoves(purified);
            for (final uci in _actualMoves(purified)) {
              final after = DeckManager.apply(purified, ChessMoveAction(uci));
              final affectedMoved = uci.startsWith(
                Square.algebraic(_square('c5', owner)),
              );
              expect(
                after.rules.pieceEffects.map((effect) => effect.id),
                survivor.type == PieceEffectType.mineDebuff && !affectedMoved
                    ? [survivor.id]
                    : isEmpty,
              );
            }
          },
        );
      }
    }

    test(
      '${owner.name} Mine survives unrelated moves and ends on its own quiet move',
      () {
        final root = _root(owner, [CardId.mine]);
        final cast = _cast(root, CardId.mine, target: _square('c5', owner));
        var state = _move(_pass(_move(cast, 'd3d4', owner)), 'c6c5', owner);
        final id = state.rules.pieceEffects.single.id;
        state = _move(_pass(state), 'e4d3', owner);
        state = _move(_pass(state), 'e8f8', owner);
        expect(state.rules.pieceEffects.single.id, id);
        state = _move(_pass(state), 'd3e4', owner);
        state = _pass(state);
        _expectLiteralMoves(state);
        expect(_actualMoves(state), isNot(contains(_uci('c5c4', owner))));
        expect(_actualMoves(state), contains(_uci('c5c6', owner)));
        state = _move(state, 'c5c6', owner);
        expect(state.rules.pieceEffects, isEmpty);
        state = _move(_pass(state), 'e4f3', owner);
        state = _pass(state);
        expect(_actualMoves(state), contains(_uci('c6c4', owner)));
      },
    );

    for (final castle in [false, true]) {
      test(
        '${owner.name} Mine and Watch both trigger on ${castle ? 'castling rook' : 'rook'} arrival',
        () {
          final root = _root(
            owner,
            [CardId.mine, CardId.watchVow],
            fen: castle ? 'r3k2r/8/8/8/8/8/3P4/4K3 w kq - 0 10' : _effectsFen,
            mana: 4,
          );
          final target = _square(castle ? 'f8' : 'c5', owner);
          var state = _cast(root, CardId.mine, target: target);
          state = _move(state, castle ? 'd2d3' : 'd3d4', owner);
          state = _move(_pass(state), castle ? 'a8a7' : 'e8f8', owner);
          state = _cast(state, CardId.watchVow, target: target);
          state = _move(state, castle ? 'd3d4' : 'e4d3', owner);
          expect(state.rules.mana[owner], 1);
          state = _move(_pass(state), castle ? 'e8g8' : 'c6c5', owner);
          expect(state.rules.mana[owner], 4);
          expect(state.rules.boardEffects, isEmpty);
          expect(state.rules.vows, isEmpty);
          expect(state.rules.pieceEffects, hasLength(1));
          expect(
            state.rules.pieceEffects.single.type,
            PieceEffectType.mineDebuff,
          );
          expect(
            state.rules.pieceEffects.single.pieceId,
            state.rules.pieceIds[target],
          );
          expect(state.rules.board.squares[target]?.type, PieceType.rook);
          expect(state.rules.board.squares[target]?.color, owner.opposite);
        },
      );
    }

    for (final promotion in ['q', 'r', 'b', 'n']) {
      for (final special in [false, true]) {
        test(
          '${owner.name} Hunt follows promotion=$promotion: ${special ? 'special capture pays zero' : 'normal capture pays two'}',
          () {
            final root = _root(
              owner,
              [CardId.huntVow, CardId.angryN],
              fen:
                  special
                      ? '7k/1p6/8/8/8/8/p5P1/1N5K w - - 0 10'
                      : '7k/1p6/8/8/8/8/pR6/7K w - - 0 10',
              mana: special ? 6 : 2,
            );
            final huntedId = root.rules.pieceIds[_square('a2', owner)];
            var state = _cast(
              root,
              CardId.huntVow,
              target: _square('a2', owner),
            );
            state = _move(state, special ? 'g2g3' : 'b2b1', owner);
            state = _move(_pass(state), 'a2a1$promotion', owner);
            expect(state.rules.pieceIds[_square('a1', owner)], huntedId);
            expect(state.rules.vows.single.pieceId, huntedId);
            expect(state.rules.vows.single.remainingMoves, 1);
            state =
                special
                    ? _cast(state, CardId.angryN, target: _square('b1', owner))
                    : _pass(state);
            state = _move(state, 'b1a1', owner);
            expect(state.rules.vows, isEmpty);
            expect(state.rules.mana[owner], special ? 2 : 3);
            expect(state.rules.pieceIds, isNot(contains(huntedId)));
            expect(state.rules.special, isNull);
          },
        );
      }
    }

    for (final protection in [CardId.shelter, CardId.fog]) {
      for (final attack in [
        CardId.chain,
        CardId.freeze,
        CardId.slow,
        CardId.huntVow,
      ]) {
        for (final close in ['pass', 'discard', 'prophecy', 'fate']) {
          test(
            '${owner.name} ${protection.wire} blocks ${attack.wire} until $close closes the window',
            () {
              final root = _root(
                owner,
                [protection],
                enemy: [attack, CardId.prophecy, CardId.fateExchange],
              );
              final target = _square('c4', owner);
              var state = _cast(
                root,
                protection,
                target:
                    protection == CardId.shelter
                        ? target
                        : _square(owner.isWhite ? 'b3' : 'b4', owner),
              );
              state = _move(state, 'd3d4', owner);
              final actions = BattleRulesCore.legalActions(
                state.view(owner.opposite),
              );
              expect(
                actions.whereType<PlayCardAction>().where(
                  (action) => action.card == attack && action.target == target,
                ),
                isEmpty,
              );
              expect(
                actions.whereType<PlayCardAction>().where(
                  (action) =>
                      action.card == attack &&
                      action.target == _square('e4', owner),
                ),
                isNotEmpty,
              );
              final before = jsonEncode(state.toJson());
              expect(
                () => _cast(state, attack, target: target),
                throwsStateError,
              );
              expect(jsonEncode(state.toJson()), before);
              expect(
                BattleRulesCore.legalMoves(
                  state.rules,
                  owner.opposite,
                ).map((move) => move.uci),
                contains(_uci('c6c4', owner)),
              );
              state = switch (close) {
                'pass' => _pass(state),
                'discard' => DeckManager.apply(state, DiscardAction(attack)),
                'prophecy' => _cast(state, CardId.prophecy),
                _ => DeckManager.apply(
                  state,
                  PlayCardAction(CardId.fateExchange, sacrifice: attack),
                ),
              };
              if (state.rules.phase == BattlePhase.pending) {
                expect(
                  state.rules.pieceEffects.length +
                      state.rules.boardEffects.length,
                  1,
                );
                final inspected =
                    state.hidden.knowledge[owner.opposite]!.pendingCards;
                final selected = close == 'fate' ? inspected.first : null;
                state = DeckManager.apply(
                  state,
                  ResolveAction(
                    inspected.where((card) => card != selected).toList(),
                    selected: selected,
                  ),
                );
              }
              expect(state.rules.pieceEffects, isEmpty);
              expect(state.rules.boardEffects, isEmpty);
              _expectLiteralMoves(state);
              expect(_actualMoves(state), contains(_uci('c6c4', owner)));
            },
          );
        }

        test(
          '${owner.name} moving ${protection.wire} target: ${attack.wire} respects piece versus zone identity',
          () {
            final root = _root(owner, [protection], enemy: [attack]);
            var state = _cast(
              root,
              protection,
              target: _square(
                protection == CardId.shelter
                    ? 'c4'
                    : owner.isWhite
                    ? 'b3'
                    : 'b4',
                owner,
              ),
            );
            final rookId = root.rules.pieceIds[_square('c4', owner)];
            state = _move(state, 'c4c2', owner);
            expect(state.rules.pieceIds[_square('c2', owner)], rookId);
            final targetActions = BattleRulesCore.legalActions(
              state.view(owner.opposite),
            ).whereType<PlayCardAction>().where(
              (action) =>
                  action.card == attack &&
                  action.target == _square('c2', owner),
            );
            expect(
              targetActions,
              protection == CardId.shelter ? isEmpty : isNotEmpty,
            );
          },
        );
      }
    }

    for (final boardCard in [
      CardId.lockedSquare,
      CardId.boardSeal,
      CardId.fog,
    ]) {
      for (final removeMine in [false, true]) {
        test(
          '${owner.name} Break Seal chooses one of Mine + ${boardCard.wire}: mine=$removeMine',
          () {
            final root = _root(
              owner,
              [CardId.mine, boardCard],
              enemy: [CardId.breakSeal],
            );
            var state = _cast(root, CardId.mine, target: _square('c5', owner));
            state = _move(state, 'd3d4', owner);
            state = _move(_pass(state), 'e8f8', owner);
            state = _cast(
              state,
              boardCard,
              target: _square(
                boardCard == CardId.lockedSquare
                    ? 'c5'
                    : owner.isWhite
                    ? 'b4'
                    : 'b5',
                owner,
              ),
            );
            state = _move(state, 'e4d3', owner);
            expect(state.rules.boardEffects, hasLength(2));
            final mine = state.rules.boardEffects.singleWhere(
              (effect) => effect.type == BoardEffectType.mine,
            );
            final other = state.rules.boardEffects.singleWhere(
              (effect) => effect.type != BoardEffectType.mine,
            );
            final before = jsonEncode(state.toJson());
            final cast = _cast(
              state,
              CardId.breakSeal,
              target: removeMine ? mine.id : other.id,
            );
            expect(jsonEncode(state.toJson()), before);
            final remaining =
                removeMine
                    ? boardCard == CardId.fog
                        ? <String>[]
                        : [other.id]
                    : [mine.id];
            expect(
              cast.rules.boardEffects.map((effect) => effect.id),
              remaining,
            );
            _expectLiteralMoves(cast);
            final mayArrive = !removeMine || boardCard == CardId.fog;
            expect(_actualMoves(cast).contains(_uci('c6c5', owner)), mayArrive);
            final after = _move(cast, mayArrive ? 'c6c5' : 'f8g8', owner);
            expect(after.rules.boardEffects, isEmpty);
            expect(after.rules.pieceEffects.length, removeMine ? 0 : 1);
            if (!removeMine) {
              expect(
                after.rules.pieceEffects.single.type,
                PieceEffectType.mineDebuff,
              );
            }
          },
        );
      }
    }

    test(
      '${owner.name} own arrival does not trigger Mine; enemy capture does',
      () {
        final root = _root(owner, [CardId.mine]);
        var state = _cast(root, CardId.mine, target: _square('c5', owner));
        state = _move(state, 'c4c5', owner);
        expect(state.rules.boardEffects, hasLength(1));
        expect(state.rules.pieceEffects, isEmpty);
        state = _move(_pass(state), 'c6c5', owner);
        expect(state.rules.boardEffects, isEmpty);
        expect(
          state.rules.pieceEffects.single.type,
          PieceEffectType.mineDebuff,
        );
        expect(
          state.rules.pieceEffects.single.pieceId,
          state.rules.pieceIds[_square('c5', owner)],
        );
      },
    );

    test(
      '${owner.name} Mine under a king remains removable without king debuff',
      () {
        final root = _root(
          owner,
          [CardId.mine],
          enemy: [CardId.breakSeal],
          fen: '4k3/8/8/8/8/8/3P4/4K3 w - - 0 10',
        );
        var state = _cast(root, CardId.mine, target: _square('d7', owner));
        state = _move(state, 'd2d3', owner);
        state = _move(_pass(state), 'e8d7', owner);
        expect(state.rules.pieceEffects, isEmpty);
        expect(state.rules.boardEffects, hasLength(1));
        state = _move(_pass(state), 'd3d4', owner);
        state = _cast(
          state,
          CardId.breakSeal,
          target: state.rules.boardEffects.single.id,
        );
        expect(state.rules.boardEffects, isEmpty);
        expect(state.rules.pieceEffects, isEmpty);
      },
    );

    for (final movement in movementCards) {
      final from = switch (movement) {
        CardId.pawnDeviation || CardId.pawnAdvance => 'b2',
        CardId.rookBend => 'c4',
        CardId.angryN => 'f4',
        _ => 'e4',
      };
      final ordinaryDestinations = switch (movement) {
        CardId.pawnDeviation => ['a3', 'c3'],
        CardId.pawnAdvance => ['b4'],
        CardId.rookBend => ['b3', 'b5'],
        CardId.angryN => ['f3', 'f5', 'g4'],
        _ => ['b1', 'c2'],
      };
      for (final incoming in [
        null,
        CardId.chain,
        CardId.freeze,
        if (movement == CardId.rookBend || movement == CardId.shadowPass)
          CardId.slow,
      ]) {
        test(
          '${owner.name} ${movement.wire}: exact bound movement under ${incoming?.wire ?? 'no restriction'}',
          () {
            final initial = _root(
              owner,
              [movement],
              enemy: incoming == null ? [CardId.radar] : [incoming],
              fen: '4k3/8/2r1b3/3q1p2/2R1BN2/3P4/1P6/4K3 w - - 0 10',
            );
            var state = initial;
            if (incoming != null) {
              final board = initial.rules.board;
              final responseStart = RuleDraft(initial.rules)
                ..board = Board(
                  squares: board.squares,
                  turn: owner.opposite,
                  castling: board.castling,
                  enPassant: null,
                  halfmoveClock: board.halfmoveClock,
                  fullmoveNumber: board.fullmoveNumber,
                );
              state = AuthoritativeBattleState(
                responseStart.freeze(),
                initial.hidden,
              );
              state = _cast(state, incoming, target: _square(from, owner));
              state = _move(state, 'e8f8', owner);
            }
            final target = _square(from, owner);
            final before = jsonEncode(state.toJson());
            if (incoming == CardId.freeze) {
              expect(
                () => _cast(state, movement, target: target),
                throwsStateError,
              );
              expect(jsonEncode(state.toJson()), before);
              final discarded = DeckManager.apply(
                state,
                DiscardAction(movement),
              );
              expect(discarded.rules.mana[owner], state.rules.mana[owner]);
              _expectLiteralMoves(discarded);
              expect(
                _actualMoves(
                  discarded,
                ).where((move) => move.startsWith(Square.algebraic(target))),
                isEmpty,
              );
              return;
            }
            final destinations = ordinaryDestinations.where((to) {
              if (incoming == CardId.chain &&
                  movement == CardId.angryN &&
                  to == 'f5') {
                return false;
              }
              if (incoming == CardId.slow &&
                  movement == CardId.shadowPass &&
                  to == 'b1') {
                return false;
              }
              return true;
            });
            final expected =
                destinations.map((to) => _uci('$from$to', owner)).toList()
                  ..sort();
            final cast = _cast(state, movement, target: target);
            expect(_actualMoves(cast), expected);
            expect(cast.rules.special?.from, target);
            expect(cast.rules.special?.card, movement);
            final cost =
                movement == CardId.angryN || movement == CardId.shadowPass
                    ? 3
                    : 2;
            expect(cast.rules.mana[owner], state.rules.mana[owner]! - cost);
            for (final uci in expected) {
              final after = DeckManager.apply(cast, ChessMoveAction(uci));
              expect(after.rules.special, isNull);
              expect(after.rules.pieceEffects, isEmpty);
              expect(after.rules.used[owner], [movement]);
              expect(jsonEncode(state.toJson()), before);
            }
          },
        );
      }
    }

    for (final queried in CardId.values) {
      for (final inHand in [false, true]) {
        test(
          '${owner.name} Radar ${queried.wire}: inHand=$inHand and later observation becomes stale correctly',
          () {
            final fillers =
                CardId.values.where((card) => card != queried).take(3).toList();
            final root = _root(owner, [
              CardId.radar,
            ], enemy: inHand ? [queried] : [...fillers, queried]);
            var state = _cast(root, CardId.radar, target: queried.wire);
            final observation =
                state.hidden.knowledge[owner]!.radarObservations.single;
            expect(observation.queriedCardId, queried);
            expect(observation.inHand, inHand);
            expect(observation.stale, isFalse);
            expect(
              state.hidden.hands[owner.opposite]!.contains(queried),
              inHand,
            );
            expect(state.rules.mana[owner], 5);
            state = _move(state, 'd3d4', owner);
            state =
                inHand
                    ? DeckManager.apply(state, DiscardAction(queried))
                    : _pass(state);
            expect(
              state.hidden.knowledge[owner]!.radarObservations.single.stale,
              inHand,
            );
            if (!inHand) {
              state = _move(state, 'e8f8', owner);
              expect(state.hidden.hands[owner.opposite], contains(queried));
              final later =
                  state.hidden.knowledge[owner]!.radarObservations.single;
              expect(later.stale, isTrue);
              expect(later.inHand, isFalse);
            }
            expect(observation.stale, isFalse);
            expect(observation.inHand, inHand);
          },
        );
      }
    }

    for (final named in [
      CardId.radar,
      CardId.prophecy,
      CardId.freeze,
      CardId.boardSeal,
    ]) {
      final baseCost = switch (named) {
        CardId.radar || CardId.prophecy => 1,
        CardId.freeze => 4,
        _ => 5,
      };
      for (final modifier in [CardId.echo, CardId.manaSabotage]) {
        test(
          '${owner.name} ${modifier.wire} on ${named.wire}: one charge and one payoff',
          () {
            final root = _root(owner, [modifier], enemy: [named], mana: 3);
            var state = _cast(root, modifier, target: named.wire);
            state = _move(state, 'd3d4', owner);
            final extra = modifier == CardId.manaSabotage ? 1 : 0;
            expect(
              BattleRulesCore.effectiveCost(state.rules, owner.opposite, named),
              baseCost + extra,
            );
            final target = switch (named) {
              CardId.radar => CardId.prophecy.wire,
              CardId.freeze => _square('c4', owner),
              CardId.boardSeal => _square('d7', owner),
              _ => null,
            };
            state = _cast(state, named, target: target);
            expect(state.rules.mana[owner.opposite], 6 - baseCost - extra);
            expect(state.rules.mana[owner], modifier == CardId.echo ? 3 : 1);
            expect(state.rules.used[owner.opposite], [named]);
            if (named == CardId.prophecy) {
              expect(state.rules.phase, BattlePhase.pending);
              state = DeckManager.apply(
                state,
                ResolveAction(
                  state.hidden.knowledge[owner.opposite]!.pendingCards,
                ),
              );
              expect(state.rules.mana[owner.opposite], 6 - baseCost - extra);
              expect(state.rules.mana[owner], modifier == CardId.echo ? 3 : 1);
            }
            expect(state.rules.modifiers, isEmpty);
            expect(
              BattleRulesCore.effectiveCost(state.rules, owner.opposite, named),
              baseCost,
            );
          },
        );
      }

      test(
        '${owner.name} Card Block on ${named.wire}: cannot cast, can discard, never skips chess',
        () {
          final root = _root(
            owner,
            [CardId.cardBlock],
            enemy: [named],
            mana: 3,
          );
          var state = _cast(root, CardId.cardBlock, target: named.wire);
          state = _move(state, 'd3d4', owner);
          expect(
            BattleRulesCore.legalActions(state.view(owner.opposite))
                .whereType<PlayCardAction>()
                .where((action) => action.card == named),
            isEmpty,
          );
          final before = jsonEncode(state.toJson());
          state = DeckManager.apply(state, DiscardAction(named));
          expect(state.rules.mana[owner.opposite], 6);
          expect(state.rules.discarded[owner.opposite], [named]);
          expect(state.rules.modifiers, isEmpty);
          expect(before, isNot(jsonEncode(state.toJson())));
          _expectLiteralMoves(state);
          expect(_actualMoves(state), contains(_uci('e8f8', owner)));
          state = _move(state, 'e8f8', owner);
          expect(state.rules.ply, 2);
        },
      );
    }

    for (final close in ['freeze', 'prophecy', 'pass', 'discard']) {
      test(
        '${owner.name} Contract minimum price and one-window expiry via $close',
        () {
          final root = _root(owner, [
            CardId.shadowContract,
            CardId.freeze,
            CardId.radar,
          ], mana: 2);
          var state = DeckManager.apply(
            root,
            const PlayCardAction(
              CardId.shadowContract,
              sacrifice: CardId.radar,
            ),
          );
          expect(state.rules.mana[owner], 1);
          expect(state.rules.discarded[owner], [CardId.radar]);
          state = _move(state, 'd3d4', owner);
          state = _move(_pass(state), 'e8f8', owner);
          expect(state.rules.mana[owner], 2);
          expect(
            BattleRulesCore.effectiveCost(state.rules, owner, CardId.freeze),
            2,
          );
          expect(
            BattleRulesCore.effectiveCost(state.rules, owner, CardId.prophecy),
            1,
          );
          state = switch (close) {
            'freeze' => _cast(
              state,
              CardId.freeze,
              target: _square('c6', owner),
            ),
            'prophecy' => _cast(state, CardId.prophecy),
            'discard' => DeckManager.apply(
              state,
              const DiscardAction(CardId.freeze),
            ),
            _ => _pass(state),
          };
          expect(
            state.rules.mana[owner],
            close == 'freeze'
                ? 0
                : close == 'prophecy'
                ? 1
                : 2,
          );
          if (close == 'prophecy') {
            state = DeckManager.apply(
              state,
              ResolveAction(state.hidden.knowledge[owner]!.pendingCards),
            );
          }
          expect(state.rules.modifiers, isEmpty);
          expect(
            BattleRulesCore.effectiveCost(state.rules, owner, CardId.freeze),
            4,
          );
          expect(state.rules.phase, BattlePhase.chess);
        },
      );
    }

    test(
      '${owner.name} Contract + Sabotage cannot make a three-mana Freeze affordable with two',
      () {
        final root = _root(
          owner,
          [CardId.shadowContract, CardId.freeze, CardId.radar],
          enemy: [CardId.manaSabotage],
          mana: 2,
        );
        var state = DeckManager.apply(
          root,
          const PlayCardAction(CardId.shadowContract, sacrifice: CardId.radar),
        );
        state = _move(state, 'd3d4', owner);
        state = _cast(state, CardId.manaSabotage, target: CardId.freeze.wire);
        state = _move(state, 'e8f8', owner);
        expect(state.rules.mana[owner], 2);
        expect(state.rules.modifiers, hasLength(2));
        expect(
          BattleRulesCore.effectiveCost(state.rules, owner, CardId.freeze),
          3,
        );
        final before = jsonEncode(state.toJson());
        expect(
          () => _cast(state, CardId.freeze, target: _square('c6', owner)),
          throwsStateError,
        );
        expect(jsonEncode(state.toJson()), before);
        state = _pass(state);
        expect(state.rules.modifiers, isEmpty);
        expect(state.rules.mana[owner], 2);
        _expectLiteralMoves(state);
      },
    );
  }
}
