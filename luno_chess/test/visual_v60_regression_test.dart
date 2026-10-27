import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
  ]) {
    for (final turn in ['W', 'B']) {
      testWidgets('Online hand $size turn $turn and busy controls', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.5),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
            home: OnlineMatchScreen(
              matchId: 'hand-fixture',
              initialView: {
                'status': 'active',
                'viewerColor': 'W',
                'turn': turn,
                'phase': 'card',
                'board': <Object?>[],
                'hand': kCards.keys.take(6).toList(),
                'mana': {'W': 10, 'B': 10},
                'player': {'name': 'Player'},
                'opponent': {'name': 'Opponent'},
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final action = find.byWidgetPredicate(
          (w) =>
              w is LunoButton &&
              (w.label == 'HAMLEYE GEÇ' || w.label == 'RAKİP OYNUYOR'),
        );
        expect(
          tester.widget<LunoButton>(action).onPressed,
          turn == 'W' ? isNotNull : isNull,
        );
        final dynamic state = tester.state(find.byType(OnlineMatchScreen));
        state.setState(() {
          state.busy = true;
        });
        await tester.pump();
        expect(tester.widget<LunoButton>(action).onPressed, isNull);
        expect(tester.takeException(), isNull);
        for (final entry in {-3: 1, 0: 1, 1: 1, 2: 2, 199: 100}.entries) {
          state.setState(() {
            state.view['phase'] = 'move';
            state.view['moveCount'] = entry.key;
          });
          await tester.pump();
          expect(find.text('Tur ${entry.value}'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
