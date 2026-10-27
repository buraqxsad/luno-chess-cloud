import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final local in [false, true]) {
    for (final result in [
      MatchResult.whiteWins,
      MatchResult.blackWins,
      MatchResult.draw,
    ]) {
      testWidgets('Result presentation local=$local result=$result', (
        tester,
      ) async {
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
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                ),
            home: ResultScreen(
              result: result,
              level: aiLevels.first,
              reward: 999999,
              local: local,
            ),
          ),
        );
        await tester.pump();
        final art =
            result == MatchResult.draw
                ? LunoAssets.resultDraw
                : local || result == MatchResult.whiteWins
                ? LunoAssets.resultVictory
                : LunoAssets.resultDefeat;
        expect(
          find.byWidgetPredicate((w) => w is LunoArt && w.path == art),
          findsOneWidget,
        );
        expect(
          find.text('+999999 altın'),
          !local && result == MatchResult.whiteWins
              ? findsOneWidget
              : findsNothing,
        );
        await tester.ensureVisible(find.text('TEKRAR OYNA'));
        await tester.ensureVisible(find.text('ANA MENÜ'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
