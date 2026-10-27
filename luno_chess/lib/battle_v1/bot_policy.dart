import 'dart:math';

import '../engine/ai.dart';
import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/move_gen.dart';
import '../engine/piece.dart';
import 'core.dart';
import 'model.dart';

class BattleBotDecision {
  final BattleAction? action;
  final int legalCount, searchedNodes, nodeBudget;
  final Map<String, double> utilities;
  const BattleBotDecision({
    required this.action,
    required this.legalCount,
    required this.searchedNodes,
    required this.nodeBudget,
    required this.utilities,
  });
}

/// A bounded, public-information policy. No authority, hidden hand or deck is
/// accepted by this API; difficulty changes judgment, never card/chess rules.
class BattleV1BotPolicy {
  // PlayerView excludes opponent secrets; Mines and repetition history are public.
  static PlayerView planningView(PlayerView view) => view;

  static int tier(AiLevel level) => switch (level.id) {
    'bebek' => 0,
    'comez' => 1,
    'sovalye' => 2,
    'bilge' => 3,
    'usta' => 4,
    'efsane' => 5,
    _ => (level.depth - 1).clamp(0, 5),
  };

  static BattleBotDecision decide(PlayerView input, AiLevel level, Random rng) {
    final view = planningView(input);
    final legal = BattleRulesCore.legalActions(view);
    final difficulty = tier(level);
    final budget = const [0, 0, 24, 64, 128, 256][difficulty];
    if (legal.isEmpty) {
      return BattleBotDecision(
        action: null,
        legalCount: 0,
        searchedNodes: 0,
        nodeBudget: budget,
        utilities: const {},
      );
    }
    final position = _Position(view);
    final scores = <String, double>{
      for (final action in legal) action.key: position.score(action),
    };
    var nodes = 0;
    if (budget > 0 && view.rules.phase == BattlePhase.card) {
      final candidates =
          legal.whereType<PlayCardAction>().where((a) {
              return a.card != CardId.prophecy &&
                  a.card != CardId.fateExchange &&
                  scores[a.key]! > 0;
            }).toList()
            ..sort((a, b) => _compare(a, b, scores));
      final limit = const [0, 0, 4, 6, 8, 12][difficulty];
      for (final action in candidates.take(limit)) {
        if (nodes >= budget) break;
        final projected = BattleRulesCore.transition(view, action).rules;
        final search = position.followup(projected, budget - nodes);
        nodes += search.nodes;
        scores[action.key] = scores[action.key]! + search.value;
      }
    }
    final ordered = [...legal]..sort((a, b) => _compare(a, b, scores));
    BattleAction choice = ordered.first;
    final play =
        ordered
            .whereType<PlayCardAction>()
            .where((a) => scores[a.key]! > .05)
            .toList();
    if (view.rules.phase == BattlePhase.card) {
      final fallback = ordered.where((a) => a is! PlayCardAction).first;
      if (play.isEmpty || rng.nextDouble() >= level.cardUseRate.clamp(0, 1)) {
        choice = fallback;
      } else {
        final noise = const [3.0, 1.8, .9, .45, .18, .04][difficulty];
        final noisy = <String, double>{
          for (final action in play)
            action.key:
                scores[action.key]! + (rng.nextDouble() * 2 - 1) * noise,
        };
        play.sort((a, b) => _compare(a, b, noisy));
        choice = play.first;
      }
    }
    return BattleBotDecision(
      action: choice,
      legalCount: legal.length,
      searchedNodes: nodes,
      nodeBudget: budget,
      utilities: Map.unmodifiable(scores),
    );
  }

  static int _compare(
    BattleAction a,
    BattleAction b,
    Map<String, double> scores,
  ) {
    final order = scores[b.key]!.compareTo(scores[a.key]!);
    return order != 0 ? order : a.key.compareTo(b.key);
  }
}

double _value(PieceType? type) => switch (type) {
  PieceType.pawn => 1,
  PieceType.knight => 3.2,
  PieceType.bishop => 3.3,
  PieceType.rook => 5,
  PieceType.queen => 9,
  PieceType.king => 20,
  null => 0,
};

