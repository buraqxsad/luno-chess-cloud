import 'dart:convert';

import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

const cardBlockQuietFen = 'r1b3k1/1n3ppp/8/8/8/8/1N3PPP/R1B3K1 w - - 0 21';

int cardBlockSquare(String text, PieceColor perspective) {
  final rank = int.parse(text[1]) - 1;
  return Square.of(
    text.codeUnitAt(0) - 97,
    perspective.isWhite ? rank : 7 - rank,
  );
}

String cardBlockMove(String whiteUci, PieceColor perspective) {
  if (perspective.isWhite) return whiteUci;
  return '${whiteUci[0]}${9 - int.parse(whiteUci[1])}'
      '${whiteUci[2]}${9 - int.parse(whiteUci[3])}${whiteUci.substring(4)}';
}

Board cardBlockBoard(String fen, PieceColor perspective) {
  final white = Board.fromFen(fen);
  if (perspective.isWhite) return white;
  return Board(
    squares: [
      for (var i = 0; i < 64; i++)
        white.squares[i ^ 56]?.copyWith(
          color: white.squares[i ^ 56]!.color.opposite,
        ),
    ],
    turn: white.turn.opposite,
    castling: ((white.castling & 3) << 2) | ((white.castling & 12) >> 2),
    enPassant: white.enPassant == null ? null : white.enPassant! ^ 56,
    halfmoveClock: white.halfmoveClock,
    fullmoveNumber: white.fullmoveNumber,
  );
}

List<CardId> _arsenal(List<CardId> first) {
  final distinct = first.toSet().toList();
  if (distinct.length > 10) throw ArgumentError('fixture-arsenal-overflow');
  return [
    ...distinct,
    ...CardId.values.where((c) => !distinct.contains(c)),
  ].take(10).toList();
}

/// Synthetic card boundary, not a claim that every combination is reachable.
/// Each side still has a complete, disjoint ten-card partition.
AuthoritativeBattleState cardBlockFixture({
  required PieceColor blocker,
  CardId target = CardId.prophecy,
  String fen = cardBlockQuietFen,
  List<CardId> casterHand = const [
    CardId.cardBlock,
    CardId.radar,
    CardId.shelter,
  ],
  List<CardId>? victimHand,
  List<CardId> victimDeckPrefix = const [],
  List<CardId> casterUsed = const [],
  List<CardId> victimUsed = const [],
  List<CardId> victimDiscarded = const [],
  int casterMana = 6,
  int victimMana = 6,
  int casterTurn = 4,
  int victimTurn = 4,
  bool removalTargets = false,
}) {
  final victim = blocker.opposite;
  final hand =
      victimHand ??
      {target, CardId.prophecy, CardId.shelter, CardId.radar}.take(3).toList();
  final consumed =
      {
        ...casterUsed,
        if (removalTargets && target == CardId.purify) CardId.chain,
        if (removalTargets && target == CardId.breakSeal) CardId.mine,
      }.toList();
  final casterArsenal = _arsenal([
    ...casterHand,
    ...consumed,
    CardId.prophecy,
    CardId.fateExchange,
    CardId.shadowContract,
    CardId.echo,
    CardId.manaSabotage,
  ]);
  final victimArsenal = _arsenal([
    ...hand,
    ...victimUsed,
    ...victimDiscarded,
    ...victimDeckPrefix,
    target,
  ]);
  final casterDeck =
      casterArsenal
          .where((c) => !casterHand.contains(c) && !consumed.contains(c))
          .toList();
  final victimDeck =
      victimArsenal
          .where(
            (c) =>
                !hand.contains(c) &&
                !victimUsed.contains(c) &&
                !victimDiscarded.contains(c),
          )
          .toList();
  final initial = DeckManager.newBattle(
    board: cardBlockBoard(fen, blocker),
    white: blocker.isWhite ? casterArsenal : victimArsenal,
    black: blocker.isWhite ? victimArsenal : casterArsenal,
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.card
        ..ownTurns[blocker] = casterTurn
        ..ownTurns[victim] = victimTurn
        ..mana[blocker] = casterMana
        ..mana[victim] = victimMana
        ..used[blocker] = consumed
        ..used[victim] = [...victimUsed]
        ..discarded[victim] = [...victimDiscarded]
        ..handCounts[blocker] = casterHand.length
        ..handCounts[victim] = hand.length
        ..deckCounts[blocker] = casterDeck.length
        ..deckCounts[victim] = victimDeck.length
        ..drawCounts[blocker] = 10 - casterDeck.length
        ..drawCounts[victim] = 10 - victimDeck.length
        ..effectSequence = 100
        ..repetitions = {};
  if (removalTargets && target == CardId.purify) {
    draft.pieceEffects.add(
      ActivePieceEffect(
        id: 'cb-chain',
        type: PieceEffectType.chain,
        owner: blocker,
        pieceId: draft.pieceIds[cardBlockSquare('f7', blocker)]!,
        responseSide: victim,
        duration: EffectDuration.move,
      ),
    );
  }
  if (removalTargets && target == CardId.breakSeal) {
    draft.boardEffects.add(
      BoardEffectInstance(
        id: 'cb-mine',
        type: BoardEffectType.mine,
        owner: blocker,
        squares: [cardBlockSquare('d4', blocker)],
        responseSide: victim,
        duration: EffectDuration.persistent,
      ),
    );
  }
  return AuthoritativeBattleState(
    draft.freeze(),
    AuthoritativeHiddenState(
      hands: {blocker: casterHand, victim: hand},
      decks: {blocker: casterDeck, victim: victimDeck},
      knowledge: {
        for (final side in PieceColor.values) side: PlayerKnowledgeState(),
      },
    ),
  );
}

AuthoritativeBattleState cardBlockEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState cardBlockRoundTrip(AuthoritativeBattleState state) =>
    AuthoritativeBattleState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map,
    );

