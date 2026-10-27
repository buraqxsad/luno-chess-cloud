import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/match/match_ai.dart';
import 'package:luno_chess/match/match_state.dart';

void main() {
  test('mat-in-1 bulur (Rh8#)', () {
    final b = Board.fromFen('k7/8/1K6/8/8/8/8/7R w - - 0 1');
    final mv = AiEngine().search(b, 3);
    final after = b.apply(mv);
    expect(
      MoveGen.legal(after).isEmpty,
      true,
      reason: 'rakibin hamlesi kalmamalı',
    );
    expect(
      MoveGen.inCheck(after, PieceColor.black),
      true,
      reason: 'şah mat olmalı (pat değil)',
    );
  });

  test('asılı veziri alır', () {
    // Beyaz kalesi h1; siyah vezir h4 bedava.
    final b = Board.fromFen('4k3/8/8/8/7q/8/8/4K2R w - - 0 1');
    final mv = AiEngine().search(b, 2);
    expect(
      b.pieceAt(mv.to)?.type,
      PieceType.queen,
      reason: 'AI bedava veziri almalı',
    );
  });

  test('başlangıçtan yasal hamle döndürür', () {
    final b = Board.start();
    final mv = AiEngine().search(b, 2);
    expect(MoveGen.legal(b).contains(mv), true);
  });

  test('UI disi AI aramasi yasal hamle dondurur', () async {
    final match = MatchState.newGame();
    final selected = await MatchAi().chooseMoveAsync(match, aiLevels[2]);

    expect(selected, isNotNull);
    final move = selected!;
    expect(
      match
          .allLegal(match.turn)
          .any(
            (candidate) => candidate[0] == move[0] && candidate[1] == move[1],
          ),
      isTrue,
    );
  });
}
