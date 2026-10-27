import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

enum ManaSabotagePosition { open, crowded, inCheck }

const manaSabotagePool = <CardId>[
  CardId.radar,
  CardId.prophecy,
  CardId.shelter,
  CardId.chain,
  CardId.slow,
  CardId.pawnDeviation,
  CardId.pawnAdvance,
  CardId.lockedSquare,
  CardId.freeze,
  CardId.purify,
  CardId.mine,
  CardId.breakSeal,
  CardId.fog,
  CardId.manaSabotage,
  CardId.cardBlock,
  CardId.rookBend,
  CardId.angryN,
  CardId.shadowPass,
  CardId.huntVow,
  CardId.watchVow,
  CardId.echo,
  CardId.fateExchange,
  CardId.shadowContract,
  CardId.boardSeal,
];

List<CardId> manaSabotageDeck(List<CardId> hand, List<CardId> prefix) {
  final required = [...hand, ...prefix];
  if (required.toSet().length != required.length || required.length > 10) {
    throw ArgumentError('audit fixture requires distinct cards');
  }
  return [
    ...required,
    ...manaSabotagePool.where((card) => !required.contains(card)),
  ].take(10).toList();
}

// Snapshot fixtures vary hand/deck partitions independently of the V222 board.
AuthoritativeBattleState manaSabotageState({
  required PieceColor side,
  ManaSabotagePosition position = ManaSabotagePosition.open,
  List<CardId> hand = const [
    CardId.manaSabotage,
    CardId.radar,
    CardId.prophecy,
  ],
  List<CardId> opponentHand = const [
    CardId.radar,
    CardId.prophecy,
    CardId.shelter,
  ],
  List<CardId> deckPrefix = const [],
  List<CardId> opponentDeckPrefix = const [],
  int mana = 6,
  int opponentMana = 3,
  int ownTurn = 4,
  int opponentTurn = 3,
}) {
  final fen = switch (position) {
    ManaSabotagePosition.open => '4k3/pp3ppp/8/8/8/8/PP3PPP/4K3 w - - 0 12',
    ManaSabotagePosition.crowded =>
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 12',
    ManaSabotagePosition.inCheck =>
      '4r1k1/pp3ppp/8/8/8/8/PP3PPP/4K3 w - - 0 12',
  };
  final whiteBoard = Board.fromFen(fen);
  final board =
      side.isWhite
          ? whiteBoard
          : Board(
            squares: List.generate(64, (i) {
              final piece = whiteBoard.squares[i ^ 56];
              return piece?.copyWith(color: piece.color.opposite);
            }),
            turn: side,
            castling: 0,
            enPassant: null,
            halfmoveClock: 0,
            fullmoveNumber: 12,
          );
  final ownDeck = manaSabotageDeck(hand, deckPrefix);
  final enemyDeck = manaSabotageDeck(opponentHand, opponentDeckPrefix);
  final seed = DeckManager.newBattle(
    board: board,
    white: side.isWhite ? ownDeck : enemyDeck,
    black: side.isWhite ? enemyDeck : ownDeck,
  );
  final draft =
      RuleDraft(seed.rules)
        ..phase = BattlePhase.card
        ..terminal = null
        ..ownTurns[side] = ownTurn
        ..ownTurns[side.opposite] = opponentTurn
        ..mana[side] = mana
        ..mana[side.opposite] = opponentMana
        ..effectSequence = 40
        ..ply = 8
        ..repetitions.clear();
  final hands = <PieceColor, List<CardId>>{
    side: [...hand],
    side.opposite: [...opponentHand],
  };
  final decks = <PieceColor, List<CardId>>{
    side: ownDeck.skip(hand.length).toList(),
    side.opposite: enemyDeck.skip(opponentHand.length).toList(),
  };
  for (final color in PieceColor.values) {
    draft.handCounts[color] = hands[color]!.length;
    draft.deckCounts[color] = decks[color]!.length;
    draft.drawCounts[color] = hands[color]!.length;
  }
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: hands,
      decks: decks,
      knowledge: {
        for (final color in PieceColor.values) color: PlayerKnowledgeState(),
      },
    ),
  );
}

AuthoritativeBattleState manaSabotageEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

PendingModifier manaSabotageModifier({
  required String id,
  required PieceColor responseSide,
  required int ownTurn,
  CardId? target = CardId.radar,
  ModifierType type = ModifierType.manaSabotage,
}) => PendingModifier(
  id: id,
  type: type,
  owner: type == ModifierType.discount ? responseSide : responseSide.opposite,
  responseSide: responseSide,
  targetCard: type == ModifierType.discount ? null : target,
  ownTurn: ownTurn,
);

AuthoritativeBattleState manaSabotageTaxed(
  AuthoritativeBattleState state, {
  CardId target = CardId.radar,
  int taxes = 1,
  int discounts = 0,
  bool reverse = false,
}) => manaSabotageEdit(state, (draft) {
  final side = state.rules.board.turn;
  final modifiers = <PendingModifier>[
    for (var i = 0; i < taxes; i++)
      manaSabotageModifier(
        id: 'tax-$i',
        responseSide: side,
        ownTurn: draft.ownTurns[side]!,
        target: target,
      ),
    for (var i = 0; i < discounts; i++)
      manaSabotageModifier(
        id: 'discount-$i',
        responseSide: side,
        ownTurn: draft.ownTurns[side]!,
        type: ModifierType.discount,
      ),
  ];
  draft.modifiers.addAll(reverse ? modifiers.reversed : modifiers);
});

