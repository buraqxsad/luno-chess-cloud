import 'dart:math' as math;
import '../engine/board.dart';
import '../engine/piece.dart';
import 'core.dart';
import 'model.dart';

class AuthoritativeHiddenState {
  final Map<PieceColor, List<CardId>> hands, decks;
  final Map<PieceColor, PlayerKnowledgeState> knowledge;
  AuthoritativeHiddenState({
    required Map<PieceColor, List<CardId>> hands,
    required Map<PieceColor, List<CardId>> decks,
    required Map<PieceColor, PlayerKnowledgeState> knowledge,
  }) : hands = Map.unmodifiable({
         for (final c in PieceColor.values)
           c: List<CardId>.unmodifiable(hands[c]!),
       }),
       decks = Map.unmodifiable({
         for (final c in PieceColor.values)
           c: List<CardId>.unmodifiable(decks[c]!),
       }),
       knowledge = Map.unmodifiable(knowledge);
  factory AuthoritativeHiddenState.fromJson(Map j) => AuthoritativeHiddenState(
    hands: parsePair(j['hands'] as Map, parseCards),
    decks: parsePair(j['decks'] as Map, parseCards),
    knowledge: parsePair(
      j['knowledge'] as Map,
      (v) => PlayerKnowledgeState.fromJson(v as Map),
    ),
  );
  Map<String, Object?> toJson() => {
    'hands': pairJson(hands, (v) => v.map((c) => c.wire).toList()),
    'decks': pairJson(decks, (v) => v.map((c) => c.wire).toList()),
    'knowledge': pairJson(knowledge, (v) => v.toJson()),
  };
}

class AuthoritativeBattleState {
  final RuleState rules;
  final AuthoritativeHiddenState hidden;
  const AuthoritativeBattleState(this.rules, this.hidden);
  factory AuthoritativeBattleState.fromJson(Map j) => AuthoritativeBattleState(
    RuleState.fromJson(j['rules'] as Map),
    AuthoritativeHiddenState.fromJson(j['hidden'] as Map),
  );
  PlayerView view(PieceColor side) =>
      PlayerView(rules, side, hidden.hands[side]!, hidden.knowledge[side]!);
  Map<String, Object?> toJson() => {
    'rules': rules.toJson(),
    'hidden': hidden.toJson(),
  };
}

/// Fully local/server authority, separate from redacted legality and bot planning.
class DeckManager {
  static AuthoritativeBattleState newBattle({
    List<CardId> white = starterDeck,
    List<CardId> black = starterDeck,
    Board? board,
  }) {
    validateDeck(white);
    validateDeck(black);
    final initial = board ?? Board.start();
    if (initial.squares.length != 64 ||
        initial.halfmoveClock < 0 ||
        initial.fullmoveNumber < 1 ||
        initial.castling < 0 ||
        initial.castling > 15 ||
        PieceColor.values.any(
          (color) =>
              initial.squares
                  .where((p) => p?.color == color && p?.type == PieceType.king)
                  .length !=
              1,
        ) ||
        [
          ...initial.squares.take(8),
          ...initial.squares.skip(56),
        ].any((p) => p?.type == PieceType.pawn)) {
      throw ArgumentError('invalid-initial-board');
    }
    String symbol(Piece p) {
      final type =
          const {
            PieceType.pawn: 'p',
            PieceType.knight: 'n',
            PieceType.bishop: 'b',
            PieceType.rook: 'r',
            PieceType.queen: 'q',
            PieceType.king: 'k',
          }[p.type]!;
      return p.color == PieceColor.white ? type.toUpperCase() : type;
    }

    final state = RuleState(
      board: initial,
      pieceIds: [
        for (var i = 0; i < 64; i++)
          initial.squares[i] == null
              ? null
              : '${symbol(initial.squares[i]!)}:$i',
      ],
      movedPawns: [],
      phase: BattlePhase.chess,
      mana: {for (final c in PieceColor.values) c: 1},
      ownTurns: {
        for (final c in PieceColor.values) c: c == initial.turn ? 1 : 0,
      },
      handCounts: {for (final c in PieceColor.values) c: 3},
      deckCounts: {for (final c in PieceColor.values) c: 7},
      drawCounts: {for (final c in PieceColor.values) c: 3},
      arsenals: {
        PieceColor.white: [...white]..sort((a, b) => a.wire.compareTo(b.wire)),
        PieceColor.black: [...black]..sort((a, b) => a.wire.compareTo(b.wire)),
      },
      used: {for (final c in PieceColor.values) c: []},
      discarded: {for (final c in PieceColor.values) c: []},
      pieceEffects: [],
      boardEffects: [],
      modifiers: [],
      vows: [],
      special: null,
      pending: null,
      terminal: null,
      effectSequence: 0,
      ply: 0,
      repetitions: {},
    );
    final draft = RuleDraft(state);
    BattleRulesCore.initializeTerminal(draft);
    return AuthoritativeBattleState(
      draft.freeze(),
      AuthoritativeHiddenState(
        hands: {
          PieceColor.white: white.take(3).toList(),
          PieceColor.black: black.take(3).toList(),
        },
        decks: {
          PieceColor.white: white.skip(3).toList(),
          PieceColor.black: black.skip(3).toList(),
        },
        knowledge: {
          for (final c in PieceColor.values) c: PlayerKnowledgeState(),
        },
      ),
    );
  }

