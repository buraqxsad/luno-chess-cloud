import '../engine/board.dart';
import '../engine/piece.dart';

enum CardId {
  radar,
  prophecy,
  shelter,
  chain,
  slow,
  pawnDeviation,
  pawnAdvance,
  lockedSquare,
  freeze,
  purify,
  mine,
  breakSeal,
  fog,
  manaSabotage,
  cardBlock,
  rookBend,
  angryN,
  shadowPass,
  huntVow,
  watchVow,
  echo,
  fateExchange,
  shadowContract,
  boardSeal;

  String get wire =>
      const {
        pawnDeviation: 'pawn_deviation',
        pawnAdvance: 'pawn_advance',
        lockedSquare: 'locked_square',
        breakSeal: 'break_seal',
        manaSabotage: 'mana_sabotage',
        cardBlock: 'card_block',
        rookBend: 'rook_bend',
        angryN: 'angry_n',
        shadowPass: 'shadow_pass',
        huntVow: 'hunt_vow',
        watchVow: 'watch_vow',
        fateExchange: 'fate_exchange',
        shadowContract: 'shadow_contract',
        boardSeal: 'board_seal',
      }[this] ??
      name;
  static CardId parse(String value) => values.firstWhere(
    (c) => c.wire == value,
    orElse: () => throw FormatException('Unknown card: $value'),
  );
}

enum BattlePhase { card, chess, pending, terminal }

enum Rarity { common, rare, epic, legendary }

enum CardCategory {
  knowledge,
  protection,
  restriction,
  movement,
  board,
  removal,
  modifier,
  vow,
}

enum CardTargetType {
  opponentCard,
  none,
  ownPiece,
  opponentPiece,
  opponentSlider,
  ownPawn,
  emptySquare,
  ownPieceEffect,
  opponentBoardEffect,
  zone,
  ownRook,
  ownKnight,
  ownBishopRook,
  sacrifice,
}

enum EffectDuration { card, move, pieceMove, persistent }

enum PieceEffectType { shelter, chain, slow, freeze, mineDebuff }

enum BoardEffectType { mine, lockedSquare, fog, boardSeal }

enum ModifierType { manaSabotage, cardBlock, echo, discount }

enum VowType { hunt, watch }

String sideWire(PieceColor side) => side == PieceColor.white ? 'w' : 'b';
PieceColor parseSide(String side) => switch (side) {
  'w' => PieceColor.white,
  'b' => PieceColor.black,
  _ => throw FormatException('Unknown side: $side'),
};
String enumWire(Enum value) => value.name.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);
T parseEnum<T extends Enum>(List<T> values, String wire) => values.firstWhere(
  (e) => enumWire(e) == wire,
  orElse: () => throw FormatException('Unknown enum: $wire'),
);
List<CardId> parseCards(Object? value) =>
    (value as List).map((c) => CardId.parse(c as String)).toList();
Map<PieceColor, T> parsePair<T>(Map raw, T Function(Object?) parser) => {
  for (final c in PieceColor.values) c: parser(raw[sideWire(c)]),
};
Map<String, Object?> pairJson<T>(
  Map<PieceColor, T> pair,
  Object? Function(T) encoder,
) => {for (final c in PieceColor.values) sideWire(c): encoder(pair[c] as T)};

class CardDefinition {
  final CardId id;
  final int cost;
  final Rarity rarity;
  final CardCategory category;
  final CardTargetType target;
  const CardDefinition(
    this.id,
    this.cost,
    this.rarity,
    this.category,
    this.target,
  );
  Map<String, Object> toJson() => {
    'id': id.wire,
    'cost': cost,
    'rarity': rarity.name,
    'category': category.name,
    'target': enumWire(target),
  };
}

