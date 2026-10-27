import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

const radarOwnDeck = [
  CardId.radar,
  CardId.chain,
  CardId.shelter,
  CardId.prophecy,
  CardId.slow,
  CardId.pawnDeviation,
  CardId.pawnAdvance,
  CardId.lockedSquare,
  CardId.freeze,
  CardId.purify,
];

const radarOpponentDeck = [
  CardId.fateExchange,
  CardId.freeze,
  CardId.chain,
  CardId.shelter,
  CardId.radar,
  CardId.prophecy,
  CardId.echo,
  CardId.cardBlock,
  CardId.manaSabotage,
  CardId.shadowContract,
];

AuthoritativeBattleState radarFixture({
  PieceColor side = PieceColor.white,
  List<CardId> ownDeck = radarOwnDeck,
  List<CardId> opponentDeck = radarOpponentDeck,
  String? fen,
  int mana = 6,
}) {
  final initial = DeckManager.newBattle(
    board: Board.fromFen(
      fen ?? '4k3/pp6/8/8/8/8/PP6/4K3 ${side.isWhite ? 'w' : 'b'} - - 0 12',
    ),
    white: side.isWhite ? ownDeck : opponentDeck,
    black: side.isWhite ? opponentDeck : ownDeck,
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
        ..ownTurns[side] = 3
        ..ownTurns[side.opposite] = 3
        ..mana[side] = mana
        ..mana[side.opposite] = 6;
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}

AuthoritativeBattleState radarEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState radarRepartition(
  AuthoritativeBattleState state,
  PieceColor side, {
  required List<CardId> hand,
  required List<CardId> deck,
  List<CardId> used = const [],
  List<CardId> discarded = const [],
}) {
  final draft =
      RuleDraft(state.rules)
        ..handCounts[side] = hand.length
        ..deckCounts[side] = deck.length
        ..drawCounts[side] = hand.length + used.length + discarded.length
        ..used[side] = [...used]
        ..discarded[side] = [...discarded];
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: {...state.hidden.hands, side: hand},
      decks: {...state.hidden.decks, side: deck},
      knowledge: state.hidden.knowledge,
    ),
  );
}

AuthoritativeBattleState radarCast(
  AuthoritativeBattleState state,
  CardId queried,
) => DeckManager.apply(
  state,
  PlayCardAction(CardId.radar, target: queried.wire),
);

AuthoritativeBattleState radarAdvance(AuthoritativeBattleState state) =>
    DeckManager.apply(
      state,
      BattleRulesCore.legalActions(
        state.view(state.rules.board.turn),
      ).whereType<ChessMoveAction>().first,
    );

RadarObservation radarResult(
  AuthoritativeBattleState state,
  PieceColor observer,
) => state.view(observer).knowledge.radarObservations.single;

Iterable<List<T>> radarCombinations<T>(List<T> values, int count) sync* {
  if (count == 0) {
    yield <T>[];
    return;
  }
  for (var i = 0; i <= values.length - count; i++) {
    for (final tail in radarCombinations(values.sublist(i + 1), count - 1)) {
      yield [values[i], ...tail];
    }
  }
}

Iterable<List<T>> radarPermutations<T>(List<T> values) sync* {
  if (values.isEmpty) {
    yield <T>[];
    return;
  }
  for (var i = 0; i < values.length; i++) {
    for (final tail in radarPermutations([
      ...values.take(i),
      ...values.skip(i + 1),
    ])) {
      yield [values[i], ...tail];
    }
  }
}

typedef RadarEdgePosition =
    ({
      String id,
      String fen,
      List<String> requiredMoves,
      List<String> forbiddenMoves,
      bool kingOnly,
    });

List<CardId> radarQueryDeck(CardId query, int index) {
  final deck = CardId.values.where((c) => c != query).take(9).toList();
  deck.insert(index, query);
  return deck;
}

List<RadarEdgePosition> radarEdgePositions(PieceColor side) => [
  (
    id: 'absolute-knight-pin',
    fen:
        side.isWhite
            ? 'k3r3/8/8/8/8/8/4N3/4K3 w - - 0 12'
            : '4k3/4n3/8/8/8/8/8/K3R3 b - - 0 12',
    requiredMoves: side.isWhite ? ['e1d1'] : ['e8d8'],
    forbiddenMoves: side.isWhite ? ['e2c3', 'e2f4'] : ['e7c6', 'e7f5'],
    kingOnly: true,
  ),
  (
    id: 'double-check',
    fen:
        side.isWhite
            ? 'k3r3/8/8/8/1b6/8/P7/4K3 w - - 0 12'
            : '4k3/p7/8/1B6/8/8/8/K3R3 b - - 0 12',
    requiredMoves: side.isWhite ? ['e1f1'] : ['e8f8'],
    forbiddenMoves: side.isWhite ? ['a2a3', 'e1d2'] : ['a7a6', 'e8d7'],
    kingOnly: true,
  ),
  (
    id: 'en-passant-discovered-check',
    fen:
        side.isWhite
            ? 'k7/8/8/r4pPK/8/8/8/8 w - f6 0 12'
            : '8/8/8/8/R4Ppk/8/8/K7 b - f3 0 12',
    requiredMoves: side.isWhite ? ['g5g6'] : ['g4g3'],
    forbiddenMoves: side.isWhite ? ['g5f6'] : ['g4f3'],
    kingOnly: false,
  ),
  (
    id: 'en-passant-legal',
    fen:
        side.isWhite
            ? '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 12'
            : '4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 12',
    requiredMoves: side.isWhite ? ['e5d6'] : ['e4d3'],
    forbiddenMoves: const [],
    kingOnly: false,
  ),
  (
    id: 'both-castles',
    fen: 'r3k2r/8/8/8/8/8/8/R3K2R ${side.isWhite ? 'w' : 'b'} KQkq - 0 12',
    requiredMoves: side.isWhite ? ['e1g1', 'e1c1'] : ['e8g8', 'e8c8'],
    forbiddenMoves: const [],
    kingOnly: false,
  ),
  (
    id: 'four-promotions',
    fen:
        side.isWhite
            ? '7k/P7/8/8/8/8/8/4K3 w - - 0 12'
            : '4k3/8/8/8/8/8/p7/7K b - - 0 12',
    requiredMoves: [
      for (final p in ['q', 'r', 'b', 'n'])
        '${side.isWhite ? 'a7a8' : 'a2a1'}$p',
    ],
    forbiddenMoves: [side.isWhite ? 'a7a8' : 'a2a1'],
    kingOnly: false,
  ),
  (
    id: 'seventy-five-move-boundary',
    fen: '4k3/pp6/8/8/8/8/PP6/4K3 ${side.isWhite ? 'w' : 'b'} - - 149 12',
    requiredMoves: side.isWhite ? ['e1d1'] : ['e8d8'],
    forbiddenMoves: const [],
    kingOnly: false,
  ),
];
