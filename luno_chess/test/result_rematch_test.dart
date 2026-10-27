import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'battle_deck_account_test.dart' show response;
import 'online_request_session_test.dart' show TestAuth;
import 'v214_active_deck_test.dart' show reply;
import 'v217_player_journey_support.dart' show journeyAwait, journeyPump;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

void main() {
  setupPracticeTestAssets();
  setUpAll(GameStore.instance.load);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });
  for (final local in [false, true]) {
    for (final result in [
      MatchResult.whiteWins,
      MatchResult.blackWins,
      MatchResult.draw,
    ]) {
      testWidgets('rematch starts clean once: local=$local result=$result', (
        tester,
      ) async {
        final store = GameStore.instance;
        final original = store.data;
        addTearDown(() => store.data = original);
        store.data = PlayerData.initial();
        store.loaded = true;
        store.hasCompletedTutorial = true;
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: TestAuth(),
          playerStore: store,
          client: MockClient((_) async => reply(response())),
          appCheck: () async => 'check',
        );
        addTearDown(online.dispose);
        await journeyAwait(tester, online.start);
        await journeyAwait(tester, online.getBattleV1Deck);
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
                (_) => ResultScreen(
                  result: result,
                  level: aiLevels.last,
                  reward: 0,
                  local: local,
                  timeControlMinutes: 3,
                  online: online,
                ),
          ),
        );
        await tester.pumpAndSettle();
        final callback =
            tester
                .widget<LunoButton>(
                  find.byWidgetPredicate(
                    (w) => w is LunoButton && w.label == 'TEKRAR OYNA',
                  ),
                )
                .onPressed!;
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('COVER')),
          ),
        );
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(find.text('COVER'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        callback();
        callback();
        await tester.pumpAndSettle();
        await journeyPump(tester);
        expect(find.byType(ResultScreen, skipOffstage: false), findsNothing);
        expect(
          find.byType(BattleV1Screen, skipOffstage: false),
          findsOneWidget,
        );
        final game = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
        expect(game.local, local);
        expect(game.level, aiLevels.last);
        expect(game.timeControlMinutes, 3);
        final match = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
        expect(match.rules.terminal, isNull);
        expect(match.rules.ply, 0);
        expect(match.rules.board.turn, PieceColor.white);
        expect(
          match.rules.board.squares.where((piece) => piece != null).length,
          32,
        );
        expect(match.ownHand, hasLength(3));
        expect(match.rules.handCounts[PieceColor.white], 3);
        expect(match.rules.deckCounts[PieceColor.white], 7);
        callback();
        await tester.pump();
        expect(
          find.byType(BattleV1Screen, skipOffstage: false),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await journeyAwait(tester, () => store.bindAccount(store.accountUid));
        await journeyAwait(tester, store.flush);
      });
    }
  }
}