const cardDefinitions = <CardId, CardDefinition>{
  CardId.radar: CardDefinition(
    CardId.radar,
    1,
    Rarity.common,
    CardCategory.knowledge,
    CardTargetType.opponentCard,
  ),
  CardId.prophecy: CardDefinition(
    CardId.prophecy,
    1,
    Rarity.rare,
    CardCategory.knowledge,
    CardTargetType.none,
  ),
  CardId.shelter: CardDefinition(
    CardId.shelter,
    2,
    Rarity.common,
    CardCategory.protection,
    CardTargetType.ownPiece,
  ),
  CardId.chain: CardDefinition(
    CardId.chain,
    2,
    Rarity.common,
    CardCategory.restriction,
    CardTargetType.opponentPiece,
  ),
  CardId.slow: CardDefinition(
    CardId.slow,
    2,
    Rarity.common,
    CardCategory.restriction,
    CardTargetType.opponentSlider,
  ),
  CardId.pawnDeviation: CardDefinition(
    CardId.pawnDeviation,
    2,
    Rarity.common,
    CardCategory.movement,
    CardTargetType.ownPawn,
  ),
  CardId.pawnAdvance: CardDefinition(
    CardId.pawnAdvance,
    2,
    Rarity.common,
    CardCategory.movement,
    CardTargetType.ownPawn,
  ),
  CardId.lockedSquare: CardDefinition(
    CardId.lockedSquare,
    2,
    Rarity.common,
    CardCategory.board,
    CardTargetType.emptySquare,
  ),
  CardId.freeze: CardDefinition(
    CardId.freeze,
    4,
    Rarity.rare,
    CardCategory.restriction,
    CardTargetType.opponentPiece,
  ),
  CardId.purify: CardDefinition(
    CardId.purify,
    1,
    Rarity.common,
    CardCategory.removal,
    CardTargetType.ownPieceEffect,
  ),
  CardId.mine: CardDefinition(
    CardId.mine,
    2,
    Rarity.rare,
    CardCategory.board,
    CardTargetType.emptySquare,
  ),
  CardId.breakSeal: CardDefinition(
    CardId.breakSeal,
    1,
    Rarity.rare,
    CardCategory.removal,
    CardTargetType.opponentBoardEffect,
  ),
  CardId.fog: CardDefinition(
    CardId.fog,
    3,
    Rarity.rare,
    CardCategory.protection,
    CardTargetType.zone,
  ),
  CardId.manaSabotage: CardDefinition(
    CardId.manaSabotage,
    2,
    Rarity.rare,
    CardCategory.modifier,
    CardTargetType.opponentCard,
  ),
  CardId.cardBlock: CardDefinition(
    CardId.cardBlock,
    3,
    Rarity.rare,
    CardCategory.modifier,
    CardTargetType.opponentCard,
  ),
  CardId.rookBend: CardDefinition(
    CardId.rookBend,
    2,
    Rarity.epic,
    CardCategory.movement,
    CardTargetType.ownRook,
  ),
  CardId.angryN: CardDefinition(
    CardId.angryN,
    3,
    Rarity.epic,
    CardCategory.movement,
    CardTargetType.ownKnight,
  ),
  CardId.shadowPass: CardDefinition(
    CardId.shadowPass,
    3,
    Rarity.epic,
    CardCategory.movement,
    CardTargetType.ownBishopRook,
  ),
  CardId.huntVow: CardDefinition(
    CardId.huntVow,
    2,
    Rarity.epic,
    CardCategory.vow,
    CardTargetType.opponentPiece,
  ),
  CardId.watchVow: CardDefinition(
    CardId.watchVow,
    2,
    Rarity.epic,
    CardCategory.vow,
    CardTargetType.emptySquare,
  ),
  CardId.echo: CardDefinition(
    CardId.echo,
    2,
    Rarity.epic,
    CardCategory.modifier,
    CardTargetType.opponentCard,
  ),
  CardId.fateExchange: CardDefinition(
    CardId.fateExchange,
    3,
    Rarity.legendary,
    CardCategory.knowledge,
    CardTargetType.sacrifice,
  ),
  CardId.shadowContract: CardDefinition(
    CardId.shadowContract,
    1,
    Rarity.legendary,
    CardCategory.modifier,
    CardTargetType.sacrifice,
  ),
  CardId.boardSeal: CardDefinition(
    CardId.boardSeal,
    5,
    Rarity.legendary,
    CardCategory.board,
    CardTargetType.zone,
  ),
};
const starterDeck = <CardId>[
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
];
const movementCards = <CardId>[
  CardId.pawnDeviation,
  CardId.pawnAdvance,
  CardId.rookBend,
  CardId.angryN,
  CardId.shadowPass,
];
void validateDeck(List<CardId> deck) {
  if (deck.length != 10 || deck.toSet().length != 10) {
    throw ArgumentError('invalid-deck');
  }
}

