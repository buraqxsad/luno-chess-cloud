import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_introduction_screen.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:http/testing.dart';
import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'v214_first_match_ui_test.dart' show resign, settleRoute;
import 'v215_visual_capture.dart';
import 'online_request_session_test.dart' show TestAuth;
import 'v214_active_deck_test.dart' show reply;

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
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      testWidgets(
        'V215 first-loop actual frames $language ${size.width} text150',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final suffix = '$language-${size.width.toInt()}';
          final online = LunoOnlineService.forTesting(
            bootstrap: () async {},
            auth: TestAuth(),
            playerStore: GameStore.instance,
            client: MockClient((_) async => reply(response())),
            appCheck: () async => 'check',
          );
          addTearDown(online.dispose);
          await tester.runAsync(online.start);
          GameStore.instance
            ..hasCompletedTutorial = true
            ..hasChosenUsername = true
            ..firstSessionMatchesStarted = 0;
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
          noOverflow(tester);
          await captureV215(tester, 'home-$suffix');
          await tester.tap(find.byKey(const ValueKey('home-primary-battle')));
          await settleRoute(tester);
          expect(find.byType(BattleV1Screen), findsOneWidget);
          noOverflow(tester);
          await captureV215(tester, 'battle-$suffix');
          await resign(tester);
          noOverflow(tester);
          await captureV215(tester, 'result-top-$suffix');
          await tester.ensureVisible(find.byKey(const ValueKey('result-deck')));
          noOverflow(tester);
          await captureV215(tester, 'result-actions-$suffix');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            shell(
              BattleDeckScreen(loadOverride: () async => response()),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          noOverflow(tester);
          await captureV215(tester, 'deck-$suffix');
          await tester.pumpWidget(const SizedBox());
          GameStore.instance.hasCompletedTutorial = false;
          GameStore.instance.introductionStep =
              IntroductionStage.mineConfirm.index;
          await tester.pumpWidget(
            shell(
              const BattleIntroductionScreen(),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          noOverflow(tester);
          await captureV215(tester, 'intro-mine-$suffix');
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(GameStore.instance.save);
        },
      );
    }
  }
}
