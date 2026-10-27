import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final action in ['restart', 'resign', 'leave']) {
    for (final change in ['replacement', 'paused']) {
      testWidgets('$action confirmation ignores $change game', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.instance;
        final original = store.data;
        addTearDown(() => store.data = original);
        store.data = PlayerData.initial();
        store.loaded = true;
        store.hasCompletedTutorial = true;
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
            builder: (_) => GameScreen(level: aiLevels.first, local: true),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(GameScreen));
        if (action == 'restart') {
          await tester.tap(find.byTooltip('Yeniden başlat'));
        } else {
          await tester.tap(find.byTooltip('Maç menüsü'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(action == 'resign' ? 'Maçı bitir' : 'Menüye dön'),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        if (change == 'replacement') {
          state.m = MatchState.newGame(
            white: ['barbarian'],
            black: ['barbarian'],
          );
        } else {
          state.didChangeAppLifecycleState(AppLifecycleState.paused);
        }
        final MatchState current = state.m;
        final label =
            action == 'restart'
                ? 'YENİDEN BAŞLAT'
                : action == 'resign'
                ? 'ONAYLA'
                : 'ÇIK';
        tester
            .widget<LunoButton>(
              find.byWidgetPredicate(
                (w) => w is LunoButton && w.label == label,
              ),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        expect(find.byType(GameScreen), findsOneWidget);
        expect(identical(state.m, current), isTrue);
        expect(current.over, isFalse);
        expect(current.moveCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