class ActivePieceEffect {
  final String id, pieceId;
  final PieceEffectType type;
  final PieceColor owner, responseSide;
  final EffectDuration duration;
  const ActivePieceEffect({
    required this.id,
    required this.type,
    required this.owner,
    required this.pieceId,
    required this.responseSide,
    required this.duration,
  });
  factory ActivePieceEffect.fromJson(Map j) => ActivePieceEffect(
    id: j['id'] as String,
    type: parseEnum(PieceEffectType.values, j['type'] as String),
    owner: parseSide(j['owner'] as String),
    pieceId: j['pieceId'] as String,
    responseSide: parseSide(j['responseSide'] as String),
    duration: parseEnum(EffectDuration.values, j['duration'] as String),
  );
  Map<String, Object> toJson() => {
    'id': id,
    'type': enumWire(type),
    'owner': sideWire(owner),
    'pieceId': pieceId,
    'responseSide': sideWire(responseSide),
    'duration': enumWire(duration),
  };
}

class BoardEffectInstance {
  final String id;
  final BoardEffectType type;
  final PieceColor owner, responseSide;
  final List<int> squares;
  final EffectDuration duration;
  BoardEffectInstance({
    required this.id,
    required this.type,
    required this.owner,
    required List<int> squares,
    required this.responseSide,
    required this.duration,
  }) : squares = List.unmodifiable(squares);
  factory BoardEffectInstance.fromJson(Map j) => BoardEffectInstance(
    id: j['id'] as String,
    type: parseEnum(BoardEffectType.values, j['type'] as String),
    owner: parseSide(j['owner'] as String),
    squares: (j['squares'] as List).cast<int>(),
    responseSide: parseSide(j['responseSide'] as String),
    duration: parseEnum(EffectDuration.values, j['duration'] as String),
  );
  Map<String, Object> toJson() => {
    'id': id,
    'type': enumWire(type),
    'owner': sideWire(owner),
    'squares': squares,
    'responseSide': sideWire(responseSide),
    'duration': enumWire(duration),
  };
}

class PendingModifier {
  final String id;
  final ModifierType type;
  final PieceColor owner, responseSide;
  final CardId? targetCard;
  final int ownTurn;
  const PendingModifier({
    required this.id,
    required this.type,
    required this.owner,
    required this.responseSide,
    required this.targetCard,
    required this.ownTurn,
  });
  factory PendingModifier.fromJson(Map j) => PendingModifier(
    id: j['id'] as String,
    type: parseEnum(ModifierType.values, j['type'] as String),
    owner: parseSide(j['owner'] as String),
    responseSide: parseSide(j['responseSide'] as String),
    targetCard:
        j['targetCard'] == null
            ? null
            : CardId.parse(j['targetCard'] as String),
    ownTurn: j['ownTurn'] as int,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'type': enumWire(type),
    'owner': sideWire(owner),
    'responseSide': sideWire(responseSide),
    'targetCard': targetCard?.wire,
    'ownTurn': ownTurn,
  };
}

class VowState {
  final String id;
  final VowType type;
  final PieceColor owner;
  final String? pieceId;
  final int? square;
  final int remainingMoves;
  const VowState({
    required this.id,
    required this.type,
    required this.owner,
    required this.pieceId,
    required this.square,
    required this.remainingMoves,
  });
  VowState tick() => VowState(
    id: id,
    type: type,
    owner: owner,
    pieceId: pieceId,
    square: square,
    remainingMoves: remainingMoves - 1,
  );
  factory VowState.fromJson(Map j) => VowState(
    id: j['id'] as String,
    type: parseEnum(VowType.values, j['type'] as String),
    owner: parseSide(j['owner'] as String),
    pieceId: j['pieceId'] as String?,
    square: j['square'] as int?,
    remainingMoves: j['remainingMoves'] as int,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'owner': sideWire(owner),
    'pieceId': pieceId,
    'square': square,
    'remainingMoves': remainingMoves,
  };
}

