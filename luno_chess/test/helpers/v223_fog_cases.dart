import 'dart:convert';

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';

class FogAuditCase {
  final String name;
  final void Function() run;
  const FogAuditCase(this.name, this.run);
}

void fogCheck(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Object? _jsonValue(Object? value) {
  if (value is Enum) return value.name;
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    final converted = {
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
    return {for (final key in keys) key: _jsonValue(converted[key])};
  }
  if (value is Iterable) return value.map(_jsonValue).toList();
  return value;
}

String fogCanonical(Object? value) => jsonEncode(_jsonValue(value));

void fogEqual(Object? actual, Object? expected, String message) {
  fogCheck(
    fogCanonical(actual) == fogCanonical(expected),
    '$message: actual=$actual expected=$expected',
  );
}

int fogSquare(String text, [PieceColor side = PieceColor.white]) {
  final square = text.codeUnitAt(0) - 97 + 8 * (int.parse(text[1]) - 1);
  return side.isWhite ? square : square ^ 56;
}

String _squareText(int square) =>
    '${String.fromCharCode(97 + square % 8)}${square ~/ 8 + 1}';

String fogMove(String uci, PieceColor side) =>
    '${_squareText(fogSquare(uci.substring(0, 2), side))}'
    '${_squareText(fogSquare(uci.substring(2, 4), side))}${uci.substring(4)}';

// Independent coordinate oracle: never call production boardZone here.
List<int> fogExpectedZone(String whiteAnchor, PieceColor side) {
  final file = whiteAnchor.codeUnitAt(0) - 97;
  final rank = int.parse(whiteAnchor[1]) - 1;
  return [
    for (var row = rank; row < rank + 2; row++)
      for (var column = file; column < file + 2; column++)
        side.isWhite ? row * 8 + column : (7 - row) * 8 + column,
  ]..sort();
}

int fogAnchor(String whiteAnchor, PieceColor side) =>
    fogExpectedZone(whiteAnchor, side).first;

AuthoritativeBattleState fogScenario({
  PieceColor side = PieceColor.white,
  String fen = '7k/8/8/8/3R4/8/8/K7 w - - 0 12',
  List<CardId> ownHand = const [CardId.fog, CardId.purify, CardId.radar],
  List<CardId> enemyHand = const [
    CardId.chain,
    CardId.slow,
    CardId.freeze,
    CardId.huntVow,
  ],
  BattlePhase phase = BattlePhase.card,
  int mana = 6,
}) {
  fogCheck(ownHand.length <= 4 && enemyHand.length <= 4, 'fixture hand cap');
  final source = Board.fromFen(fen);
  final board =
      side.isWhite
          ? source
          : Board(
            squares: [
              for (var i = 0; i < 64; i++)
                source.squares[i ^ 56]?.copyWith(
                  color: source.squares[i ^ 56]!.color.opposite,
                ),
            ],
            turn: source.turn.opposite,
            castling:
                ((source.castling & 3) << 2) | ((source.castling & 12) >> 2),
            enPassant: source.enPassant == null ? null : source.enPassant! ^ 56,
            halfmoveClock: source.halfmoveClock,
            fullmoveNumber: source.fullmoveNumber,
          );
  final hands = {side: ownHand, side.opposite: enemyHand};
  final orders = {
    for (final color in PieceColor.values)
      color: [
        ...hands[color]!,
        ...CardId.values
            .where((card) => !hands[color]!.contains(card))
            .take(10 - hands[color]!.length),
      ],
  };
  final initial = DeckManager.newBattle(
    board: board,
    white: orders[PieceColor.white]!,
    black: orders[PieceColor.black]!,
  );
  fogCheck(
    initial.rules.terminal == null,
    'fixture must not start terminal: $fen',
  );
  fogCheck(
    !MoveGen.inCheck(board, board.turn.opposite),
    'fixture nonmoving king must not already be in check: $fen',
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = phase
        ..effectSequence = 100
        ..repetitions.clear();
  for (final color in PieceColor.values) {
    draft.ownTurns[color] = 3;
    draft.mana[color] = color == side ? mana : 6;
    draft.handCounts[color] = hands[color]!.length;
    draft.deckCounts[color] = 10 - hands[color]!.length;
    draft.drawCounts[color] = hands[color]!.length;
  }
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: hands,
      decks: {
        for (final color in PieceColor.values)
          color: orders[color]!.skip(hands[color]!.length).toList(),
      },
      knowledge: {
        for (final color in PieceColor.values) color: PlayerKnowledgeState(),
      },
    ),
  );
}

AuthoritativeBattleState fogEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState fogRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

AuthoritativeBattleState fogInject(
  AuthoritativeBattleState state,
  PieceColor owner,
  List<int> squares, {
  String id = 'fixture-fog',
}) => fogEdit(
  state,
  (draft) => draft.boardEffects.add(
    BoardEffectInstance(
      id: id,
      type: BoardEffectType.fog,
      owner: owner,
      squares: squares,
      responseSide: owner.opposite,
      duration: EffectDuration.card,
    ),
  ),
);

