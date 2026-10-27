import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import '../../tool/battle_fixture_support.dart';

Object? swapSides(Object? value) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        e.key == 'w'
            ? 'b'
            : e.key == 'b'
            ? 'w'
            : e.key: swapSides(e.value),
    };
  }
  if (value is List) return value.map(swapSides).toList();
  return value == 'w'
      ? 'b'
      : value == 'b'
      ? 'w'
      : value;
}

AuthoritativeBattleState mirrored(AuthoritativeBattleState source) {
  final j = swapSides(source.toJson()) as Map;
  final board = source.rules.board;
  final squares = <Piece?>[
    for (var i = 0; i < 64; i++)
      board.squares[i ^ 56]?.copyWith(
        color: board.squares[i ^ 56]!.color.opposite,
      ),
  ];
  final reflected = Board(
    squares: squares,
    turn: board.turn.opposite,
    castling: ((board.castling & 3) << 2) | ((board.castling & 12) >> 2),
    enPassant: board.enPassant == null ? null : board.enPassant! ^ 56,
    halfmoveClock: board.halfmoveClock,
    fullmoveNumber: board.fullmoveNumber,
  );
  final rules = j['rules'] as Map;
  rules['fen'] =
      '${reflected.positionKey()} ${reflected.halfmoveClock} ${reflected.fullmoveNumber}';
  rules['pieceIds'] = [
    for (var i = 0; i < 64; i++) source.rules.pieceIds[i ^ 56],
  ];
  for (final effect in rules['boardEffects'] as List) {
    effect['squares'] = [
      for (final square in effect['squares'] as List) (square as int) ^ 56,
    ];
  }
  rules['repetitions'] = <String, int>{};
  return AuthoritativeBattleState.fromJson(j);
}

void invariants(AuthoritativeBattleState s) {
  for (final side in PieceColor.values) {
    final hand = s.hidden.hands[side]!, deck = s.hidden.decks[side]!;
    expect(hand.length, s.rules.handCounts[side]);
    expect(deck.length, s.rules.deckCounts[side]);
    expect(hand.length, lessThanOrEqualTo(4));
    final inventory = [
      ...hand,
      ...deck,
      ...s.rules.used[side]!,
      ...s.rules.discarded[side]!,
    ];
    expect(inventory.length, 10);
    expect(inventory.toSet().length, 10);
    expect(inventory.toSet(), s.rules.arsenals[side]!.toSet());
    expect(s.rules.mana[side], inInclusiveRange(0, 6));
    expect(
      BattleRulesCore.legalActions(s.view(side)),
      isA<List<BattleAction>>(),
    );
  }
  expect(AuthoritativeBattleState.fromJson(s.toJson()).toJson(), s.toJson());
}