class SpecialMoveAuthorization {
  final CardId card;
  final int from;
  final List<String> moves;
  SpecialMoveAuthorization(this.card, this.from, List<String> moves)
    : moves = List.unmodifiable(moves);
  factory SpecialMoveAuthorization.fromJson(Map j) => SpecialMoveAuthorization(
    CardId.parse(j['card'] as String),
    j['from'] as int,
    (j['moves'] as List).cast<String>(),
  );
  Map<String, Object> toJson() => {
    'card': card.wire,
    'from': from,
    'moves': moves,
  };
}

class PendingResolution {
  final CardId card;
  final PieceColor owner;
  const PendingResolution(this.card, this.owner);
  factory PendingResolution.fromJson(Map j) => PendingResolution(
    CardId.parse(j['card'] as String),
    parseSide(j['owner'] as String),
  );
  Map<String, Object> toJson() => {'card': card.wire, 'owner': sideWire(owner)};
}

class TerminalState {
  final String reason;
  final PieceColor? winner;
  final bool mateByRestriction, mateBySpecialMove, stalemateByRestriction;
  const TerminalState(
    this.reason, {
    this.winner,
    this.mateByRestriction = false,
    this.mateBySpecialMove = false,
    this.stalemateByRestriction = false,
  });
  factory TerminalState.fromJson(Map j) => TerminalState(
    j['reason'] as String,
    winner: j['winner'] == null ? null : parseSide(j['winner'] as String),
    mateByRestriction: j['mateByRestriction'] as bool,
    mateBySpecialMove: j['mateBySpecialMove'] as bool,
    stalemateByRestriction: j['stalemateByRestriction'] as bool,
  );
  Map<String, Object?> toJson() => {
    'reason': reason,
    'winner': winner == null ? null : sideWire(winner!),
    'mateByRestriction': mateByRestriction,
    'mateBySpecialMove': mateBySpecialMove,
    'stalemateByRestriction': stalemateByRestriction,
  };
}

class RadarObservation {
  final CardId queriedCardId;
  final bool inHand, stale;
  final int observedTurn, opponentCumulativeDrawCountAtObservation;
  const RadarObservation(
    this.queriedCardId, {
    required this.inHand,
    required this.observedTurn,
    required this.opponentCumulativeDrawCountAtObservation,
    this.stale = false,
  });
  RadarObservation asStale() => RadarObservation(
    queriedCardId,
    inHand: inHand,
    observedTurn: observedTurn,
    opponentCumulativeDrawCountAtObservation:
        opponentCumulativeDrawCountAtObservation,
    stale: true,
  );
  factory RadarObservation.fromJson(Map j) {
    final result = j['result'];
    if (result != 'IN_HAND' && result != 'NOT_IN_HAND') {
      throw const FormatException('Invalid Radar observation result');
    }
    return RadarObservation(
      CardId.parse(j['queriedCardId'] as String),
      inHand: result == 'IN_HAND',
      observedTurn: j['observedTurn'] as int,
      opponentCumulativeDrawCountAtObservation:
          j['opponentCumulativeDrawCountAtObservation'] as int,
      stale: j['stale'] as bool,
    );
  }
  Map<String, Object> toJson() => {
    'queriedCardId': queriedCardId.wire,
    'result': inHand ? 'IN_HAND' : 'NOT_IN_HAND',
    'observedTurn': observedTurn,
    'opponentCumulativeDrawCountAtObservation':
        opponentCumulativeDrawCountAtObservation,
    'stale': stale,
  };
}

class PlayerKnowledgeState {
  final List<CardId> knownUpcomingCards, pendingCards;
  final List<RadarObservation> radarObservations;
  PlayerKnowledgeState({
    List<CardId> knownUpcomingCards = const [],
    List<CardId> pendingCards = const [],
    List<RadarObservation> radarObservations = const [],
  }) : knownUpcomingCards = List.unmodifiable(knownUpcomingCards),
       pendingCards = List.unmodifiable(pendingCards),
       radarObservations = List.unmodifiable(radarObservations);
  PlayerKnowledgeState copyWith({
    List<CardId>? knownUpcomingCards,
    List<CardId>? pendingCards,
    List<RadarObservation>? radarObservations,
  }) => PlayerKnowledgeState(
    knownUpcomingCards: knownUpcomingCards ?? this.knownUpcomingCards,
    pendingCards: pendingCards ?? this.pendingCards,
    radarObservations: radarObservations ?? this.radarObservations,
  );
  factory PlayerKnowledgeState.fromJson(Map j) => PlayerKnowledgeState(
    knownUpcomingCards: parseCards(j['knownUpcomingCards']),
    pendingCards: parseCards(j['pendingCards']),
    radarObservations:
        (j['radarObservations'] as List)
            .map((e) => RadarObservation.fromJson(e as Map))
            .toList(),
  );
  Map<String, Object> toJson() => {
    'knownUpcomingCards': knownUpcomingCards.map((c) => c.wire).toList(),
    'pendingCards': pendingCards.map((c) => c.wire).toList(),
    'radarObservations': radarObservations.map((e) => e.toJson()).toList(),
  };
}

