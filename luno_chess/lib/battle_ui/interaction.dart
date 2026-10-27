import '../battle_v1/core.dart';
import '../battle_v1/model.dart';
import '../engine/square.dart';

/// Selection and previews only. The core is the sole source of legal actions.
class BattleInteraction {
  CardId? card;
  int? piece;
  PlayCardAction? play;
  ChessMoveAction? specialDestination;
  bool invalidTarget = false;
  int? _version;
  PlayerView? _targetView;
  void synchronize(PlayerView view, int version) {
    if (_version != version) {
      cancel();
      piece = view.rules.special?.from;
      _version = version;
    }
  }

  void cancel() {
    card = null;
    piece = null;
    play = null;
    specialDestination = null;
    invalidTarget = false;
    _targetView = null;
  }

  void select(CardId id, List<BattleAction> actions) {
    if (!actions.any(
      (a) =>
          a is PlayCardAction && a.card == id ||
          a is DiscardAction && a.card == id,
    )) {
      return;
    }
    if (card == id) {
      cancel();
      return;
    }
    cancel();
    card = id;
    final untargeted = actions.whereType<PlayCardAction>().where(
      (a) => a.card == id && a.target == null && a.sacrifice == null,
    );
    if (untargeted.length == 1) play = untargeted.single;
  }

  List<PlayCardAction> options(List<BattleAction> actions) {
    final choices =
        actions
            .whereType<PlayCardAction>()
            .where((a) => a.card == card)
            .toList();
    final selected = play;
    if (selected != null && !choices.any((a) => a.key == selected.key)) {
      // Revoking a cast must not silently cancel the card and allow a PASS.
      play = null;
      piece = null;
      specialDestination = null;
      invalidTarget = false;
    }
    return choices;
  }

  List<ChessMoveAction> moves(PlayerView view, List<BattleAction> actions) {
    if (card != null) {
      final choices = options(actions);
      if (!movementCards.contains(card) ||
          piece == null ||
          !choices.any((a) => a.target == piece)) {
        return const [];
      }
      final available =
          BattleRulesCore.specialMoves(
            view.rules,
            card!,
            piece!,
            view.viewer,
          ).map((m) => ChessMoveAction(m.uci)).toList();
      final destination = specialDestination;
      if (destination != null &&
          !available.any((m) => m.key == destination.key)) {
        specialDestination = null;
      }
      return available;
    }
    if (actions.any((a) => a is PassAction)) {
      final preview =
          BattleRulesCore.transition(view, const PassAction()).rules;
      return BattleRulesCore.legalActions(
        PlayerView(preview, view.viewer, view.ownHand, view.knowledge),
      ).whereType<ChessMoveAction>().toList();
    }
    return actions.whereType<ChessMoveAction>().toList();
  }

  Set<int> targets(PlayerView view, List<BattleAction> actions) {
    final choices = options(actions);
    if (card != null && !(movementCards.contains(card) && piece != null)) {
      return {
        ...choices.map((a) => a.target).whereType<int>(),
        for (final choice in choices)
          for (final effect in view.rules.boardEffects)
            if (effect.id == choice.target) ...effect.squares,
        for (final choice in choices)
          for (final effect in view.rules.pieceEffects)
            if (effect.id == choice.target)
              for (var square = 0; square < 64; square++)
                if (view.rules.pieceIds[square] == effect.pieceId) square,
      };
    }
    final from = card == null ? view.rules.special?.from ?? piece : piece;
    return moves(view, actions)
        .where((m) => from != null && m.uci.startsWith(Square.algebraic(from)))
        .map(
          (m) => Square.of(m.uci.codeUnitAt(2) - 97, int.parse(m.uci[3]) - 1),
        )
        .toSet();
  }

  Set<int> preview() {
    final target = play?.target;
    if (target is! int) {
      final view = _targetView;
      if (view == null || target == null) return const {};
      return {
        for (final effect in view.rules.boardEffects)
          if (effect.id == target) ...effect.squares,
        for (final effect in view.rules.pieceEffects)
          if (effect.id == target)
            for (var square = 0; square < 64; square++)
              if (view.rules.pieceIds[square] == effect.pieceId) square,
      };
    }
    if (cardDefinitions[card]?.target == CardTargetType.zone) {
      return boardZone(target).toSet();
    }
    final destination = specialDestination?.uci;
    return {
      target,
      if (destination != null)
        Square.of(
          destination.codeUnitAt(2) - 97,
          int.parse(destination[3]) - 1,
        ),
    };
  }

  List<BattleAction> tap(
    int square,
    PlayerView view,
    List<BattleAction> actions,
  ) {
    _targetView = view;
    if (square < 0 || square >= 64) return const [];
    final candidates = options(actions);
    if (view.rules.phase == BattlePhase.pending) return const [];
    if (card != null) {
      final targetType = cardDefinitions[card]!.target;
      if (targetType == CardTargetType.none ||
          targetType == CardTargetType.opponentCard ||
          targetType == CardTargetType.sacrifice) {
        return const [];
      }
      if (movementCards.contains(card) && piece != null) {
        final to = moves(view, actions).where(
          (m) => m.uci.startsWith(
            Square.algebraic(piece!) + Square.algebraic(square),
          ),
        );
        if (to.isNotEmpty) {
          specialDestination = to.first;
          invalidTarget = false;
          return const [];
        }
      }
      final direct = candidates.where((a) => a.target == square).toList();
      if (direct.isNotEmpty) {
        play = direct.single;
        piece = movementCards.contains(card) ? square : null;
        specialDestination = null;
        invalidTarget = false;
        return const [];
      }
      final effects =
          candidates
              .where(
                (a) =>
                    view.rules.boardEffects.any(
                      (e) => e.id == a.target && e.squares.contains(square),
                    ) ||
                    view.rules.pieceEffects.any(
                      (e) =>
                          e.id == a.target &&
                          e.pieceId == view.rules.pieceIds[square],
                    ),
              )
              .toList();
      specialDestination = null;
      if (effects.length == 1) {
        play = effects.single;
        invalidTarget = false;
      } else {
        // A new tap must never confirm the previous target by accident.
        if (!movementCards.contains(card) || piece == null) play = null;
        invalidTarget = effects.isEmpty;
      }
      return effects.length > 1 ? effects : const [];
    }
    // A committed special move survives cancellation of local previews.
    piece = view.rules.special?.from ?? piece;
    final legal = moves(view, actions);
    if (piece != null) {
      final matches =
          legal
              .where(
                (m) => m.uci.startsWith(
                  Square.algebraic(piece!) + Square.algebraic(square),
                ),
              )
              .toList();
      if (matches.isNotEmpty) {
        invalidTarget = false;
        return matches;
      }
      if (view.rules.board.pieceAt(square)?.color != view.viewer) {
        invalidTarget = true;
        return const [];
      }
    }
    if (view.rules.special != null) {
      piece = view.rules.special!.from;
      return const [];
    }
    // A restricted own piece is still inspectable. Selecting it grants no move;
    // the legal-action list remains the only source of destinations.
    piece =
        view.rules.board.pieceAt(square)?.color == view.viewer ? square : null;
    invalidTarget = false;
    return const [];
  }
}