class _Position {
  final PlayerView view;
  late final RuleState rules = view.rules;
  late final PieceColor side = view.viewer, enemy = side.opposite;
  late final Board board = rules.board;
  late final List<Move> own = BattleRulesCore.legalMoves(
    rules,
    side,
    authorization: rules.board.turn == side ? rules.special : null,
  );
  late final List<Move> opposing = BattleRulesCore.legalMoves(rules, enemy);
  final _future = <CardId, double>{};
  _Position(this.view);

  double score(BattleAction action) => switch (action) {
    PassAction() => 0,
    DiscardAction() =>
      view.ownHand.length >= 4 && rules.deckCounts[side]! > 0
          ? .35 - future(action.card) * .55
          : -2,
    PlayCardAction() => play(action),
    ResolveAction() =>
      (action.selected == null ? 0 : future(action.selected!) * 2) +
          [
            for (var i = 0; i < action.order.length; i++)
              future(action.order[i]) / (i + 1),
          ].fold(0.0, (a, b) => a + b),
    ChessMoveAction() => moveValue(
      own.firstWhere((move) => move.uci == action.uci),
    ),
  };

  double activity(
    int square, {
    bool capturesOnly = false,
    bool longOnly = false,
  }) {
    final moves = board.pieceAt(square)?.color == side ? own : opposing;
    return moves
        .where((m) {
          return m.from == square &&
              (!capturesOnly || board.pieceAt(m.to) != null || m.isEnPassant) &&
              (!longOnly ||
                  max(
                        (m.to % 8 - m.from % 8).abs(),
                        (m.to ~/ 8 - m.from ~/ 8).abs(),
                      ) >
                      2);
        })
        .fold(0.0, (sum, m) {
          final victim = _value(board.pieceAt(m.to)?.type);
          return sum + .13 + victim * .25 + (m.isEnPassant ? .25 : 0);
        });
  }

  double destination(int square, {bool mine = false}) {
    final candidates = opposing.where((m) {
      return m.to == square &&
          (!mine || board.pieceAt(m.from)?.type != PieceType.king);
    });
    var best = 0.0;
    for (final move in candidates) {
      final piece = board.pieceAt(move.from)!;
      var priority = .55 + _value(piece.type) * .12;
      final next = board.apply(move);
      if (MoveGen.inCheck(next, side)) priority += 1.5;
      if (MoveGen.isSquareAttacked(next, square, side)) priority *= .45;
      best = max(best, priority);
    }
    return best;
  }

  double vulnerability(int square) {
    final piece = board.pieceAt(square);
    if (piece == null) return 0;
    // Siper/Fog protect from cards, not chess captures. Valuable active pieces
    // exposed to available public hostile cards are the relevant vulnerability.
    final threats =
        remaining(enemy).where((card) {
          return [
            CardId.chain,
            CardId.slow,
            CardId.freeze,
            CardId.huntVow,
          ].contains(card);
        }).length;
    final sheltered = rules.pieceEffects.any((effect) {
      return effect.type == PieceEffectType.shelter &&
          effect.pieceId == rules.pieceIds[square];
    });
    if (sheltered || threats == 0) return 0;
    return (_value(piece.type) * .13 + activity(square) * .3) * min(threats, 2);
  }

  Iterable<CardId> remaining(PieceColor color) => rules.arsenals[color]!.where(
    (c) =>
        !rules.used[color]!.contains(c) && !rules.discarded[color]!.contains(c),
  );

  double likelihood(CardId card) {
    for (final observation in view.knowledge.radarObservations.reversed) {
      if (observation.queriedCardId == card && !observation.stale) {
        return observation.inHand ? 1 : 0;
      }
    }
    final count = remaining(enemy).length;
    return count == 0 ? 0 : (rules.handCounts[enemy]! / count).clamp(0, 1);
  }

