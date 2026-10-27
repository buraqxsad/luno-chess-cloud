import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const prophecyWhite = PieceColor.white;
const prophecyBlack = PieceColor.black;
const prophecyDeck = <CardId>[
  CardId.prophecy,
  CardId.fateExchange,
  CardId.shelter,
  CardId.chain,
  CardId.slow,
  CardId.freeze,
  CardId.purify,
  CardId.radar,
  CardId.lockedSquare,
  CardId.echo,
];
const prophecyOpponentDeck = <CardId>[
  CardId.mine,
  CardId.freeze,
  CardId.purify,
  CardId.echo,
  CardId.manaSabotage,
  CardId.cardBlock,
  CardId.shelter,
  CardId.fog,
  CardId.chain,
  CardId.slow,
];
const prophecyFens = <String, String>{
  'opening': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 10',
  'quiet': '4k3/pp3ppp/8/8/8/8/PP3PPP/4K2R w - - 0 10',
  'rook-check': 'k3r3/8/8/8/8/8/3R4/4K3 w - - 0 10',
  'double-check': 'k3r3/8/8/8/1b6/8/3R4/4K3 w - - 0 10',
  'pinned-rook': 'k3r3/8/8/8/8/8/4R3/4K3 w - - 0 10',
  'en-passant': '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 10',
  'castling': '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 10',
  'mate-next': '7k/8/5KQ1/8/8/8/8/8 w - - 0 10',
  'stalemate-next': '7k/8/5K2/6Q1/8/8/8/8 w - - 0 10',
  'automatic-75': '4k3/pp3ppp/8/8/8/8/PP3PPP/4K2R w - - 149 10',
  'v223-pinned-ep': '4r1k1/8/8/3pP3/8/8/8/4K3 w - d6 0 10',
  'v223-discovered-ep': '6k1/8/8/r4pPK/8/8/8/8 w - f6 0 10',
  'v223-castle-transit': '4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 10',
  'v223-castle-check': 'k3r3/8/8/8/8/8/8/R3K2R w KQ - 0 10',
  'v223-bishop-pin': '4r1k1/8/8/8/8/8/4B3/4K3 w - - 0 10',
  'v223-queen-pin': '6k1/8/8/7b/8/8/4Q3/3K4 w - - 0 10',
  'v223-knight-check': '6k1/8/8/8/8/5n2/3P4/4K3 w - - 0 10',
  'v223-bishop-block': 'k7/8/8/8/1b6/8/8/3RK3 w - - 0 10',
  'v223-promotion': '1r2k3/6P1/8/8/8/8/8/K7 w - - 0 10',
  'v223-promotion-escape': 'r6k/1P6/8/8/8/8/8/K7 w - - 0 10',
  'v223-mate': '7k/5Q2/6K1/8/8/8/8/8 w - - 0 10',
  'v223-dense-castle':
      'r3k2r/ppp2ppp/2n2n2/3p4/3P4/2N2N2/PPP2PPP/R3K2R w KQkq - 0 10',
  'v223-fortress': '4k3/8/8/2p1p3/2P1P3/8/8/4K3 w - - 0 10',
  'v223-capture-rook': '4k3/8/8/8/8/8/p7/R3K3 w - - 0 10',
};

String prophecyMirrorUci(String uci, PieceColor side) {
  if (side.isWhite) return uci;
  String square(String text) => Square.algebraic(
    prophecyMirrorSquare(
      Square.of(text.codeUnitAt(0) - 97, int.parse(text[1]) - 1),
    ),
  );
  return '${square(uci.substring(0, 2))}${square(uci.substring(2, 4))}'
      '${uci.length == 5 ? uci[4] : ''}';
}

