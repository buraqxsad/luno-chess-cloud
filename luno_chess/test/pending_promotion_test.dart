import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/match/mpiece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scenario in [
    'success',
    'cancel',
    'replacement',
    'turn',
    'ended',
    'paused',
  ]) {
    testWidgets('pending promotion handles $scenario without a stale move', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial();
      store.loaded = true;
      store.hasCompletedTutorial = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: GameScreen(level: aiLevels.first, local: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final dynamic state = tester.state(find.byType(GameScreen));
      final MatchState pending = state.m;
      for (var i = 0; i < 64; i++) {
        pending.board[i] = null;
      }
      pending.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
      pending.board[Square.of(4, 7)] = MPiece(PieceColor.black, PieceType.king);
      final from = Square.of(0, 6), to = Square.of(0, 7);
      pending.board[from] = MPiece(PieceColor.white, PieceType.pawn);
      pending.turn = PieceColor.white;
      state.setState(() {});
      await tester.pump();
      final tap =
          tester.widget<MatchBoardView>(find.byType(MatchBoardView)).onTap;
      tap(from);
      tap(to);
      await tester.pumpAndSettle();
      expect(find.text('PİYON TERFİSİ'), findsOneWidget);
      expect(pending.board[from]?.type, PieceType.pawn);
      switch (scenario) {
        case 'replacement':
          state.m = MatchState.newGame(
            white: ['barbarian'],
            black: ['barbarian'],
          );
        case 'turn':
          pending.turn = PieceColor.black;
        case 'ended':
          pending.result = MatchResult.blackWins;
        case 'paused':
          state.didChangeAppLifecycleState(AppLifecycleState.paused);
      }
      if (scenario == 'cancel') {
        Navigator.of(tester.element(find.text('PİYON TERFİSİ'))).pop();
      } else {
        await tester.tap(find.text('Vezir'));
      }
      await tester.pump(const Duration(milliseconds: 400));
      if (scenario == 'success') {
        expect(pending.board[from], isNull);
        expect(pending.board[to]?.type, PieceType.queen);
        expect(pending.moveCount, 1);
      } else {
        expect(pending.board[from]?.type, PieceType.pawn);
        expect(pending.board[to], isNull);
        expect(pending.moveCount, 0);
        if (scenario == 'replacement') expect(state.m.moveCount, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
