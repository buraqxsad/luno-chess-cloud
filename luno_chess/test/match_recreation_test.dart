import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'AI and local recreation preserve unfinished and finished results',
    (tester) async {
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      for (final local in [false, true]) {
        for (final complete in [false, true]) {
          SharedPreferences.setMockInitialValues({});
          store.data = PlayerData.fromJson(PlayerData.initial().toJson());
          store.loaded = true;
          store.hasCompletedTutorial = true;
          await tester.runAsync(store.save);
          final before = store.data.toJson();
          final initialGold = store.data.gold;
          final initialXp = store.data.passXp;
          final initialGames = store.data.gamesPlayed;
          final initialLosses = store.data.losses;
          var now = DateTime(2026, 9, 28);
          Widget game() => MaterialApp(
            theme: LunoTheme.dark,
            home: GameScreen(
              level: aiLevels.first,
              local: local,
              timeControlMinutes: 1,
              clockNow: () => now,
            ),
          );
          await tester.pumpWidget(game());
          await tester.pumpAndSettle();
          if (complete) {
            now = now.add(const Duration(seconds: 61));
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pumpAndSettle();
            expect(find.byType(ResultScreen), findsOneWidget);
            expect(store.data.gamesPlayed, initialGames + 1);
            expect(store.data.losses, initialLosses + 1);
            expect(store.data.gold, initialGold + (local ? 0 : 20));
            expect(store.data.passXp, initialXp + (local ? 0 : 15));
          } else {
            final tap =
                tester
                    .widget<MatchBoardView>(find.byType(MatchBoardView))
                    .onTap;
            tap(Square.of(4, 1));
            tap(Square.of(4, 3));
            final dynamic state = tester.state(find.byType(GameScreen));
            state.didChangeAppLifecycleState(AppLifecycleState.paused);
            expect((state.m as MatchState).moveCount, 1);
            expect(store.data.toJson(), before);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(store.flush);
          final expected = store.data.toJson();
          for (var launch = 0; launch < 2; launch++) {
            final restored = GameStore.createForTesting();
            await tester.runAsync(restored.load);
            expect(restored.data.toJson(), expected);
            store.data = restored.data;
            restored.dispose();
            await tester.pumpWidget(game());
            await tester.pumpAndSettle();
            final dynamic state = tester.state(find.byType(GameScreen));
            final MatchState fresh = state.m;
            expect(fresh.moveCount, 0);
            expect(fresh.over, isFalse);
            expect(find.byType(ResultScreen), findsNothing);
            expect(store.data.toJson(), expected);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 1));
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
