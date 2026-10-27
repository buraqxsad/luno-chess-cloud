import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/deck_metrics.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

void main() {
  final byCost = [...CardId.values]..sort(
    (a, b) => cardDefinitions[a]!.cost.compareTo(cardDefinitions[b]!.cost),
  );

  test(
    'first legal card phase has two mana after chess-only first turns',
    () async {
      final session = BattleV1LocalSession(hotseat: true, clockNow: () => 0);
      addTearDown(session.dispose);
      expect(session.view.rules.phase, BattlePhase.chess);
      expect(session.view.rules.mana[PieceColor.white], 1);
      expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
      expect(session.view.rules.phase, BattlePhase.chess);
      expect(session.view.rules.mana[PieceColor.black], 1);
      expect(await session.submit(const ChessMoveAction('e7e5')), isTrue);
      expect(session.view.rules.phase, BattlePhase.card);
      expect(session.view.rules.mana[PieceColor.white], 2);
      expect(BattleDeckMetrics.openingMana, 2);
    },
  );

  test('current 24-card catalog bounds ten unique cards at 1.5 to 3.0', () {
    final costs = CardId.values.map((c) => cardDefinitions[c]!.cost).toList();
    expect(costs, hasLength(24));
    expect(
      {
        for (var cost = 1; cost <= 5; cost++)
          cost: costs.where((value) => value == cost).length,
      },
      {1: 5, 2: 12, 3: 5, 4: 1, 5: 1},
    );

    // An exchange with a cheaper/more expensive unselected card can only
    // improve the respective bound, so the sorted extremes are exact.
    final cheapest = byCost.take(10).toList();
    final priciest = byCost.reversed.take(10).toList();
    expect(cheapest.toSet(), hasLength(10));
    expect(priciest.toSet(), hasLength(10));
    expect(BattleDeckMetrics.fromCards(cheapest).totalMana, 15);
    expect(BattleDeckMetrics.fromCards(priciest).totalMana, 30);
    expect(BattleDeckMetrics.minimumAverage, 1.5);
    expect(BattleDeckMetrics.maximumAverage, 3.0);
    expect(BattleDeckMetrics.maximumAverage, lessThan(3.5));
    expect(BattleDeckMetrics.fromCards(priciest).heavy, isTrue);
    expect(BattleDeckMetrics.fromCards(starterDeck).heavy, isFalse);
  });

  test('slow opening means a strict majority costs more than opening mana', () {
    final expensive = byCost.where((c) => cardDefinitions[c]!.cost > 2);
    final affordable = byCost.where((c) => cardDefinitions[c]!.cost <= 2);
    final balanced = BattleDeckMetrics.fromCards([
      ...expensive.take(5),
      ...affordable.take(5),
    ]);
    final slow = BattleDeckMetrics.fromCards([
      ...expensive.take(6),
      ...affordable.take(4),
    ]);
    expect(balanced.openingAffordableCount, 5);
    expect(balanced.heavy, isFalse);
    expect(slow.openingAffordableCount, 4);
    expect(slow.aboveOpeningManaCount, 6);
    expect(slow.heavy, isTrue);
  });

  test('incomplete and duplicate selections are drafts, not heavy decks', () {
    for (final cards in <List<CardId>>[
      [],
      [CardId.freeze],
      [...byCost.reversed.take(9)],
      List.filled(10, CardId.boardSeal),
      [...CardId.values],
    ]) {
      final stats = BattleDeckMetrics.fromCards(cards);
      expect(stats.isCompleteDeck, isFalse);
      expect(stats.heavy, isFalse);
      expect(stats.curve.fold<int>(0, (a, b) => a + b), cards.length);
    }
    expect(BattleDeckMetrics.fromCards([]).average, 0);
  });

  test('affordability is distinct from removal and sacrifice conditions', () {
    final stats = BattleDeckMetrics.fromCards([
      CardId.purify,
      CardId.breakSeal,
      CardId.shadowContract,
      CardId.fateExchange,
      CardId.freeze,
      CardId.boardSeal,
      CardId.pawnAdvance,
      CardId.rookBend,
      CardId.angryN,
      CardId.shadowPass,
    ]);
    expect(stats.isCompleteDeck, isTrue);
    expect(stats.openingAffordableCount, 5);
    expect(stats.highCostCount, 2);
    expect(stats.reactiveRemovalCount, 2);
    expect(stats.sacrificeRequiredCount, 2);
    expect(stats.pieceSpecificCount, 4);
    expect(stats.curve, [3, 2, 3, 2]);
  });
}
