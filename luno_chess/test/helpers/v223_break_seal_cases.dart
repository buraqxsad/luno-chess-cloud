import 'dart:convert';

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

int breakSealSquare(String text) =>
    text.codeUnitAt(0) - 97 + 8 * (text.codeUnitAt(1) - 49);

String breakSealChoose(PieceColor side, String white, String black) =>
    side == PieceColor.white ? white : black;

List<CardId> _deck(List<CardId> hand) {
  if (hand.length != 3 || hand.toSet().length != 3) {
    throw ArgumentError('Break Seal requires three distinct starting cards');
  }
  return [
    ...hand,
    ...CardId.values.where((card) => !hand.contains(card)).take(7),
  ];
}

AuthoritativeBattleState breakSealPosition(
  PieceColor side, {
  String? fen,
  List<CardId> hand = const [CardId.breakSeal, CardId.chain, CardId.prophecy],
  List<CardId>? enemyHand,
}) {
  final own = _deck(hand), enemy = _deck(enemyHand ?? hand);
  final state = DeckManager.newBattle(
    board: Board.fromFen(
      fen ??
          breakSealChoose(
            side,
            '6k1/8/8/1p6/8/8/1R6/5K2 w - - 17 23',
            '5k2/1r6/8/8/1P6/8/8/6K1 b - - 17 23',
          ),
    ),
    white: side == PieceColor.white ? own : enemy,
    black: side == PieceColor.black ? own : enemy,
  );
  breakSealRequire(state.rules.terminal == null, 'fixture must be nonterminal');
  breakSealRequire(state.rules.board.turn == side, 'fixture actor');
  return breakSealEdit(state, (draft) {
    draft.phase = BattlePhase.card;
    draft.ownTurns = {for (final color in PieceColor.values) color: 2};
    draft.mana = {for (final color in PieceColor.values) color: 6};
    draft.effectSequence = 100;
    draft.repetitions = {};
  });
}

AuthoritativeBattleState breakSealEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

BoardEffectInstance breakSealEffect(
  String id,
  BoardEffectType type,
  PieceColor owner,
  List<int> squares,
) => BoardEffectInstance(
  id: id,
  type: type,
  owner: owner,
  squares: squares,
  responseSide: owner.opposite,
  duration:
      type == BoardEffectType.mine
          ? EffectDuration.persistent
          : type == BoardEffectType.fog
          ? EffectDuration.card
          : EffectDuration.move,
);

AuthoritativeBattleState breakSealRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

void breakSealRequire(bool condition, String detail) {
  if (!condition) throw StateError('V223 Break Seal: $detail');
}

void breakSealEqual(Object? actual, Object? expected, String detail) {
  Object? jsonValue(Object? value) {
    if (value is Enum) return '${value.runtimeType}.${value.name}';
    if (value is Map) {
      return {
        for (final entry in value.entries)
          (entry.key is Enum
              ? '${entry.key.runtimeType}.${(entry.key as Enum).name}'
              : entry.key as String): jsonValue(entry.value),
      };
    }
    if (value is Iterable) return value.map(jsonValue).toList();
    return value;
  }

  breakSealRequire(
    jsonEncode(canonicalObject(jsonValue(actual))) ==
        jsonEncode(canonicalObject(jsonValue(expected))),
    '$detail; expected=$expected actual=$actual',
  );
}

List<String> breakSealTargets(
  AuthoritativeBattleState state,
  PieceColor side,
) =>
    BattleRulesCore.cardTargets(
        state.view(side),
        CardId.breakSeal,
      ).cast<String>().toList()
      ..sort();

List<String> _plays(AuthoritativeBattleState state, PieceColor side) =>
    BattleRulesCore.legalActions(state.view(side))
        .whereType<PlayCardAction>()
        .where((action) => action.card == CardId.breakSeal)
        .map((action) => action.target as String)
        .toList()
      ..sort();

List<String> breakSealMoves(AuthoritativeBattleState state, {String? from}) =>
    BattleRulesCore.legalMoves(state.rules, state.rules.board.turn)
        .map((move) => move.uci)
        .where((uci) => from == null || uci.startsWith(from))
        .toList()
      ..sort();