// These expectations are authored from chess geometry, not legalActions output.
const prophecyGeometryExpectations =
    <String, ({List<String> allowed, List<String> forbidden})>{
      'v223-pinned-ep': (allowed: ['e5e6'], forbidden: ['e5d6']),
      'v223-discovered-ep': (allowed: ['g5g6'], forbidden: ['g5f6']),
      'v223-castle-transit': (allowed: ['e1c1'], forbidden: ['e1g1']),
      'v223-castle-check': (allowed: ['e1d1'], forbidden: ['e1c1', 'e1g1']),
      'v223-bishop-pin': (allowed: ['e1d1'], forbidden: ['e2d3', 'e2f3']),
      'v223-queen-pin': (allowed: ['e2f3', 'e2h5'], forbidden: ['e2e3']),
      'v223-knight-check': (allowed: ['e1e2'], forbidden: ['d2d3', 'd2d4']),
      'v223-bishop-block': (allowed: ['d1d2'], forbidden: ['d1d3']),
      'v223-promotion': (
        allowed: ['g7g8q', 'g7g8r', 'g7g8b', 'g7g8n'],
        forbidden: ['g7g8'],
      ),
      'v223-promotion-escape': (
        allowed: ['b7a8q', 'b7a8r', 'b7a8b', 'b7a8n'],
        forbidden: ['b7b8q', 'b7b8n'],
      ),
      'v223-mate': (allowed: ['f7g7'], forbidden: ['g6h7']),
    };

int prophecyMirrorSquare(int square) =>
    Square.of(Square.fileOf(square), 7 - Square.rankOf(square));

Board prophecyBoard(String fen, PieceColor side) {
  final white = Board.fromFen(fen);
  if (side == prophecyWhite) return white;
  return Board(
    squares: [
      for (var square = 0; square < 64; square++)
        white.squares[prophecyMirrorSquare(square)]?.copyWith(
          color: white.squares[prophecyMirrorSquare(square)]!.color.opposite,
        ),
    ],
    turn: prophecyBlack,
    castling: ((white.castling & 3) << 2) | ((white.castling & 12) >> 2),
    enPassant:
        white.enPassant == null ? null : prophecyMirrorSquare(white.enPassant!),
    halfmoveClock: white.halfmoveClock,
    fullmoveNumber: white.fullmoveNumber,
  );
}

