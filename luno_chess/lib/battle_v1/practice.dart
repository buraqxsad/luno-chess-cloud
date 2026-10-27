import '../engine/ai.dart';
import '../engine/piece.dart';
import 'model.dart';

const battlePracticeCards = [
  CardId.shelter,
  CardId.freeze,
  CardId.pawnAdvance,
  CardId.prophecy,
];

class BattleLearningCheckpoint {
  final int moves;
  final bool cast, discarded, passed;
  const BattleLearningCheckpoint({
    this.moves = 0,
    this.cast = false,
    this.discarded = false,
    this.passed = false,
  });
  factory BattleLearningCheckpoint.fromJson(Object? value) {
    if (value is! Map || value['schema'] != 1) {
      return const BattleLearningCheckpoint();
    }
    return BattleLearningCheckpoint(
      moves: value['moves'] is int ? (value['moves'] as int).clamp(0, 4) : 0,
      cast: value['cast'] == true,
      discarded: value['discarded'] == true,
      passed: value['passed'] == true,
    );
  }
  BattleLearningCheckpoint merge(BattleLearningCheckpoint next) =>
      BattleLearningCheckpoint(
        moves: (moves > next.moves ? moves : next.moves).clamp(0, 4),
        cast: cast || next.cast,
        discarded: discarded || next.discarded,
        passed: passed || next.passed,
      );
  Map<String, Object> toJson() => {
    'schema': 1,
    'moves': moves.clamp(0, 4),
    'cast': cast,
    'discarded': discarded,
    'passed': passed,
  };
}

class BattlePracticeProgress {
  final int stage;
  final bool onboarding;
  final bool guidedMatch;
  int moves;
  final Set<String> _accepted = {};
  bool cast, discarded, passed;
  bool resolved = false;
  BattleAction? lastAction;
  BattlePracticeProgress(
    this.stage, {
    this.onboarding = false,
    this.guidedMatch = false,
    BattleLearningCheckpoint checkpoint = const BattleLearningCheckpoint(),
  }) : moves = guidedMatch ? checkpoint.moves.clamp(0, 4) : 0,
       cast = guidedMatch && checkpoint.cast,
       discarded = guidedMatch && checkpoint.discarded,
       passed = guidedMatch && checkpoint.passed,
       assert(stage >= 0 && stage < (onboarding ? 3 : 4)),
       assert(!guidedMatch || (onboarding && stage == 0));
  BattleLearningCheckpoint get checkpoint => BattleLearningCheckpoint(
    moves: moves.clamp(0, 4),
    cast: cast,
    discarded: discarded,
    passed: passed,
  );
  bool get freePlay => onboarding && stage == 2;
  AiLevel get level => aiLevels[stage];
  CardId get card => battlePracticeCards[stage];
  List<CardId> get deck => [
    card,
    ...starterDeck.where((c) => c != card && c != CardId.purify),
    CardId.purify,
  ];
  bool get complete =>
      moves >= 4 &&
      (guidedMatch
          ? cast && discarded && passed
          : freePlay ||
              (cast && discarded && (card != CardId.prophecy || resolved)));

  bool get stopsPlay => complete && !freePlay;
  bool canFinish(PlayerView view) =>
      guidedMatch
          ? complete || view.rules.terminal != null
          : complete || (freePlay && view.rules.terminal != null);

  /// Lesson gates belong to the coach, not to the card rule engine.
  List<BattleAction> lessonActions(PlayerView view, List<BattleAction> legal) {
    if (guidedMatch ||
        freePlay ||
        complete ||
        view.rules.board.turn != view.viewer) {
      return legal;
    }
    if (view.rules.phase != BattlePhase.card) return legal;
    if (!cast) {
      final canTeach = legal.whereType<PlayCardAction>().any(
        (action) => action.card == card,
      );
      if (!canTeach) {
        return legal.whereType<PassAction>().toList();
      }
      return legal
          .where((action) => action is PlayCardAction && action.card == card)
          .toList();
    }
    if (!discarded && view.ownHand.isNotEmpty) {
      return legal.whereType<DiscardAction>().toList();
    }
    return legal;
  }

  void accepted(
    BattleAction action,
    PlayerView before,
    PlayerView after, {
    bool explicitCardPass = true,
  }) {
    if (before.viewer != PieceColor.white ||
        before.rules.board.turn != PieceColor.white ||
        after.rules.ply < before.rules.ply) {
      return;
    }
    if (identical(before.rules, after.rules) ||
        !_accepted.add(
          '${before.rules.ply}:${before.rules.effectSequence}:${action.key}',
        )) {
      return;
    }
    lastAction = action;
    if (action is ChessMoveAction && after.rules.ply == before.rules.ply + 1) {
      moves++;
    }
    if (action is PlayCardAction &&
        (guidedMatch ? action.target is int : action.card == card) &&
        after.rules.used[before.viewer]!.contains(action.card)) {
      cast = true;
    }
    if (action is DiscardAction &&
        after.rules.discarded[before.viewer]!.contains(action.card)) {
      discarded = true;
    }
    if (explicitCardPass &&
        action is PassAction &&
        before.rules.phase == BattlePhase.card &&
        after.rules.ply == before.rules.ply &&
        after.rules.phase == BattlePhase.chess) {
      passed = true;
    }
    if (action is ResolveAction && before.rules.pending?.card == card) {
      resolved = true;
    }
  }
}
