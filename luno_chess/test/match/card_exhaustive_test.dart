import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/cards/card_def.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/match/mpiece.dart';

MatchState _emptyMatch(String card) {
  final match = MatchState.newGame(white: [card], black: [card]);
  for (var index = 0; index < 64; index++) {
    match.board[index] = null;
  }
  match.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
  match.board[Square.of(4, 7)] = MPiece(PieceColor.black, PieceType.king);
  match.turn = PieceColor.white;
  match.mana[PieceColor.white] = 10;
  return match;
}

void _prepareCard(MatchState match, String key) {
  if (key == 'freeze') {
    match.board[Square.of(0, 6)] = MPiece(PieceColor.black, PieceType.pawn);
  } else if (key == 'poison_q') {
    match.board[Square.of(3, 7)] = MPiece(PieceColor.black, PieceType.queen);
  } else if (const [
    'resist1',
    'resist2',
    'resist3',
    'barbarian',
    'archer',
  ].contains(key)) {
    match.board[Square.of(0, 1)] = MPiece(
      PieceColor.white,
      key == 'resist2' ? PieceType.knight : PieceType.pawn,
    );
    if (key == 'archer') {
      match.board[Square.of(1, 2)] = MPiece(PieceColor.black, PieceType.rook);
    }
  } else if (key == 'angry_n') {
    match.board[Square.of(1, 0)] = MPiece(PieceColor.white, PieceType.knight);
  } else if (key == 'angry_b') {
    match.board[Square.of(2, 0)] = MPiece(PieceColor.white, PieceType.bishop);
  } else if (key == 'glue') {
    match.board[Square.of(3, 3)] = MPiece(PieceColor.white, PieceType.pawn);
    match.board[Square.of(4, 3)] = MPiece(PieceColor.white, PieceType.pawn);
  } else if (key == 'reinforce') {
    match.board[Square.of(4, 4)] = MPiece(PieceColor.white, PieceType.pawn);
  } else if (key == 'immunity') {
    match.board[Square.of(0, 1)] = MPiece(
      PieceColor.white,
      PieceType.knight,
      frozen: 2,
      poisoned: true,
      poisonedDur: 2,
      plagueUntil: 4,
      trapped: 2,
    );
  }
}

int? _targetFor(MatchState match, String key) {
  final card = kCards[key]!;
  if (card.target == CardTarget.none) return null;
  if (key == 'glue') return Square.of(3, 3);
  final targets = match.cardTargets(key);
  return targets.isEmpty ? null : targets.first;
}