AuthoritativeBattleState cardBlockReorderHand(
  AuthoritativeBattleState state,
  PieceColor side,
  List<CardId> hand,
) => AuthoritativeBattleState(
  state.rules,
  AuthoritativeHiddenState(
    hands: {...state.hidden.hands, side: hand},
    decks: state.hidden.decks,
    knowledge: state.hidden.knowledge,
  ),
);

AuthoritativeBattleState cardBlockCast(
  AuthoritativeBattleState state,
  CardId target,
) => DeckManager.apply(
  state,
  PlayCardAction(CardId.cardBlock, target: target.wire),
);

AuthoritativeBattleState cardBlockIncoming(
  AuthoritativeBattleState state,
  PieceColor blocker,
  CardId target, {
  String move = 'g1h1',
}) => DeckManager.apply(
  cardBlockCast(state, target),
  ChessMoveAction(cardBlockMove(move, blocker)),
);

// Literal witnesses from card rules and the quiet fixture, not legalActions.
PlayCardAction cardBlockWitness(CardId card, PieceColor victim) {
  final caster = victim.opposite;
  final sacrifice = card == CardId.radar ? CardId.shelter : CardId.radar;
  return switch (card) {
    CardId.radar ||
    CardId.manaSabotage ||
    CardId.cardBlock ||
    CardId.echo => PlayCardAction(card, target: 'radar'),
    CardId.prophecy => const PlayCardAction(CardId.prophecy),
    CardId.shelter || CardId.pawnDeviation || CardId.pawnAdvance =>
      PlayCardAction(card, target: cardBlockSquare('f7', caster)),
    CardId.chain || CardId.freeze || CardId.huntVow => PlayCardAction(
      card,
      target: cardBlockSquare('b2', caster),
    ),
    CardId.slow => PlayCardAction(card, target: cardBlockSquare('a1', caster)),
    CardId.purify => const PlayCardAction(CardId.purify, target: 'cb-chain'),
    CardId.breakSeal => const PlayCardAction(
      CardId.breakSeal,
      target: 'cb-mine',
    ),
    CardId.rookBend || CardId.shadowPass => PlayCardAction(
      card,
      target: cardBlockSquare('a8', caster),
    ),
    CardId.angryN => PlayCardAction(
      card,
      target: cardBlockSquare('b7', caster),
    ),
    CardId.fateExchange ||
    CardId.shadowContract => PlayCardAction(card, sacrifice: sacrifice),
    CardId.lockedSquare ||
    CardId.mine ||
    CardId.fog ||
    CardId.watchVow ||
    CardId.boardSeal => PlayCardAction(
      card,
      target: cardBlockSquare('e4', caster),
    ),
  };
}
