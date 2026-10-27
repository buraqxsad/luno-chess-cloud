import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

AuthoritativeBattleState battleFixture({
  List<CardId> hand = const [CardId.shelter, CardId.chain, CardId.lockedSquare],
  bool firstTurn = false,
}) {
  final deck = [
    ...hand,
    ...CardId.values.where((c) => !hand.contains(c)).take(10 - hand.length),
  ];
  final base = DeckManager.newBattle(white: deck, black: starterDeck);
  final rules = RuleDraft(base.rules);
  if (!firstTurn) {
    rules.phase = BattlePhase.card;
    rules.ownTurns[PieceColor.white] = 2;
    rules.mana[PieceColor.white] = 6;
  }
  rules.handCounts[PieceColor.white] = hand.length;
  rules.deckCounts[PieceColor.white] = 10 - hand.length;
  return AuthoritativeBattleState(
    rules.freeze(),
    AuthoritativeHiddenState(
      hands: {
        PieceColor.white: hand,
        PieceColor.black: base.hidden.hands[PieceColor.black]!,
      },
      decks: {
        PieceColor.white: deck.skip(hand.length).toList(),
        PieceColor.black: base.hidden.decks[PieceColor.black]!,
      },
      knowledge: base.hidden.knowledge,
    ),
  );
}
