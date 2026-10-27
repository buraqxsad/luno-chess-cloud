import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

import 'battle_ui/fixtures.dart';
import 'helpers/v222_card_scenarios.dart';

const _side = PieceColor.white;
const _pawnCast = PlayCardAction(CardId.pawnDeviation, target: 12);
const _pawnMove = ChessMoveAction('e2f3');

AuthoritativeBattleState _edit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) change,
) {
  final draft = RuleDraft(state.rules);
  change(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

BattleInteraction _preparePawn(AuthoritativeBattleState state) {
  final view = state.view(_side);
  final actions = BattleRulesCore.legalActions(view);
  expect(BattleRulesCore.isLegalAction(view, _pawnCast), isTrue);
  final interaction = BattleInteraction()..synchronize(view, 7);
  interaction.select(CardId.pawnDeviation, actions);
  expect(interaction.tap(12, view, actions), isEmpty);
  expect(interaction.tap(21, view, actions), isEmpty);
  expect(interaction.play?.key, _pawnCast.key);
  expect(interaction.specialDestination?.key, _pawnMove.key);
  return interaction;
}

void main() {
  for (final side in PieceColor.values) {
    for (final card in CardId.values) {
      test('${side.name} ${card.wire} revokes stale UI admission', () {
        final state = cardScenario(card, side);
        final view = state.view(side);
        final actions = BattleRulesCore.legalActions(view);
        final cast = actions.whereType<PlayCardAction>().firstWhere(
          (action) => action.card == card,
        );
        final reduced = _edit(state, (draft) => draft.mana[side] = 0);
        final reducedView = reduced.view(side);
        final reducedActions = BattleRulesCore.legalActions(reducedView);
        expect(BattleRulesCore.isLegalAction(reducedView, cast), isFalse);
        expect(
          reducedActions.whereType<DiscardAction>().map((a) => a.card),
          contains(card),
        );

        for (final entryPoint in ['options', 'moves', 'targets', 'tap']) {
          final interaction = BattleInteraction()..select(card, actions);
          // Target and sacrifice sheets also install an admitted action here.
          interaction.play = cast;
          if (movementCards.contains(card)) {
            interaction.piece = cast.target as int;
            final special = BattleRulesCore.specialMoves(
              view.rules,
              card,
              interaction.piece!,
              side,
            );
            expect(special, isNotEmpty);
            interaction.specialDestination = ChessMoveAction(special.first.uci);
          }

          switch (entryPoint) {
            case 'options':
              expect(interaction.options(reducedActions), isEmpty);
              break;
            case 'moves':
              expect(interaction.moves(reducedView, reducedActions), isEmpty);
              break;
            case 'targets':
              expect(interaction.targets(reducedView, reducedActions), isEmpty);
              break;
            case 'tap':
              expect(interaction.tap(0, reducedView, reducedActions), isEmpty);
              break;
          }

          expect(interaction.card, card, reason: entryPoint);
          expect(interaction.play, isNull, reason: entryPoint);
          expect(interaction.piece, isNull, reason: entryPoint);
          expect(interaction.specialDestination, isNull, reason: entryPoint);
          expect(interaction.preview(), isEmpty, reason: entryPoint);
          expect(interaction.tap(0, reducedView, reducedActions), isEmpty);
          expect(reducedView.rules.phase, BattlePhase.card);
        }
      });
    }
  }

  for (final entryPoint in ['options', 'moves', 'targets', 'tap']) {
    test('revoked movement cast is cleared through $entryPoint', () {
      final state = battleFixture(hand: [CardId.pawnDeviation]);
      final interaction = _preparePawn(state);
      final reduced = _edit(state, (draft) => draft.mana[_side] = 0);
      final view = reduced.view(_side);
      final actions = BattleRulesCore.legalActions(view);
      expect(BattleRulesCore.isLegalAction(view, _pawnCast), isFalse);
      expect(actions.whereType<DiscardAction>(), isNotEmpty);
      expect(actions.whereType<PassAction>(), isNotEmpty);

      switch (entryPoint) {
        case 'options':
          expect(interaction.options(actions), isEmpty);
          break;
        case 'moves':
          expect(interaction.moves(view, actions), isEmpty);
          break;
        case 'targets':
          expect(interaction.targets(view, actions), isEmpty);
          break;
        case 'tap':
          expect(interaction.tap(21, view, actions), isEmpty);
          break;
      }

      expect(interaction.play, isNull);
      expect(interaction.piece, isNull);
      expect(interaction.specialDestination, isNull);
      expect(interaction.preview(), isEmpty);
      expect(interaction.card, CardId.pawnDeviation);
      // A revoked cast must not turn the next board gesture into an implicit PASS.
      expect(interaction.tap(12, view, actions), isEmpty);
      expect(interaction.tap(28, view, actions), isEmpty);
      expect(interaction.play, isNull);
      expect(view.rules.phase, BattlePhase.card);
    });
  }

  test('revoked source exposes remaining sources and can finish a turn', () {
    final state = battleFixture(hand: [CardId.pawnDeviation]);
    final interaction = _preparePawn(state);
    final frozen = _edit(state, (draft) {
      draft.pieceEffects.add(
        ActivePieceEffect(
          id: 'v228-freeze',
          type: PieceEffectType.freeze,
          owner: PieceColor.black,
          pieceId: state.rules.pieceIds[12]!,
          responseSide: _side,
          duration: EffectDuration.move,
        ),
      );
    });
    final view = frozen.view(_side);
    final actions = BattleRulesCore.legalActions(view);
    expect(BattleRulesCore.isLegalAction(view, _pawnCast), isFalse);
    expect(
      BattleRulesCore.isLegalAction(
        view,
        const PlayCardAction(CardId.pawnDeviation, target: 11),
      ),
      isTrue,
    );

    final targets = interaction.targets(view, actions);
    expect(targets, isNot(contains(12)));
    expect(targets, contains(11));
    expect(interaction.play, isNull);
    expect(interaction.specialDestination, isNull);
    interaction.tap(11, view, actions);
    interaction.tap(18, view, actions);
    final cast = DeckManager.apply(frozen, interaction.play!);
    final moved = DeckManager.apply(cast, interaction.specialDestination!);
    expect(moved.rules.board.turn, PieceColor.black);
    expect(moved.rules.board.pieceAt(18)?.type, PieceType.pawn);
    expect(moved.rules.special, isNull);
  });

  test('changed destination is revoked without losing an admitted source', () {
    final state = battleFixture(hand: [CardId.pawnDeviation]);
    final interaction = _preparePawn(state);
    final locked = _edit(state, (draft) {
      draft.boardEffects.add(
        BoardEffectInstance(
          id: 'v228-lock',
          type: BoardEffectType.lockedSquare,
          owner: PieceColor.black,
          squares: [21],
          responseSide: _side,
          duration: EffectDuration.move,
        ),
      );
    });
    final view = locked.view(_side);
    final actions = BattleRulesCore.legalActions(view);
    expect(BattleRulesCore.isLegalAction(view, _pawnCast), isTrue);
    final cast = DeckManager.apply(locked, _pawnCast);
    expect(BattleRulesCore.isLegalAction(cast.view(_side), _pawnMove), isFalse);

    expect(interaction.targets(view, actions), {19});
    expect(interaction.specialDestination, isNull);
    expect(interaction.play?.key, _pawnCast.key);
    expect(interaction.preview(), {12});
    interaction.tap(19, view, actions);
    expect(interaction.specialDestination?.uci, 'e2d3');
    final moved = DeckManager.apply(cast, interaction.specialDestination!);
    expect(moved.rules.board.turn, PieceColor.black);
    expect(moved.rules.board.pieceAt(19)?.type, PieceType.pawn);
  });

  for (final card in [CardId.shelter, CardId.prophecy]) {
    test('revoked ${card.wire} cannot keep an old confirmation on a tap', () {
      final state = battleFixture(hand: [card]);
      final view = state.view(_side);
      final actions = BattleRulesCore.legalActions(view);
      final interaction = BattleInteraction()..select(card, actions);
      if (card == CardId.shelter) interaction.tap(12, view, actions);
      final captured = interaction.play!;
      expect(BattleRulesCore.isLegalAction(view, captured), isTrue);
      final reduced = _edit(state, (draft) => draft.mana[_side] = 0);
      final reducedView = reduced.view(_side);
      expect(BattleRulesCore.isLegalAction(reducedView, captured), isFalse);

      expect(
        interaction.tap(
          60,
          reducedView,
          BattleRulesCore.legalActions(reducedView),
        ),
        isEmpty,
      );
      expect(interaction.card, card);
      expect(interaction.play, isNull);
      expect(interaction.preview(), isEmpty);
    });
  }

  test('pending resolution revokes a previously prepared movement cast', () {
    final state = battleFixture(hand: [CardId.pawnDeviation, CardId.prophecy]);
    final interaction = _preparePawn(state);
    final pending = DeckManager.apply(
      state,
      const PlayCardAction(CardId.prophecy),
    );
    final view = pending.view(_side);
    final actions = BattleRulesCore.legalActions(view);
    expect(view.rules.phase, BattlePhase.pending);
    expect(actions, isNotEmpty);
    expect(actions.every((action) => action is ResolveAction), isTrue);

    expect(interaction.tap(21, view, actions), isEmpty);
    expect(interaction.play, isNull);
    expect(interaction.specialDestination, isNull);
    expect(interaction.moves(view, actions), isEmpty);
    expect(interaction.targets(view, actions), isEmpty);
    expect(interaction.preview(), isEmpty);

    final resolved = DeckManager.apply(pending, actions.first);
    final resolvedView = resolved.view(_side);
    final resolvedActions = BattleRulesCore.legalActions(resolvedView);
    interaction.synchronize(resolvedView, 9);
    expect(interaction.tap(12, resolvedView, resolvedActions), isEmpty);
    final move = interaction.tap(28, resolvedView, resolvedActions).single;
    expect(move.key, 'move:e2e4');
    final moved = DeckManager.apply(resolved, move);
    expect(moved.rules.board.turn, PieceColor.black);
    expect(moved.rules.pending, isNull);
    expect(moved.rules.special, isNull);
  });

  for (final poll in [false, true]) {
    test('cancelled committed source continues on first tap, poll=$poll', () {
      final state = battleFixture(hand: [CardId.pawnDeviation]);
      final cast = DeckManager.apply(state, _pawnCast);
      final view = cast.view(_side);
      final actions = BattleRulesCore.legalActions(view);
      final interaction = BattleInteraction()..synchronize(view, 8);
      interaction.cancel();
      if (poll) interaction.synchronize(cast.view(_side), 8);
      expect(interaction.card, isNull);
      expect(interaction.play, isNull);
      expect(interaction.preview(), isEmpty);
      expect(interaction.targets(view, actions), {19, 21});

      final continuation = interaction.tap(21, view, actions).single;
      expect(continuation.key, _pawnMove.key);
      final moved = DeckManager.apply(cast, continuation);
      expect(moved.rules.board.turn, PieceColor.black);
      expect(moved.rules.board.pieceAt(12), isNull);
      expect(moved.rules.board.pieceAt(21)?.type, PieceType.pawn);
      expect(moved.rules.special, isNull);
    });
  }

  test(
    'cancelling an uncommitted preview leaves ordinary movement available',
    () {
      final state = battleFixture(hand: [CardId.pawnDeviation]);
      final interaction = _preparePawn(state)..cancel();
      final view = state.view(_side);
      final actions = BattleRulesCore.legalActions(view);
      expect(interaction.tap(12, view, actions), isEmpty);
      final move = interaction.tap(28, view, actions).single;
      expect(move.key, 'move:e2e4');
      final passed = DeckManager.apply(state, const PassAction());
      final moved = DeckManager.apply(passed, move);
      expect(moved.rules.board.turn, PieceColor.black);
      expect(moved.hidden.hands[_side], contains(CardId.pawnDeviation));
      expect(moved.rules.used[_side], isNot(contains(CardId.pawnDeviation)));
      expect(moved.rules.special, isNull);
    },
  );

  test('unchanged polling preserves a cast with freshly generated actions', () {
    final state = battleFixture(hand: [CardId.pawnDeviation]);
    final interaction = _preparePawn(state);
    final view = state.view(_side);
    interaction.synchronize(view, 7);
    final actions = BattleRulesCore.legalActions(view);
    expect(interaction.targets(view, actions), {19, 21});
    expect(interaction.preview(), {12, 21});
    expect(interaction.play?.key, _pawnCast.key);
    final cast = DeckManager.apply(state, interaction.play!);
    final moved = DeckManager.apply(cast, interaction.specialDestination!);
    expect(moved.rules.board.turn, PieceColor.black);
  });
}