  static AuthoritativeBattleState apply(
    AuthoritativeBattleState input,
    BattleAction action,
  ) {
    final side = input.rules.board.turn,
        view = input.view(side),
        change = BattleRulesCore.transition(view, action);
    final hands = {
      for (final c in PieceColor.values) c: [...input.hidden.hands[c]!],
    };
    final decks = {
      for (final c in PieceColor.values) c: [...input.hidden.decks[c]!],
    };
    final knowledge = {...input.hidden.knowledge};
    if (action is PlayCardAction || action is DiscardAction) {
      final card =
          action is PlayCardAction
              ? action.card
              : (action as DiscardAction).card;
      if (!hands[side]!.remove(card)) {
        throw StateError('hidden-hand-inconsistent');
      }
      if (action is PlayCardAction &&
          action.sacrifice != null &&
          !hands[side]!.remove(action.sacrifice)) {
        throw StateError('hidden-sacrifice-inconsistent');
      }
    }
    if (change.radar != null) {
      final enemy = side.opposite;
      knowledge[side] = knowledge[side]!.copyWith(
        radarObservations: [
          ...knowledge[side]!.radarObservations,
          RadarObservation(
            change.radar!,
            inHand: hands[enemy]!.contains(change.radar),
            observedTurn: change.rules.ply,
            opponentCumulativeDrawCountAtObservation:
                change.rules.drawCounts[enemy]!,
          ),
        ],
      );
    }
    if (change.inspect > 0) {
      knowledge[side] = knowledge[side]!.copyWith(
        pendingCards:
            decks[side]!
                .take(math.min(change.inspect, decks[side]!.length))
                .toList(),
      );
    }
    if (action is ResolveAction) {
      final inspected = knowledge[side]!.pendingCards;
      decks[side] = [...action.order, ...decks[side]!.skip(inspected.length)];
      knowledge[side] = knowledge[side]!.copyWith(
        knownUpcomingCards: action.order,
        pendingCards: [],
      );
      if (action.selected != null) hands[side]!.add(action.selected!);
    }
    if (change.draw != null) {
      final color = change.draw!;
      if (decks[color]!.isEmpty) throw StateError('draw-state-inconsistent');
      final card = decks[color]!.removeAt(0);
      hands[color]!.add(card);
      final known = knowledge[color]!.knownUpcomingCards;
      knowledge[color] = knowledge[color]!.copyWith(
        knownUpcomingCards:
            known.isNotEmpty && known.first == card
                ? known.skip(1).toList()
                : [],
      );
    }
    for (final color in PieceColor.values) {
      final enemy = color.opposite;
      knowledge[color] = knowledge[color]!.copyWith(
        radarObservations:
            knowledge[color]!.radarObservations.map((o) {
              final stale =
                  o.inHand
                      ? (change.rules.used[enemy]!.contains(o.queriedCardId) ||
                          change.rules.discarded[enemy]!.contains(
                            o.queriedCardId,
                          ))
                      : change.rules.drawCounts[enemy]! >
                          o.opponentCumulativeDrawCountAtObservation;
              return stale ? o.asStale() : o;
            }).toList(),
      );
      if (hands[color]!.length != change.rules.handCounts[color] ||
          decks[color]!.length != change.rules.deckCounts[color]) {
        throw StateError('hidden-count-inconsistent');
      }
    }
    return AuthoritativeBattleState(
      change.rules,
      AuthoritativeHiddenState(
        hands: hands,
        decks: decks,
        knowledge: knowledge,
      ),
    );
  }
}
