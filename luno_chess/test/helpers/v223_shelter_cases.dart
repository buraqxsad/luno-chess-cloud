import 'dart:convert';

import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

class ShelterAuditCase {
  final String name;
  final void Function() run;
  const ShelterAuditCase(this.name, this.run);
}

void shelterCheck(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Object? _shelterJson(Object? value) {
  if (value is Enum) return enumWire(value);
  if (value is Map) {
    return {
      for (final entry in value.entries)
        (entry.key is Enum
            ? enumWire(entry.key as Enum)
            : '${entry.key}'): _shelterJson(entry.value),
    };
  }
  if (value is Iterable) return value.map(_shelterJson).toList();
  return value;
}

String shelterCanonical(Object? value) =>
    jsonEncode(canonicalObject(_shelterJson(value)));

void shelterEqual(Object? actual, Object? expected, String message) {
  shelterCheck(
    shelterCanonical(actual) == shelterCanonical(expected),
    '$message: actual=$actual expected=$expected',
  );
}

int shelterSquare(String text, PieceColor side) {
  final square = Square.of(text.codeUnitAt(0) - 97, text.codeUnitAt(1) - 49);
  return side.isWhite ? square : square ^ 56;
}

String shelterMove(String uci, PieceColor side) =>
    '${Square.algebraic(shelterSquare(uci.substring(0, 2), side))}'
    '${Square.algebraic(shelterSquare(uci.substring(2, 4), side))}'
    '${uci.length > 4 ? uci.substring(4) : ''}';

AuthoritativeBattleState shelterScenario({
  String fen = '7k/8/8/8/8/8/2NR4/K7 w - - 0 12',
  PieceColor side = PieceColor.white,
  List<CardId> ownHand = const [CardId.shelter, CardId.purify],
  List<CardId> enemyHand = const [
    CardId.chain,
    CardId.slow,
    CardId.freeze,
    CardId.huntVow,
  ],
  int mana = 6,
}) {
  final original = Board.fromFen(fen);
  final board =
      side.isWhite
          ? original
          : Board(
            squares: [
              for (var i = 0; i < 64; i++)
                original.squares[i ^ 56]?.copyWith(
                  color: original.squares[i ^ 56]!.color.opposite,
                ),
            ],
            turn: original.turn.opposite,
            castling:
                ((original.castling & 3) << 2) |
                ((original.castling & 12) >> 2),
            enPassant:
                original.enPassant == null ? null : original.enPassant! ^ 56,
            halfmoveClock: original.halfmoveClock,
            fullmoveNumber: original.fullmoveNumber,
          );
  final hands = {side: ownHand, side.opposite: enemyHand};
  final decks = {
    for (final color in PieceColor.values)
      color: [
        ...hands[color]!,
        ...CardId.values
            .where((c) => !hands[color]!.contains(c))
            .take(10 - hands[color]!.length),
      ],
  };
  final initial = DeckManager.newBattle(
    board: board,
    white: decks[PieceColor.white]!,
    black: decks[PieceColor.black]!,
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
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
          color: decks[color]!.skip(hands[color]!.length).toList(),
      },
      knowledge: {
        for (final color in PieceColor.values) color: PlayerKnowledgeState(),
      },
    ),
  );
}

AuthoritativeBattleState shelterEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState shelterRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

List<ActivePieceEffect> shelterEffects(AuthoritativeBattleState state) =>
    state.rules.pieceEffects
        .where((e) => e.type == PieceEffectType.shelter)
        .toList();

void shelterReject(AuthoritativeBattleState state, BattleAction action) {
  final before = shelterCanonical(state.toJson());
  shelterCheck(
    !BattleRulesCore.isLegalAction(state.view(state.rules.board.turn), action),
    'Rejected action is in legal actions: ${action.key}',
  );
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError catch (error) {
    shelterEqual(error.message, 'illegal-action', 'Rejection reason');
    rejected = true;
  }
  shelterCheck(rejected, 'Action was not rejected: ${action.key}');
  shelterEqual(
    shelterCanonical(state.toJson()),
    before,
    'Rejection changed authority, mana, hidden hand, or effect state',
  );
}

AuthoritativeBattleState shelterCastAndMove(
  AuthoritativeBattleState state,
  PieceColor side, {
  String from = 'd2',
  String move = 'd2d6',
}) {
  final target = shelterSquare(from, side);
  final before = shelterCanonical(state.toJson());
  var next = DeckManager.apply(
    state,
    PlayCardAction(CardId.shelter, target: target),
  );
  shelterEqual(shelterCanonical(state.toJson()), before, 'Cast mutated input');
  shelterEqual(next.rules.phase.name, 'chess', 'Shelter closes own window');
  final id = state.rules.pieceIds[target];
  shelterEqual(
    shelterEffects(next).single.pieceId,
    id,
    'Shelter must bind to identity',
  );
  next = DeckManager.apply(next, ChessMoveAction(shelterMove(move, side)));
  shelterEqual(
    shelterEffects(next).single.pieceId,
    id,
    'Shelter must survive own move',
  );
  return shelterRoundTrip(next);
}

ActivePieceEffect shelterDebuff(
  RuleDraft draft,
  PieceColor side,
  int square,
  PieceEffectType type, {
  String? id,
}) => ActivePieceEffect(
  id: id ?? 'adversarial-${type.name}',
  type: type,
  owner: side.opposite,
  pieceId: draft.pieceIds[square]!,
  responseSide: side,
  duration:
      type == PieceEffectType.mineDebuff
          ? EffectDuration.pieceMove
          : EffectDuration.move,
);

