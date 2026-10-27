import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/v223_rook_bend_cases.dart';

List<String> _moves(AuthoritativeBattleState state, PieceColor side) =>
    BattleRulesCore.legalActions(
        state.view(side),
      ).whereType<ChessMoveAction>().map((a) => a.uci).toList()
      ..sort();

void _reject(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(state.toJson());
  final view = state.view(state.rules.board.turn);
  expect(BattleRulesCore.isLegalAction(view, action), isFalse);
  final illegal = isA<StateError>().having(
    (error) => error.message,
    'message',
    'illegal-action',
  );
  expect(() => BattleRulesCore.transition(view, action), throwsA(illegal));
  expect(() => DeckManager.apply(state, action), throwsA(illegal));
  expect(jsonEncode(state.toJson()), before);
}

void _counts(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    expect(state.rules.handCounts[side], state.hidden.hands[side]!.length);
    expect(state.rules.deckCounts[side], state.hidden.decks[side]!.length);
  }
  final ids = state.rules.pieceIds.whereType<String>().toList();
  expect(ids.toSet().length, ids.length);
  for (var square = 0; square < 64; square++) {
    expect(
      state.rules.pieceIds[square] == null,
      state.rules.board.squares[square] == null,
    );
  }
}

class _RookTransport {
  AuthoritativeBattleState state;
  final PieceColor side;
  final requests = <Map<String, dynamic>>[];
  final accepted = <BattleAction>[];
  final persisted = <String?>[];
  final receipts = <String, String>{};
  final requestStarted = Completer<void>();
  int version = 0;
  bool loseCast = false, loseMove = false;
  Completer<void>? gate;
  late final BattleV1Controller controller;

  _RookTransport(this.side, {AuthoritativeBattleState? initial})
    : state = initial ?? rbFixture(side: side) {
    controller = BattleV1Controller(
      uid: side.isWhite ? 'rookWhite' : 'rookBlack',
      matchId: 'bv1_0123456789abcdef0123456789abcdef',
      initialResponse: response(),
      persistPending: (json) async {
        persisted.add(json);
      },
      request: (path, body) async {
        if (path != '/submitBattleV1Action') return response();
        requests.add(Map<String, dynamic>.from(body));
        final id = body['actionId'] as String;
        final intent = jsonEncode(body['intent']);
        final prior = receipts[id];
        if (prior != null) {
          if (prior != intent) {
            throw const BattleV1Rejection('ACTION_ID_CONFLICT');
          }
          return response();
        }
        if (body['expectedStateVersion'] != version) {
          throw const BattleV1Rejection('STALE_STATE');
        }
        if (!requestStarted.isCompleted) requestStarted.complete();
        if (gate != null) await gate!.future;
        final action = BattleAction.fromJson(body['intent'] as Map);
        state = DeckManager.apply(state, action);
        accepted.add(action);
        receipts[id] = intent;
        version++;
        if (action is PlayCardAction && loseCast) {
          loseCast = false;
          throw StateError('rook-bend-lost-cast-response');
        }
        if (action is ChessMoveAction && loseMove) {
          loseMove = false;
          throw StateError('rook-bend-lost-move-response');
        }
        return response();
      },
    );
  }

  Map<String, dynamic> response() => {
    'ok': true,
    'matchId': 'bv1_0123456789abcdef0123456789abcdef',
    'status': state.rules.terminal == null ? 'active' : 'finished',
    'serverNow': 1000 + version,
    'view': {
      'public': {
        'matchId': 'bv1_0123456789abcdef0123456789abcdef',
        'protocolVersion': 'LUNO_BATTLE_V1',
        'rulesetVersion': 1,
        'stateVersion': version,
        'participants': {'rookWhite': true, 'rookBlack': true},
        'players': {
          'w': {'uid': 'rookWhite', 'name': 'White', 'bot': false},
          'b': {'uid': 'rookBlack', 'name': 'Black', 'bot': false},
        },
        'rulesJson': jsonEncode(state.rules.toJson()),
        'clock': {
          'w': 300000,
          'b': 300000,
          'activeSide': sideWire(state.rules.board.turn),
          'startedAt': 1000 + version,
          'incrementMs': 2000,
        },
        'result':
            state.rules.terminal == null
                ? null
                : {
                  'reason': state.rules.terminal!.reason,
                  'winner':
                      state.rules.terminal!.winner == null
                          ? null
                          : sideWire(state.rules.terminal!.winner!),
                  'finishedAt': 1000 + version,
                },
        'settlementStatus': state.rules.terminal == null ? 'none' : 'pending',
        'rated': true,
        'createdAt': 1000,
        'lastEvent': null,
      },
      'private': {
        'stateVersion': version,
        'viewer': sideWire(side),
        'handJson': jsonEncode(
          state.hidden.hands[side]!.map((card) => card.wire).toList(),
        ),
        'knowledgeJson': jsonEncode(state.hidden.knowledge[side]!.toJson()),
      },
    },
  };
}

