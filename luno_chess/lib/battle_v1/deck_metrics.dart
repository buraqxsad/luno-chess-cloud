import 'model.dart';

class BattleDeckMetrics {
  static const deckSize = 10;
  // The first turn is chess-only; the first card phase starts at two mana.
  static const openingMana = 2;

  final int count;
  final int uniqueCount;
  final int totalMana;
  final List<int> curve;
  final int reactiveRemovalCount;
  final int sacrificeRequiredCount;
  final int pieceSpecificCount;
  const BattleDeckMetrics(
    this.count,
    this.totalMana,
    this.curve, {
    required this.uniqueCount,
    required this.reactiveRemovalCount,
    required this.sacrificeRequiredCount,
    required this.pieceSpecificCount,
  });

  factory BattleDeckMetrics.fromCards(Iterable<CardId> cards) {
    final curve = List<int>.filled(4, 0);
    final unique = <CardId>{};
    var count = 0, total = 0, removal = 0, sacrifice = 0, pieceSpecific = 0;
    for (final card in cards) {
      final definition = cardDefinitions[card]!;
      final cost = definition.cost;
      curve[(cost - 1).clamp(0, 3)]++;
      unique.add(card);
      count++;
      total += cost;
      switch (definition.target) {
        case CardTargetType.ownPieceEffect:
        case CardTargetType.opponentBoardEffect:
          removal++;
        case CardTargetType.sacrifice:
          sacrifice++;
        case CardTargetType.ownPawn:
        case CardTargetType.ownRook:
        case CardTargetType.ownKnight:
        case CardTargetType.ownBishopRook:
          pieceSpecific++;
        default:
          break;
      }
    }
    return BattleDeckMetrics(
      count,
      total,
      List.unmodifiable(curve),
      uniqueCount: unique.length,
      reactiveRemovalCount: removal,
      sacrificeRequiredCount: sacrifice,
      pieceSpecificCount: pieceSpecific,
    );
  }

  double get average => count == 0 ? 0 : totalMana / count;
  bool get isCompleteDeck => count == deckSize && uniqueCount == deckSize;
  int get openingAffordableCount => curve[0] + curve[1];
  int get aboveOpeningManaCount => count - openingAffordableCount;
  int get highCostCount => curve[3];

  // A strict majority cannot be afforded at the first card phase. This is a
  // composition warning, not a prediction of legal targets or draw outcomes.
  bool get heavy => isCompleteDeck && aboveOpeningManaCount > count / 2;

  static List<int> get _catalogCosts =>
      [for (final card in CardId.values) cardDefinitions[card]!.cost]..sort();
  static double get minimumAverage =>
      _catalogCosts.take(deckSize).fold<int>(0, (a, b) => a + b) / deckSize;
  static double get maximumAverage =>
      _catalogCosts.reversed.take(deckSize).fold<int>(0, (a, b) => a + b) /
      deckSize;
}