Iterable<ShelterAuditCase> shelterAuditCases() sync* {
  for (final side in PieceColor.values) {
    final tag = side.name;
    yield ShelterAuditCase('$tag/moved-identity-rejects-four-direct-cards', () {
      final state = shelterCastAndMove(shelterScenario(side: side), side);
      final target = shelterSquare('d6', side);
      shelterEqual(
        state.rules.pieceIds[target],
        state.rules.pieceEffects.single.pieceId,
        'Moved target identity',
      );
      for (final card in [
        CardId.chain,
        CardId.slow,
        CardId.freeze,
        CardId.huntVow,
      ]) {
        shelterReject(state, PlayCardAction(card, target: target));
      }
      shelterEqual(
        shelterEffects(state).length,
        1,
        'Rejected direct cast must not consume Shelter',
      );
      final next = DeckManager.apply(
        state,
        PlayCardAction(CardId.chain, target: shelterSquare('c2', side)),
      );
      shelterCheck(
        shelterEffects(next).isEmpty,
        'Legal cast on another piece must close Shelter window',
      );
      shelterEqual(
        next.rules.pieceEffects.single.type.name,
        'chain',
        'Only the other piece receives Chain',
      );
    });

    for (final close in ['pass', 'discard', 'fog', 'board-seal', 'shelter']) {
      yield ShelterAuditCase('$tag/opponent-window-closes-by-$close', () {
        final enemyCards = switch (close) {
          'fog' => [CardId.fog],
          'board-seal' => [CardId.boardSeal],
          'shelter' => [CardId.shelter],
          _ => [CardId.chain],
        };
        final state = shelterCastAndMove(
          shelterScenario(
            side: side,
            fen: '7k/6p1/8/8/8/8/2NR4/K7 w - - 0 12',
            enemyHand: enemyCards,
          ),
          side,
        );
        final BattleAction action = switch (close) {
          'pass' => const PassAction(),
          'discard' => const DiscardAction(CardId.chain),
          'fog' => PlayCardAction(
            CardId.fog,
            target: shelterSquare('d6', side),
          ),
          'board-seal' => PlayCardAction(
            CardId.boardSeal,
            target: shelterSquare('d6', side),
          ),
          _ => PlayCardAction(
            CardId.shelter,
            target: shelterSquare('g7', side),
          ),
        };
        final next = DeckManager.apply(state, action);
        shelterEqual(next.rules.phase.name, 'chess', 'Response phase');
        shelterCheck(
          !next.rules.pieceEffects.any(
            (e) => e.type == PieceEffectType.shelter && e.owner == side,
          ),
          'Old Shelter survives completed opponent card choice',
        );
        if (close == 'shelter') {
          shelterEqual(
            shelterEffects(next).single.owner.name,
            side.opposite.name,
            'New opposite Shelter must survive',
          );
        } else {
          shelterCheck(shelterEffects(next).isEmpty, 'Old Shelter remains');
        }
        if (close == 'board-seal' || close == 'fog') {
          shelterCheck(
            next.rules.boardEffects.single.squares.contains(
              shelterSquare('d6', side),
            ),
            'Area targeting must be legal through Shelter',
          );
        }
        if (close == 'pass') {
          for (final card in [
            CardId.chain,
            CardId.slow,
            CardId.freeze,
            CardId.huntVow,
          ]) {
            shelterCheck(
              BattleRulesCore.cardTargets(
                next.view(side.opposite),
                card,
              ).contains(shelterSquare('d6', side)),
              'Raw target eligibility must return after expiry: ${card.wire}',
            );
          }
          shelterReject(
            next,
            PlayCardAction(CardId.chain, target: shelterSquare('d6', side)),
          );
        }
      });
    }

    for (final pending in [CardId.prophecy, CardId.fateExchange]) {
      yield ShelterAuditCase(
        '$tag/${pending.wire}-defers-protection-expiry',
        () {
          final state = shelterCastAndMove(
            shelterScenario(side: side, enemyHand: [pending, CardId.radar]),
            side,
          );
          final entered = DeckManager.apply(
            state,
            PlayCardAction(
              pending,
              sacrifice: pending == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          shelterEqual(entered.rules.phase.name, 'pending', 'Pending phase');
          shelterEqual(
            shelterEffects(entered).length,
            1,
            'Pending choice must not close opponent card window early',
          );
          shelterReject(entered, const PassAction());
          shelterReject(
            entered,
            const PlayCardAction(CardId.shelter, target: 12),
          );
          final options =
              BattleRulesCore.legalActions(
                entered.view(side.opposite),
              ).whereType<ResolveAction>().toList();
          shelterCheck(
            options.length > 1,
            'Exercise alternative private orders',
          );
          for (final choice in options) {
            final resolved = DeckManager.apply(
              shelterRoundTrip(entered),
              choice,
            );
            shelterCheck(
              shelterEffects(resolved).isEmpty,
              'Resolution must expire Shelter for every legal order',
            );
            shelterEqual(resolved.rules.phase.name, 'chess', 'Resolved phase');
            shelterReject(resolved, choice);
          }
        },
      );
    }

    yield ShelterAuditCase('$tag/pinned-rook-stays-pinned-with-protection', () {
      final state = shelterScenario(
        side: side,
        fen: '4r2k/8/8/8/8/8/4R3/4K3 w - - 0 12',
      );
      final next = DeckManager.apply(
        state,
        PlayCardAction(CardId.shelter, target: shelterSquare('e2', side)),
      );
      shelterReject(next, ChessMoveAction(shelterMove('e2d2', side)));
      final alongPin = DeckManager.apply(
        next,
        ChessMoveAction(shelterMove('e2e3', side)),
      );
      shelterEqual(
        shelterEffects(alongPin).single.pieceId,
        state.rules.pieceIds[shelterSquare('e2', side)],
        'Pin-line movement',
      );
      shelterCheck(
        !MoveGen.inCheck(alongPin.rules.board, side),
        'Protection must not override king safety',
      );
    });

    yield ShelterAuditCase('$tag/check-escape-needs-real-interposition', () {
      final state = shelterScenario(
        side: side,
        fen: '4r2k/8/8/8/8/8/R7/4K3 w - - 0 12',
      );
      shelterCheck(
        MoveGen.inCheck(state.rules.board, side),
        'Fixture is check',
      );
      final cast = DeckManager.apply(
        state,
        PlayCardAction(CardId.shelter, target: shelterSquare('a2', side)),
      );
      shelterCheck(
        MoveGen.inCheck(cast.rules.board, side),
        'Shelter itself is not a check escape',
      );
      shelterReject(cast, ChessMoveAction(shelterMove('a2a3', side)));
      final escape = DeckManager.apply(
        cast,
        ChessMoveAction(shelterMove('a2e2', side)),
      );
      shelterCheck(
        !MoveGen.inCheck(escape.rules.board, side),
        'Interposition must escape check',
      );
      shelterEqual(
        shelterEffects(escape).single.pieceId,
        state.rules.pieceIds[shelterSquare('a2', side)],
        'Protected blocker',
      );
    });

    yield ShelterAuditCase(
      '$tag/freeze-overlap-does-not-cleanse-or-enable-castling',
      () {
        var state = shelterScenario(
          side: side,
          fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 12',
        );
        state = shelterEdit(
          state,
          (d) => d.pieceEffects.add(
            shelterDebuff(
              d,
              side,
              shelterSquare('h1', side),
              PieceEffectType.freeze,
            ),
          ),
        );
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: shelterSquare('h1', side)),
        );
        shelterEqual(cast.rules.pieceEffects.length, 2, 'Freeze remains');
        shelterReject(cast, ChessMoveAction(shelterMove('e1g1', side)));
        shelterReject(cast, ChessMoveAction(shelterMove('h1h2', side)));
        final moved = DeckManager.apply(
          cast,
          ChessMoveAction(shelterMove('e1d1', side)),
        );
        shelterEqual(
          moved.rules.pieceEffects.single.type.name,
          'shelter',
          'Another-piece move consumes Freeze but not Shelter',
        );
      },
    );

    yield ShelterAuditCase(
      '$tag/castling-rook-carries-shelter-onto-enemy-mine',
      () {
        var state = shelterScenario(
          side: side,
          fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 12',
        );
        state = shelterEdit(
          state,
          (d) => d.boardEffects.add(
            BoardEffectInstance(
              id: 'arrival-mine',
              type: BoardEffectType.mine,
              owner: side.opposite,
              squares: [shelterSquare('f1', side)],
              responseSide: side,
              duration: EffectDuration.persistent,
            ),
          ),
        );
        final moved = shelterCastAndMove(state, side, from: 'h1', move: 'e1g1');
        final id = state.rules.pieceIds[shelterSquare('h1', side)];
        shelterEqual(
          moved.rules.pieceIds[shelterSquare('f1', side)],
          id,
          'Castling rook identity',
        );
        shelterEqual(
          moved.rules.pieceEffects.map((e) => e.type.name).toList(),
          ['shelter', 'mineDebuff'],
          'Shelter must not block trap trigger',
        );
        shelterCheck(moved.rules.boardEffects.isEmpty, 'Mine is consumed');
        final closed = DeckManager.apply(moved, const PassAction());
        shelterEqual(
          closed.rules.pieceEffects.single.type.name,
          'mineDebuff',
          'Card-window expiry must not cleanse newly triggered Mine',
        );
      },
    );

    yield ShelterAuditCase(
      '$tag/protected-pawn-promotes-with-same-identity',
      () {
        final state = shelterScenario(
          side: side,
          fen: '7k/1P6/8/8/8/8/8/K7 w - - 0 12',
        );
        final moved = shelterCastAndMove(
          state,
          side,
          from: 'b7',
          move: 'b7b8n',
        );
        shelterEqual(
          moved.rules.board.pieceAt(shelterSquare('b8', side))?.type.name,
          'knight',
          'Promotion result',
        );
        shelterEqual(
          shelterEffects(moved).single.pieceId,
          state.rules.pieceIds[shelterSquare('b7', side)],
          'Promotion identity',
        );
        shelterReject(
          moved,
          PlayCardAction(CardId.huntVow, target: shelterSquare('b8', side)),
        );
      },
    );

    yield ShelterAuditCase(
      '$tag/en-passant-removes-protected-victim-and-preexisting-hunt',
      () {
        var state = shelterScenario(
          side: side,
          fen: '7k/8/8/8/3p4/8/4P3/K7 w - - 0 12',
        );
        final victim = state.rules.pieceIds[shelterSquare('e2', side)];
        state = shelterEdit(
          state,
          (d) => d.vows.add(
            VowState(
              id: 'prior-hunt',
              type: VowType.hunt,
              owner: side.opposite,
              pieceId: victim,
              square: null,
              remainingMoves: 2,
            ),
          ),
        );
        final moved = shelterCastAndMove(state, side, from: 'e2', move: 'e2e4');
        shelterEqual(
          moved.rules.vows.single.remainingMoves,
          2,
          'Shelter must not cancel or tick opponent existing Hunt',
        );
        final closed = DeckManager.apply(moved, const PassAction());
        final captured = DeckManager.apply(
          closed,
          ChessMoveAction(shelterMove('d4e3', side)),
        );
        shelterCheck(
          !captured.rules.pieceIds.contains(victim),
          'EP victim removed',
        );
        shelterCheck(captured.rules.pieceEffects.isEmpty, 'No ghost Shelter');
        shelterCheck(captured.rules.vows.isEmpty, 'Captured Hunt is consumed');
        shelterEqual(
          captured.rules.pieceIds[shelterSquare('e4', side)],
          null,
          'EP capture square does not retain victim identity',
        );
      },
    );

    yield ShelterAuditCase(
      '$tag/purify-one-of-three-overlaps-preserves-own-shelter',
      () {
        var state = shelterScenario(
          side: side,
          ownHand: [CardId.purify, CardId.shelter],
        );
        final square = shelterSquare('d2', side);
        state = shelterEdit(state, (d) {
          d.pieceEffects.addAll([
            ActivePieceEffect(
              id: 'prior-shelter',
              type: PieceEffectType.shelter,
              owner: side,
              pieceId: d.pieceIds[square]!,
              responseSide: side.opposite,
              duration: EffectDuration.card,
            ),
            shelterDebuff(d, side, square, PieceEffectType.freeze),
            shelterDebuff(d, side, square, PieceEffectType.mineDebuff),
          ]);
        });
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(state.view(side));
        final interaction =
            BattleInteraction()
              ..synchronize(view, 20)
              ..select(CardId.purify, actions);
        final choices = interaction.tap(square, view, actions);
        shelterEqual(
          choices.map((a) => (a as PlayCardAction).target).toList()..sort(),
          ['adversarial-freeze', 'adversarial-mineDebuff'],
          'Overlapping removal chooser excludes positive Shelter',
        );
        shelterEqual(
          interaction.play,
          null,
          'Ambiguous removal must not autocast',
        );
        shelterReject(
          state,
          const PlayCardAction(CardId.purify, target: 'prior-shelter'),
        );
        final purified = DeckManager.apply(
          state,
          const PlayCardAction(CardId.purify, target: 'adversarial-freeze'),
        );
        shelterEqual(purified.rules.pieceEffects.map((e) => e.id).toList(), [
          'prior-shelter',
          'adversarial-mineDebuff',
        ], 'Only Freeze is removed');
        final moved = DeckManager.apply(
          purified,
          ChessMoveAction(shelterMove('d2d3', side)),
        );
        shelterEqual(
          moved.rules.pieceEffects.single.id,
          'prior-shelter',
          'Noncapture consumes Mine debuff independently of Shelter',
        );
      },
    );

    yield ShelterAuditCase(
      '$tag/fog-removal-and-window-expiry-remain-distinct',
      () {
        var state = shelterScenario(
          side: side,
          enemyHand: [CardId.breakSeal, CardId.freeze],
        );
        state = shelterEdit(
          state,
          (d) => d.boardEffects.add(
            BoardEffectInstance(
              id: 'old-fog',
              type: BoardEffectType.fog,
              owner: side,
              squares: boardZone(
                shelterSquare(side.isWhite ? 'd6' : 'd7', side),
              ),
              responseSide: side.opposite,
              duration: EffectDuration.card,
            ),
          ),
        );
        final moved = shelterCastAndMove(state, side);
        final target = shelterSquare('d6', side);
        shelterReject(moved, PlayCardAction(CardId.freeze, target: target));
        final broken = DeckManager.apply(
          moved,
          const PlayCardAction(CardId.breakSeal, target: 'old-fog'),
        );
        shelterCheck(broken.rules.boardEffects.isEmpty, 'Fog removed');
        shelterCheck(
          shelterEffects(broken).isEmpty,
          'Shelter expires because opponent window closed, not removal',
        );
        shelterEqual(broken.rules.used[side]!.map((c) => c.wire).toList(), [
          'shelter',
        ], 'Break Seal must not refund or recast Shelter');
      },
    );

    yield ShelterAuditCase('$tag/combined-cost-echo-and-stale-intent', () {
      var state = shelterScenario(side: side, mana: 2);
      state = shelterEdit(state, (d) {
        d.mana[side.opposite] = 3;
        d.modifiers.addAll([
          PendingModifier(
            id: 'tax',
            type: ModifierType.manaSabotage,
            owner: side.opposite,
            responseSide: side,
            targetCard: CardId.shelter,
            ownTurn: d.ownTurns[side]!,
          ),
          PendingModifier(
            id: 'deal',
            type: ModifierType.discount,
            owner: side,
            responseSide: side,
            targetCard: null,
            ownTurn: d.ownTurns[side]!,
          ),
          PendingModifier(
            id: 'echo',
            type: ModifierType.echo,
            owner: side.opposite,
            responseSide: side,
            targetCard: CardId.shelter,
            ownTurn: d.ownTurns[side]!,
          ),
        ]);
      });
      shelterEqual(
        BattleRulesCore.effectiveCost(state.rules, side, CardId.shelter),
        1,
        'Tax and discount combine before minimum-cost clamp',
      );
      final view = state.view(side),
          actions = BattleRulesCore.legalActions(state.view(side));
      final selection =
          BattleInteraction()
            ..synchronize(view, 20)
            ..select(CardId.shelter, actions);
      selection.tap(shelterSquare('d2', side), view, actions);
      final saved = selection.play!;
      final next = DeckManager.apply(state, saved);
      shelterEqual(next.rules.mana[side], 1, 'Combined Shelter cost');
      shelterEqual(next.rules.mana[side.opposite], 5, 'Echo pays exactly once');
      shelterCheck(next.rules.modifiers.isEmpty, 'Current modifiers consumed');
      selection.synchronize(next.view(side), 21);
      shelterEqual(selection.play, null, 'Version change clears saved Shelter');
      shelterEqual(selection.card, null, 'Version change clears selected card');
      shelterReject(next, saved);
      shelterEqual(
        next.rules.mana[side.opposite],
        5,
        'Duplicate cannot repay Echo',
      );
      shelterEqual(next.rules.used[side]!.map((c) => c.wire).toList(), [
        'shelter',
      ], 'No second consumption');
    });
  }
  yield* shelterEdgeCases();
  yield* shelterMechanicEdgeCases();
}