List<BoardEffectInstance> fogEffects(AuthoritativeBattleState state) =>
    state.rules.boardEffects
        .where((effect) => effect.type == BoardEffectType.fog)
        .toList();

AuthoritativeBattleState fogApply(
  AuthoritativeBattleState state,
  BattleAction action,
) {
  final before = fogCanonical(state.toJson());
  final result = DeckManager.apply(state, action);
  fogEqual(
    state.toJson(),
    jsonDecode(before),
    'accepted action mutated its input',
  );
  for (final color in PieceColor.values) {
    fogEqual(
      result.rules.handCounts[color],
      result.hidden.hands[color]!.length,
      'public/private hand count',
    );
    fogEqual(
      result.rules.deckCounts[color],
      result.hidden.decks[color]!.length,
      'public/private deck count',
    );
    fogCheck(
      result.hidden.hands[color]!.toSet().length ==
          result.hidden.hands[color]!.length,
      'unique hidden hand',
    );
  }
  fogCheck(
    result.rules.boardEffects.map((effect) => effect.id).toSet().length ==
        result.rules.boardEffects.length,
    'unique board effect ids',
  );
  if (result.rules.phase != BattlePhase.terminal) {
    fogCheck(
      BattleRulesCore.legalActions(
        result.view(result.rules.board.turn),
      ).isNotEmpty,
      'accepted action stranded a nonterminal turn',
    );
  }
  return result;
}

void fogReject(AuthoritativeBattleState state, BattleAction action) {
  final before = fogCanonical(state.toJson());
  final view = state.view(state.rules.board.turn);
  fogCheck(
    !BattleRulesCore.isLegalAction(view, action),
    'illegal action advertised as legal',
  );
  for (final attempt in <void Function()>[
    () {
      BattleRulesCore.transition(view, action);
    },
    () {
      DeckManager.apply(state, action);
    },
  ]) {
    var rejected = false;
    try {
      attempt();
    } on StateError catch (error) {
      fogEqual(error.message, 'illegal-action', 'precise action rejection');
      rejected = true;
    }
    fogCheck(rejected, 'action was not rejected');
    fogEqual(
      state.toJson(),
      jsonDecode(before),
      'rejection changed rules or hidden state',
    );
  }
}

AuthoritativeBattleState fogCast(
  AuthoritativeBattleState state,
  PieceColor side, {
  String anchor = 'd4',
}) => fogApply(
  state,
  PlayCardAction(CardId.fog, target: fogAnchor(anchor, side)),
);

AuthoritativeBattleState fogOpponentWindow(
  PieceColor side, {
  List<CardId> enemyHand = const [CardId.chain, CardId.prophecy, CardId.radar],
}) {
  final state = fogScenario(
    side: side,
    fen: '7k/7r/8/8/3R4/8/2N5/K7 w - - 0 12',
    enemyHand: enemyHand,
  );
  return fogApply(fogCast(state, side), ChessMoveAction(fogMove('a1a2', side)));
}

AuthoritativeBattleState fogWithDeckSize(
  AuthoritativeBattleState state,
  PieceColor side,
  int count,
) {
  final original = state.hidden.decks[side]!;
  fogCheck(count >= 1 && count <= original.length, 'fixture deck size');
  final draft =
      RuleDraft(state.rules)
        ..deckCounts[side] = count
        ..drawCounts[side] = 10 - count;
  draft.discarded[side]!.addAll(original.skip(count));
  draft.discarded[side]!.sort((a, b) => a.wire.compareTo(b.wire));
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: state.hidden.hands,
      decks: {...state.hidden.decks, side: original.take(count).toList()},
      knowledge: state.hidden.knowledge,
    ),
  );
}

List<List<T>> _orders<T>(List<T> cards) {
  if (cards.isEmpty) return [[]];
  return [
    for (var i = 0; i < cards.length; i++)
      for (final rest in _orders([
        for (var j = 0; j < cards.length; j++)
          if (i != j) cards[j],
      ]))
        [cards[i], ...rest],
  ];
}

