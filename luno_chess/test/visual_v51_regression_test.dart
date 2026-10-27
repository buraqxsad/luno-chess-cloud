import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final alreadyFinished in [false, true]) {
    testWidgets(
      'AI resignation preserves correct result; finished=$alreadyFinished',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.instance;
        store.data = PlayerData.initial();
        store.loaded = true;
        store.hasCompletedTutorial = true;
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!,
                ),
            home: GameScreen(level: aiLevels.first),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final dynamic state = tester.state(find.byType(GameScreen));
        await tester.tap(find.byTooltip('Maç menüsü'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Teslim ol'));
        await tester.pumpAndSettle();
        expect(find.text('Teslim ol?'), findsOneWidget);
        if (alreadyFinished) state.m.result = MatchResult.draw;
        await tester.tap(find.text('ONAYLA'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          state.m.result,
          alreadyFinished ? MatchResult.draw : MatchResult.blackWins,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
