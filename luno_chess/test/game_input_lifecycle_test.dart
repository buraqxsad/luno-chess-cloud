import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_board.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('covered, paused and disposed board callbacks are inert', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
    GameStore.instance.hasCompletedTutorial = true;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: LunoTheme.dark,
        home: GameScreen(level: aiLevels.first, local: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final dynamic state = tester.state(find.byType(GameScreen));
    final tap =
        tester.widget<MatchBoardView>(find.byType(MatchBoardView)).onTap;
    final skip =
        tester
            .widget<LunoButton>(
              find.byWidgetPredicate(
                (w) => w is LunoButton && w.label == 'HAMLEYE GEÇ',
              ),
            )
            .onPressed!;
    final from = Square.of(4, 1), to = Square.of(4, 3);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pump(const Duration(milliseconds: 400));
    tap(from);
    tap(to);
    skip();
    expect(state.selected, isNull);
    expect(state.m.moveCount, 0);
    expect(state.m.cardUsed, false);
    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 400));
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    tap(from);
    skip();
    expect(state.selected, isNull);
    expect(state.m.cardUsed, false);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    tap(from);
    expect(state.selected, from);
    tap(to);
    await tester.pump();
    expect(state.m.moveCount, 1);
    expect(state.m.board[from], isNull);
    expect(state.m.board[to], isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tap(from);
    skip();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