void main() {
  for (final side in PieceColor.values) {
    group('rook_bend/${side.name}', () {
      for (var source = 0; source < 64; source++) {
        final origin = source;
        test(
          'independent geometry and full transition at ${rbName(origin)}',
          () {
            final state = rbFixture(
              side: side,
              whiteBoard: rbGeometryBoard(origin),
            );
            final from = rbSquare(side, rbName(origin));
            final expected = rbOracleMoves(state.rules, from, side);
            final before = jsonEncode(state.toJson());
            expect(
              BattleRulesCore.specialMoves(
                  state.rules,
                  CardId.rookBend,
                  from,
                  side,
                ).map((m) => m.uci).toList()
                ..sort(),
              expected,
            );
            expect(
              BattleRulesCore.cardTargets(state.view(side), CardId.rookBend),
              expected.isEmpty ? <int>[] : [from],
            );
            if (expected.isEmpty) {
              _reject(state, PlayCardAction(CardId.rookBend, target: from));
              return;
            }
            final cast = rbCast(state, source: rbName(origin));
            expect(_moves(cast, side), expected);
            expect(cast.rules.fen, state.rules.fen);
            expect(cast.rules.ply, 0);
            expect(cast.rules.mana[side], 4);
            expect(cast.rules.used[side], [CardId.rookBend]);
            expect(cast.hidden.hands[side], [CardId.radar, CardId.prophecy]);
            expect(cast.rules.special!.from, from);
            expect(cast.rules.special!.card, CardId.rookBend);
            expect(cast.rules.special!.moves, expected);
            _reject(cast, PlayCardAction(CardId.rookBend, target: from));
            _reject(cast, const PassAction());
            _reject(cast, const DiscardAction(CardId.radar));
            for (final uci in expected) {
              final to = rbIndex(uci.substring(2, 4));
              final after = DeckManager.apply(cast, ChessMoveAction(uci));
              final expectedBoard =
                  [...state.rules.board.squares]
                    ..[from] = null
                    ..[to] = state.rules.board.squares[from];
              final expectedIds =
                  [...state.rules.pieceIds]
                    ..[from] = null
                    ..[to] = state.rules.pieceIds[from];
              expect(after.rules.board.squares, expectedBoard);
              expect(after.rules.pieceIds, expectedIds);
              expect(after.rules.movedPawns, state.rules.movedPawns);
              expect(after.rules.board.halfmoveClock, 38);
              expect(after.rules.board.fullmoveNumber, side.isWhite ? 10 : 11);
              expect(after.rules.board.enPassant, isNull);
              expect(after.rules.board.turn, side.opposite);
              expect(after.rules.ply, 1);
              expect(after.rules.special, isNull);
              expect(BattleRulesCore.legalActions(after.view(side)), isEmpty);
              expect(
                rbAttacked(
                  after.rules.board.squares,
                  after.rules.board.kingSquare(side),
                  side.opposite,
                ),
                isFalse,
              );
              _counts(after);
              if (after.rules.terminal == null) {
                expect(after.rules.drawCounts[side], 4);
                expect(after.hidden.hands[side], [
                  CardId.radar,
                  CardId.prophecy,
                  CardId.shelter,
                ]);
                final passed = DeckManager.apply(after, const PassAction());
                expect(_moves(passed, side.opposite), isNotEmpty);
              } else {
                expect(after.rules.phase, BattlePhase.terminal);
                expect(
                  BattleRulesCore.legalActions(after.view(side.opposite)),
                  isEmpty,
                );
              }
            }
            expect(jsonEncode(state.toJson()), before);
            _counts(cast);
          },
        );
      }

      for (final destination in ['c3', 'c5', 'e3', 'e5']) {
        for (final owner in PieceColor.values) {
          for (final type in PieceType.values) {
            test(
              'occupied $destination ${owner.name}/${type.name} rejects capture',
              () {
                final base = Board.fromFen('8/7k/8/8/3R4/8/8/K7 w - - 37 10');
                final squares = [...base.squares];
                if (type == PieceType.king) {
                  squares[owner.isWhite ? rbIndex('a1') : rbIndex('h7')] = null;
                }
                squares[rbIndex(destination)] = Piece(owner, type);
                final state = rbFixture(
                  side: side,
                  whiteBoard: Board(
                    squares: squares,
                    turn: PieceColor.white,
                    castling: 0,
                    enPassant: null,
                    halfmoveClock: 37,
                    fullmoveNumber: 10,
                  ),
                );
                final from = rbSquare(side, 'd4');
                final expected = rbOracleMoves(state.rules, from, side);
                expect(
                  expected,
                  isNot(contains(rbUci(side, 'd4$destination'))),
                );
                expect(
                  BattleRulesCore.specialMoves(
                      state.rules,
                      CardId.rookBend,
                      from,
                      side,
                    ).map((m) => m.uci).toList()
                    ..sort(),
                  expected,
                );
                if (expected.isEmpty) {
                  _reject(state, PlayCardAction(CardId.rookBend, target: from));
                } else {
                  final cast = rbCast(state);
                  expect(_moves(cast, side), expected);
                  _reject(cast, ChessMoveAction(rbUci(side, 'd4$destination')));
                }
              },
            );
          }
        }
      }

      const safety = <(String, String, String, List<String>)>[
        ('file pin', '4r2k/8/8/8/8/8/4R3/4K3 w - - 0 10', 'e2', []),
        (
          'diagonal pin stays on ray',
          '7k/8/8/5b2/8/3R4/8/1K6 w - - 0 10',
          'd3',
          ['d3c2', 'd3e4'],
        ),
        (
          'escape check by interposition',
          '4r2k/8/8/8/8/8/3R4/4K3 w - - 0 10',
          'd2',
          ['d2e3'],
        ),
        (
          'double check cannot be blocked by rook',
          '4r2k/8/8/8/1b6/3R4/8/4K3 w - - 0 10',
          'd3',
          [],
        ),
      ];
      for (final (label, fen, source, whiteExpected) in safety) {
        test(label, () {
          final state = rbFixture(side: side, fen: fen);
          final from = rbSquare(side, source);
          final expected =
              whiteExpected.map((m) => rbUci(side, m)).toList()..sort();
          expect(rbOracleMoves(state.rules, from, side), expected);
          expect(
            BattleRulesCore.specialMoves(
                state.rules,
                CardId.rookBend,
                from,
                side,
              ).map((m) => m.uci).toList()
              ..sort(),
            expected,
          );
          if (expected.isEmpty) {
            _reject(state, PlayCardAction(CardId.rookBend, target: from));
          } else {
            expect(_moves(rbCast(state, source: source), side), expected);
          }
        });
      }

      test('frozen enemy slider still attacks own king', () {
        var state = rbFixture(
          side: side,
          fen: '4r2k/8/8/8/8/8/4R3/4K3 w - - 0 10',
        );
        state = rbEdit(
          state,
          (d) => d.pieceEffects.add(
            rbPieceEffect(
              state,
              PieceEffectType.freeze,
              source: 'e8',
              owner: side,
              responseSide: side.opposite,
            ),
          ),
        );
        expect(rbOracleMoves(state.rules, rbSquare(side, 'e2'), side), isEmpty);
        _reject(
          state,
          PlayCardAction(CardId.rookBend, target: rbSquare(side, 'e2')),
        );
      });

      test('piece effects x destination owners independent matrix', () {
        const types = [
          PieceEffectType.shelter,
          PieceEffectType.chain,
          PieceEffectType.slow,
          PieceEffectType.mineDebuff,
          PieceEffectType.freeze,
        ];
        for (var mask = 0; mask < 32; mask++) {
          for (var boardMode = 0; boardMode < 4; boardMode++) {
            var state = rbFixture(side: side);
            state = rbEdit(state, (d) {
              for (var bit = 0; bit < types.length; bit++) {
                if ((mask & (1 << bit)) != 0) {
                  d.pieceEffects.add(rbPieceEffect(state, types[bit]));
                }
              }
              d.boardEffects.add(
                rbBoardEffect(state, BoardEffectType.fog, [
                  'd4',
                  'e4',
                  'd5',
                  'e5',
                ]),
              );
              d.boardEffects.add(
                rbBoardEffect(state, BoardEffectType.mine, ['c5']),
              );
              if (boardMode > 0) {
                d.boardEffects.add(
                  rbBoardEffect(state, BoardEffectType.lockedSquare, [
                    'c3',
                  ], owner: boardMode == 1 ? side : side.opposite),
                );
              }
              if (boardMode == 3) {
                d.boardEffects.add(
                  rbBoardEffect(state, BoardEffectType.boardSeal, [
                    'e5',
                    'f5',
                    'e6',
                    'f6',
                  ]),
                );
              }
            });
            final whiteExpected =
                (mask & 16) != 0
                    ? <String>[]
                    : [
                      if (boardMode < 2) 'd4c3',
                      'd4c5',
                      'd4e3',
                      if (boardMode != 3) 'd4e5',
                    ];
            final expected =
                whiteExpected.map((m) => rbUci(side, m)).toList()..sort();
            final from = rbSquare(side, 'd4');
            expect(
              rbOracleMoves(state.rules, from, side),
              expected,
              reason: 'oracle mask=$mask board=$boardMode',
            );
            expect(
              BattleRulesCore.specialMoves(
                  state.rules,
                  CardId.rookBend,
                  from,
                  side,
                ).map((m) => m.uci).toList()
                ..sort(),
              expected,
              reason: 'core mask=$mask board=$boardMode',
            );
            if (expected.isEmpty) {
              _reject(state, PlayCardAction(CardId.rookBend, target: from));
            } else {
              final cast = rbCast(state);
              expect(_moves(cast, side), expected);
              expect(
                cast.rules.boardEffects.any(
                  (e) => e.type == BoardEffectType.fog,
                ),
                isFalse,
              );
              for (final uci in expected) {
                final moved = DeckManager.apply(cast, ChessMoveAction(uci));
                expect(
                  moved.rules.pieceEffects.where(
                    (e) =>
                        e.type == PieceEffectType.chain ||
                        e.type == PieceEffectType.slow,
                  ),
                  isEmpty,
                );
                final shelters =
                    moved.rules.pieceEffects
                        .where((e) => e.type == PieceEffectType.shelter)
                        .toList();
                expect(shelters.length, (mask & 1) != 0 ? 1 : 0);
                if (shelters.isNotEmpty) {
                  expect(shelters.single.pieceId, state.rules.pieceIds[from]);
                }
                final debuffs =
                    moved.rules.pieceEffects
                        .where((e) => e.type == PieceEffectType.mineDebuff)
                        .toList();
                expect(debuffs.length, uci == rbUci(side, 'd4c5') ? 1 : 0);
                if (debuffs.isNotEmpty) {
                  expect(debuffs.single.id, isNot('rb-mineDebuff'));
                  expect(debuffs.single.pieceId, state.rules.pieceIds[from]);
                }
                _counts(moved);
              }
            }
          }
        }
      });

      test(
        'own Mine persists; enemy Mine triggers once and follows rook ID',
        () {
          for (final mineOwner in [side, side.opposite]) {
            var state = rbFixture(side: side);
            state = rbEdit(
              state,
              (d) => d.boardEffects.add(
                rbBoardEffect(state, BoardEffectType.mine, [
                  'c5',
                ], owner: mineOwner),
              ),
            );
            final moved = rbMove(rbCast(state), 'd4c5');
            expect(
              moved.rules.boardEffects.any(
                (e) => e.type == BoardEffectType.mine,
              ),
              mineOwner == side,
            );
            final debuffs =
                moved.rules.pieceEffects
                    .where((e) => e.type == PieceEffectType.mineDebuff)
                    .toList();
            expect(debuffs.length, mineOwner == side ? 0 : 1);
            if (debuffs.isNotEmpty) {
              expect(
                debuffs.single.pieceId,
                state.rules.pieceIds[rbSquare(side, 'd4')],
              );
              expect(debuffs.single.duration, EffectDuration.pieceMove);
              expect(debuffs.single.responseSide, side);
            }
          }
        },
      );

      test(
        'Mine from bend survives another mover, rejects capture, consumes on rook move',
        () {
          var state = rbFixture(
            side: side,
            fen: '7k/2n5/8/8/3R4/8/P7/K7 w - - 37 10',
          );
          state = rbEdit(
            state,
            (d) => d.boardEffects.add(
              rbBoardEffect(state, BoardEffectType.mine, ['c5']),
            ),
          );
          state = rbMove(rbCast(state), 'd4c5');
          final debuff = state.rules.pieceEffects.singleWhere(
            (e) => e.type == PieceEffectType.mineDebuff,
          );
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(rbUci(side, 'h8h7')),
          );
          state = DeckManager.apply(state, const PassAction());
          _reject(state, ChessMoveAction(rbUci(side, 'c5c7')));
          state = DeckManager.apply(
            state,
            ChessMoveAction(rbUci(side, 'a2a3')),
          );
          expect(
            state.rules.pieceEffects.map((e) => e.id),
            contains(debuff.id),
          );
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(rbUci(side, 'h7h8')),
          );
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(rbUci(side, 'c5c6')),
          );
          expect(
            state.rules.pieceEffects.map((e) => e.id),
            isNot(contains(debuff.id)),
          );
          expect(state.rules.pieceIds[rbSquare(side, 'c6')], debuff.pieceId);
          expect(
            state.rules.board.squares[rbSquare(side, 'c7')]?.type,
            PieceType.knight,
          );
          _counts(state);
        },
      );

      test(
        'all four locked destinations reject cast but leave discard and chess usable',
        () {
          var state = rbFixture(side: side);
          state = rbEdit(
            state,
            (d) => d.boardEffects.add(
              rbBoardEffect(state, BoardEffectType.lockedSquare, [
                'c3',
                'c5',
                'e3',
                'e5',
              ]),
            ),
          );
          expect(
            BattleRulesCore.cardTargets(state.view(side), CardId.rookBend),
            isEmpty,
          );
          _reject(
            state,
            PlayCardAction(CardId.rookBend, target: rbSquare(side, 'd4')),
          );
          final discarded = DeckManager.apply(
            state,
            const DiscardAction(CardId.rookBend),
          );
          expect(_moves(discarded, side), contains(rbUci(side, 'd4d5')));
          expect(discarded.rules.terminal, isNull);
          expect(discarded.rules.special, isNull);
        },
      );

      for (final source in ['a1', 'h1']) {
        test(
          '$source revokes only its castling side, never restores on return',
          () {
            final state = rbFixture(
              side: side,
              fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 10',
            );
            final destination = source == 'a1' ? 'b2' : 'g2';
            final after = rbMove(
              rbCast(state, source: source),
              '$source$destination',
            );
            final revoked =
                side.isWhite
                    ? (source == 'a1'
                        ? Castling.whiteQueen
                        : Castling.whiteKing)
                    : (source == 'a1'
                        ? Castling.blackQueen
                        : Castling.blackKing);
            expect(after.rules.board.castling, Castling.all & ~revoked);
            var next = DeckManager.apply(after, const PassAction());
            next = DeckManager.apply(
              next,
              ChessMoveAction(rbUci(side, 'e8e7')),
            );
            next = DeckManager.apply(next, const PassAction());
            next = DeckManager.apply(
              next,
              ChessMoveAction(rbUci(side, '$destination${destination[0]}1')),
            );
            next = DeckManager.apply(next, const PassAction());
            next = DeckManager.apply(
              next,
              ChessMoveAction(rbUci(side, 'e7e8')),
            );
            next = DeckManager.apply(next, const PassAction());
            next = DeckManager.apply(
              next,
              ChessMoveAction(rbUci(side, '${destination[0]}1$source')),
            );
            expect(next.rules.board.castling & revoked, 0);
            expect(
              next.rules.pieceIds[rbSquare(side, source)],
              state.rules.pieceIds[rbSquare(side, source)],
            );
          },
        );
      }

      test(
        'special mate overrides 75-move draw and attributes only the special move',
        () {
          final state = rbFixture(side: side, fen: rbMateFen);
          final cast = rbCast(state, source: 'b6');
          expect(cast.rules.terminal, isNull);
          final moved = rbMove(cast, 'b6a7');
          expect(moved.rules.board.halfmoveClock, 150);
          expect(moved.rules.terminal?.reason, 'checkmate');
          expect(moved.rules.terminal?.winner, side);
          expect(moved.rules.terminal?.mateBySpecialMove, isTrue);
          expect(moved.rules.terminal?.mateByRestriction, isFalse);
          expect(moved.rules.terminal?.stalemateByRestriction, isFalse);
          expect(moved.rules.phase, BattlePhase.terminal);
          expect(moved.rules.special, isNull);
          expect(moved.rules.drawCounts, state.rules.drawCounts);
          expect(moved.hidden.decks, state.hidden.decks);
          for (final viewer in PieceColor.values) {
            expect(BattleRulesCore.legalActions(moved.view(viewer)), isEmpty);
          }
          _reject(moved, ChessMoveAction(rbUci(side, 'a7a6')));
        },
      );

      test('special stalemate is a draw, not special checkmate', () {
        final state = rbFixture(side: side, fen: rbStalemateFen);
        final moved = rbMove(rbCast(state, source: 'b6'), 'b6c7');
        expect(moved.rules.terminal?.reason, 'stalemate');
        expect(moved.rules.terminal?.winner, isNull);
        expect(moved.rules.terminal?.mateBySpecialMove, isFalse);
        expect(moved.rules.terminal?.mateByRestriction, isFalse);
        expect(moved.rules.terminal?.stalemateByRestriction, isFalse);
        expect(moved.rules.drawCounts, state.rules.drawCounts);
      });

      test('quiet nonmate at threshold ends as 75-move draw', () {
        final state = rbFixture(
          side: side,
          fen: rbBaseFen.replaceFirst('37 10', '149 10'),
        );
        final moved = rbMove(rbCast(state), 'd4c3');
        expect(moved.rules.terminal?.reason, 'seventy_five_moves');
        expect(moved.rules.terminal?.winner, isNull);
        expect(moved.rules.terminal?.mateBySpecialMove, isFalse);
      });

      test(
        'cast admission gates cost, first turn, hand membership and card block',
        () {
          _reject(
            rbFixture(side: side, mana: 1),
            PlayCardAction(CardId.rookBend, target: rbSquare(side, 'd4')),
          );
          final noHand = rbFixture(
            side: side,
            deck: [
              ...rbDeck.skip(1).take(3),
              CardId.rookBend,
              ...rbDeck.skip(4),
            ],
          );
          _reject(
            noHand,
            PlayCardAction(CardId.rookBend, target: rbSquare(side, 'd4')),
          );
          final first = rbEdit(rbFixture(side: side), (d) {
            d.ownTurns[side] = 1;
            d.phase = BattlePhase.chess;
          });
          _reject(
            first,
            PlayCardAction(CardId.rookBend, target: rbSquare(side, 'd4')),
          );
          var blocked = rbFixture(side: side);
          blocked = rbEdit(
            blocked,
            (d) => d.modifiers.add(
              PendingModifier(
                id: 'rb-card-block',
                type: ModifierType.cardBlock,
                owner: side.opposite,
                responseSide: side,
                targetCard: CardId.rookBend,
                ownTurn: 2,
              ),
            ),
          );
          _reject(
            blocked,
            PlayCardAction(CardId.rookBend, target: rbSquare(side, 'd4')),
          );
          final discarded = DeckManager.apply(
            blocked,
            const DiscardAction(CardId.rookBend),
          );
          expect(discarded.rules.special, isNull);
          expect(discarded.rules.mana, blocked.rules.mana);
          expect(discarded.rules.modifiers, isEmpty);
          expect(_moves(discarded, side), contains(rbUci(side, 'd4d5')));
          expect(_moves(discarded, side), isNot(contains(rbUci(side, 'd4c3'))));
        },
      );

      test(
        'returning turn has no leftover diagonal privilege or second card use',
        () {
          var state = rbMove(rbCast(rbFixture(side: side)), 'd4c3');
          state = DeckManager.apply(state, const PassAction());
          state = DeckManager.apply(
            state,
            ChessMoveAction(rbUci(side, 'h8h7')),
          );
          _reject(
            state,
            PlayCardAction(CardId.rookBend, target: rbSquare(side, 'c3')),
          );
          state = DeckManager.apply(state, const PassAction());
          expect(state.rules.special, isNull);
          _reject(state, ChessMoveAction(rbUci(side, 'c3b2')));
          expect(_moves(state, side), contains(rbUci(side, 'c3c4')));
        },
      );

      test(
        'quiet bend clears en passant without touching pawn identities/history',
        () {
          var state = rbFixture(
            side: side,
            fen: '7k/8/8/3pP3/3R4/8/8/K7 w - d6 37 10',
          );
          state = rbEdit(state, (d) {
            d.movedPawns.addAll([
              d.pieceIds[rbSquare(side, 'd5')]!,
              d.pieceIds[rbSquare(side, 'e5')]!,
            ]);
            d.movedPawns.sort();
          });
          final cast = rbCast(state);
          expect(cast.rules.board.enPassant, rbSquare(side, 'd6'));
          final moved = rbMove(cast, 'd4c3');
          expect(moved.rules.board.enPassant, isNull);
          expect(moved.rules.movedPawns, state.rules.movedPawns);
          for (final pawn in ['d5', 'e5']) {
            expect(
              moved.rules.pieceIds[rbSquare(side, pawn)],
              state.rules.pieceIds[rbSquare(side, pawn)],
            );
            expect(
              moved.rules.board.squares[rbSquare(side, pawn)],
              state.rules.board.squares[rbSquare(side, pawn)],
            );
          }
          expect(moved.rules.board.halfmoveClock, 38);
        },
      );

      test('malformed source and wrong sacrifice reject atomically', () {
        final state = rbFixture(side: side);
        final from = rbSquare(side, 'd4');
        final before = jsonEncode(state.toJson());
        for (final target in <Object?>[
          null,
          -1,
          64,
          1 << 30,
          from + .5,
          double.nan,
          double.infinity,
          -double.infinity,
          '$from',
          'd4',
          false,
          true,
          <Object?>[],
          <String, Object?>{'square': from},
          rbSquare(side, 'a1'),
          rbSquare(side, 'h8'),
          rbSquare(side, 'a2'),
        ]) {
          _reject(state, PlayCardAction(CardId.rookBend, target: target));
          _reject(
            state,
            BattleAction.fromJson({
              'type': 'play',
              'card': 'rook_bend',
              'target': target,
            }),
          );
        }
        _reject(
          state,
          PlayCardAction(CardId.rookBend, target: from.toDouble()),
        );
        for (final sacrifice in [
          CardId.rookBend,
          CardId.radar,
          CardId.freeze,
        ]) {
          _reject(
            state,
            PlayCardAction(CardId.rookBend, target: from, sacrifice: sacrifice),
          );
        }
        final expected = rbCast(state).toJson();
        for (final number in ['$from', '$from.0', '${from}e0']) {
          final parsed = BattleAction.fromJson(
            jsonDecode('{"type":"play","card":"rook_bend","target":$number}')
                as Map,
          );
          expect((parsed as PlayCardAction).target, isA<int>());
          expect(DeckManager.apply(state, parsed).toJson(), expected);
          expect(jsonEncode(state.toJson()), before);
        }
      });

      test('source must be own rook, not any other friendly/enemy piece', () {
        for (final owner in PieceColor.values) {
          for (final type in PieceType.values) {
            if (owner == PieceColor.white && type == PieceType.rook) continue;
            final squares = [
              ...Board.fromFen('8/7k/8/8/3R4/8/8/K7 w - - 37 10').squares,
            ];
            if (type == PieceType.king) {
              squares[rbIndex(owner.isWhite ? 'a1' : 'h7')] = null;
            }
            squares[rbIndex('d4')] = Piece(owner, type);
            final state = rbFixture(
              side: side,
              whiteBoard: Board(
                squares: squares,
                turn: PieceColor.white,
                castling: 0,
                enPassant: null,
                halfmoveClock: 37,
                fullmoveNumber: 10,
              ),
            );
            expect(
              BattleRulesCore.specialMoves(
                state.rules,
                CardId.rookBend,
                rbSquare(side, 'd4'),
                side,
              ),
              isEmpty,
            );
            _reject(
              state,
              PlayCardAction(CardId.rookBend, target: rbSquare(side, 'd4')),
            );
          }
        }
      });

      test(
        'authorization rejects ordinary moves, other rook and malformed UCI',
        () {
          final state = rbFixture(
            side: side,
            fen: '7k/8/8/8/3RR3/8/8/K7 w - - 0 10',
          );
          final cast = rbCast(state);
          for (final whiteUci in ['d4d5', 'd4f6', 'd4d4', 'e4f5', 'd4c3q']) {
            _reject(cast, ChessMoveAction(rbUci(side, whiteUci)));
          }
          for (final raw in ['', 'd4', 'd4c9', 'D4C3', ' d4c3', 'd4c3\n']) {
            _reject(cast, ChessMoveAction(raw));
          }
          final moved = rbMove(cast, 'd4c3');
          expect(BattleRulesCore.legalActions(moved.view(side)), isEmpty);
          _reject(moved, ChessMoveAction(rbUci(side, 'c3b2')));
        },
      );

      test('wire round trip preserves exact source, allowed set and IDs', () {
        final state = rbFixture(side: side);
        final cast = rbCast(state);
        final restored = AuthoritativeBattleState.fromJson(
          jsonDecode(jsonEncode(cast.toJson())) as Map,
        );
        expect(restored.toJson(), cast.toJson());
        expect(restored.rules.special!.toJson(), {
          'card': 'rook_bend',
          'from': rbSquare(side, 'd4'),
          'moves':
              [
                  'd4c3',
                  'd4c5',
                  'd4e3',
                  'd4e5',
                ].map((m) => rbUci(side, m)).toList()
                ..sort(),
        });
        expect(
          rbMove(restored, 'd4c3').toJson(),
          rbMove(cast, 'd4c3').toJson(),
        );
        final extra = BattleAction.fromJson({
          'type': 'play',
          'card': 'rook_bend',
          'target': rbSquare(side, 'd4'),
          'uci': 'd4d8',
          'moves': ['d4d8'],
        });
        expect(DeckManager.apply(state, extra).toJson(), cast.toJson());
      });

      test(
        'authorization allowlist cannot invent unsafe or non-diagonal geometry',
        () {
          final cast = rbCast(rbFixture(side: side));
          final altered = rbEdit(cast, (d) {
            d.special = SpecialMoveAuthorization(
              CardId.rookBend,
              rbSquare(side, 'd4'),
              ['d4c3', 'd4d5', 'd4f6'].map((m) => rbUci(side, m)).toList(),
            );
          });
          expect(_moves(altered, side), [rbUci(side, 'd4c3')]);
          _reject(altered, ChessMoveAction(rbUci(side, 'd4d5')));
          _reject(altered, ChessMoveAction(rbUci(side, 'd4e5')));
        },
      );

      test(
        'interaction binds source and clears stale destination without rendering',
        () {
          final state = rbFixture(side: side), view = state.view(side);
          final actions = BattleRulesCore.legalActions(view);
          final ui = BattleInteraction()..synchronize(view, 0);
          ui.select(CardId.rookBend, actions);
          expect(ui.targets(view, actions), {rbSquare(side, 'd4')});
          ui.tap(rbSquare(side, 'd4'), view, actions);
          expect(ui.specialDestination, isNull);
          expect(
            ui.targets(view, actions),
            {'c3', 'c5', 'e3', 'e5'}.map((s) => rbSquare(side, s)).toSet(),
          );
          ui.tap(rbSquare(side, 'c3'), view, actions);
          expect(ui.specialDestination?.uci, rbUci(side, 'd4c3'));
          ui.tap(rbSquare(side, 'd5'), view, actions);
          expect(ui.specialDestination, isNull);
          expect(ui.play?.target, rbSquare(side, 'd4'));
          expect(ui.invalidTarget, isTrue);
          final cast = rbCast(state), castView = cast.view(side);
          ui.synchronize(castView, 1);
          expect(ui.card, isNull);
          expect(ui.piece, rbSquare(side, 'd4'));
          expect(
            ui.tap(
              rbSquare(side, 'a1'),
              castView,
              BattleRulesCore.legalActions(castView),
            ),
            isEmpty,
          );
          expect(ui.piece, rbSquare(side, 'd4'));
          expect(
            ui
                .tap(
                  rbSquare(side, 'c3'),
                  castView,
                  BattleRulesCore.legalActions(castView),
                )
                .single
                .key,
            'move:${rbUci(side, 'd4c3')}',
          );
        },
      );

      for (final lost in ['cast', 'move']) {
        test(
          'lost $lost response retries one intent and releases busy state',
          () async {
            final harness = _RookTransport(side);
            addTearDown(harness.controller.dispose);
            final controller = harness.controller;
            harness.loseCast = lost == 'cast';
            harness.loseMove = lost == 'move';
            final castAction = PlayCardAction(
              CardId.rookBend,
              target: rbSquare(side, 'd4'),
            );
            expect(await controller.submit(castAction), lost != 'cast');
            if (lost == 'cast') {
              expect(controller.busy, isFalse);
              expect(controller.hasPendingIntent, isTrue);
              await controller.retryPending();
            }
            expect(controller.view!.rules.special?.card, CardId.rookBend);
            expect(
              await controller.submit(ChessMoveAction(rbUci(side, 'd4c3'))),
              lost != 'move',
            );
            if (lost == 'move') {
              expect(controller.busy, isFalse);
              expect(controller.hasPendingIntent, isTrue);
              await controller.retryPending();
            }
            expect(controller.busy, isFalse);
            expect(controller.hasPendingIntent, isFalse);
            expect(controller.error, isNull);
            expect(controller.view!.rules.ply, 1);
            expect(controller.view!.rules.special, isNull);
            expect(harness.accepted.map((a) => a.key), [
              castAction.key,
              'move:${rbUci(side, 'd4c3')}',
            ]);
            final duplicateRequests =
                harness.requests
                    .where(
                      (body) =>
                          (body['intent'] as Map)['type'] ==
                          (lost == 'cast' ? 'play' : 'move'),
                    )
                    .toList();
            expect(duplicateRequests, hasLength(2));
            expect(duplicateRequests[0], duplicateRequests[1]);
            expect(harness.persisted.where((p) => p == null), hasLength(2));
            _counts(harness.state);
          },
        );
      }

      test(
        'in-flight cast blocks duplicate submission then exposes bounded move',
        () async {
          final harness = _RookTransport(side)..gate = Completer<void>();
          addTearDown(harness.controller.dispose);
          final action = PlayCardAction(
            CardId.rookBend,
            target: rbSquare(side, 'd4'),
          );
          final pending = harness.controller.submit(action);
          try {
            await harness.requestStarted.future;
            expect(harness.controller.busy, isTrue);
            expect(await harness.controller.submit(action), isFalse);
            expect(
              await harness.controller.submit(
                ChessMoveAction(rbUci(side, 'd4c3')),
              ),
              isFalse,
            );
          } finally {
            harness.gate!.complete();
          }
          expect(await pending, isTrue);
          expect(harness.controller.busy, isFalse);
          expect(harness.controller.hasPendingIntent, isFalse);
          expect(harness.accepted, hasLength(1));
          expect(
            harness.controller.legalActions.whereType<ChessMoveAction>(),
            hasLength(4),
          );
        },
      );

      test(
        'malformed local submission cannot start transport or leave busy/pending',
        () async {
          final harness = _RookTransport(side);
          addTearDown(harness.controller.dispose);
          for (final target in <Object?>[
            false,
            'd4',
            -1,
            64,
            rbSquare(side, 'a1'),
          ]) {
            expect(
              await harness.controller.submit(
                PlayCardAction(CardId.rookBend, target: target),
              ),
              isFalse,
            );
            expect(harness.controller.busy, isFalse);
            expect(harness.controller.hasPendingIntent, isFalse);
            expect(harness.controller.error, isNull);
          }
          expect(harness.requests, isEmpty);
          expect(harness.persisted, isEmpty);
        },
      );

      test(
        'terminal special mate projection releases controller without pending action',
        () async {
          final harness = _RookTransport(
            side,
            initial: rbFixture(side: side, fen: rbMateFen),
          );
          addTearDown(harness.controller.dispose);
          expect(
            await harness.controller.submit(
              PlayCardAction(CardId.rookBend, target: rbSquare(side, 'b6')),
            ),
            isTrue,
          );
          expect(
            await harness.controller.submit(
              ChessMoveAction(rbUci(side, 'b6a7')),
            ),
            isTrue,
          );
          expect(harness.controller.busy, isFalse);
          expect(harness.controller.error, isNull);
          expect(harness.controller.hasPendingIntent, isFalse);
          expect(harness.controller.snapshot!.result?['reason'], 'checkmate');
          expect(
            harness.controller.view!.rules.terminal!.mateBySpecialMove,
            isTrue,
          );
          expect(harness.controller.legalActions, isEmpty);
        },
      );
    });
  }
}
