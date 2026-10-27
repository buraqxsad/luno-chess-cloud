import 'model.dart';
import 'online.dart';
import '../services/battle_v1_deck_result.dart';

class BattleDeckAccount {
  final List<CardId> deck;
  final Set<CardId> owned;
  final bool available;
  final BattleDeckProgression? progression;

  const BattleDeckAccount({
    required this.deck,
    required this.owned,
    required this.available,
    this.progression,
  });

  factory BattleDeckAccount.fromResponse(Map<String, dynamic> response) {
    if (response['ok'] != true ||
        response['protocolVersion'] != battleV1Protocol ||
        response['available'] is! bool ||
        response['deck'] is! List ||
        response['entitlements'] is! List) {
      throw const FormatException('Invalid battle deck account');
    }
    final deck = _cards(response['deck'] as List);
    final owned = _cards(response['entitlements'] as List).toSet();
    if (deck.length != 10 ||
        deck.toSet().length != 10 ||
        !owned.containsAll(starterDeck) ||
        !owned.containsAll(deck)) {
      throw const FormatException('Invalid battle deck ownership');
    }
    return BattleDeckAccount(
      deck: List.unmodifiable(deck),
      owned: Set.unmodifiable(owned),
      available: response['available'] as bool,
      progression: parseBattleV1DeckProgression(
        response['progression'],
        owned: owned,
      ),
    );
  }

  static List<CardId> _cards(List<dynamic> values) =>
      values.map((value) {
        if (value is! String) {
          throw const FormatException('Invalid battle card');
        }
        return CardId.parse(value);
      }).toList();
}
