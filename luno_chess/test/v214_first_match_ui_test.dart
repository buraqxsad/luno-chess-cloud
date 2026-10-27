import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/first_session_telemetry.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'v214_social_safety_ui_test.dart' show capture;
import 'v214_active_deck_test.dart' show reply;
import 'battle_deck_account_test.dart' show response;
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:http/testing.dart';
import 'online_request_session_test.dart' show TestAuth;

Future<void> settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> resign(WidgetTester tester) async {
  await tester.tap(
    find.byTooltip('Maç menüsü').evaluate().isNotEmpty
        ? find.byTooltip('Maç menüsü')
        : find.byTooltip('Match menu'),
  );
  await settleRoute(tester);
  final label =
      find.text('Teslim ol').evaluate().isNotEmpty ? 'Teslim ol' : 'Resign';
  await tester.tap(find.text(label).last);
  await settleRoute(tester);
  await tester.tap(find.text(label).last);
  await settleRoute(tester);
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true
      ..hasCompletedTutorial = true
      ..hasChosenUsername = true
      ..firstSessionMatchesStarted = 0;
  });
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      testWidgets('first AI/result/rematch/Home journey $language $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: TestAuth(),
          playerStore: GameStore.instance,
          client: MockClient((request) async => reply(response())),
          appCheck: () async => 'check',
        );
        await tester.runAsync(online.start);
        // A first guest bind preserves the local onboarding fixture explicitly.
        GameStore.instance
          ..hasCompletedTutorial = true
          ..hasChosenUsername = true
          ..firstSessionMatchesStarted = 0;
        addTearDown(online.dispose);
        await tester.runAsync(online.getBattleV1Deck);
        await tester.pumpWidget(
          shell(
            HomeScreen(online: online),
            language: language,
            scale: 1.5,
            reduced: true,
          ),
        );
        await settleRoute(tester);
        final primary = find.byKey(const ValueKey('home-primary-battle'));
        expect(primary, findsOneWidget);
        expect(tester.getRect(primary).bottom, lessThanOrEqualTo(size.height));
        final home = tester.widget<InkWell>(primary).onTap!;
        await capture(tester, 'first-home-$language-${size.width.toInt()}');
        home();
        home();
        await settleRoute(tester);
        expect(find.byType(BattleV1Screen), findsOneWidget);
        final game = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
        expect(game.local, isFalse);
        expect(game.practiceStage, isNull);
        expect(GameStore.instance.firstSessionMatchesStarted, 1);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
          0,
        );
        noOverflow(tester);
        await capture(tester, 'first-ai-$language-${size.width.toInt()}');
        await resign(tester);
        final rematch = find.byKey(const ValueKey('local-rematch'));
        expect(rematch, findsOneWidget);
        final command = tester.widget<BattleCommand>(rematch);
        expect(command.primary, isTrue);
        expect(
          find.byKey(const ValueKey('training-result-policy')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('result-deck')), findsOneWidget);
        expect(GameStore.instance.firstSessionMatchCompleted, isTrue);
        noOverflow(tester);
        await capture(tester, 'first-result-$language-${size.width.toInt()}');
        final replay = command.onPressed!;
        replay();
        replay();
        await settleRoute(tester);
        expect(GameStore.instance.firstSessionMatchesStarted, 2);
        expect(find.byKey(const ValueKey('local-rematch')), findsNothing);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
          0,
        );
        await resign(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('result-home')));
        await tester.tap(find.byKey(const ValueKey('result-home')));
        await settleRoute(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
        final events =
            FirstSessionTelemetry.forStore(
              GameStore.instance,
            ).samples.map((s) => s.event).toSet();
        expect(
          events,
          containsAll([
            FirstSessionEvent.homeFirstSeen,
            FirstSessionEvent.firstMatchCtaPressed,
            FirstSessionEvent.firstMatchStarted,
            FirstSessionEvent.firstMatchFinished,
            FirstSessionEvent.resultSeen,
            FirstSessionEvent.secondMatchPressed,
            FirstSessionEvent.secondMatchStarted,
          ]),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(GameStore.instance.save);
        noOverflow(tester);
      });
    }
  }
}