class RuleState {
  final Board board;
  final List<String?> pieceIds;
  final List<String> movedPawns;
  final BattlePhase phase;
  final Map<PieceColor, int> mana, ownTurns, handCounts, deckCounts, drawCounts;
  final Map<PieceColor, List<CardId>> arsenals, used, discarded;
  final List<ActivePieceEffect> pieceEffects;
  final List<BoardEffectInstance> boardEffects;
  final List<PendingModifier> modifiers;
  final List<VowState> vows;
  final SpecialMoveAuthorization? special;
  final PendingResolution? pending;
  final TerminalState? terminal;
  final int effectSequence, ply;
  final Map<String, int> repetitions;
  RuleState({
    required this.board,
    required List<String?> pieceIds,
    required List<String> movedPawns,
    required this.phase,
    required Map<PieceColor, int> mana,
    required Map<PieceColor, int> ownTurns,
    required Map<PieceColor, int> handCounts,
    required Map<PieceColor, int> deckCounts,
    required Map<PieceColor, int> drawCounts,
    required Map<PieceColor, List<CardId>> arsenals,
    required Map<PieceColor, List<CardId>> used,
    required Map<PieceColor, List<CardId>> discarded,
    required List<ActivePieceEffect> pieceEffects,
    required List<BoardEffectInstance> boardEffects,
    required List<PendingModifier> modifiers,
    required List<VowState> vows,
    required this.special,
    required this.pending,
    required this.terminal,
    required this.effectSequence,
    required this.ply,
    required Map<String, int> repetitions,
  }) : pieceIds = List.unmodifiable(pieceIds),
       movedPawns = List.unmodifiable(movedPawns),
       mana = Map.unmodifiable(mana),
       ownTurns = Map.unmodifiable(ownTurns),
       handCounts = Map.unmodifiable(handCounts),
       deckCounts = Map.unmodifiable(deckCounts),
       drawCounts = Map.unmodifiable(drawCounts),
       arsenals = _cardPair(arsenals),
       used = _cardPair(used),
       discarded = _cardPair(discarded),
       pieceEffects = List.unmodifiable(pieceEffects),
       boardEffects = List.unmodifiable(boardEffects),
       modifiers = List.unmodifiable(modifiers),
       vows = List.unmodifiable(vows),
       repetitions = Map.unmodifiable(repetitions);
  static Map<PieceColor, List<CardId>> _cardPair(
    Map<PieceColor, List<CardId>> source,
  ) => Map.unmodifiable({
    for (final c in PieceColor.values) c: List<CardId>.unmodifiable(source[c]!),
  });
  String get fen =>
      '${board.positionKey()} ${board.halfmoveClock} ${board.fullmoveNumber}';
  factory RuleState.fromJson(Map j) => RuleState(
    board: Board.fromFen(j['fen'] as String),
    pieceIds: (j['pieceIds'] as List).cast<String?>(),
    movedPawns: (j['movedPawns'] as List).cast<String>(),
    phase: parseEnum(BattlePhase.values, j['phase'] as String),
    mana: parsePair(j['mana'] as Map, (v) => v as int),
    ownTurns: parsePair(j['ownTurns'] as Map, (v) => v as int),
    handCounts: parsePair(j['handCounts'] as Map, (v) => v as int),
    deckCounts: parsePair(j['deckCounts'] as Map, (v) => v as int),
    drawCounts: parsePair(j['drawCounts'] as Map, (v) => v as int),
    arsenals: parsePair(j['arsenals'] as Map, parseCards),
    used: parsePair(j['used'] as Map, parseCards),
    discarded: parsePair(j['discarded'] as Map, parseCards),
    pieceEffects:
        (j['pieceEffects'] as List)
            .map((e) => ActivePieceEffect.fromJson(e as Map))
            .toList(),
    boardEffects:
        (j['boardEffects'] as List)
            .map((e) => BoardEffectInstance.fromJson(e as Map))
            .toList(),
    modifiers:
        (j['modifiers'] as List)
            .map((e) => PendingModifier.fromJson(e as Map))
            .toList(),
    vows: (j['vows'] as List).map((e) => VowState.fromJson(e as Map)).toList(),
    special:
        j['special'] == null
            ? null
            : SpecialMoveAuthorization.fromJson(j['special'] as Map),
    pending:
        j['pending'] == null
            ? null
            : PendingResolution.fromJson(j['pending'] as Map),
    terminal:
        j['terminal'] == null
            ? null
            : TerminalState.fromJson(j['terminal'] as Map),
    effectSequence: j['effectSequence'] as int,
    ply: j['ply'] as int,
    repetitions: (j['repetitions'] as Map).cast<String, int>(),
  );
  Map<String, Object?> toJson() => {
    'fen': fen,
    'pieceIds': pieceIds,
    'movedPawns': movedPawns,
    'phase': phase.name,
    'mana': pairJson(mana, (v) => v),
    'ownTurns': pairJson(ownTurns, (v) => v),
    'handCounts': pairJson(handCounts, (v) => v),
    'deckCounts': pairJson(deckCounts, (v) => v),
    'drawCounts': pairJson(drawCounts, (v) => v),
    'arsenals': pairJson(arsenals, (v) => v.map((c) => c.wire).toList()),
    'used': pairJson(used, (v) => v.map((c) => c.wire).toList()),
    'discarded': pairJson(discarded, (v) => v.map((c) => c.wire).toList()),
    'pieceEffects': pieceEffects.map((e) => e.toJson()).toList(),
    'boardEffects': boardEffects.map((e) => e.toJson()).toList(),
    'modifiers': modifiers.map((e) => e.toJson()).toList(),
    'vows': vows.map((e) => e.toJson()).toList(),
    'special': special?.toJson(),
    'pending': pending?.toJson(),
    'terminal': terminal?.toJson(),
    'effectSequence': effectSequence,
    'ply': ply,
    'repetitions': repetitions,
  };
}