Iterable<FogAuditCase> fogAuditCases() sync* {
  yield FogAuditCase('definition-is-literal-v1-contract', () {
    final definition = cardDefinitions[CardId.fog]!;
    fogEqual(definition.toJson(), {
      'id': 'fog',
      'cost': 3,
      'rarity': 'rare',
      'category': 'protection',
      'target': 'zone',
    }, 'Fog definition');
  });

  for (final side in PieceColor.values) {
    final tag = side.name;
    yield FogAuditCase('$tag/all-49-anchors-advertised-exactly-once', () {
      final state = fogScenario(side: side);
      final expected = [
        for (var rank = 0; rank < 7; rank++)
          for (var file = 0; file < 7; file++) rank * 8 + file,
      ];
      final advertised =
          BattleRulesCore.legalActions(state.view(side))
              .whereType<PlayCardAction>()
              .where((action) => action.card == CardId.fog)
              .map((action) => action.target as int)
              .toList()
            ..sort();
      fogEqual(
        advertised,
        expected,
        '49 legal anchors without wrapping or duplicates',
      );
    });

    for (var rank = 0; rank < 7; rank++) {
      for (var file = 0; file < 7; file++) {
        final anchor = rank * 8 + file;
        yield FogAuditCase('$tag/geometry/anchor-$anchor', () {
          final state = fogScenario(side: side);
          final after = fogApply(
            state,
            PlayCardAction(CardId.fog, target: anchor),
          );
          final effect = fogEffects(after).single;
          fogEqual(effect.toJson(), {
            'id': 'e101',
            'type': 'fog',
            'owner': sideWire(side),
            'squares': [
              for (var row = rank; row <= rank + 1; row++)
                for (var column = file; column <= file + 1; column++)
                  row * 8 + column,
            ],
            'responseSide': sideWire(side.opposite),
            'duration': 'card',
          }, 'exact public zone contract');
          fogEqual(
            after.rules.fen,
            state.rules.fen,
            'casting does not move pieces',
          );
          fogEqual(
            after.rules.pieceIds,
            state.rules.pieceIds,
            'casting preserves identities',
          );
          fogEqual(after.rules.ply, state.rules.ply, 'no extra ply');
          fogEqual(
            after.rules.ownTurns,
            state.rules.ownTurns,
            'no turn advance',
          );
          fogEqual(after.rules.mana[side], 3, 'literal three mana cost');
          fogEqual(
            after.rules.mana[side.opposite],
            6,
            'opponent mana unchanged',
          );
          fogEqual(after.rules.phase, BattlePhase.chess, 'one card then chess');
          fogEqual(after.rules.used[side], [CardId.fog], 'Fog consumed once');
          fogEqual(after.hidden.hands[side], [
            CardId.purify,
            CardId.radar,
          ], 'only Fog leaves hand');
          fogEqual(
            after.hidden.decks,
            state.hidden.decks,
            'cast does not draw',
          );
          fogEqual(
            after.hidden.knowledge[side]!.toJson(),
            state.hidden.knowledge[side]!.toJson(),
            'Fog has no private choice or concealment',
          );
          fogEqual(
            fogRoundTrip(after).toJson(),
            after.toJson(),
            'authority wire round trip',
          );
          for (final viewer in PieceColor.values) {
            fogEqual(
              after.view(viewer).rules.boardEffects.single.toJson(),
              effect.toJson(),
              'zone is public to both colors',
            );
          }
          fogReject(after, PlayCardAction(CardId.fog, target: anchor));
        });
      }
    }

    yield FogAuditCase('$tag/malformed-and-wrapping-anchors-are-atomic', () {
      final state = fogScenario(side: side);
      final invalid = <Object?>[
        -1,
        -64,
        64,
        65,
        999999,
        for (var rank = 0; rank < 8; rank++) rank * 8 + 7,
        for (var file = 0; file < 7; file++) 56 + file,
        null,
        true,
        false,
        27.5,
        double.nan,
        double.infinity,
        -double.infinity,
        '27',
        'd4',
        '',
        <int>[27],
        <String, Object?>{'square': 27},
      ];
      for (final target in invalid) {
        fogReject(state, PlayCardAction(CardId.fog, target: target));
        fogReject(
          state,
          BattleAction.fromJson({
            'type': 'play',
            'card': 'fog',
            'target': target,
          }),
        );
      }
      fogReject(state, const PlayCardAction(CardId.fog, target: 27.0));
      fogReject(
        state,
        PlayCardAction(
          CardId.fog,
          target: fogAnchor('d4', side),
          sacrifice: CardId.radar,
        ),
      );
      fogCheck(
        BattleRulesCore.isLegalAction(state.view(side), const PassAction()),
        'bad attempts leave pass available',
      );
      final anchor = fogAnchor('d4', side);
      final expected = fogCast(state, side).toJson();
      for (final number in ['$anchor', '$anchor.0', '${anchor}e0']) {
        final parsed = BattleAction.fromJson(
          jsonDecode('{"type":"play","card":"fog","target":$number}') as Map,
        );
        fogCheck(
          (parsed as PlayCardAction).target is int,
          'whole JSON number normalizes to an integer anchor',
        );
        fogEqual(
          fogApply(state, parsed).toJson(),
          expected,
          'equivalent JSON integer spelling preserves the complete Fog state',
        );
      }
    });

    yield FogAuditCase('$tag/mana-and-phase-admission', () {
      final target = fogAnchor('d4', side);
      for (final mana in [0, 1, 2]) {
        fogReject(
          fogScenario(side: side, mana: mana),
          PlayCardAction(CardId.fog, target: target),
        );
      }
      fogEqual(
        fogCast(fogScenario(side: side, mana: 3), side).rules.mana[side],
        0,
        'exact mana remains playable',
      );
      final original = fogScenario(side: side);
      final first = fogEdit(original, (draft) {
        draft.ownTurns[side] = 1;
      });
      fogReject(first, PlayCardAction(CardId.fog, target: target));
      final chess = fogEdit(original, (draft) {
        draft.phase = BattlePhase.chess;
      });
      fogReject(chess, PlayCardAction(CardId.fog, target: target));
      final terminal = fogEdit(original, (draft) {
        draft.phase = BattlePhase.terminal;
        draft.terminal = const TerminalState('seventy_five_moves');
      });
      fogReject(terminal, PlayCardAction(CardId.fog, target: target));
      fogCheck(
        BattleRulesCore.legalActions(original.view(side.opposite)).isEmpty,
        'nonmoving player cannot cast',
      );
    });

    yield FogAuditCase('$tag/fully-occupied-zone-needs-no-empty-square', () {
      final state = fogScenario(
        side: side,
        fen: '7k/8/8/8/2PN4/2RB4/8/K7 w - - 0 12',
      );
      final expected = fogExpectedZone('c3', side);
      fogCheck(
        expected.every((square) => state.rules.board.squares[square] != null),
        'fixture really has four occupied squares',
      );
      fogEqual(
        fogEffects(fogCast(state, side, anchor: 'c3')).single.squares,
        expected,
        'fully occupied Fog zone',
      );
    });

    for (final symbol in ['P', 'N', 'B', 'R', 'Q']) {
      for (final ownerIsAttacker in [false, true]) {
        yield FogAuditCase(
          '$tag/fixture-target-matrix/$symbol/attacker-owns-fog-$ownerIsAttacker',
          () {
            final original = fogScenario(
              side: side,
              fen: '7k/8/2R5/8/3${symbol}4/8/8/K7 b - - 0 12',
            );
            final attacker = side.opposite, target = fogSquare('d4', side);
            final state = fogInject(
              original,
              ownerIsAttacker ? attacker : side,
              fogExpectedZone('d4', side),
            );
            for (final card in [
              CardId.chain,
              CardId.slow,
              CardId.freeze,
              CardId.huntVow,
            ]) {
              final typeAllowed =
                  card != CardId.slow || ['B', 'R', 'Q'].contains(symbol);
              final baseline = BattleRulesCore.cardTargets(
                original.view(attacker),
                card,
              );
              fogEqual(
                baseline.contains(target),
                typeAllowed,
                'independent piece eligibility baseline',
              );
              final expected = typeAllowed && ownerIsAttacker;
              fogEqual(
                BattleRulesCore.cardTargets(
                  state.view(attacker),
                  card,
                ).contains(target),
                expected,
                'Fog only protects its owner from opposing direct targeting',
              );
              fogEqual(
                BattleRulesCore.isLegalAction(
                  state.view(attacker),
                  PlayCardAction(card, target: target),
                ),
                expected,
                'target list and admission agree',
              );
              fogCheck(
                BattleRulesCore.cardTargets(
                  state.view(attacker),
                  card,
                ).contains(fogSquare('c6', side)),
                'outside-zone rook remains targetable',
              );
              if (!expected) {
                fogReject(state, PlayCardAction(card, target: target));
              }
            }
          },
        );
      }
    }

    yield FogAuditCase(
      '$tag/king-zone-does-not-enable-direct-king-targets',
      () {
        final state = fogCast(
          fogScenario(side: side, fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 12'),
          side,
          anchor: 'e1',
        );
        final without = fogEdit(state, (draft) {
          draft.boardEffects.clear();
        });
        for (final card in [
          CardId.chain,
          CardId.slow,
          CardId.freeze,
          CardId.huntVow,
        ]) {
          for (final current in [state, without]) {
            fogCheck(
              !BattleRulesCore.cardTargets(
                current.view(side.opposite),
                card,
              ).contains(fogSquare('e1', side)),
              'kings are never direct card targets',
            );
          }
        }
        fogEqual(
          BattleRulesCore.legalMoves(
            state.rules,
            side,
          ).map((move) => move.uci).toList(),
          BattleRulesCore.legalMoves(
            without.rules,
            side,
          ).map((move) => move.uci).toList(),
          'Fog cannot restrict king or castling geometry',
        );
      },
    );

    for (final movement in [
      (from: 'd4', to: 'd5', protected: true),
      (from: 'd4', to: 'd6', protected: false),
      (from: 'd4', to: 'f4', protected: false),
      (from: 'd2', to: 'd4', protected: true),
      (from: 'c4', to: 'd4', protected: true),
      (from: 'e5', to: 'd5', protected: true),
    ]) {
      yield FogAuditCase(
        '$tag/zone-not-identity/${movement.from}-${movement.to}',
        () {
          final squares = List<String>.filled(8, '8');
          final file = movement.from.codeUnitAt(0) - 97;
          squares[8 - int.parse(movement.from[1])] =
              '${file == 0 ? '' : file}R${file == 7 ? '' : 7 - file}';
          squares[0] = '7k';
          squares[7] = 'K7';
          final original = fogScenario(
            side: side,
            fen: '${squares.join('/')} w - - 0 12',
          );
          final id = original.rules.pieceIds[fogSquare(movement.from, side)];
          final cast = fogCast(original, side);
          final moved = fogRoundTrip(
            fogApply(
              cast,
              ChessMoveAction(fogMove('${movement.from}${movement.to}', side)),
            ),
          );
          final target = fogSquare(movement.to, side);
          fogEqual(
            moved.rules.pieceIds[target],
            id,
            'mover identity follows chess move',
          );
          fogEqual(
            fogEffects(moved).single.squares,
            fogExpectedZone('d4', side),
            'zone stays at its original four squares',
          );
          for (final card in [
            CardId.chain,
            CardId.slow,
            CardId.freeze,
            CardId.huntVow,
          ]) {
            fogEqual(
              BattleRulesCore.isLegalAction(
                moved.view(side.opposite),
                PlayCardAction(card, target: target),
              ),
              !movement.protected,
              'entering is protected; leaving is not',
            );
          }
        },
      );
    }

    yield FogAuditCase('$tag/square-targets-and-card-queries-bypass-fog', () {
      final state = fogOpponentWindow(
        side,
        enemyHand: const [
          CardId.mine,
          CardId.lockedSquare,
          CardId.watchVow,
          CardId.boardSeal,
        ],
      );
      final square = fogSquare('e4', side);
      for (final card in [CardId.mine, CardId.lockedSquare, CardId.watchVow]) {
        fogCheck(
          BattleRulesCore.isLegalAction(
            state.view(side.opposite),
            PlayCardAction(card, target: square),
          ),
          'empty square inside Fog remains targetable',
        );
        final after = fogApply(state, PlayCardAction(card, target: square));
        fogCheck(
          fogEffects(after).isEmpty,
          'normal card completion expires opposing Fog',
        );
        if (card == CardId.watchVow) {
          fogEqual(
            after.rules.vows.single.square,
            square,
            'square vow is not a direct piece target',
          );
        } else {
          fogEqual(after.rules.boardEffects.single.squares, [
            square,
          ], 'square effect survives Fog expiry');
        }
      }
      final sealed = fogApply(
        state,
        PlayCardAction(CardId.boardSeal, target: fogAnchor('d4', side)),
      );
      fogEqual(
        sealed.rules.boardEffects.single.type,
        BoardEffectType.boardSeal,
        'zone targeting is not blocked by Fog',
      );
      final radarState = fogOpponentWindow(
        side,
        enemyHand: const [CardId.radar],
      );
      final queried = fogApply(
        radarState,
        PlayCardAction(CardId.radar, target: CardId.purify.wire),
      );
      fogEqual(
        queried
            .hidden
            .knowledge[side.opposite]!
            .radarObservations
            .single
            .queriedCardId,
        CardId.purify,
        'Fog does not hide card information',
      );
    });

    yield FogAuditCase('$tag/chess-capture-not-card-protection', () {
      final original = fogScenario(
        side: side,
        fen: '3r3k/8/8/8/3R4/8/8/K7 w - - 0 12',
      );
      final cast = fogCast(original, side);
      for (final player in PieceColor.values) {
        fogEqual(
          BattleRulesCore.legalMoves(
            cast.rules,
            player,
          ).map((move) => move.uci).toList(),
          BattleRulesCore.legalMoves(
            original.rules,
            player,
          ).map((move) => move.uci).toList(),
          'Fog changes no chess move list',
        );
      }
      var state = fogApply(cast, ChessMoveAction(fogMove('a1a2', side)));
      final victim = state.rules.pieceIds[fogSquare('d4', side)];
      state = fogApply(state, const PassAction());
      fogCheck(
        fogEffects(state).isEmpty,
        'Fog ends before responding chess move',
      );
      state = fogApply(state, ChessMoveAction(fogMove('d8d4', side)));
      fogCheck(
        !state.rules.pieceIds.contains(victim),
        'ordinary capture removes protected former occupant',
      );
      fogEqual(
        state.rules.board.squares[fogSquare('d4', side)]!.color,
        side.opposite,
        'enemy captures normally',
      );
    });

    yield FogAuditCase(
      '$tag/caster-capture-keeps-zone-not-captured-identity',
      () {
        final original = fogScenario(
          side: side,
          fen: '7k/8/8/3n4/3R4/8/8/K7 w - - 0 12',
        );
        final victim = original.rules.pieceIds[fogSquare('d5', side)];
        final moved = fogApply(
          fogCast(original, side),
          ChessMoveAction(fogMove('d4d5', side)),
        );
        fogCheck(
          !moved.rules.pieceIds.contains(victim),
          'captured identity is removed',
        );
        fogEqual(
          fogEffects(moved).single.squares,
          fogExpectedZone('d4', side),
          'capture does not shrink or relocate Fog',
        );
        fogReject(
          moved,
          PlayCardAction(CardId.freeze, target: fogSquare('d5', side)),
        );
      },
    );

    yield FogAuditCase('$tag/en-passant-during-caster-move', () {
      final original = fogScenario(
        side: side,
        fen: '7k/8/8/3pP3/8/8/8/K7 w - d6 0 12',
      );
      final mover = original.rules.pieceIds[fogSquare('e5', side)];
      final victim = original.rules.pieceIds[fogSquare('d5', side)];
      final cast = fogCast(original, side, anchor: 'd5');
      fogEqual(
        cast.rules.board.enPassant,
        fogSquare('d6', side),
        'cast preserves EP right',
      );
      final moved = fogApply(cast, ChessMoveAction(fogMove('e5d6', side)));
      fogEqual(
        moved.rules.pieceIds[fogSquare('d6', side)],
        mover,
        'EP mover identity',
      );
      fogEqual(
        moved.rules.pieceIds[fogSquare('d5', side)],
        null,
        'EP victim square cleared',
      );
      fogCheck(
        !moved.rules.pieceIds.contains(victim),
        'EP captured identity removed',
      );
      fogEqual(
        fogEffects(moved).single.squares,
        fogExpectedZone('d5', side),
        'EP leaves static Fog zone',
      );
    });

    yield FogAuditCase('$tag/en-passant-after-opponent-pass', () {
      final original = fogScenario(
        side: side,
        fen: '7k/8/8/8/3p4/8/4P3/K7 w - - 0 12',
      );
      var state = fogApply(
        fogCast(original, side, anchor: 'd3'),
        ChessMoveAction(fogMove('e2e4', side)),
      );
      final victim = state.rules.pieceIds[fogSquare('e4', side)];
      state = fogApply(state, const PassAction());
      fogCheck(fogEffects(state).isEmpty, 'pass expires Fog');
      fogEqual(
        state.rules.board.enPassant,
        fogSquare('e3', side),
        'pass preserves chess EP',
      );
      state = fogApply(state, ChessMoveAction(fogMove('d4e3', side)));
      fogEqual(
        state.rules.board.squares[fogSquare('e4', side)],
        null,
        'EP captures zone occupant',
      );
      fogCheck(
        !state.rules.pieceIds.contains(victim),
        'EP leaves no ghost victim',
      );
    });

    for (final castle in [
      (uci: 'e1g1', anchor: 'f1', king: 'g1', rookFrom: 'h1', rookTo: 'f1'),
      (uci: 'e1c1', anchor: 'c1', king: 'c1', rookFrom: 'a1', rookTo: 'd1'),
    ]) {
      yield FogAuditCase('$tag/castle/${castle.uci}', () {
        final original = fogScenario(
          side: side,
          fen: '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 12',
        );
        final king = original.rules.pieceIds[fogSquare('e1', side)];
        final rook = original.rules.pieceIds[fogSquare(castle.rookFrom, side)];
        final moved = fogApply(
          fogCast(original, side, anchor: castle.anchor),
          ChessMoveAction(fogMove(castle.uci, side)),
        );
        fogEqual(
          moved.rules.pieceIds[fogSquare(castle.king, side)],
          king,
          'castled king identity',
        );
        fogEqual(
          moved.rules.pieceIds[fogSquare(castle.rookTo, side)],
          rook,
          'castled rook identity',
        );
        fogEqual(
          moved.rules.pieceIds[fogSquare(castle.rookFrom, side)],
          null,
          'rook source cleared',
        );
        fogEqual(
          fogEffects(moved).single.squares,
          fogExpectedZone(castle.anchor, side),
          'castling cannot transport Fog',
        );
        fogReject(
          moved,
          PlayCardAction(CardId.chain, target: fogSquare(castle.rookTo, side)),
        );
      });
    }

    yield FogAuditCase('$tag/check-remains-a-chess-obligation', () {
      final cast = fogCast(
        fogScenario(side: side, fen: 'r6k/8/8/8/3R4/8/8/K7 w - - 0 12'),
        side,
      );
      fogReject(cast, ChessMoveAction(fogMove('d4d5', side)));
      final escaped = fogApply(cast, ChessMoveAction(fogMove('a1b1', side)));
      fogEqual(
        escaped.rules.phase,
        BattlePhase.card,
        'legal check escape advances normally',
      );
      fogCheck(
        fogEffects(escaped).isNotEmpty,
        'own king move does not expire Fog',
      );
    });

    for (final close in [
      'pass',
      'discard',
      'mine',
      'shelter',
      'fog',
      'rook-bend',
      'contract',
    ]) {
      yield FogAuditCase('$tag/expiry/$close', () {
        final hand = switch (close) {
          'mine' => <CardId>[CardId.mine],
          'shelter' => <CardId>[CardId.shelter],
          'fog' => <CardId>[CardId.fog],
          'rook-bend' => <CardId>[CardId.rookBend],
          'contract' => <CardId>[CardId.shadowContract, CardId.radar],
          _ => <CardId>[CardId.chain],
        };
        final state = fogOpponentWindow(side, enemyHand: hand);
        final action = switch (close) {
          'pass' => const PassAction(),
          'discard' => const DiscardAction(CardId.chain),
          'mine' => PlayCardAction(CardId.mine, target: fogSquare('e4', side)),
          'shelter' => PlayCardAction(
            CardId.shelter,
            target: fogSquare('h7', side),
          ),
          'fog' => PlayCardAction(CardId.fog, target: fogAnchor('d4', side)),
          'rook-bend' => PlayCardAction(
            CardId.rookBend,
            target: fogSquare('h7', side),
          ),
          _ => const PlayCardAction(
            CardId.shadowContract,
            sacrifice: CardId.radar,
          ),
        };
        final after = fogApply(state, action);
        fogCheck(
          !fogEffects(after).any((effect) => effect.owner == side),
          'old Fog expires when opponent finishes card choice',
        );
        fogEqual(
          after.rules.phase,
          BattlePhase.chess,
          'expiry is before chess',
        );
        fogEqual(
          after.rules.ply,
          state.rules.ply,
          'expiry does not consume chess move',
        );
        if (close == 'fog') {
          fogEqual(
            fogEffects(after).single.owner,
            side.opposite,
            'new opposing Fog is not swept away',
          );
          fogEqual(
            fogEffects(after).single.responseSide,
            side,
            'new Fog waits for other window',
          );
        }
        if (close == 'rook-bend') {
          fogEqual(
            after.rules.special?.card,
            CardId.rookBend,
            'special move authorization survives expiry',
          );
          fogApply(after, ChessMoveAction(fogMove('h7g6', side)));
        }
      });
    }

    for (final card in [CardId.prophecy, CardId.fateExchange]) {
      for (final deckSize in [1, 2, 3]) {
        yield FogAuditCase('$tag/pending/${card.wire}/deck-$deckSize', () {
          final actor = side.opposite;
          final before = fogWithDeckSize(
            fogOpponentWindow(side, enemyHand: [card, CardId.radar]),
            actor,
            deckSize,
          );
          final expectedDeck = before.hidden.decks[actor]!;
          final inspectCount =
              card == CardId.prophecy
                  ? (deckSize < 2 ? deckSize : 2)
                  : deckSize;
          final inspected = expectedDeck.take(inspectCount).toList();
          final pending = fogRoundTrip(
            fogApply(
              before,
              PlayCardAction(
                card,
                sacrifice: card == CardId.fateExchange ? CardId.radar : null,
              ),
            ),
          );
          fogEqual(
            pending.rules.phase,
            BattlePhase.pending,
            'private choice stays pending',
          );
          fogEqual(
            pending.hidden.knowledge[actor]!.pendingCards,
            inspected,
            'only expected deck prefix inspected',
          );
          fogEqual(
            fogEffects(pending).single.squares,
            fogExpectedZone('d4', side),
            'Fog remains throughout unfinished private choice',
          );
          fogCheck(
            pending.hidden.knowledge[side]!.pendingCards.isEmpty,
            'Fog owner cannot see opponent private choice',
          );
          fogReject(pending, const PassAction());
          fogReject(pending, DiscardAction(CardId.radar));
          fogReject(pending, ChessMoveAction(fogMove('h8g8', side)));
          fogReject(pending, ResolveAction([]));
          fogReject(pending, ResolveAction([inspected.first, inspected.first]));
          fogReject(
            pending,
            PlayCardAction(CardId.chain, target: fogSquare('d4', side)),
          );
          final choices = <ResolveAction>[
            if (card == CardId.prophecy)
              for (final order in _orders(inspected)) ResolveAction(order)
            else
              for (final selected in inspected)
                for (final order in _orders(
                  inspected.where((value) => value != selected).toList(),
                ))
                  ResolveAction(order, selected: selected),
          ];
          fogEqual(
            BattleRulesCore.legalActions(pending.view(actor))
                .map((action) => action.key)
                .toSet()
                .difference(choices.map((action) => action.key).toSet())
                .length,
            0,
            'no unexpected private resolution',
          );
          fogEqual(
            BattleRulesCore.legalActions(pending.view(actor)).length,
            choices.length,
            'independently enumerated private choices',
          );
          for (final choice in choices) {
            final resolved = fogApply(pending, choice);
            fogCheck(
              fogEffects(resolved).isEmpty,
              'resolution closes Fog lifetime',
            );
            fogEqual(resolved.rules.pending, null, 'pending marker cleared');
            fogEqual(
              resolved.rules.phase,
              BattlePhase.chess,
              'resolution restores chess',
            );
            fogEqual(
              resolved.rules.ply,
              pending.rules.ply,
              'resolution is not a move',
            );
            fogEqual(
              resolved.rules.mana,
              pending.rules.mana,
              'resolution cannot charge Fog or choice twice',
            );
            fogEqual(resolved.hidden.decks[actor], [
              ...choice.order,
              ...expectedDeck.skip(inspectCount),
            ], 'private deck order follows explicit choice');
            fogCheck(
              resolved.hidden.knowledge[actor]!.pendingCards.isEmpty,
              'private pending cards cleared',
            );
            fogReject(resolved, choice);
            fogApply(resolved, ChessMoveAction(fogMove('h8g8', side)));
          }
        });
      }
    }

    yield FogAuditCase(
      '$tag/break-seal-removes-one-zone-and-expiry-is-separate',
      () {
        var state = fogOpponentWindow(
          side,
          enemyHand: const [CardId.breakSeal],
        );
        final id = fogEffects(state).single.id;
        state = fogEdit(state, (draft) {
          draft.boardEffects.addAll([
            BoardEffectInstance(
              id: 'overlap-mine',
              type: BoardEffectType.mine,
              owner: side,
              squares: [fogSquare('e4', side)],
              responseSide: side.opposite,
              duration: EffectDuration.persistent,
            ),
            BoardEffectInstance(
              id: 'overlap-seal',
              type: BoardEffectType.boardSeal,
              owner: side,
              squares: fogExpectedZone('d4', side),
              responseSide: side.opposite,
              duration: EffectDuration.move,
            ),
          ]);
        });
        final after = fogApply(
          state,
          PlayCardAction(CardId.breakSeal, target: id),
        );
        fogEqual(after.rules.boardEffects.map((effect) => effect.id).toList(), [
          'overlap-mine',
          'overlap-seal',
        ], 'unrelated overlapping effects are retained');
        fogReject(
          state,
          PlayCardAction(CardId.breakSeal, target: fogSquare('d4', side)),
        );
        fogReject(after, PlayCardAction(CardId.breakSeal, target: id));
      },
    );

    yield FogAuditCase(
      '$tag/fixture-overlap-union-and-response-side-cleanup',
      () {
        final base = fogScenario(
          side: side,
          fen: '7k/8/8/8/3RR3/8/8/K7 b - - 0 12',
          enemyHand: const [CardId.chain, CardId.breakSeal],
        );
        var state = fogInject(
          base,
          side,
          fogExpectedZone('c4', side),
          id: 'left-fog',
        );
        state = fogInject(
          state,
          side,
          fogExpectedZone('d4', side),
          id: 'right-fog',
        );
        state = fogInject(
          state,
          side.opposite,
          fogExpectedZone('d4', side),
          id: 'actor-fog',
        );
        for (final at in ['d4', 'e4']) {
          fogReject(
            state,
            PlayCardAction(CardId.chain, target: fogSquare(at, side)),
          );
        }
        final after = fogApply(state, const PassAction());
        fogEqual(fogEffects(after).map((effect) => effect.id).toList(), [
          'actor-fog',
        ], 'close removes every due enemy Fog, not friendly Fog');
        fogCheck(
          BattleRulesCore.cardTargets(
            after.view(side.opposite),
            CardId.chain,
          ).contains(fogSquare('e4', side)),
          'attacker-owned Fog cannot protect enemy piece',
        );
        fogReject(
          state,
          const PlayCardAction(CardId.breakSeal, target: 'actor-fog'),
        );
        final broken = fogApply(
          state,
          const PlayCardAction(CardId.breakSeal, target: 'left-fog'),
        );
        fogEqual(
          fogEffects(broken).map((effect) => effect.id).toList(),
          ['actor-fog'],
          'other due Fog expires by window closure, not explicit area deletion',
        );
      },
    );

    for (final type in [
      PieceEffectType.chain,
      PieceEffectType.slow,
      PieceEffectType.freeze,
      PieceEffectType.mineDebuff,
    ]) {
      yield FogAuditCase('$tag/no-retroactive-cleanse/${type.name}', () {
        final original = fogEdit(fogScenario(side: side), (draft) {
          draft.pieceEffects.add(
            ActivePieceEffect(
              id: 'old-debuff',
              type: type,
              owner: side.opposite,
              pieceId: draft.pieceIds[fogSquare('d4', side)]!,
              responseSide: side,
              duration:
                  type == PieceEffectType.mineDebuff
                      ? EffectDuration.pieceMove
                      : EffectDuration.move,
            ),
          );
        });
        final after = fogCast(original, side);
        fogEqual(
          after.rules.pieceEffects.single.toJson(),
          original.rules.pieceEffects.single.toJson(),
          'Fog cannot purge a preexisting restriction',
        );
        fogEqual(
          BattleRulesCore.legalMoves(
            after.rules,
            side,
          ).map((move) => move.uci).toList(),
          BattleRulesCore.legalMoves(
            original.rules,
            side,
          ).map((move) => move.uci).toList(),
          'Fog cannot silently bypass preexisting move restrictions',
        );
      });
    }

    yield FogAuditCase(
      '$tag/mine-entry-inside-friendly-fog-still-triggers',
      () {
        final original = fogEdit(
          fogScenario(side: side, fen: '7k/8/8/8/8/8/3R4/K7 w - - 0 12'),
          (draft) {
            draft.boardEffects.add(
              BoardEffectInstance(
                id: 'enemy-mine',
                type: BoardEffectType.mine,
                owner: side.opposite,
                squares: [fogSquare('d4', side)],
                responseSide: side,
                duration: EffectDuration.persistent,
              ),
            );
          },
        );
        final moved = fogApply(
          fogCast(original, side),
          ChessMoveAction(fogMove('d2d4', side)),
        );
        fogCheck(
          !moved.rules.boardEffects.any((effect) => effect.id == 'enemy-mine'),
          'Mine is consumed on entry',
        );
        fogEqual(
          moved.rules.pieceEffects.single.type,
          PieceEffectType.mineDebuff,
          'Fog is not square-effect immunity',
        );
        fogEqual(
          moved.rules.pieceEffects.single.pieceId,
          moved.rules.pieceIds[fogSquare('d4', side)],
          'Mine attaches to arriving identity',
        );
        fogEqual(
          fogEffects(moved).single.squares,
          fogExpectedZone('d4', side),
          'trigger leaves Fog intact',
        );
      },
    );
  }
}