// Expected targets and moves below are authored from piece ownership, chess
// geometry and the card contract, not copied from a rules-engine fixture.
Iterable<ShelterAuditCase> shelterEdgeCases() sync* {
  for (final side in PieceColor.values) {
    final tag = side.name;
    int q(String text) => shelterSquare(text, side);
    String move(String text) => shelterMove(text, side);
    final direct = [CardId.chain, CardId.slow, CardId.freeze, CardId.huntVow];

    yield ShelterAuditCase('$tag/five-archetypes-exact-target-mask', () {
      final state = shelterScenario(
        side: side,
        fen: '7k/7p/8/8/8/8/P1NBRQ2/K7 w - - 0 12',
      );
      final expected = ['a2', 'c2', 'd2', 'e2', 'f2'].map(q).toList()..sort();
      final view = state.view(side);
      shelterEqual(
        BattleRulesCore.cardTargets(view, CardId.shelter).cast<int>().toList()
          ..sort(),
        expected,
        'Exact own non-king mask',
      );
      for (final square in expected) {
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: square),
        );
        final effect = shelterEffects(cast).single;
        shelterEqual(effect.toJson(), {
          'id': 'e101',
          'type': 'shelter',
          'owner': sideWire(side),
          'pieceId': state.rules.pieceIds[square],
          'responseSide': sideWire(side.opposite),
          'duration': 'card',
        }, 'New effect binds only selected identity and opposite window');
        shelterEqual(
          cast.rules.pieceIds,
          state.rules.pieceIds,
          'Protection cannot move or replace any piece',
        );
        shelterEqual(
          cast.rules.fen,
          state.rules.fen,
          'Shelter is not a chess move',
        );
        shelterEqual(cast.rules.ply, 0, 'Shelter does not advance ply');
        shelterEqual(
          cast.rules.drawCounts,
          state.rules.drawCounts,
          'Shelter itself does not draw',
        );
      }
    });

    yield ShelterAuditCase(
      '$tag/retarget-preview-is-one-square-and-atomic',
      () {
        final state = shelterScenario(
          side: side,
          fen: '7k/7p/8/8/8/8/P1NBRQ2/K7 w - - 0 12',
        );
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(view);
        final selection =
            BattleInteraction()
              ..synchronize(view, 10)
              ..select(CardId.shelter, actions);
        shelterEqual(
          selection.targets(view, actions).toList()..sort(),
          ['a2', 'c2', 'd2', 'e2', 'f2'].map(q).toList()..sort(),
          'UI highlights the independent ownership mask',
        );
        for (final square in ['a2', 'f2', 'c2'].map(q)) {
          selection.tap(square, view, actions);
          shelterEqual(
            selection.play?.target,
            square,
            'Retarget replaces intent',
          );
          shelterEqual(selection.preview().toList(), [
            square,
          ], 'No zone preview');
          shelterEqual(
            selection.piece,
            null,
            'Card target is not a bound move',
          );
          shelterCheck(
            !selection.invalidTarget,
            'Legal target reported invalid',
          );
        }
        for (final square in ['a1', 'h7', 'h8', 'b4'].map(q)) {
          selection.tap(q('e2'), view, actions);
          selection.tap(square, view, actions);
          shelterEqual(selection.play, null, 'Invalid retarget clears cast');
          shelterCheck(
            selection.preview().isEmpty,
            'Invalid target keeps preview',
          );
          shelterCheck(
            selection.invalidTarget,
            'Invalid target feedback absent',
          );
          shelterEqual(selection.card, CardId.shelter, 'Card remains selected');
        }
        selection.tap(q('d2'), view, actions);
        selection.select(CardId.shelter, actions);
        shelterEqual(selection.card, null, 'Second card tap cancels Shelter');
        shelterCheck(selection.preview().isEmpty, 'Cancel retains target');
      },
    );

    for (final protected in ['a2', 'c2', 'd2', 'e2', 'f2']) {
      yield ShelterAuditCase('$tag/$protected-direct-protection-is-local', () {
        final state = shelterScenario(
          side: side,
          fen: '7k/7p/8/8/8/8/P1NBRQ2/K7 w - - 0 12',
        );
        var cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: q(protected)),
        );
        cast = DeckManager.apply(cast, ChessMoveAction(move('a1b1')));
        for (final card in direct) {
          final eligible =
              ['a2', 'c2', 'd2', 'e2', 'f2']
                  .where((s) => s != protected)
                  .where(
                    (s) =>
                        card != CardId.slow || ['d2', 'e2', 'f2'].contains(s),
                  )
                  .map(q)
                  .toList()
                ..sort();
          shelterEqual(
            BattleRulesCore.cardTargets(
                cast.view(side.opposite),
                card,
              ).cast<int>().toList()
              ..sort(),
            eligible,
            'Only protected identity disappears from ${card.wire} mask',
          );
        }
      });
    }

    for (final overlap in [
      PieceEffectType.chain,
      PieceEffectType.slow,
      PieceEffectType.freeze,
      PieceEffectType.mineDebuff,
    ]) {
      yield ShelterAuditCase(
        '$tag/${overlap.name}-persists-through-shelter',
        () {
          var state = shelterScenario(
            side: side,
            fen: '7k/8/8/8/4p3/8/4R3/K7 w - - 0 12',
          );
          state = shelterEdit(
            state,
            (d) => d.pieceEffects.add(shelterDebuff(d, side, q('e2'), overlap)),
          );
          final cast = DeckManager.apply(
            state,
            PlayCardAction(CardId.shelter, target: q('e2')),
          );
          shelterEqual(
            cast.rules.pieceEffects.map((e) => e.type.name).toList(),
            [overlap.name, 'shelter'],
            'Shelter cannot cleanse existing debuff',
          );
          final capture = ChessMoveAction(move('e2e4'));
          if (overlap == PieceEffectType.slow) {
            shelterCheck(
              BattleRulesCore.isLegalAction(cast.view(side), capture),
              'Two-square slow capture is legal despite overlap',
            );
          } else {
            shelterReject(cast, capture);
          }
          final quiet = ChessMoveAction(move('e2e3'));
          if (overlap == PieceEffectType.freeze) {
            shelterReject(cast, quiet);
          } else {
            final moved = DeckManager.apply(cast, quiet);
            shelterEqual(
              moved.rules.pieceEffects.map((e) => e.type.name).toList(),
              ['shelter'],
              'Existing restriction consumes on proper move only',
            );
            shelterEqual(
              shelterEffects(moved).single.pieceId,
              state.rules.pieceIds[q('e2')],
              'Protection follows quiet mover',
            );
          }
        },
      );
    }

    yield ShelterAuditCase(
      '$tag/slow-range-is-not-increased-by-protection',
      () {
        var state = shelterScenario(
          side: side,
          fen: '7k/8/8/8/8/8/4R3/K7 w - - 0 12',
        );
        state = shelterEdit(
          state,
          (d) => d.pieceEffects.add(
            shelterDebuff(d, side, q('e2'), PieceEffectType.slow),
          ),
        );
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: q('e2')),
        );
        shelterCheck(
          BattleRulesCore.isLegalAction(
            cast.view(side),
            ChessMoveAction(move('e2e4')),
          ),
          'Exactly two squares stays legal',
        );
        shelterReject(cast, ChessMoveAction(move('e2e5')));
      },
    );

    yield ShelterAuditCase('$tag/old-hunt-still-pays-for-ordinary-capture', () {
      var state = shelterScenario(
        side: side,
        fen: '3r3k/8/8/8/8/8/3R4/K7 w - - 0 12',
      );
      final victim = state.rules.pieceIds[q('d2')];
      state = shelterEdit(state, (d) {
        d.mana[side.opposite] = 0;
        d.vows.add(
          VowState(
            id: 'preexisting-hunt',
            type: VowType.hunt,
            owner: side.opposite,
            pieceId: victim,
            square: null,
            remainingMoves: 2,
          ),
        );
      });
      var next = shelterCastAndMove(state, side);
      shelterEqual(
        next.rules.vows.single.pieceId,
        victim,
        'Protection is not retroactive vow cancellation',
      );
      next = DeckManager.apply(next, const PassAction());
      next = DeckManager.apply(next, ChessMoveAction(move('d8d6')));
      shelterEqual(
        next.rules.mana[side.opposite],
        3,
        'One turn income plus old Hunt two-mana reward',
      );
      shelterCheck(
        !next.rules.pieceIds.contains(victim),
        'Protected victim captured',
      );
      shelterCheck(next.rules.vows.isEmpty, 'Paying Hunt is consumed');
      shelterCheck(
        next.rules.pieceEffects.isEmpty,
        'No orphaned Shelter after capture',
      );
    });

    yield ShelterAuditCase(
      '$tag/angry-knight-capture-is-not-a-direct-card-target',
      () {
        var state = shelterScenario(
          side: side,
          fen: '7k/8/4n3/8/8/8/3R4/K7 w - - 0 12',
          enemyHand: [CardId.angryN],
        );
        final victim = state.rules.pieceIds[q('d2')];
        state = shelterEdit(state, (d) {
          d.mana[side.opposite] = 0;
          d.vows.add(
            VowState(
              id: 'prior-hunt',
              type: VowType.hunt,
              owner: side.opposite,
              pieceId: victim,
              square: null,
              remainingMoves: 2,
            ),
          );
        });
        var next = shelterCastAndMove(state, side);
        next = shelterEdit(next, (d) => d.mana[side.opposite] = 6);
        next = DeckManager.apply(
          next,
          PlayCardAction(CardId.angryN, target: q('e6')),
        );
        shelterCheck(
          shelterEffects(next).isEmpty,
          'Movement card completes enemy card window before the capture',
        );
        shelterCheck(
          next.rules.special!.moves.contains(move('e6d6')),
          'Authorized orthogonal capture targets the occupied chess square',
        );
        final after = DeckManager.apply(next, ChessMoveAction(move('e6d6')));
        shelterCheck(
          !after.rules.pieceIds.contains(victim),
          'Special capture succeeds',
        );
        shelterEqual(
          after.rules.mana[side.opposite],
          3,
          'Special capture cannot pay existing Hunt reward',
        );
        shelterCheck(after.rules.vows.isEmpty, 'Captured Hunt still removed');
      },
    );

    yield ShelterAuditCase(
      '$tag/shelter-cast-is-independent-of-opponent-secrets',
      () {
        final state = shelterScenario(side: side);
        final enemy = side.opposite;
        final pool = [
          ...state.hidden.hands[enemy]!,
          ...state.hidden.decks[enemy]!,
        ];
        final altered = AuthoritativeBattleState(
          state.rules,
          AuthoritativeHiddenState(
            hands: {
              ...state.hidden.hands,
              enemy: pool.reversed.take(4).toList(),
            },
            decks: {
              ...state.hidden.decks,
              enemy: pool.reversed.skip(4).toList(),
            },
            knowledge: {
              ...state.hidden.knowledge,
              enemy: PlayerKnowledgeState(
                knownUpcomingCards: pool.reversed.skip(4).take(2).toList(),
              ),
            },
          ),
        );
        shelterEqual(
          state.view(side).toJson(),
          altered.view(side).toJson(),
          'Actor view cannot reveal alternate enemy hand or deck order',
        );
        final action = PlayCardAction(CardId.shelter, target: q('d2'));
        final originalCast = DeckManager.apply(state, action);
        final alternateCast = DeckManager.apply(altered, action);
        shelterEqual(
          originalCast.view(side).toJson(),
          alternateCast.view(side).toJson(),
          'Shelter output cannot depend on opponent private contents',
        );
        shelterEqual(
          alternateCast.hidden.knowledge[enemy]!.toJson(),
          altered.hidden.knowledge[enemy]!.toJson(),
          'Shelter must not alter enemy knowledge',
        );
        shelterEqual(
          alternateCast.hidden.decks[enemy],
          altered.hidden.decks[enemy],
          'Shelter must not inspect or reorder enemy deck',
        );
        shelterEqual(
          alternateCast.hidden.hands[enemy],
          altered.hidden.hands[enemy],
          'Shelter must not touch enemy hand',
        );
      },
    );

    for (final pending in [CardId.prophecy, CardId.fateExchange]) {
      yield ShelterAuditCase(
        '$tag/${pending.wire}-private-resolution-no-leak',
        () {
          final state = shelterCastAndMove(
            shelterScenario(side: side, enemyHand: [pending, CardId.radar]),
            side,
          );
          final enemy = side.opposite;
          final entered = DeckManager.apply(
            state,
            PlayCardAction(
              pending,
              sacrifice: pending == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          shelterCheck(
            entered.view(side).knowledge.pendingCards.isEmpty,
            'Shield owner cannot see enemy inspected cards',
          );
          shelterCheck(
            entered.view(side).knowledge.knownUpcomingCards.isEmpty,
            'Shield owner cannot see enemy deck order',
          );
          shelterCheck(
            BattleRulesCore.legalActions(entered.view(side)).isEmpty,
            'Shield owner has no enemy resolution action',
          );
          final choices =
              BattleRulesCore.legalActions(
                entered.view(enemy),
              ).whereType<ResolveAction>().toList();
          shelterEqual(
            choices.length,
            pending == CardId.prophecy ? 2 : 6,
            'Enumerate every private resolution branch',
          );
          for (final action in choices) {
            final resolved = DeckManager.apply(entered, action);
            shelterCheck(
              shelterEffects(resolved).isEmpty,
              'Every private order closes original protection window',
            );
            shelterCheck(
              resolved.view(side).knowledge.pendingCards.isEmpty,
              'Private order leaked after resolution',
            );
            shelterCheck(
              resolved.view(side).knowledge.knownUpcomingCards.isEmpty,
              'Upcoming order leaked after resolution',
            );
            shelterEqual(
              resolved.hidden.hands[side],
              entered.hidden.hands[side],
              'Enemy resolution cannot modify shield owner hand',
            );
          }
        },
      );
    }

    yield ShelterAuditCase(
      '$tag/presentation-tracker-retains-shield-cast-before-move',
      () {
        final state = shelterScenario(side: side);
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: q('d2')),
        );
        final moved = DeckManager.apply(cast, ChessMoveAction(move('d2d6')));
        final expired = DeckManager.apply(moved, const PassAction());
        final tracker =
            BattlePresentationTracker()..observe(state.view(side), 20);
        tracker.observe(cast.view(side), 21);
        tracker.observe(moved.view(side), 22);
        tracker.observe(expired.view(side), 23);
        shelterEqual(
          tracker.frames.length,
          3,
          'Three independent accepted deltas',
        );
        shelterEqual(
          shelterEffects(
            AuthoritativeBattleState(
              tracker.frames.first.after.rules,
              cast.hidden,
            ),
          ).single.pieceId,
          state.rules.pieceIds[q('d2')],
          'Retained cast identifies target',
        );
        shelterEqual(
          tracker.frames.first.after.rules.pieceIds[q('d2')],
          state.rules.pieceIds[q('d2')],
          'Cast frame retains original square',
        );
        shelterEqual(
          tracker.frames[1].after.rules.pieceIds[q('d6')],
          state.rules.pieceIds[q('d2')],
          'Move frame retains destination',
        );
        shelterCheck(
          tracker.frames.last.after.rules.pieceEffects.isEmpty,
          'Expiry is not confused with a second cast',
        );
        tracker.observe(expired.view(side), 23);
        shelterEqual(tracker.frames.length, 3, 'Same version does not replay');
        tracker.observe(expired.view(side), 23, epoch: 1);
        shelterCheck(tracker.frames.isEmpty, 'Reconnect clears cast history');
      },
    );

    for (final promotion in ['q', 'r', 'b', 'n']) {
      yield ShelterAuditCase('$tag/$promotion-promotion-capture-onto-mine', () {
        var state = shelterScenario(
          side: side,
          fen: 'r6k/1P6/8/8/8/8/8/K7 w - - 0 12',
        );
        final identity = state.rules.pieceIds[q('b7')];
        state = shelterEdit(
          state,
          (d) => d.boardEffects.add(
            BoardEffectInstance(
              id: 'promotion-mine',
              type: BoardEffectType.mine,
              owner: side.opposite,
              squares: [q('a8')],
              responseSide: side,
              duration: EffectDuration.persistent,
            ),
          ),
        );
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: q('b7')),
        );
        final next = DeckManager.apply(
          cast,
          ChessMoveAction(move('b7a8$promotion')),
        );
        shelterEqual(
          next.rules.pieceIds[q('a8')],
          identity,
          'Capture promotion preserves protected pawn identity',
        );
        shelterEqual(
          next.rules.board.pieceAt(q('a8'))!.type.name,
          {'q': 'queen', 'r': 'rook', 'b': 'bishop', 'n': 'knight'}[promotion],
          'Promotion type follows explicit request',
        );
        shelterEqual(next.rules.pieceEffects.map((e) => e.type.name).toList(), [
          'shelter',
          'mineDebuff',
        ], 'Mine triggers on promotion arrival');
        shelterCheck(next.rules.boardEffects.isEmpty, 'Arrival mine consumed');
        for (final card in direct) {
          shelterCheck(
            !BattleRulesCore.cardTargets(
              next.view(side.opposite),
              card,
            ).contains(q('a8')),
            'Promoted identity remains protected',
          );
        }
        final closed = DeckManager.apply(next, const PassAction());
        shelterEqual(
          closed.rules.pieceEffects.single.type.name,
          'mineDebuff',
          'Shield expiry must preserve promotion Mine debuff',
        );
        shelterEqual(
          BattleRulesCore.cardTargets(
            closed.view(side.opposite),
            CardId.slow,
          ).contains(q('a8')),
          promotion != 'n',
          'Post-expiry Slow eligibility uses current promoted type',
        );
      });
    }

    yield ShelterAuditCase(
      '$tag/legal-en-passant-right-survives-card-cast',
      () {
        var state = shelterScenario(
          side: side,
          fen: '7k/8/8/3pP3/8/8/8/K7 w - d6 0 12',
        );
        final id = state.rules.pieceIds[q('e5')];
        final victim = state.rules.pieceIds[q('d5')];
        state = shelterEdit(
          state,
          (d) => d.boardEffects.add(
            BoardEffectInstance(
              id: 'ep-mine',
              type: BoardEffectType.mine,
              owner: side.opposite,
              squares: [q('d6')],
              responseSide: side,
              duration: EffectDuration.persistent,
            ),
          ),
        );
        final cast = DeckManager.apply(
          state,
          PlayCardAction(CardId.shelter, target: q('e5')),
        );
        shelterEqual(
          cast.rules.board.enPassant,
          q('d6'),
          'Card use is not a chess ply and must preserve EP rights',
        );
        final moved = DeckManager.apply(cast, ChessMoveAction(move('e5d6')));
        shelterEqual(
          moved.rules.pieceIds[q('d6')],
          id,
          'Sheltered EP attacker follows',
        );
        shelterCheck(
          !moved.rules.pieceIds.contains(victim),
          'EP victim removed',
        );
        shelterEqual(
          moved.rules.pieceIds[q('d5')],
          null,
          'EP capture square cleared',
        );
        shelterEqual(
          moved.rules.pieceEffects.map((e) => e.type.name).toList(),
          ['shelter', 'mineDebuff'],
          'Shelter does not prevent EP arrival Mine',
        );
      },
    );

    yield ShelterAuditCase('$tag/pinned-en-passant-remains-illegal', () {
      final state = shelterScenario(
        side: side,
        fen: '4r2k/8/8/3pP3/8/8/8/4K3 w - d6 0 12',
      );
      final cast = DeckManager.apply(
        state,
        PlayCardAction(CardId.shelter, target: q('e5')),
      );
      shelterEqual(
        cast.rules.board.enPassant,
        q('d6'),
        'EP opportunity retained',
      );
      shelterReject(cast, ChessMoveAction(move('e5d6')));
      final escaped = DeckManager.apply(cast, ChessMoveAction(move('e1d1')));
      shelterEqual(
        shelterEffects(escaped).single.pieceId,
        state.rules.pieceIds[q('e5')],
        'King move does not consume Shield',
      );
      shelterEqual(
        escaped.rules.board.enPassant,
        null,
        'Real chess move, not Shelter, ends EP opportunity',
      );
    });

    yield ShelterAuditCase('$tag/board-seal-stops-quiet-entry-not-capture', () {
      final state = shelterScenario(
        side: side,
        fen: '7k/3p4/8/8/8/8/3R4/K7 w - - 0 12',
        enemyHand: [CardId.boardSeal],
      );
      var next = shelterCastAndMove(state, side);
      next = DeckManager.apply(
        next,
        PlayCardAction(CardId.boardSeal, target: q('d6')),
      );
      shelterCheck(
        shelterEffects(next).isEmpty,
        'Seal closes protection window',
      );
      next = DeckManager.apply(next, ChessMoveAction(move('h8h7')));
      next = DeckManager.apply(next, const PassAction());
      shelterReject(next, ChessMoveAction(move('d6e6')));
      shelterCheck(
        BattleRulesCore.isLegalAction(
          next.view(side),
          ChessMoveAction(move('d6d7')),
        ),
        'Occupied sealed square remains capturable',
      );
      final captured = DeckManager.apply(next, ChessMoveAction(move('d6d7')));
      shelterCheck(
        captured.rules.boardEffects.isEmpty,
        'Next owner chess move consumes Seal independently of expired Shelter',
      );
    });

    yield ShelterAuditCase('$tag/break-seal-cannot-select-piece-shield', () {
      var state = shelterScenario(side: side, enemyHand: [CardId.breakSeal]);
      state = shelterEdit(
        state,
        (d) => d.boardEffects.add(
          BoardEffectInstance(
            id: 'old-own-mine',
            type: BoardEffectType.mine,
            owner: side,
            squares: [q('c4')],
            responseSide: side.opposite,
            duration: EffectDuration.persistent,
          ),
        ),
      );
      final moved = shelterCastAndMove(state, side);
      final shield = shelterEffects(moved).single;
      shelterEqual(
        BattleRulesCore.cardTargets(
          moved.view(side.opposite),
          CardId.breakSeal,
        ),
        ['old-own-mine'],
        'Removal lists board effects only',
      );
      shelterReject(moved, PlayCardAction(CardId.breakSeal, target: shield.id));
      final removed = DeckManager.apply(
        moved,
        const PlayCardAction(CardId.breakSeal, target: 'old-own-mine'),
      );
      shelterCheck(removed.rules.boardEffects.isEmpty, 'Selected Mine removed');
      shelterCheck(
        shelterEffects(removed).isEmpty,
        'Shield expires at window closure, not because it was selected',
      );
    });
  }
}