/// Mutable transaction-local copy. Never returned as a player or authority state.
class RuleDraft {
  Board board;
  List<String?> pieceIds;
  List<String> movedPawns;
  BattlePhase phase;
  Map<PieceColor, int> mana, ownTurns, handCounts, deckCounts, drawCounts;
  Map<PieceColor, List<CardId>> arsenals, used, discarded;
  List<ActivePieceEffect> pieceEffects;
  List<BoardEffectInstance> boardEffects;
  List<PendingModifier> modifiers;
  List<VowState> vows;
  SpecialMoveAuthorization? special;
  PendingResolution? pending;
  TerminalState? terminal;
  int effectSequence, ply;
  Map<String, int> repetitions;
  RuleDraft(RuleState s)
    : board = s.board,
      pieceIds = [...s.pieceIds],
      movedPawns = [...s.movedPawns],
      phase = s.phase,
      mana = {...s.mana},
      ownTurns = {...s.ownTurns},
      handCounts = {...s.handCounts},
      deckCounts = {...s.deckCounts},
      drawCounts = {...s.drawCounts},
      arsenals = {
        for (final c in PieceColor.values) c: [...s.arsenals[c]!],
      },
      used = {
        for (final c in PieceColor.values) c: [...s.used[c]!],
      },
      discarded = {
        for (final c in PieceColor.values) c: [...s.discarded[c]!],
      },
      pieceEffects = [...s.pieceEffects],
      boardEffects = [...s.boardEffects],
      modifiers = [...s.modifiers],
      vows = [...s.vows],
      special = s.special,
      pending = s.pending,
      terminal = s.terminal,
      effectSequence = s.effectSequence,
      ply = s.ply,
      repetitions = {...s.repetitions};
  RuleState freeze() => RuleState(
    board: board,
    pieceIds: pieceIds,
    movedPawns: movedPawns,
    phase: phase,
    mana: mana,
    ownTurns: ownTurns,
    handCounts: handCounts,
    deckCounts: deckCounts,
    drawCounts: drawCounts,
    arsenals: arsenals,
    used: used,
    discarded: discarded,
    pieceEffects: pieceEffects,
    boardEffects: boardEffects,
    modifiers: modifiers,
    vows: vows,
    special: special,
    pending: pending,
    terminal: terminal,
    effectSequence: effectSequence,
    ply: ply,
    repetitions: repetitions,
  );
}