void main() {
  test('skip-move cards expire en passant even after both sides skip', () {
    final match = _emptyMatch('freeze');
    match.board[36] = MPiece(PieceColor.white, PieceType.pawn, moved: true);
    match.board[35] = MPiece(PieceColor.black, PieceType.pawn, moved: true);
    match.board[0] = MPiece(PieceColor.white, PieceType.rook);
    match.board[56] = MPiece(PieceColor.black, PieceType.rook);
    match.epTarget = 43;
    match.mana[PieceColor.black] = 10;
    expect(match.legalFrom(36), contains(43));
    expect(match.playCard('freeze', idx: 56), isTrue);
    expect(match.epTarget, isNull);
    expect(match.playCard('freeze', idx: 0), isTrue);
    expect(match.turn, PieceColor.white);
    expect(match.legalFrom(36), isNot(contains(43)));
    expect(match.makeMove(36, 43), isFalse);
    expect(match.board[35]?.type, PieceType.pawn);
  });

  test('every catalog card resolves once with a valid target contract', () {
    expect(kCards.length, 29);
    for (final key in kCards.keys) {
      final match = _emptyMatch(key);
      _prepareCard(match, key);
      final target = _targetFor(match, key);
      final secondary = key == 'glue' ? Square.of(4, 3) : null;
      final before = match.manaOf(PieceColor.white);
      final played = match.playCard(key, idx: target, idx2: secondary);
      expect(played, isTrue, reason: 'card $key should have a valid setup');
      if (!kCards[key]!.skipMove) {
        expect(match.cardUsed, isTrue, reason: 'card $key must lock the phase');
      }
      expect(match.manaOf(PieceColor.white), lessThan(before));
    }
  });

  test('an upgraded held card can be played at a cheaper lower level', () {
    final match = _emptyMatch('trap3');
    match.mana[PieceColor.white] = 3;
    expect(match.playCard('trap1', idx: Square.of(3, 3)), isTrue);
    expect(match.traps[Square.of(3, 3)]?.lvl, 1);
    expect(match.manaOf(PieceColor.white), 0);
  });

  test('AI resolves the highest affordable level from an upgraded hand', () {
    final match = _emptyMatch('trap3');
    match.mana[PieceColor.white] = 3;
    final ai = MatchAi(_NoopRandom());
    String? played;
    for (var attempt = 0; attempt < 5 && played == null; attempt++) {
      played = ai.maybeCard(match, aiLevels.last);
    }
    expect(played, 'trap1');
    expect(match.traps.values.single.lvl, 1);
  });

  test('AI archer chooses a pawn that actually has a firing target', () {
    final match = _emptyMatch('archer');
    final quietPawn = Square.of(0, 1);
    final firingPawn = Square.of(2, 1);
    match.board[quietPawn] = MPiece(PieceColor.white, PieceType.pawn);
    match.board[firingPawn] = MPiece(PieceColor.white, PieceType.pawn);
    match.board[Square.of(3, 2)] = MPiece(PieceColor.black, PieceType.rook);

    final played = MatchAi(_NoopRandom()).maybeCard(match, aiLevels.last);

    expect(played, 'archer');
    expect(match.board[firingPawn]?.type, PieceType.pawn);
    expect(match.board[Square.of(3, 2)], isNull);
    expect(match.board[quietPawn]?.type, PieceType.pawn);
  });

  test('skipping the card phase keeps the same turn for the chess move', () {
    final match = MatchState.newGame();
    expect(match.turn, PieceColor.white);
    expect(match.cardUsed, isFalse);

    expect(match.skipCardPhase(), isTrue);
    expect(match.turn, PieceColor.white);
    expect(match.cardUsed, isTrue);
    expect(match.allLegal(PieceColor.white), isNotEmpty);

    final move = match.allLegal(PieceColor.white).first;
    expect(match.makeMove(move[0], move[1]), isTrue);
    expect(match.turn, PieceColor.black);
  });

  test(
    'every AI difficulty returns a legal move inside its bounded search',
    () {
      for (final level in aiLevels) {
        final match = MatchState.newGame();
        final chosen = MatchAi(_NoopRandom()).chooseMove(match, level);
        expect(chosen, isNotNull, reason: level.id);
        final legal = match.allLegal(PieceColor.white);
        expect(
          legal.any((move) => move[0] == chosen![0] && move[1] == chosen[1]),
          isTrue,
          reason: level.id,
        );
      }
    },
  );

  test('card target failures are atomic and do not consume mana', () {
    final match = _emptyMatch('reinforce');
    match.board[Square.of(4, 1)] = MPiece(PieceColor.white, PieceType.pawn);
    final before = match.manaOf(PieceColor.white);
    expect(match.playCard('reinforce', idx: Square.of(4, 1)), isFalse);
    expect(match.manaOf(PieceColor.white), before);
    expect(match.cardUsed, isFalse);

    final ghosts = _emptyMatch('ghosts');
    for (final file in [3, 4, 5]) {
      ghosts.board[Square.of(file, 1)] = MPiece(
        PieceColor.white,
        PieceType.pawn,
      );
    }
    expect(ghosts.playCard('ghosts'), isFalse);
    expect(ghosts.manaOf(PieceColor.white), 10);
    expect(ghosts.cardUsed, isFalse);
  });

  test('custom card attacks affect check and never permit king exposure', () {
    final angryKnight = _emptyMatch('angry_n');
    angryKnight.board[Square.of(3, 3)] = MPiece(
      PieceColor.black,
      PieceType.knight,
      angryN: true,
    );
    expect(angryKnight.inCheck(PieceColor.white), isTrue);

    final angryBishop = _emptyMatch('angry_b');
    angryBishop.board[Square.of(3, 0)] = MPiece(
      PieceColor.black,
      PieceType.bishop,
      angryB: true,
    );
    expect(angryBishop.attacked(Square.of(4, 0), PieceColor.black), isTrue);
  });

  test('glued pawns move as a safe pair and reject blocked partners', () {
    final match = _emptyMatch('glue');
    _prepareCard(match, 'glue');
    expect(
      match.playCard('glue', idx: Square.of(3, 3), idx2: Square.of(4, 3)),
      isTrue,
    );
    expect(match.board[Square.of(3, 3)]?.linkTo, Square.of(4, 3));
    expect(match.board[Square.of(4, 3)]?.linkTo, Square.of(3, 3));

    match.board[Square.of(3, 4)] = MPiece(PieceColor.white, PieceType.knight);
    expect(match.legalFrom(Square.of(4, 3)), isNot(contains(Square.of(4, 4))));

    final stale = _emptyMatch('glue');
    final pawn = MPiece(
      PieceColor.white,
      PieceType.pawn,
      linkTo: Square.of(4, 3),
    );
    stale.board[Square.of(3, 3)] = pawn;
    stale.board[Square.of(4, 3)] = MPiece(PieceColor.white, PieceType.pawn);
    expect(stale.legalFrom(Square.of(3, 3)), isEmpty);
  });

  test(
    'a glued partner resolves its landing trap without leaving a stale link',
    () {
      final match = _emptyMatch('glue');
      _prepareCard(match, 'glue');
      final first = Square.of(3, 3);
      final second = Square.of(4, 3);
      final partnerLanding = Square.of(4, 4);
      expect(match.playCard('glue', idx: first, idx2: second), isTrue);
      match.traps[partnerLanding] = Trap(PieceColor.black, 2, 3, 4);

      expect(match.makeMove(first, Square.of(3, 4)), isTrue);
      expect(match.board[Square.of(3, 4)]?.type, PieceType.pawn);
      expect(match.board[partnerLanding], isNull);
      expect(match.traps[partnerLanding], isNull);
      expect(match.board[Square.of(3, 4)]?.linkTo, isNull);
    },
  );

  test('a trap on the moving glued pawn prevents the partner from moving', () {
    final match = _emptyMatch('glue');
    _prepareCard(match, 'glue');
    final first = Square.of(3, 3);
    final second = Square.of(4, 3);
    final mainLanding = Square.of(3, 4);
    expect(match.playCard('glue', idx: first, idx2: second), isTrue);
    match.traps[mainLanding] = Trap(PieceColor.black, 2, 3, 4);

    expect(match.makeMove(first, mainLanding), isTrue);
    expect(match.board[mainLanding], isNull);
    expect(match.board[second]?.type, PieceType.pawn);
    expect(match.board[second]?.linkTo, isNull);
    expect(match.traps[mainLanding], isNull);
  });

  test('pit trap spares a king but locks it for the trap duration', () {
    final match = _emptyMatch('trap3');
    final king = Square.of(4, 0);
    final trapSquare = Square.of(5, 1);
    match.traps[trapSquare] = Trap(PieceColor.white, 2, 3, 4);
    expect(match.makeMove(king, trapSquare), isTrue);
    expect(match.board[trapSquare]?.type, PieceType.king);
    expect(match.board[trapSquare]?.trapped, 2);
  });

  test('an effect-locked side passes instead of becoming checkmate', () {
    final match = _emptyMatch('freeze');
    final whiteKing = Square.of(4, 0);
    match.board[Square.of(0, 7)] = MPiece(PieceColor.black, PieceType.rook);
    match.board[whiteKing]!.trapped = 2;
    match.forcePassTurn();
    expect(match.turn, PieceColor.black);
    expect(match.result, MatchResult.ongoing);
  });

  test('reinforce and ghosts never spawn onto blocked overlays', () {
    final reinforce = _emptyMatch('reinforce');
    final pawn = Square.of(4, 4);
    reinforce.board[pawn] = MPiece(PieceColor.white, PieceType.pawn);
    reinforce.traps[Square.of(4, 3)] = Trap(PieceColor.black, 2, 2, 4);
    expect(reinforce.playCard('reinforce', idx: pawn), isFalse);
    expect(reinforce.board[Square.of(4, 3)], isNull);

    final ghosts = _emptyMatch('ghosts');
    for (final file in [3, 4, 5]) {
      ghosts.blocks[Square.of(file, 1)] = 2;
    }
    expect(ghosts.playCard('ghosts'), isFalse);
    expect(ghosts.board.where((piece) => piece?.ghost == true), isEmpty);
  });

  test('capturing a linked piece clears its partner backlink', () {
    final match = _emptyMatch('card_block');
    final captured = MPiece(
      PieceColor.black,
      PieceType.pawn,
      linkTo: Square.of(2, 0),
    );
    final partner = MPiece(
      PieceColor.black,
      PieceType.pawn,
      linkTo: Square.of(1, 0),
    );
    match.board[Square.of(0, 0)] = MPiece(PieceColor.white, PieceType.rook);
    match.board[Square.of(1, 0)] = captured;
    match.board[Square.of(2, 0)] = partner;
    expect(match.makeMove(Square.of(0, 0), Square.of(1, 0)), isTrue);
    expect(match.board[Square.of(2, 0)]?.linkTo, isNull);
  });

  test('plague, immunity, medium, radar and capture effects retain state', () {
    final plague = _emptyMatch('plague');
    plague.board[Square.of(0, 1)] = MPiece(PieceColor.white, PieceType.pawn);
    plague.board[Square.of(0, 6)] = MPiece(PieceColor.black, PieceType.pawn);
    expect(plague.playCard('plague'), isTrue);
    expect(plague.board[Square.of(0, 1)]?.plagueUntil, 2);
    expect(plague.legalFrom(Square.of(0, 1)), isEmpty);

    final immunity = _emptyMatch('immunity');
    _prepareCard(immunity, 'immunity');
    expect(immunity.playCard('immunity', idx: Square.of(0, 1)), isTrue);
    final clean = immunity.board[Square.of(0, 1)]!;
    expect(clean.frozen, 0);
    expect(clean.plagueUntil, 0);
    expect(clean.poisoned, isFalse);
    expect(clean.trapped, 0);

    final medium = _emptyMatch('medium');
    expect(medium.playCard('medium'), isTrue);
    expect(medium.mediumActiveFor(PieceColor.white), isTrue);
    expect(medium.revealedHandFor(PieceColor.white), ['medium']);

    final radar = _emptyMatch('radar3');
    radar.traps[Square.of(2, 2)] = Trap(PieceColor.black, 2, 2, 4);
    expect(radar.playCard('radar3'), isTrue);
    expect(
      radar.traps[Square.of(2, 2)]!.revealedFor,
      contains(PieceColor.white),
    );
  });
}

class _NoopRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.0;

  @override
  int nextInt(int max) => 0;
}
