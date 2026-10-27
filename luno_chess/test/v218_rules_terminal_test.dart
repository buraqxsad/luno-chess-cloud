import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';

void main() {
  for (final (fen, uci, reason, half) in [
    ('7k/8/8/8/8/8/8/R3K3 w - - 149 1', 'a1a2', 'seventy_five_moves', 150),
    ('r3k3/8/8/8/8/8/8/7K b - - 149 1', 'a8a7', 'seventy_five_moves', 150),
    ('7k/8/5KQ1/8/8/8/8/8 w - - 149 1', 'g6g7', 'checkmate', 150),
    ('8/8/8/8/8/5kq1/8/7K b - - 149 1', 'g3g2', 'checkmate', 150),
    ('7k/8/8/8/8/8/4P3/4K3 w - - 149 1', 'e2e3', null, 0),
    ('7k/8/8/8/8/8/8/4K3 w - - 0 1', 'e1f1', null, 1),
  ]) {
    test('battle terminal boundary: $uci from $fen', () {
      final source = DeckManager.newBattle(board: Board.fromFen(fen));
      expect(source.rules.terminal, isNull);
      final side = source.rules.board.turn;
      final after = DeckManager.apply(source, ChessMoveAction(uci));
      expect(after.rules.terminal?.reason, reason);
      expect(after.rules.board.halfmoveClock, half);
      if (reason != null) {
        expect(after.rules.phase, BattlePhase.terminal);
        expect(after.rules.drawCounts[side], source.rules.drawCounts[side]);
        expect(after.rules.handCounts[side], source.rules.handCounts[side]);
        expect(
          after.rules.terminal!.winner,
          reason == 'checkmate' ? side : null,
        );
      }
    });
  }
}
