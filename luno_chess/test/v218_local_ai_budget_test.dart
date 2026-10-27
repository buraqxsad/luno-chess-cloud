import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';

class _CountingEngine extends AiEngine {
  int evaluations = 0;

  @override
  int evaluateWhite(Board board) {
    evaluations++;
    return super.evaluateWhite(board);
  }
}

void main() {
  const level = AiLevel(
    id: 'budget-regression',
    name: '',
    desc: '',
    depth: 4,
    errorRate: .01,
    power: 0,
    rewardMult: 0,
  );

  for (final entry in ['search', 'pickAmong', 'pickMove']) {
    test('$entry does not search after an already exhausted budget', () {
      final board = Board.start();
      final engine = _CountingEngine();
      final legal = MoveGen.legal(board);
      final move = switch (entry) {
        'search' => engine.search(board, 4, budget: Duration.zero),
        'pickAmong' => engine.pickAmong(
          board,
          legal,
          level,
          Random(42),
          budget: Duration.zero,
        ),
        _ => engine.pickMove(board, level, Random(42), budget: Duration.zero),
      };
      expect(legal, contains(move));
      expect(engine.evaluations, 0);
    });
  }

  test('direct search rejects nonpositive depths instead of recursing', () {
    final engine = AiEngine();
    for (final depth in [0, -1, -100]) {
      expect(() => engine.search(Board.start(), depth), throwsArgumentError);
    }
  });

  test('a stopped engine can be reused for a complete search', () {
    final engine = _CountingEngine();
    engine.search(Board.start(), 4, budget: Duration.zero);
    final board = Board.fromFen('4k3/8/8/8/7q/8/8/4K2R w - - 0 1');
    final move = engine.search(board, 2);
    expect(move.uci, 'h1h4');
    expect(engine.evaluations, greaterThan(0));
  });
}