AuthoritativeBattleState manaSabotageRetireOpponentCard(
  AuthoritativeBattleState state,
  CardId card, {
  required bool discarded,
}) {
  final enemy = state.rules.board.turn.opposite;
  final hands = {
    for (final color in PieceColor.values)
      color: [...state.hidden.hands[color]!],
  };
  final decks = {
    for (final color in PieceColor.values)
      color: [...state.hidden.decks[color]!],
  };
  final wasInHand = hands[enemy]!.remove(card);
  if (!wasInHand && !decks[enemy]!.remove(card)) {
    throw ArgumentError('retired card must belong to fixture arsenal');
  }
  final draft = RuleDraft(state.rules);
  (discarded ? draft.discarded[enemy]! : draft.used[enemy]!).add(card);
  draft.handCounts[enemy] = hands[enemy]!.length;
  draft.deckCounts[enemy] = decks[enemy]!.length;
  if (!wasInHand) draft.drawCounts[enemy] = draft.drawCounts[enemy]! + 1;
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: hands,
      decks: decks,
      knowledge: state.hidden.knowledge,
    ),
  );
}

AuthoritativeBattleState manaSabotageSwapOpponentHidden(
  AuthoritativeBattleState state,
  CardId cardInHand,
  CardId cardInDeck,
) {
  final enemy = state.rules.board.turn.opposite;
  final hands = {
    for (final color in PieceColor.values)
      color: [...state.hidden.hands[color]!],
  };
  final decks = {
    for (final color in PieceColor.values)
      color: [...state.hidden.decks[color]!],
  };
  final handIndex = hands[enemy]!.indexOf(cardInHand);
  final deckIndex = decks[enemy]!.indexOf(cardInDeck);
  if (handIndex < 0 || deckIndex < 0) {
    throw ArgumentError('invalid hidden swap');
  }
  hands[enemy]![handIndex] = cardInDeck;
  decks[enemy]![deckIndex] = cardInHand;
  return AuthoritativeBattleState(
    state.rules,
    AuthoritativeHiddenState(
      hands: hands,
      decks: decks,
      knowledge: state.hidden.knowledge,
    ),
  );
}

AuthoritativeBattleState manaSabotageOpponentPartition(
  AuthoritativeBattleState state,
  List<CardId> order,
) {
  final enemy = state.rules.board.turn.opposite;
  final arsenal = state.rules.arsenals[enemy]!;
  if (order.length != 10 ||
      order.toSet().length != 10 ||
      order.any((card) => !arsenal.contains(card))) {
    throw ArgumentError('partition must conserve the original arsenal');
  }
  final handSize = state.hidden.hands[enemy]!.length;
  return AuthoritativeBattleState(
    state.rules,
    AuthoritativeHiddenState(
      hands: {...state.hidden.hands, enemy: order.take(handSize).toList()},
      decks: {...state.hidden.decks, enemy: order.skip(handSize).toList()},
      knowledge: state.hidden.knowledge,
    ),
  );
}

String manaSabotageOwnerMove(PieceColor side) => side.isWhite ? 'a2a3' : 'a7a6';
String manaSabotageReplyMove(PieceColor side) => side.isWhite ? 'h7h6' : 'h2h3';

typedef ManaSabotageCostRow =
    ({CardId card, int base, int taxes, int discounts, int expected});

// Literal oracles: sum all active adjustments, then clamp only the final minimum.
const manaSabotageCostRows = <ManaSabotageCostRow>[
  (card: CardId.radar, base: 1, taxes: 0, discounts: 0, expected: 1),
  (card: CardId.radar, base: 1, taxes: 1, discounts: 0, expected: 2),
  (card: CardId.radar, base: 1, taxes: 2, discounts: 0, expected: 3),
  (card: CardId.radar, base: 1, taxes: 1, discounts: 1, expected: 1),
  (card: CardId.radar, base: 1, taxes: 3, discounts: 2, expected: 1),
  (card: CardId.radar, base: 1, taxes: 5, discounts: 2, expected: 2),
  (card: CardId.shadowContract, base: 1, taxes: 1, discounts: 1, expected: 1),
  (card: CardId.shadowContract, base: 1, taxes: 4, discounts: 1, expected: 3),
  (card: CardId.freeze, base: 4, taxes: 1, discounts: 0, expected: 5),
  (card: CardId.freeze, base: 4, taxes: 1, discounts: 1, expected: 3),
  (card: CardId.freeze, base: 4, taxes: 2, discounts: 1, expected: 4),
  (card: CardId.boardSeal, base: 5, taxes: 1, discounts: 0, expected: 6),
  (card: CardId.boardSeal, base: 5, taxes: 2, discounts: 0, expected: 7),
  (card: CardId.boardSeal, base: 5, taxes: 3, discounts: 1, expected: 6),
  (card: CardId.boardSeal, base: 5, taxes: 1, discounts: 3, expected: 1),
  (card: CardId.manaSabotage, base: 2, taxes: 1, discounts: 0, expected: 3),
  (card: CardId.manaSabotage, base: 2, taxes: 2, discounts: 1, expected: 2),
];