void main() {
  final fixtures =
      (jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
              as Map)['fixtures']
          as List;
  final counts = <String, Map<String, int>>{};
  for (final card in CardId.values) {
    test(
      '${card.wire}: 1000 state variants, authority and chess continuation',
      () {
        final fixture = fixtures.cast<Map>().singleWhere(
          (f) => f['fixtureId'] == 'card-${card.wire}',
        );
        var legalCount = 0, rejected = 0, moves = 0, resolves = 0, discards = 0;
        for (var index = 0; index < 1000; index++) {
          var s = fixtureInitial(fixture);
          if (index.isOdd) s = mirrored(s);
          final side = s.rules.board.turn;
          final d = RuleDraft(s.rules);
          d.ownTurns = {
            for (final c in PieceColor.values) c: 2 + (index ~/ 7) % 17,
          };
          d.mana[side] = index % 7;
          d.board = Board(
            squares: d.board.squares,
            turn: side,
            castling: d.board.castling,
            enPassant: d.board.enPassant,
            halfmoveClock: index % 140,
            fullmoveNumber: 1 + index,
          );
          if (index % 11 == 0) {
            d.phase = BattlePhase.chess;
            d.ownTurns[side] = 1;
          }
          if (index % 11 == 1) d.phase = BattlePhase.chess;
          if (index % 9 < 3) {
            d.modifiers.add(
              PendingModifier(
                id: 'stress-$index',
                type:
                    [
                      ModifierType.cardBlock,
                      ModifierType.manaSabotage,
                      ModifierType.discount,
                    ][index % 9],
                owner: side.opposite,
                responseSide: side,
                targetCard: card,
                ownTurn: d.ownTurns[side]!,
              ),
            );
          }
          s = AuthoritativeBattleState(d.freeze(), s.hidden);
          final before = jsonEncode(canonicalObject(s.toJson()));
          final options =
              BattleRulesCore.legalActions(s.view(side))
                  .whereType<PlayCardAction>()
                  .where((a) => a.card == card)
                  .toList();
          invariants(s);
          if (options.isEmpty) {
            final sample =
                (fixture['steps'] as List).cast<Map>().firstWhere(
                      (step) => step['action']?['type'] == 'play',
                    )['action']
                    as Map;
            expect(
              () => DeckManager.apply(s, BattleAction.fromJson(sample)),
              throwsStateError,
            );
            rejected++;
          } else {
            final action = options[(index ~/ 7) % options.length];
            final cost = BattleRulesCore.effectiveCost(s.rules, side, card);
            var after = DeckManager.apply(s, action);
            expect(after.rules.board.turn, side);
            expect(after.rules.ply, s.rules.ply);
            expect(after.rules.mana[side], s.rules.mana[side]! - cost);
            expect(after.hidden.hands[side], isNot(contains(card)));
            expect(after.rules.used[side], contains(card));
            invariants(after);
            legalCount++;
            if (after.rules.phase == BattlePhase.pending) {
              final pending = after.hidden.knowledge[side]!.pendingCards;
              expect(pending, isNotEmpty);
              final resolution =
                  BattleRulesCore.legalActions(
                    after.view(side),
                  ).whereType<ResolveAction>().toList();
              final picked = resolution[(index ~/ 7) % resolution.length];
              after = DeckManager.apply(after, picked);
              expect(
                after.hidden.knowledge[side]!.knownUpcomingCards,
                picked.order,
              );
              expect(
                after.hidden.decks[side]!.take(picked.order.length),
                picked.order,
              );
              resolves++;
            }
            expect(after.rules.phase, BattlePhase.chess);
            final chess =
                BattleRulesCore.legalActions(
                  after.view(side),
                ).whereType<ChessMoveAction>().toList();
            expect(
              chess,
              isNotEmpty,
              reason: '${card.wire}: committed card must preserve a move',
            );
            after = DeckManager.apply(
              after,
              chess[(index ~/ 7) % chess.length],
            );
            expect(after.rules.ply, s.rules.ply + 1);
            expect(after.rules.board.turn, side.opposite);
            invariants(after);
            moves++;
          }
          expect(
            jsonEncode(canonicalObject(s.toJson())),
            before,
            reason: 'input remains immutable',
          );
          if (s.rules.phase == BattlePhase.card) {
            var discarded = DeckManager.apply(s, DiscardAction(card));
            expect(discarded.rules.phase, BattlePhase.chess);
            expect(discarded.rules.board.turn, side);
            expect(discarded.rules.mana[side], s.rules.mana[side]);
            final chess =
                BattleRulesCore.legalActions(
                  discarded.view(side),
                ).whereType<ChessMoveAction>().toList();
            expect(chess, isNotEmpty);
            discarded = DeckManager.apply(
              discarded,
              chess[index % chess.length],
            );
            invariants(discarded);
            discards++;
          }
        }
        expect(legalCount, greaterThan(0));
        expect(rejected, greaterThan(0));
        counts[card.wire] = {
          'scenarios': 1000,
          'casts': legalCount,
          'rejected': rejected,
          'chessMovesAfterCast': moves,
          'resolutions': resolves,
          'discardThenMove': discards,
        };
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
  tearDownAll(() {
    Directory('qa/v212').createSync(recursive: true);
    File(
      'qa/v212/card-stress-counts.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(counts));
  });
}