Iterable<ShelterAuditCase> shelterMechanicEdgeCases() sync* {
  for (final side in PieceColor.values) {
    final tag = side.name;
    int q(String text) => shelterSquare(text, side);
    String move(String text) => shelterMove(text, side);

    for (final ending in [
      (
        name: 'mate-takes-priority-over-75-moves',
        fen: '7k/8/5KQ1/8/8/8/8/8 w - - 149 40',
        target: 'g6',
        uci: 'g6g7',
        reason: 'checkmate',
      ),
      (
        name: 'stalemate-is-not-a-live-card-window',
        fen: '7k/8/5K2/6Q1/8/8/8/8 w - - 12 40',
        target: 'g5',
        uci: 'g5g6',
        reason: 'stalemate',
      ),
      (
        name: '75-move-draw-does-not-draw-a-card',
        fen: '7k/8/8/8/8/8/3R4/K7 w - - 149 40',
        target: 'd2',
        uci: 'd2d6',
        reason: 'seventy_five_moves',
      ),
    ]) {
      yield ShelterAuditCase('$tag/${ending.name}', () {
        final start = shelterScenario(side: side, fen: ending.fen);
        final cast = DeckManager.apply(
          start,
          PlayCardAction(CardId.shelter, target: q(ending.target)),
        );
        final id = shelterEffects(cast).single.pieceId;
        final next = shelterRoundTrip(
          DeckManager.apply(cast, ChessMoveAction(move(ending.uci))),
        );
        shelterEqual(
          next.rules.phase.name,
          'terminal',
          'Shelter cannot leave a finished game waiting for a card choice',
        );
        shelterEqual(
          next.rules.terminal!.reason,
          ending.reason,
          'Actual chess result takes priority over a live protection window',
        );
        shelterEqual(
          next.rules.terminal!.winner,
          ending.reason == 'checkmate' ? side : null,
          'Terminal winner',
        );
        shelterCheck(
          !next.rules.terminal!.mateByRestriction &&
              !next.rules.terminal!.mateBySpecialMove &&
              !next.rules.terminal!.stalemateByRestriction,
          'Pure protection cannot label an orthodox result as a restriction',
        );
        shelterEqual(
          next.rules.handCounts,
          cast.rules.handCounts,
          'Terminal move must not draw',
        );
        shelterEqual(
          next.rules.deckCounts,
          cast.rules.deckCounts,
          'Terminal move must not consume a hidden deck card',
        );
        shelterEqual(
          next.rules.drawCounts,
          cast.rules.drawCounts,
          'Terminal move does not change cumulative draws',
        );
        shelterEqual(
          next.rules.ownTurns,
          cast.rules.ownTurns,
          'No next turn starts after game end',
        );
        shelterEqual(
          shelterEffects(next).single.pieceId,
          id,
          'Unclosed terminal protection remains on the original identity',
        );
        shelterEqual(
          next.rules.ply,
          cast.rules.ply + 1,
          'Exactly one chess ply',
        );
        for (final viewer in PieceColor.values) {
          shelterCheck(
            BattleRulesCore.legalActions(next.view(viewer)).isEmpty,
            'Neither player has a continuation after game end',
          );
          shelterEqual(
            BattleRulesCore.chooseBotAction(next.view(viewer)),
            null,
            'Bot cannot invent a card-window action after game end',
          );
        }
        shelterReject(next, const PassAction());
      });
    }

    for (final pending in [CardId.prophecy, CardId.fateExchange]) {
      for (final remaining in [1, 2]) {
        yield ShelterAuditCase(
          '$tag/${pending.wire}-deck-tail-$remaining-has-finite-resolution',
          () {
            final responder = side.opposite;
            var state = shelterScenario(
              side: side,
              enemyHand: [pending, CardId.radar],
            );
            final deck = state.hidden.decks[responder]!;
            final keep = deck.take(remaining).toList();
            final draft = RuleDraft(state.rules);
            draft.discarded[responder]!.addAll(deck.skip(remaining));
            draft.discarded[responder]!.sort(
              (a, b) => a.wire.compareTo(b.wire),
            );
            draft.deckCounts[responder] = remaining;
            draft.drawCounts[responder] = 10 - remaining;
            draft.ownTurns[responder] = 12;
            state = AuthoritativeBattleState(
              draft.freeze(),
              AuthoritativeHiddenState(
                hands: state.hidden.hands,
                decks: {...state.hidden.decks, responder: keep},
                knowledge: state.hidden.knowledge,
              ),
            );
            state = shelterCastAndMove(state, side);
            final shieldId = shelterEffects(state).single.id;
            final beforeDeck = state.rules.deckCounts[responder]!;
            final beforeDraws = state.rules.drawCounts[responder]!;
            final beforeHand = state.rules.handCounts[responder]!;
            final entered = shelterRoundTrip(
              DeckManager.apply(
                state,
                PlayCardAction(
                  pending,
                  sacrifice:
                      pending == CardId.fateExchange ? CardId.radar : null,
                ),
              ),
            );
            shelterEqual(
              entered.rules.phase.name,
              'pending',
              'Private choice phase',
            );
            shelterEqual(
              shelterEffects(entered).single.id,
              shieldId,
              'Inspecting a short deck is not closing the card window',
            );
            shelterEqual(
              entered.hidden.knowledge[responder]!.pendingCards,
              keep,
              'Only the remaining deck cards are inspected',
            );
            shelterCheck(
              entered.view(side).knowledge.pendingCards.isEmpty,
              'Opponent cannot see the inspected tail',
            );
            shelterCheck(
              BattleRulesCore.legalActions(entered.view(side)).isEmpty,
              'Non-owner cannot resolve the private phase',
            );
            final choices =
                BattleRulesCore.legalActions(
                  entered.view(responder),
                ).whereType<ResolveAction>().toList();
            shelterEqual(
              choices.length,
              remaining,
              'One/two-card tail exposes exactly one/two finite resolutions',
            );
            shelterCheck(
              BattleRulesCore.chooseBotAction(entered.view(responder))
                  is ResolveAction,
              'Bot has a legal pending continuation',
            );
            shelterReject(entered, ResolveAction([]));
            shelterEqual(
              shelterEffects(entered).single.id,
              shieldId,
              'Rejected incomplete choice cannot consume the shield',
            );
            for (final choice in choices) {
              final resolved = shelterRoundTrip(
                DeckManager.apply(entered, choice),
              );
              final exchange = pending == CardId.fateExchange;
              shelterEqual(
                resolved.rules.phase.name,
                'chess',
                'Resolution returns to a live chess phase',
              );
              shelterCheck(
                resolved.rules.pending == null &&
                    shelterEffects(resolved).isEmpty,
                'Pending owner and shield window close together',
              );
              shelterCheck(
                resolved.hidden.knowledge[responder]!.pendingCards.isEmpty,
                'Resolution clears inspected private cards',
              );
              shelterEqual(
                resolved.rules.deckCounts[responder],
                beforeDeck - (exchange ? 1 : 0),
                'Exactly one exchange deck debit',
              );
              shelterEqual(
                resolved.rules.drawCounts[responder],
                beforeDraws + (exchange ? 1 : 0),
                'Exactly one exchange draw',
              );
              shelterEqual(
                resolved.rules.handCounts[responder],
                beforeHand - 1,
                'Exact post-choice hand count',
              );
              shelterEqual(
                resolved.hidden.decks[responder],
                choice.order,
                'Exhausted inspected tail has no phantom deck suffix',
              );
              shelterCheck(
                BattleRulesCore.legalActions(
                  resolved.view(responder),
                ).whereType<ChessMoveAction>().isNotEmpty,
                'A legal real move remains after private resolution',
              );
              final moved = DeckManager.apply(
                resolved,
                ChessMoveAction(move('h8h7')),
              );
              shelterEqual(
                moved.rules.board.turn,
                side,
                'Responder completes its real chess turn',
              );
              shelterEqual(
                moved.rules.phase.name,
                'card',
                'Next player receives a usable card window',
              );
              shelterEqual(
                moved.hidden.hands[responder]!.length,
                resolved.hidden.hands[responder]!.length +
                    (resolved.rules.deckCounts[responder]! > 0 ? 1 : 0),
                'Empty deck cannot create a card or strand the move',
              );
            }
          },
        );
      }
    }

    for (final card in [CardId.chain, CardId.slow, CardId.freeze]) {
      yield ShelterAuditCase(
        '$tag/${card.wire}-works-after-complete-shield-cycle',
        () {
          final start = shelterScenario(
            side: side,
            fen: '7k/3p4/8/8/8/8/3R4/K7 w - - 0 12',
            enemyHand: [card, CardId.radar],
          );
          final id = start.rules.pieceIds[q('d2')]!;
          var next = shelterCastAndMove(start, side);
          next = DeckManager.apply(next, const PassAction());
          next = DeckManager.apply(next, ChessMoveAction(move('h8h7')));
          next = DeckManager.apply(next, const PassAction());
          next = DeckManager.apply(next, ChessMoveAction(move('d6d5')));
          shelterCheck(
            shelterEffects(next).isEmpty,
            'Shield does not reappear on a new card window or piece move',
          );
          shelterEqual(
            next.rules.pieceIds[q('d5')],
            id,
            'The later hostile card targets the same original identity',
          );
          next = DeckManager.apply(next, PlayCardAction(card, target: q('d5')));
          shelterEqual(
            next.rules.pieceEffects.single.pieceId,
            id,
            'A later direct cast applies to the formerly protected identity',
          );
          shelterEqual(
            next.rules.pieceEffects.single.type.name,
            card.wire,
            'Only the new independent restriction is active',
          );
          next = DeckManager.apply(next, ChessMoveAction(move('h7h8')));
          next = DeckManager.apply(next, const PassAction());
          final forbidden = switch (card) {
            CardId.chain => 'd5d7',
            CardId.slow => 'd5d2',
            _ => 'd5d6',
          };
          shelterReject(next, ChessMoveAction(move(forbidden)));
          final allowed = card == CardId.freeze ? 'a1b1' : 'd5d6';
          next = shelterRoundTrip(
            DeckManager.apply(next, ChessMoveAction(move(allowed))),
          );
          shelterCheck(
            next.rules.pieceEffects.isEmpty,
            'Later restriction consumes on its response move without revival',
          );
          shelterEqual(
            next.rules.used[side],
            [CardId.shelter],
            'Original shield is spent once, not replayed by lifecycle changes',
          );
          shelterEqual(next.rules.used[side.opposite], [
            card,
          ], 'Later restriction is spent once');
        },
      );
    }

    yield ShelterAuditCase(
      '$tag/later-hunt-on-former-shield-pays-normal-capture',
      () {
        final start = shelterScenario(
          side: side,
          fen: '3r3k/8/8/8/8/8/3R4/K7 w - - 0 12',
          enemyHand: [CardId.huntVow, CardId.radar],
        );
        final id = start.rules.pieceIds[q('d2')]!;
        var next = shelterCastAndMove(start, side);
        next = DeckManager.apply(next, const PassAction());
        next = DeckManager.apply(next, ChessMoveAction(move('h8h7')));
        next = DeckManager.apply(next, const PassAction());
        next = DeckManager.apply(next, ChessMoveAction(move('d6d5')));
        next = DeckManager.apply(
          next,
          PlayCardAction(CardId.huntVow, target: q('d5')),
        );
        shelterCheck(
          shelterEffects(next).isEmpty,
          'Old shield is not a Hunt counter',
        );
        shelterEqual(
          next.rules.vows.single.pieceId,
          id,
          'Hunt binds moved identity',
        );
        next = DeckManager.apply(next, ChessMoveAction(move('h7h8')));
        shelterEqual(
          next.rules.vows.single.remainingMoves,
          1,
          'Hunt owner first normal move spends one opportunity',
        );
        next = DeckManager.apply(next, const PassAction());
        next = DeckManager.apply(next, ChessMoveAction(move('a1b1')));
        next = DeckManager.apply(next, const PassAction());
        final beforeMana = next.rules.mana[side.opposite]!;
        shelterEqual(
          beforeMana,
          5,
          'Independent mana timeline before marked capture',
        );
        next = shelterRoundTrip(
          DeckManager.apply(next, ChessMoveAction(move('d8d5'))),
        );
        shelterCheck(
          !next.rules.pieceIds.contains(id),
          'Marked identity captured',
        );
        shelterCheck(
          next.rules.vows.isEmpty,
          'Captured Hunt target removes its vow',
        );
        shelterEqual(
          next.rules.mana[side.opposite],
          6,
          'Ordinary capture earns +2 with the normal six-mana cap',
        );
        shelterCheck(
          next.rules.pieceEffects.isEmpty,
          'Neither the former shield nor an orphan effect survives capture',
        );
      },
    );

    for (final pending in [CardId.prophecy, CardId.fateExchange]) {
      yield ShelterAuditCase(
        '$tag/full-hands-${pending.wire}-inventory-and-continuation',
        () {
          final responder = side.opposite;
          final start = shelterScenario(
            side: side,
            ownHand: [CardId.shelter, CardId.purify, CardId.chain, CardId.slow],
            enemyHand: [pending, CardId.radar, CardId.freeze, CardId.mine],
          );
          final cast = DeckManager.apply(
            start,
            PlayCardAction(CardId.shelter, target: q('d2')),
          );
          shelterEqual(
            cast.rules.handCounts[side],
            3,
            'Shield spends one full-hand card',
          );
          shelterEqual(
            cast.rules.deckCounts[side],
            6,
            'Card cast does not draw',
          );
          var next = DeckManager.apply(cast, ChessMoveAction(move('d2d6')));
          shelterEqual(
            next.rules.handCounts[side],
            4,
            'Real move refills to four',
          );
          shelterEqual(
            next.rules.deckCounts[side],
            5,
            'Exactly one actual refill',
          );
          final shieldId = shelterEffects(next).single.id;
          next = DeckManager.apply(
            next,
            PlayCardAction(
              pending,
              sacrifice: pending == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          shelterEqual(
            next.rules.handCounts[responder],
            pending == CardId.fateExchange ? 2 : 3,
            'Exact cast/sacrifice debit',
          );
          shelterEqual(
            shelterEffects(next).single.id,
            shieldId,
            'A full hand does not skip the pending Shield window',
          );
          final selected =
              BattleRulesCore.legalActions(
                next.view(responder),
              ).whereType<ResolveAction>().first;
          next = DeckManager.apply(next, selected);
          shelterEqual(
            next.rules.handCounts[responder],
            3,
            'Resolution never overfills the hand',
          );
          shelterCheck(
            shelterEffects(next).isEmpty,
            'Completed private choice expires Shield',
          );
          next = shelterRoundTrip(
            DeckManager.apply(next, ChessMoveAction(move('h8h7'))),
          );
          shelterEqual(
            next.rules.handCounts[responder],
            4,
            'Responder chess move refills exactly to the hand cap',
          );
          shelterEqual(
            next.rules.deckCounts[responder],
            pending == CardId.fateExchange ? 4 : 5,
            'Exchange and refill debits stay separate',
          );
          for (final color in PieceColor.values) {
            final all = [
              ...next.hidden.hands[color]!,
              ...next.hidden.decks[color]!,
              ...next.rules.used[color]!,
              ...next.rules.discarded[color]!,
            ];
            shelterEqual(all.length, 10, 'No card lost at hand cap');
            shelterEqual(
              all.toSet().length,
              10,
              'No card duplicated at hand cap',
            );
            shelterEqual(
              next.hidden.hands[color]!.length,
              next.rules.handCounts[color],
              'Public hand count stays authoritative',
            );
          }
          shelterCheck(
            BattleRulesCore.legalActions(
              next.view(side),
            ).any((a) => a is PassAction),
            'Next side has an actionable card turn',
          );
        },
      );
    }

    yield ShelterAuditCase('$tag/repetition-distinguishes-live-protection', () {
      final start = shelterScenario(side: side);
      final cast = DeckManager.apply(
        start,
        PlayCardAction(CardId.shelter, target: q('d2')),
      );
      shelterEqual(
        cast.rules.repetitions,
        start.rules.repetitions,
        'Shelter is not a chess ply or a stable repetition boundary',
      );
      final next = DeckManager.apply(cast, ChessMoveAction(move('d2d6')));
      final key = BattleRulesCore.publicFingerprint(next.rules);
      shelterEqual(
        next.rules.repetitions[key],
        1,
        'Exactly one stable boundary is recorded after the real move',
      );
      final unprotected = shelterEdit(
        next,
        (d) => d.pieceEffects.removeWhere(
          (e) => e.type == PieceEffectType.shelter,
        ),
      );
      shelterCheck(
        BattleRulesCore.publicFingerprint(unprotected.rules) != key,
        'A targetable piece and its protected identity are not equivalent positions',
      );
      shelterCheck(
        !BattleRulesCore.isLegalAction(
          next.view(side.opposite),
          PlayCardAction(CardId.chain, target: q('d6')),
        ),
        'Protected repetition state excludes the concrete hostile action',
      );
      shelterCheck(
        BattleRulesCore.isLegalAction(
          unprotected.view(side.opposite),
          PlayCardAction(CardId.chain, target: q('d6')),
        ),
        'Unprotected comparison actually has different legal card choices',
      );
      final expired = DeckManager.apply(next, const PassAction());
      shelterEqual(
        expired.rules.repetitions,
        next.rules.repetitions,
        'Closing a card window does not invent a chess repetition',
      );
      shelterCheck(
        expired.rules.terminal == null,
        'Shield expiry is not a false draw',
      );
    });
  }
}
