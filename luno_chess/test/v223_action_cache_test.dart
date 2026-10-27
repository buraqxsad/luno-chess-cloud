import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/legal_actions.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'helpers/v222_card_scenarios.dart';

void main() {
  for (final card in CardId.values) {
    for (final side in PieceColor.values) {
      test(
        '${card.wire}/${side.name}: UI cache invalidates every accepted card/choice/move',
        () {
          var state = cardScenario(card, side);
          final cache = BattleLegalActionCache();
          List<BattleAction> checked() {
            final view = state.view(side);
            final actions = cache.forView(view);
            expect(
              actions.map((a) => a.key),
              BattleRulesCore.legalActions(view).map((a) => a.key),
            );
            expect(identical(cache.forView(state.view(side)), actions), isTrue);
            expect(() => actions.clear(), throwsUnsupportedError);
            return actions;
          }

          final initial = checked();
          state = DeckManager.apply(
            state,
            initial.whereType<PlayCardAction>().firstWhere(
              (a) => a.card == card,
            ),
          );
          var next = checked();
          expect(identical(initial, next), isFalse);
          if (state.rules.pending != null) {
            state = DeckManager.apply(
              state,
              next.whereType<ResolveAction>().first,
            );
            final resolved = checked();
            expect(identical(next, resolved), isFalse);
            next = resolved;
          }
          state = DeckManager.apply(
            state,
            next.whereType<ChessMoveAction>().first,
          );
          expect(checked(), isEmpty);
          final enemyView = state.view(side.opposite);
          expect(
            cache.forView(enemyView).map((a) => a.key),
            BattleRulesCore.legalActions(enemyView).map((a) => a.key),
          );
        },
      );
    }
  }
  test('same rules cannot reuse another private hand or pending choice', () {
    final state = cardScenario(CardId.prophecy, PieceColor.white);
    final cache = BattleLegalActionCache(), view = state.view(PieceColor.white);
    final first = cache.forView(view);
    final hand = view.ownHand.reversed.toList();
    final replaced = PlayerView(view.rules, view.viewer, hand, view.knowledge);
    final second = cache.forView(replaced);
    expect(identical(first, second), isFalse);
    expect(second.map((a) => a.key), first.map((a) => a.key));
    final cast = DeckManager.apply(
      state,
      const PlayCardAction(CardId.prophecy),
    );
    final pending = cast.view(PieceColor.white);
    final pendingActions = cache.forView(pending);
    final reordered = PlayerView(
      pending.rules,
      pending.viewer,
      pending.ownHand,
      pending.knowledge.copyWith(
        pendingCards: pending.knowledge.pendingCards.reversed.toList(),
      ),
    );
    final reorderedActions = cache.forView(reordered);
    expect(identical(pendingActions, reorderedActions), isFalse);
    expect(
      reorderedActions.map((a) => a.key),
      BattleRulesCore.legalActions(reordered).map((a) => a.key),
    );
  });
  test('rejected projection cannot poison a previously valid cache', () {
    final state = cardScenario(CardId.radar, PieceColor.white);
    final view = state.view(PieceColor.white), cache = BattleLegalActionCache();
    final valid = cache.forView(view);
    expect(
      () => cache.forView(
        PlayerView(view.rules, view.viewer, [], view.knowledge),
      ),
      throwsStateError,
    );
    expect(identical(valid, cache.forView(view)), isTrue);
  });
}