class PlayerView {
  final RuleState rules;
  final PieceColor viewer;
  final List<CardId> ownHand;
  final PlayerKnowledgeState knowledge;
  PlayerView(this.rules, this.viewer, List<CardId> hand, this.knowledge)
    : ownHand = List.unmodifiable(hand);
  Map<String, Object?> toJson() => {
    'rules': rules.toJson(),
    'viewer': sideWire(viewer),
    'ownHand': ownHand.map((c) => c.wire).toList(),
    'knowledge': knowledge.toJson(),
  };
}

// JSON has one numeric type; the server also treats 8, 8.0 and 8e0 as equal.
Object? _actionTargetFromJson(Object? value) =>
    value is double &&
            value.isFinite &&
            value >= 0 &&
            value < 64 &&
            value == value.toInt()
        ? value.toInt()
        : value;

sealed class BattleAction {
  const BattleAction();
  String get key;
  Map<String, Object?> toJson();
  factory BattleAction.fromJson(Map j) => switch (j['type']) {
    'move' => ChessMoveAction(j['uci'] as String),
    'play' => PlayCardAction(
      CardId.parse(j['card'] as String),
      target: _actionTargetFromJson(j['target']),
      sacrifice:
          j['sacrifice'] == null
              ? null
              : CardId.parse(j['sacrifice'] as String),
    ),
    'discard' => DiscardAction(CardId.parse(j['card'] as String)),
    'pass' => const PassAction(),
    'resolve' => ResolveAction(
      parseCards(j['order']),
      selected:
          j['selected'] == null ? null : CardId.parse(j['selected'] as String),
    ),
    _ => throw const FormatException('Unknown action'),
  };
}

class ChessMoveAction extends BattleAction {
  final String uci;
  const ChessMoveAction(this.uci);
  @override
  String get key => 'move:$uci';
  @override
  Map<String, Object> toJson() => {'type': 'move', 'uci': uci};
}

class PlayCardAction extends BattleAction {
  final CardId card;
  final Object? target;
  final CardId? sacrifice;
  const PlayCardAction(this.card, {this.target, this.sacrifice});
  @override
  String get key =>
      'play:${card.wire}:${target ?? ''}:${sacrifice?.wire ?? ''}';
  @override
  Map<String, Object?> toJson() => {
    'type': 'play',
    'card': card.wire,
    if (target != null) 'target': target,
    if (sacrifice != null) 'sacrifice': sacrifice!.wire,
  };
}

class DiscardAction extends BattleAction {
  final CardId card;
  const DiscardAction(this.card);
  @override
  String get key => 'discard:${card.wire}';
  @override
  Map<String, Object> toJson() => {'type': 'discard', 'card': card.wire};
}

class PassAction extends BattleAction {
  const PassAction();
  @override
  String get key => 'pass';
  @override
  Map<String, Object> toJson() => {'type': 'pass'};
}

class ResolveAction extends BattleAction {
  final List<CardId> order;
  final CardId? selected;
  ResolveAction(List<CardId> order, {this.selected})
    : order = List.unmodifiable(order);
  @override
  String get key =>
      'resolve:${selected?.wire ?? ''}:${order.map((c) => c.wire).join(',')}';
  @override
  Map<String, Object?> toJson() => {
    'type': 'resolve',
    'order': order.map((c) => c.wire).toList(),
    if (selected != null) 'selected': selected!.wire,
  };
}

class RuleTransition {
  final RuleState rules;
  final PieceColor? draw;
  final CardId? radar;
  final int inspect;
  const RuleTransition(this.rules, {this.draw, this.radar, this.inspect = 0});
}
