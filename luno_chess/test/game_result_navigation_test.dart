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
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final overlay in [
    'none',
    'promotion',
    'menu',
    'resign',
    'restart',
    'leave',
  ]) {
    testWidgets('clock expiry replaces game with overlay=$overlay', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial();
      store.loaded = true;
      store.hasCompletedTutorial = true;
      var now = DateTime(2026, 9, 28);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: const Scaffold(body: Text('ROOT')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder:
              (_) => GameScreen(
                level: aiLevels.first,
                local: true,
                timeControlMinutes: 1,
                clockNow: () => now,
              ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(GameScreen));
      final MatchState match = state.m;
      if (['menu', 'resign', 'leave'].contains(overlay)) {
        await tester.tap(find.byTooltip('Maç menüsü'));
        await tester.pumpAndSettle();
        if (overlay != 'menu') {
          await tester.tap(
            find.text(overlay == 'resign' ? 'Maçı bitir' : 'Menüye dön'),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
        }
      }
      if (overlay == 'restart') {
        await tester.tap(find.byTooltip('Yeniden başlat'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      }
      if (overlay == 'promotion') {
        for (var i = 0; i < 64; i++) {
          match.board[i] = null;
        }
        match.board[Square.of(4, 0)] = MPiece(PieceColor.white, PieceType.king);
        match.board[Square.of(4, 7)] = MPiece(PieceColor.black, PieceType.king);
        match.board[Square.of(0, 6)] = MPiece(PieceColor.white, PieceType.pawn);
        state.setState(() {});
        await tester.pump();
        final tap =
            tester.widget<MatchBoardView>(find.byType(MatchBoardView)).onTap;
        tap(Square.of(0, 6));
        tap(Square.of(0, 7));
        await tester.pumpAndSettle();
        expect(find.text('PİYON TERFİSİ'), findsOneWidget);
      }
      now = now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(match.result, MatchResult.blackWins);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.byType(GameScreen, skipOffstage: false), findsNothing);
      expect(find.text('PİYON TERFİSİ', skipOffstage: false), findsNothing);
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(match.moveCount, 0);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('ROOT'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