AuthoritativeBattleState prophecyCase({
  PieceColor side = prophecyWhite,
  String position = 'quiet',
  int deckCount = 7,
  int mana = 6,
  int handCount = 3,
  bool known = false,
  List<ModifierType> modifiers = const [],
  bool responseEffects = false,
}) {
  final discounted = modifiers.contains(ModifierType.discount);
  if (deckCount < 0 ||
      deckCount > 10 - handCount - (discounted ? 1 : 0) ||
      handCount < 3 ||
      handCount > 4) {
    throw ArgumentError('invalid-prophecy-case-counts');
  }
  final activeDeck = [...prophecyDeck];
  if (discounted) activeDeck[9] = CardId.shadowContract;
  final initial = DeckManager.newBattle(
    board: prophecyBoard(prophecyFens[position]!, side),
    white: side.isWhite ? activeDeck : prophecyOpponentDeck,
    black: side.isWhite ? prophecyOpponentDeck : activeDeck,
  );
  final hand = activeDeck.take(handCount).toList();
  final deck =
      activeDeck
          .skip(handCount)
          .where((c) => !discounted || c != CardId.shadowContract)
          .take(deckCount)
          .toList();
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
        ..ownTurns[side] = 4
        ..ownTurns[side.opposite] = 4
        ..mana[side] = mana
        ..mana[side.opposite] = 2
        ..handCounts[side] = hand.length
        ..deckCounts[side] = deck.length
        ..drawCounts[side] = hand.length
        ..used[side] = discounted ? [CardId.shadowContract] : []
        ..discarded[side] =
            activeDeck
                .where(
                  (c) =>
                      !hand.contains(c) &&
                      !deck.contains(c) &&
                      (!discounted || c != CardId.shadowContract),
                )
                .toList()
        ..repetitions = {}
        ..effectSequence = 40;
  final hands = {
    for (final color in PieceColor.values)
      color: color == side ? hand : [...initial.hidden.hands[color]!],
  };
  final decks = {
    for (final color in PieceColor.values)
      color: color == side ? deck : [...initial.hidden.decks[color]!],
  };
  void consumeOpponent(CardId card) {
    if (!hands[side.opposite]!.remove(card)) {
      decks[side.opposite]!.remove(card);
    }
    draft.used[side.opposite]!.add(card);
    draft.handCounts[side.opposite] = hands[side.opposite]!.length;
    draft.deckCounts[side.opposite] = decks[side.opposite]!.length;
  }

  for (final (index, type) in modifiers.indexed) {
    final card = switch (type) {
      ModifierType.echo => CardId.echo,
      ModifierType.manaSabotage => CardId.manaSabotage,
      ModifierType.cardBlock => CardId.cardBlock,
      ModifierType.discount => CardId.shadowContract,
    };
    if (type != ModifierType.discount) consumeOpponent(card);
    draft.modifiers.add(
      PendingModifier(
        id: 'prophecy-modifier-$index',
        type: type,
        owner: type == ModifierType.discount ? side : side.opposite,
        responseSide: side,
        targetCard: type == ModifierType.discount ? null : CardId.prophecy,
        ownTurn: draft.ownTurns[side]!,
      ),
    );
  }
  if (responseEffects) {
    consumeOpponent(CardId.fog);
    consumeOpponent(CardId.shelter);
    consumeOpponent(CardId.slow);
    final ownRook = draft.board.squares.indexWhere(
      (p) => p?.color == side && p?.type == PieceType.rook,
    );
    final enemyPawn = draft.board.squares.indexWhere(
      (p) => p?.color == side.opposite && p?.type == PieceType.pawn,
    );
    if (ownRook < 0 || enemyPawn < 0) {
      throw ArgumentError('response-effects-require-quiet-position');
    }
    draft.boardEffects.add(
      BoardEffectInstance(
        id: 'prophecy-fog',
        type: BoardEffectType.fog,
        owner: side.opposite,
        squares: side.isWhite ? [16, 17, 24, 25] : [40, 41, 48, 49],
        responseSide: side,
        duration: EffectDuration.card,
      ),
    );
    draft.pieceEffects.addAll([
      ActivePieceEffect(
        id: 'prophecy-shelter',
        type: PieceEffectType.shelter,
        owner: side.opposite,
        pieceId: draft.pieceIds[enemyPawn]!,
        responseSide: side,
        duration: EffectDuration.card,
      ),
      ActivePieceEffect(
        id: 'prophecy-slow',
        type: PieceEffectType.slow,
        owner: side.opposite,
        pieceId: draft.pieceIds[ownRook]!,
        responseSide: side,
        duration: EffectDuration.move,
      ),
    ]);
  }
  for (final color in PieceColor.values) {
    draft.used[color]!.sort((a, b) => a.wire.compareTo(b.wire));
    draft.discarded[color]!.sort((a, b) => a.wire.compareTo(b.wire));
  }
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: hands,
      decks: decks,
      knowledge: {
        for (final color in PieceColor.values)
          color: PlayerKnowledgeState(
            knownUpcomingCards:
                color == side && known ? deck.take(2).toList() : [],
          ),
      },
    ),
  );
}

AuthoritativeBattleState prophecyCast(AuthoritativeBattleState state) =>
    DeckManager.apply(state, const PlayCardAction(CardId.prophecy));

AuthoritativeBattleState prophecyResolve(
  AuthoritativeBattleState state, {
  bool reverse = true,
}) => DeckManager.apply(
  state,
  ResolveAction(
    reverse
        ? state
            .view(state.rules.board.turn)
            .knowledge
            .pendingCards
            .reversed
            .toList()
        : state.view(state.rules.board.turn).knowledge.pendingCards,
  ),
);

AuthoritativeBattleState prophecyPassMove(
  AuthoritativeBattleState state,
  String uci,
) {
  if (state.rules.phase == BattlePhase.card) {
    state = DeckManager.apply(state, const PassAction());
  }
  return DeckManager.apply(state, ChessMoveAction(uci));
}

List<String> prophecyChess(AuthoritativeBattleState state) {
  final side = state.rules.board.turn;
  if (state.rules.phase == BattlePhase.card) {
    state = DeckManager.apply(state, const PassAction());
  }
  return BattleRulesCore.legalActions(
    state.view(side),
  ).whereType<ChessMoveAction>().map((a) => a.uci).toList();
}