void breakSealRejects(AuthoritativeBattleState state, BattleAction action) {
  final before = jsonEncode(state.toJson());
  breakSealRequire(
    !BattleRulesCore.isLegalAction(state.view(state.rules.board.turn), action),
    'malformed action not legal',
  );
  for (final authority in [false, true]) {
    var rejected = false;
    try {
      if (authority) {
        DeckManager.apply(state, action);
      } else {
        BattleRulesCore.transition(state.view(state.rules.board.turn), action);
      }
    } on StateError catch (error) {
      rejected = error.message == 'illegal-action';
    }
    breakSealRequire(rejected, 'reject atomically as illegal-action');
    breakSealEqual(
      jsonEncode(state.toJson()),
      before,
      'no rejected-state mutation',
    );
  }
}

void breakSealInventory(AuthoritativeBattleState state) {
  for (final side in PieceColor.values) {
    final hand = state.hidden.hands[side]!, deck = state.hidden.decks[side]!;
    final inventory = [
      ...hand,
      ...deck,
      ...state.rules.used[side]!,
      ...state.rules.discarded[side]!,
    ];
    breakSealEqual(hand.length, state.rules.handCounts[side], 'public hand');
    breakSealEqual(deck.length, state.rules.deckCounts[side], 'public deck');
    breakSealEqual(inventory.length, 10, 'inventory conservation');
    breakSealEqual(inventory.toSet().length, 10, 'unique inventory');
    breakSealRequire(hand.length <= 4, 'hand cap');
    breakSealRequire(
      state.rules.mana[side]! >= 0 && state.rules.mana[side]! <= 6,
      'mana range',
    );
    BattleRulesCore.legalActions(state.view(side));
  }
  breakSealEqual(
    breakSealRoundTrip(state).toJson(),
    state.toJson(),
    'round trip',
  );
}