  double publicThreat(CardId card) {
    final cost = cardDefinitions[card]!.cost;
    final mana = min(6, rules.mana[enemy]! + 1);
    if (cost > mana) return 0;
    return switch (card) {
      CardId.freeze || CardId.chain || CardId.slow || CardId.huntVow =>
        .65 + own.fold(0.0, (best, m) => max(best, activity(m.from) * .2)),
      CardId.purify =>
        rules.pieceEffects.any(
              (e) => e.owner == side && e.type != PieceEffectType.shelter,
            )
            ? 1.4
            : .1,
      CardId.pawnDeviation ||
      CardId.pawnAdvance ||
      CardId.rookBend ||
      CardId.angryN ||
      CardId.shadowPass =>
        [
              for (var s = 0; s < 64; s++)
                ...BattleRulesCore.specialMoves(rules, card, s, enemy),
            ].isEmpty
            ? .05
            : 1.1,
      CardId.prophecy ||
      CardId.fateExchange => rules.deckCounts[enemy]! > 0 ? .8 : 0,
      _ => .7,
    };
  }

  double future(CardId card) => _future.putIfAbsent(card, () {
    final targets = BattleRulesCore.cardTargets(view, card);
    if (targets.isEmpty) return .1;
    if (card == CardId.fateExchange) return .8;
    if (card == CardId.shadowContract) return .5;
    return max(
      .1,
      targets
              .map((target) => play(PlayCardAction(card, target: target)))
              .fold(-10.0, max) +
          .5,
    );
  });

  double play(PlayCardAction action) {
    final card = action.card, target = action.target;
    final square = target is int ? target : -1;
    final piece = square >= 0 ? board.pieceAt(square) : null;
    final cost = BattleRulesCore.effectiveCost(rules, side, card);
    var value = switch (card) {
      CardId.radar =>
        likelihood(CardId.parse(target as String)) > 0 &&
                likelihood(CardId.parse(target)) < 1
            ? .65 + publicThreat(CardId.parse(target)) * .45
            : -.5,
      CardId.prophecy =>
        view.knowledge.knownUpcomingCards.length >=
                min(2, rules.deckCounts[side]!)
            ? -.5
            : .75 + rules.deckCounts[side]! * .035,
      CardId.shelter => vulnerability(square),
      CardId.chain => activity(square, capturesOnly: true) * 1.5,
      CardId.slow => activity(square, longOnly: true) * .85,
      CardId.freeze => activity(square) * .8 + _value(piece?.type) * .12,
      CardId.purify => _purify(target as String),
      CardId.mine => destination(square, mine: true) * 1.5,
      CardId.lockedSquare => destination(square) * .9,
      CardId.boardSeal =>
        boardZone(square).map(destination).fold(0.0, (a, b) => a + b) * .75,
      CardId.fog =>
        boardZone(square).map(vulnerability).fold(0.0, (a, b) => a + b) * .7,
      CardId.breakSeal => _breakSeal(target as String),
      CardId.manaSabotage =>
        likelihood(CardId.parse(target as String)) *
            publicThreat(CardId.parse(target)) *
            (cardDefinitions[CardId.parse(target)]!.cost ==
                    min(6, rules.mana[enemy]! + 1)
                ? 1.8
                : .7),
      CardId.cardBlock =>
        likelihood(CardId.parse(target as String)) *
            publicThreat(CardId.parse(target)) *
            1.9,
      CardId.echo =>
        rules.mana[side]! >= 5
            ? .1
            : likelihood(CardId.parse(target as String)) *
                publicThreat(CardId.parse(target)) *
                1.25,
      CardId.huntVow => own.where((m) => m.to == square).isNotEmpty ? 2.2 : .1,
      CardId.watchVow => min(1.6, destination(square)) * 1.15,
      CardId.fateExchange => rules.deckCounts[side]! >= 2 ? 1.8 : .65,
      CardId.shadowContract =>
        view.ownHand
                    .where((c) => c != card && c != action.sacrifice)
                    .map((c) => cardDefinitions[c]!.cost)
                    .fold(0, max) >=
                3
            ? 1.25
            : .1,
      CardId.pawnDeviation ||
      CardId.pawnAdvance ||
      CardId.rookBend ||
      CardId.angryN ||
      CardId.shadowPass => _movement(card, square),
    };
    value -= cost * .32;
    if (action.sacrifice != null) value -= future(action.sacrifice!) * .65;
    return value;
  }