AuthoritativeBattleState breakSealStack(PieceColor side) {
  final landing = breakSealSquare(breakSealChoose(side, 'b3', 'b6'));
  final second = breakSealSquare(breakSealChoose(side, 'b4', 'b5'));
  final state = breakSealPosition(side);
  return breakSealEdit(state, (draft) {
    draft.effectSequence = 101;
    draft.boardEffects.addAll([
      breakSealEffect('e1', BoardEffectType.mine, side.opposite, [landing]),
      breakSealEffect('e10', BoardEffectType.lockedSquare, side.opposite, [
        landing,
      ]),
      breakSealEffect(
        'e100',
        BoardEffectType.boardSeal,
        side.opposite,
        [landing, landing + 1, second, second + 1]..sort(),
      ),
      breakSealEffect(
        'e101',
        BoardEffectType.fog,
        side.opposite,
        [landing, landing + 1, second, second + 1]..sort(),
      ),
      breakSealEffect('own-mine', BoardEffectType.mine, side, [
        breakSealSquare('d4'),
      ]),
    ]);
  });
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

void _transaction(
  AuthoritativeBattleState before,
  AuthoritativeBattleState after,
) {
  final side = before.rules.board.turn;
  breakSealEqual(
    after.rules.fen,
    before.rules.fen,
    'no board/counter movement',
  );
  breakSealEqual(after.rules.pieceIds, before.rules.pieceIds, 'piece identity');
  breakSealEqual(after.rules.mana[side], 5, 'literal base mana cost one');
  breakSealEqual(after.rules.mana[side.opposite], 6, 'enemy mana unchanged');
  breakSealEqual(after.rules.used[side], [CardId.breakSeal], 'one used card');
  breakSealEqual(after.rules.discarded[side], [], 'not a discard');
  breakSealEqual(after.hidden.hands[side], [
    CardId.chain,
    CardId.prophecy,
  ], 'selected card only removed from hidden hand');
  breakSealEqual(after.rules.handCounts[side], 2, 'hand count');
  breakSealEqual(
    after.rules.deckCounts,
    before.rules.deckCounts,
    'no early draw',
  );
  breakSealEqual(
    after.rules.drawCounts,
    before.rules.drawCounts,
    'no draw event',
  );
  breakSealEqual(after.rules.ply, before.rules.ply, 'no chess ply consumed');
  breakSealEqual(
    after.rules.ownTurns,
    before.rules.ownTurns,
    'no turn consumed',
  );
  breakSealEqual(
    after.rules.phase,
    BattlePhase.chess,
    'same-turn chess window',
  );
  breakSealEqual(after.rules.pending, null, 'no private resolution');
  breakSealEqual(after.rules.special, null, 'no special move');
  breakSealEqual(after.rules.terminal, null, 'no invented terminal');
  breakSealEqual(
    after.rules.effectSequence,
    before.rules.effectSequence,
    'removal allocates no new ID',
  );
  breakSealInventory(after);
}

class BreakSealAuditCase {
  final String name;
  final void Function() run;
  const BreakSealAuditCase(this.name, this.run);
}

class _IdImpersonator {
  @override
  String toString() => 'e1';
}

List<BreakSealAuditCase> breakSealAuditCases() {
  final cases = <BreakSealAuditCase>[];
  for (final side in PieceColor.values) {
    final enemy = side.opposite, tag = sideWire(side);
    String choose(String white, String black) =>
        breakSealChoose(side, white, black);
    final rook = choose('b2', 'b7'),
        landing = breakSealSquare(choose('b3', 'b6'));
    final fullRookMoves =
        side == PieceColor.white
            ? [
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
            ]
            : [
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
            ];

    for (final selected in ['e1', 'e10', 'e100', 'e101']) {
      cases.add(
        BreakSealAuditCase('$tag/overlap/$selected/24-orderings', () {
          final base = breakSealStack(side), frozen = jsonEncode(base.toJson());
          breakSealEqual(breakSealTargets(base, side), [
            'e1',
            'e10',
            'e100',
            'e101',
          ], 'all four enemy types, never own Mine');
          final expectedBefore =
              fullRookMoves
                  .where(
                    (uci) =>
                        uci != choose('b2b3', 'b7b6') &&
                        uci != choose('b2b4', 'b7b5'),
                  )
                  .toList()
                ..sort();
          breakSealEqual(
            breakSealMoves(base, from: rook),
            expectedBefore,
            'literal overlapping restriction moves',
          );
          for (final order in _orders(
            base.rules.boardEffects.take(4).toList(),
          )) {
            final state = breakSealEdit(base, (draft) {
              draft.boardEffects = [...order, base.rules.boardEffects.last];
            });
            final after = DeckManager.apply(
              breakSealRoundTrip(state),
              PlayCardAction(CardId.breakSeal, target: selected),
            );
            final keep = [
              ...order.where(
                (effect) => effect.id != selected && effect.id != 'e101',
              ),
              base.rules.boardEffects.last,
            ];
            breakSealEqual(
              after.rules.boardEffects.map((e) => e.toJson()).toList(),
              keep.map((e) => e.toJson()).toList(),
              'selected ID removed; other records byte-equivalent; Fog naturally expires',
            );
            final expectedAfter =
                fullRookMoves
                    .where(
                      (uci) =>
                          uci != choose('b2b3', 'b7b6') &&
                          (selected == 'e100' || uci != choose('b2b4', 'b7b5')),
                    )
                    .toList()
                  ..sort();
            breakSealEqual(
              breakSealMoves(after, from: rook),
              expectedAfter,
              'literal released moves, no removal through shared square or ID prefix',
            );
            _transaction(state, after);
            breakSealRejects(
              after,
              PlayCardAction(CardId.breakSeal, target: selected),
            );
            final moved = DeckManager.apply(
              after,
              ChessMoveAction(choose('b2a2', 'b7a7')),
            );
            breakSealEqual(moved.rules.boardEffects.map((e) => e.id).toList(), [
              if (selected != 'e1') 'e1',
              'own-mine',
            ], 'move effects expire, Mines persist');
            breakSealEqual(
              moved.rules.board.turn,
              enemy,
              'enemy response window',
            );
            breakSealEqual(
              moved.rules.phase,
              BattlePhase.card,
              'enemy card phase',
            );
            breakSealEqual(
              moved.rules.drawCounts[side],
              4,
              'one chess-stage draw',
            );
            breakSealEqual(
              moved.rules.deckCounts[side],
              6,
              'deck advances once',
            );
            breakSealEqual(
              moved.rules.handCounts[side],
              3,
              'one draw after spend',
            );
            breakSealRequire(
              BattleRulesCore.legalActions(moved.view(enemy)).isNotEmpty,
              'enemy has a usable response',
            );
            breakSealInventory(moved);
          }
          breakSealEqual(
            jsonEncode(base.toJson()),
            frozen,
            'shared base immutable',
          );
        }),
      );
    }

    for (final type in BoardEffectType.values) {
      for (final occupancy in ['empty', 'own-king', 'enemy-king', 'own-rook']) {
        cases.add(
          BreakSealAuditCase('$tag/${type.name}/owner-not-$occupancy', () {
            final text = switch (occupancy) {
              'own-king' => choose('f1', 'f8'),
              'enemy-king' => choose('g8', 'g1'),
              'own-rook' => rook,
              _ => choose('d3', 'd6'),
            };
            final square = breakSealSquare(text);
            final anchor = square >= 56 ? square - 8 : square;
            // Occupied squares model effects surviving entry, not new placement.
            final squares =
                type == BoardEffectType.fog || type == BoardEffectType.boardSeal
                    ? [anchor, anchor + 1, anchor + 8, anchor + 9]
                    : [square];
            var state = breakSealPosition(side);
            state = breakSealEdit(state, (draft) {
              draft.boardEffects.addAll([
                breakSealEffect('enemy', type, enemy, squares),
                breakSealEffect('own', type, side, squares),
              ]);
            });
            breakSealEqual(breakSealTargets(state, side), [
              'enemy',
            ], 'effect owner decides; occupancy and king immunity do not');
            breakSealRejects(
              state,
              const PlayCardAction(CardId.breakSeal, target: 'own'),
            );
            breakSealRejects(
              state,
              PlayCardAction(CardId.breakSeal, target: square),
            );
            final after = DeckManager.apply(
              state,
              const PlayCardAction(CardId.breakSeal, target: 'enemy'),
            );
            breakSealEqual(
              after.rules.boardEffects.map((e) => e.toJson()).toList(),
              [state.rules.boardEffects.last.toJson()],
              'entire own effect preserved',
            );
            breakSealEqual(
              after.rules.fen,
              state.rules.fen,
              'no king or piece removed',
            );
            _transaction(state, after);
          }),
        );
      }
    }

    for (final type in [BoardEffectType.fog, BoardEffectType.boardSeal]) {
      for (var rank = 0; rank < 7; rank++) {
        for (var file = 0; file < 7; file++) {
          final anchor = rank * 8 + file;
          cases.add(
            BreakSealAuditCase('$tag/${type.name}/whole-zone/$anchor', () {
              final zone = [anchor, anchor + 1, anchor + 8, anchor + 9];
              final state = breakSealEdit(breakSealPosition(side), (draft) {
                draft.boardEffects.add(
                  breakSealEffect('zone', type, enemy, zone),
                );
                draft.boardEffects.add(
                  breakSealEffect('keeper', BoardEffectType.mine, side, [
                    zone.last,
                  ]),
                );
              });
              final after = DeckManager.apply(
                state,
                const PlayCardAction(CardId.breakSeal, target: 'zone'),
              );
              breakSealEqual(
                after.rules.boardEffects.map((e) => e.toJson()).toList(),
                [state.rules.boardEffects.last.toJson()],
                'four-square instance removed once',
              );
              breakSealEqual(
                after.rules.fen,
                state.rules.fen,
                'zone occupants unchanged',
              );
              breakSealInventory(after);
            }),
          );
        }
      }
    }

    cases.add(
      BreakSealAuditCase('$tag/malformed-targets-and-sacrifice', () {
        final state = breakSealStack(side);
        final invalid = <Object?>[
          null,
          false,
          true,
          0,
          -1,
          64,
          landing,
          landing.toDouble(),
          <Object?>[],
          ['e1'],
          <String, Object?>{'id': 'e1'},
          '',
          'e0',
          'e01',
          'E1',
          ' e1',
          'e1 ',
          'e1\u0000',
          'e1:e10',
          'missing',
          'b3',
          'own-mine',
          state.rules.pieceIds[breakSealSquare(rook)],
          List.filled(81, 'x').join(),
          _IdImpersonator(),
        ];
        for (final target in invalid) {
          breakSealRejects(
            state,
            PlayCardAction(CardId.breakSeal, target: target),
          );
          if (target is! _IdImpersonator) {
            breakSealRejects(
              state,
              BattleAction.fromJson({
                'type': 'play',
                'card': 'break_seal',
                'target': target,
              }),
            );
          }
        }
        for (final sacrifice in [CardId.breakSeal, CardId.chain, CardId.mine]) {
          breakSealRejects(
            state,
            PlayCardAction(
              CardId.breakSeal,
              target: 'e1',
              sacrifice: sacrifice,
            ),
          );
        }
        breakSealRejects(state, ResolveAction([]));
      }),
    );

    for (final gate in [
      'no-mana',
      'first-turn',
      'chess',
      'terminal',
      'card-block',
      'absent-hand',
    ]) {
      cases.add(
        BreakSealAuditCase('$tag/admission/$gate', () {
          var state =
              gate == 'absent-hand'
                  ? breakSealPosition(
                    side,
                    hand: [CardId.mine, CardId.chain, CardId.prophecy],
                  )
                  : breakSealPosition(side);
          state = breakSealEdit(state, (draft) {
            draft.boardEffects.add(
              breakSealEffect('target', BoardEffectType.mine, enemy, [landing]),
            );
            switch (gate) {
              case 'no-mana':
                draft.mana[side] = 0;
              case 'first-turn':
                draft.ownTurns[side] = 1;
              case 'chess':
                draft.phase = BattlePhase.chess;
              case 'terminal':
                draft.phase = BattlePhase.terminal;
                draft.terminal = TerminalState('timeout', winner: enemy);
              case 'card-block':
                draft.modifiers.add(
                  PendingModifier(
                    id: 'block',
                    type: ModifierType.cardBlock,
                    owner: enemy,
                    responseSide: side,
                    targetCard: CardId.breakSeal,
                    ownTurn: 2,
                  ),
                );
            }
          });
          breakSealEqual(_plays(state, side), [], 'no admitted cast');
          breakSealRejects(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'target'),
          );
        }),
      );
    }

    cases.add(
      BreakSealAuditCase('$tag/piece-effects-are-not-board-effects', () {
        final state = breakSealEdit(breakSealStack(side), (draft) {
          for (final type in PieceEffectType.values) {
            draft.pieceEffects.add(
              ActivePieceEffect(
                id: 'piece-${type.name}',
                type: type,
                owner: type == PieceEffectType.shelter ? side : enemy,
                pieceId: draft.pieceIds[breakSealSquare(rook)]!,
                responseSide: type == PieceEffectType.shelter ? enemy : side,
                duration:
                    type == PieceEffectType.shelter
                        ? EffectDuration.card
                        : type == PieceEffectType.mineDebuff
                        ? EffectDuration.pieceMove
                        : EffectDuration.move,
              ),
            );
          }
        });
        for (final effect in state.rules.pieceEffects) {
          breakSealRejects(
            state,
            PlayCardAction(CardId.breakSeal, target: effect.id),
          );
        }
        final after = DeckManager.apply(
          state,
          const PlayCardAction(CardId.breakSeal, target: 'e1'),
        );
        breakSealEqual(
          after.rules.pieceEffects.map((e) => e.toJson()).toList(),
          state.rules.pieceEffects.map((e) => e.toJson()).toList(),
          'Freeze, Chain, Slow, Shelter and triggered Mine remain',
        );
        breakSealEqual(
          breakSealMoves(after, from: rook),
          [],
          'Break Seal does not purify Freeze',
        );
        breakSealRequire(
          BattleRulesCore.legalActions(
            after.view(side),
          ).whereType<ChessMoveAction>().isNotEmpty,
          'king still moves; no stranded phase',
        );
      }),
    );

    for (final selected in [true, false]) {
      cases.add(
        BreakSealAuditCase('$tag/mine-trigger-after-removal=$selected', () {
          final state = breakSealEdit(breakSealPosition(side), (draft) {
            draft.boardEffects.add(
              breakSealEffect('mine', BoardEffectType.mine, enemy, [landing]),
            );
          });
          final afterCard = DeckManager.apply(
            state,
            selected
                ? const PlayCardAction(CardId.breakSeal, target: 'mine')
                : const PassAction(),
          );
          final moved = DeckManager.apply(
            afterCard,
            ChessMoveAction(choose('b2b3', 'b7b6')),
          );
          breakSealEqual(
            moved.rules.boardEffects,
            [],
            'removed or triggered board Mine gone',
          );
          breakSealEqual(
            moved.rules.pieceEffects.map((e) => e.type).toList(),
            selected ? [] : [PieceEffectType.mineDebuff],
            'only unremoved Mine triggers',
          );
          breakSealEqual(
            moved.rules.board.pieceAt(landing)?.color,
            side,
            'arriving rook survives',
          );
          breakSealInventory(moved);
        }),
      );
    }

    cases.add(
      BreakSealAuditCase(
        '$tag/king-entry-does-not-trigger-unselected-mine',
        () {
          final kingLanding = breakSealSquare(choose('f2', 'f7'));
          final state = breakSealEdit(breakSealPosition(side), (draft) {
            draft.boardEffects.addAll([
              breakSealEffect('mine', BoardEffectType.mine, enemy, [
                kingLanding,
              ]),
              breakSealEffect('selected', BoardEffectType.lockedSquare, enemy, [
                landing,
              ]),
            ]);
          });
          final after = DeckManager.apply(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'selected'),
          );
          final moved = DeckManager.apply(
            after,
            ChessMoveAction(choose('f1f2', 'f8f7')),
          );
          breakSealEqual(moved.rules.boardEffects.map((e) => e.id).toList(), [
            'mine',
          ], 'unselected persistent Mine survives king entry');
          breakSealEqual(moved.rules.pieceEffects, [], 'no king debuff');
          breakSealEqual(
            moved.rules.board.pieceAt(kingLanding)?.color,
            side,
            'king survives',
          );
          breakSealInventory(moved);
        },
      ),
    );

    for (final type in [
      BoardEffectType.lockedSquare,
      BoardEffectType.boardSeal,
    ]) {
      cases.add(
        BreakSealAuditCase('$tag/${type.name}/capture-and-king-immunity', () {
          final capture = breakSealSquare(choose('b5', 'b4'));
          final kingLanding = breakSealSquare(choose('f2', 'f7'));
          final state = breakSealEdit(breakSealPosition(side), (draft) {
            final captureAnchor = capture >= 56 ? capture - 8 : capture;
            draft.boardEffects.addAll([
              breakSealEffect(
                'selected',
                type,
                enemy,
                type == BoardEffectType.boardSeal
                    ? [
                      captureAnchor,
                      captureAnchor + 1,
                      captureAnchor + 8,
                      captureAnchor + 9,
                    ]
                    : [capture],
              ),
              breakSealEffect(
                'king-zone',
                BoardEffectType.lockedSquare,
                enemy,
                [kingLanding],
              ),
            ]);
          });
          final captureMove = choose('b2b5', 'b7b4'),
              kingMove = choose('f1f2', 'f8f7');
          breakSealRequire(
            breakSealMoves(state).contains(captureMove),
            'occupied-square capture already legal before removal',
          );
          breakSealRequire(
            breakSealMoves(state).contains(kingMove),
            'king already ignores unselected landing restriction',
          );
          final after = DeckManager.apply(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'selected'),
          );
          breakSealRequire(
            breakSealMoves(after).contains(captureMove),
            'capture remains legal',
          );
          breakSealRequire(
            breakSealMoves(after).contains(kingMove),
            'king remains legal',
          );
          final moved = DeckManager.apply(after, ChessMoveAction(captureMove));
          breakSealEqual(
            moved.rules.board.pieceAt(capture)?.color,
            side,
            'ordinary capture executes',
          );
          breakSealEqual(
            moved.rules.pieceEffects,
            [],
            'removal invents no piece status',
          );
          breakSealInventory(moved);
        }),
      );
    }

    for (final selected in ['mine', 'lock', 'fog', 'seal']) {
      cases.add(
        BreakSealAuditCase('$tag/sole-king-exit/$selected', () {
          final destination = breakSealSquare(choose('a2', 'a7'));
          final zone = [
            destination,
            destination + 1,
            destination + 8,
            destination + 9,
          ];
          final state = breakSealEdit(
            breakSealPosition(
              side,
              fen: choose(
                '8/8/8/8/8/1rk5/8/K7 w - - 0 1',
                'k7/8/1RK5/8/8/8/8/8 b - - 0 1',
              ),
            ),
            (draft) {
              draft.boardEffects.addAll([
                breakSealEffect('mine', BoardEffectType.mine, enemy, [
                  destination,
                ]),
                breakSealEffect('lock', BoardEffectType.lockedSquare, enemy, [
                  destination,
                ]),
                breakSealEffect('fog', BoardEffectType.fog, enemy, zone),
                breakSealEffect('seal', BoardEffectType.boardSeal, enemy, zone),
              ]);
            },
          );
          final onlyMove = choose('a1a2', 'a8a7');
          breakSealEqual(breakSealMoves(state), [
            onlyMove,
          ], 'literal sole king exit ignores every board landing restriction');
          final after = DeckManager.apply(
            state,
            PlayCardAction(CardId.breakSeal, target: selected),
          );
          breakSealEqual(
            BattleRulesCore.legalActions(
              after.view(side),
            ).whereType<ChessMoveAction>().map((move) => move.uci).toList(),
            [onlyMove],
            'removal leaves a usable, exact one-move chess phase',
          );
          final moved = DeckManager.apply(after, ChessMoveAction(onlyMove));
          breakSealEqual(
            moved.rules.boardEffects.map((e) => e.id).toList(),
            selected == 'mine' ? [] : ['mine'],
            'king entry never triggers remaining Mine',
          );
          breakSealEqual(moved.rules.pieceEffects, [], 'no king debuff');
          breakSealEqual(
            moved.rules.terminal,
            null,
            'response side is not falsely terminal',
          );
          breakSealInventory(moved);
        }),
      );
    }

    cases.add(
      BreakSealAuditCase(
        '$tag/fog-protection-is-not-protection-from-removal',
        () {
          final enemyPawn = breakSealSquare(choose('b5', 'b4'));
          final anchor = breakSealSquare(choose('a4', 'a3'));
          final state = breakSealEdit(breakSealPosition(side), (draft) {
            draft.boardEffects.add(
              breakSealEffect('fog', BoardEffectType.fog, enemy, [
                anchor,
                anchor + 1,
                anchor + 8,
                anchor + 9,
              ]),
            );
            draft.pieceEffects.add(
              ActivePieceEffect(
                id: 'shelter',
                type: PieceEffectType.shelter,
                owner: enemy,
                pieceId: draft.pieceIds[enemyPawn]!,
                responseSide: side,
                duration: EffectDuration.card,
              ),
            );
          });
          breakSealEqual(
            BattleRulesCore.cardTargets(state.view(side), CardId.chain),
            [],
            'enemy pawn is protected from a direct card',
          );
          breakSealEqual(_plays(state, side), [
            'fog',
          ], 'board removal bypasses direct-piece protection');
          final after = DeckManager.apply(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'fog'),
          );
          breakSealEqual(after.rules.boardEffects, [], 'Fog instance removed');
          breakSealEqual(
            after.rules.pieceEffects,
            [],
            'Shelter naturally expires on same card close',
          );
          breakSealEqual(
            BattleRulesCore.cardTargets(after.view(side), CardId.chain),
            [enemyPawn],
            'target enumeration reflects protection expiry, not permission for second cast',
          );
          breakSealEqual(
            _plays(after, side),
            [],
            'no second card in chess phase',
          );
          _transaction(state, after);
        },
      ),
    );

    for (final modifier in [
      ModifierType.manaSabotage,
      ModifierType.discount,
      ModifierType.echo,
    ]) {
      cases.add(
        BreakSealAuditCase('$tag/modifier/${modifier.name}', () {
          final state = breakSealEdit(breakSealPosition(side), (draft) {
            draft.boardEffects.add(
              breakSealEffect('target', BoardEffectType.mine, enemy, [landing]),
            );
            draft.mana[enemy] = 3;
            draft.modifiers.add(
              PendingModifier(
                id: 'modifier',
                type: modifier,
                owner: modifier == ModifierType.discount ? side : enemy,
                responseSide: side,
                targetCard:
                    modifier == ModifierType.discount ? null : CardId.breakSeal,
                ownTurn: 2,
              ),
            );
          });
          if (modifier == ModifierType.manaSabotage) {
            final insufficient = breakSealEdit(
              state,
              (draft) => draft.mana[side] = 1,
            );
            breakSealRejects(
              insufficient,
              const PlayCardAction(CardId.breakSeal, target: 'target'),
            );
          }
          final after = DeckManager.apply(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'target'),
          );
          breakSealEqual(
            after.rules.mana[side],
            modifier == ModifierType.manaSabotage ? 4 : 5,
            'literal cost: sabotage two, discounted floor one',
          );
          breakSealEqual(
            after.rules.mana[enemy],
            modifier == ModifierType.echo ? 5 : 3,
            'Echo rewards owner exactly once',
          );
          breakSealEqual(
            after.rules.boardEffects,
            [],
            'modifier does not alter selected removal',
          );
          breakSealEqual(
            after.rules.modifiers,
            [],
            'response modifier consumed normally',
          );
          breakSealRejects(
            after,
            const PlayCardAction(CardId.breakSeal, target: 'target'),
          );
          breakSealInventory(after);
        }),
      );
    }

    cases.add(
      BreakSealAuditCase('$tag/no-enemy-board-target-remains-playable', () {
        final state = breakSealEdit(breakSealPosition(side), (draft) {
          draft.boardEffects.add(
            breakSealEffect('own', BoardEffectType.mine, side, [landing]),
          );
        });
        breakSealEqual(
          breakSealTargets(state, side),
          [],
          'own-only board has no removal target',
        );
        breakSealEqual(_plays(state, side), [], 'no empty-target Break Seal');
        for (final action in <BattleAction>[
          const PassAction(),
          const DiscardAction(CardId.breakSeal),
        ]) {
          final after = DeckManager.apply(state, action);
          breakSealEqual(
            after.rules.boardEffects.single.id,
            'own',
            'pass/discard removes no Mine',
          );
          breakSealRequire(
            BattleRulesCore.legalActions(
              after.view(side),
            ).whereType<ChessMoveAction>().isNotEmpty,
            'fallback closes to a usable chess turn',
          );
          breakSealInventory(after);
        }
      }),
    );

    for (final type in BoardEffectType.values) {
      cases.add(
        BreakSealAuditCase('$tag/${type.name}/real-create-response-remove', () {
          final card = switch (type) {
            BoardEffectType.mine => CardId.mine,
            BoardEffectType.lockedSquare => CardId.lockedSquare,
            BoardEffectType.fog => CardId.fog,
            BoardEffectType.boardSeal => CardId.boardSeal,
          };
          var state = breakSealPosition(
            side,
            hand: [card, CardId.breakSeal, CardId.chain],
          );
          state = DeckManager.apply(
            state,
            PlayCardAction(card, target: breakSealSquare('d4')),
          );
          breakSealEqual(
            state.rules.boardEffects.single.id,
            'e101',
            'real monotonic ID',
          );
          state = DeckManager.apply(
            state,
            ChessMoveAction(choose('f1e1', 'f8e8')),
          );
          breakSealEqual(
            state.rules.phase,
            BattlePhase.card,
            'opponent response begins',
          );
          breakSealEqual(_plays(state, enemy), [
            'e101',
          ], 'effect targetable in response');
          state = breakSealRoundTrip(state);
          state = DeckManager.apply(
            state,
            const PlayCardAction(CardId.breakSeal, target: 'e101'),
          );
          breakSealEqual(
            state.rules.boardEffects,
            [],
            'selected effect removed',
          );
          breakSealEqual(
            state.rules.board.turn,
            enemy,
            'removal does not skip response chess',
          );
          state = DeckManager.apply(
            state,
            ChessMoveAction(choose('g8h8', 'g1h1')),
          );
          breakSealEqual(
            state.rules.board.turn,
            side,
            'original actor receives next turn',
          );
          breakSealEqual(
            state.rules.boardEffects,
            [],
            'removed instance does not resurrect',
          );
          breakSealInventory(state);
        }),
      );
      for (final discard in [false, true]) {
        cases.add(
          BreakSealAuditCase(
            '$tag/${type.name}/natural-response/discard=$discard',
            () {
              final card = switch (type) {
                BoardEffectType.mine => CardId.mine,
                BoardEffectType.lockedSquare => CardId.lockedSquare,
                BoardEffectType.fog => CardId.fog,
                BoardEffectType.boardSeal => CardId.boardSeal,
              };
              var state = breakSealPosition(
                side,
                hand: [card, CardId.breakSeal, CardId.chain],
              );
              state = DeckManager.apply(
                state,
                PlayCardAction(card, target: breakSealSquare('d4')),
              );
              state = DeckManager.apply(
                state,
                ChessMoveAction(choose('f1e1', 'f8e8')),
              );
              state = DeckManager.apply(
                state,
                discard
                    ? const DiscardAction(CardId.chain)
                    : const PassAction(),
              );
              breakSealEqual(
                state.rules.boardEffects.map((e) => e.id).toList(),
                type == BoardEffectType.fog ? [] : ['e101'],
                'card-response expiry boundary',
              );
              breakSealRequire(
                state.hidden.hands[enemy]!.contains(CardId.breakSeal),
                'control did not spend Break Seal',
              );
              state = DeckManager.apply(
                state,
                ChessMoveAction(choose('g8h8', 'g1h1')),
              );
              breakSealEqual(
                state.rules.boardEffects.map((e) => e.id).toList(),
                type == BoardEffectType.mine ? ['e101'] : [],
                'move expiry versus persistence',
              );
              breakSealEqual(
                state.rules.pieceEffects,
                [],
                'remote Mine did not trigger',
              );
              breakSealInventory(state);
            },
          ),
        );
      }
    }
  }
  return cases;
}