  double _purify(String id) {
    final effect = rules.pieceEffects.firstWhere((e) => e.id == id);
    final square = rules.pieceIds.indexOf(effect.pieceId);
    final removed = RuleDraft(rules)
      ..pieceEffects.removeWhere((e) => e.id == id);
    final released = BattleRulesCore.legalMoves(
      removed.freeze(),
      side,
    ).where((m) => m.from == square && !own.any((old) => old.uci == m.uci));
    return released.fold(
      0.0,
      (sum, m) => sum + .18 + _value(board.pieceAt(m.to)?.type) * .45,
    );
  }

  double _breakSeal(String id) {
    final effect = rules.boardEffects.firstWhere((e) => e.id == id);
    if (effect.type == BoardEffectType.mine) return .65;
    if (effect.type == BoardEffectType.fog) {
      return effect.squares.fold(
        0.0,
        (sum, s) =>
            sum +
            (board.pieceAt(s)?.color == enemy
                ? .25 + _value(board.pieceAt(s)?.type) * .1
                : 0),
      );
    }
    final removed = RuleDraft(rules)
      ..boardEffects.removeWhere((e) => e.id == id);
    return BattleRulesCore.legalMoves(removed.freeze(), side)
        .where((m) => !own.any((old) => old.uci == m.uci))
        .fold(0.0, (sum, m) => sum + .25 + max(0.0, moveValue(m)) * .15);
  }

  double _movement(CardId card, int from) {
    final moves = BattleRulesCore.specialMoves(rules, card, from, side);
    final best = moves.map(moveValue).fold(-20.0, max);
    final ordinary = own.map(moveValue).fold(-20.0, max);
    return max(-2.0, (best - ordinary) * .85);
  }

  double moveValue(Move move) {
    final piece = board.pieceAt(move.from)!;
    final next = board.apply(move);
    var value =
        _value(board.pieceAt(move.to)?.type) + (move.isEnPassant ? 1 : 0);
    if (move.promotion != null) value += _value(move.promotion) - 1;
    if (MoveGen.inCheck(next, enemy)) value += .55;
    if (MoveGen.isSquareAttacked(next, move.to, enemy)) {
      value -= _value(piece.type) * .65;
    }
    final sign = side.isWhite ? 1 : -1;
    value +=
        (AiEngine().evaluateWhite(next) - AiEngine().evaluateWhite(board)) *
        sign /
        500;
    return value;
  }

  ({double value, int nodes}) followup(
    RuleState projected,
    int remainingBudget,
  ) {
    final projectedView = PlayerView(
      projected,
      side,
      view.ownHand
          .where(
            (card) =>
                !projected.used[side]!.contains(card) &&
                !projected.discarded[side]!.contains(card),
          )
          .toList(),
      view.knowledge,
    );
    final position = _Position(projectedView);
    final moves = [...position.own]
      ..sort((a, b) => position.moveValue(b).compareTo(position.moveValue(a)));
    final baseline = own.map(moveValue).fold(-20.0, max);
    var best = -20.0, nodes = 0;
    for (final move in moves.take(3)) {
      if (nodes >= remainingBudget) break;
      // Use the canonical transition so piece identities, castling, en passant,
      // effect expiry and the response turn stay coherent in the projection.
      final afterRules =
          BattleRulesCore.transition(
            projectedView,
            ChessMoveAction(move.uci),
          ).rules;
      final after = afterRules.board;
      final replies = BattleRulesCore.legalMoves(afterRules, enemy);
      var counter = 0.0;
      for (final reply in replies) {
        if (nodes++ >= remainingBudget) {
          nodes = remainingBudget;
          break;
        }
        final victim = after.pieceAt(reply.to);
        counter = max(
          counter,
          _value(victim?.type) + (reply.isEnPassant ? 1 : 0),
        );
      }
      best = max(best, position.moveValue(move) - counter * .6);
    }
    return (value: ((best - baseline) * .3).clamp(-2.0, 2.0), nodes: nodes);
  }
}
