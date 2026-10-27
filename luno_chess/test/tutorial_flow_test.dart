import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'helpers/live_onboarding_driver.dart';
import 'rc_tutorial_interaction_gate_test.dart' show completeLesson;
import 'v217_player_journey_support.dart';

void main() {
  setupPracticeTestAssets();
  setUp(() async {
    await LunoSettings.instance.setLanguage(LunoSettings.languageTurkish);
    final store = GameStore.instance;
    store.data = PlayerData.initial();
    store.loaded = true;
    store.hasChosenUsername = false;
    store.hasCompletedTutorial = false;
    store.tutorialStep = 0;
    store.introductionStep = 0;
    store.onboardingBattleStage = 0;
    store.welcomeStep = 0;
    store.firstSessionMatchesStarted = 0;
    store.practiceStage = null;
  });

  void prepare(WidgetTester tester) {
    journeyViewport(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await journeyFlush(tester, GameStore.instance);
    });
  }

  Future<void> freshFlow(WidgetTester tester) async {
    prepare(tester);
    await tester.pumpWidget(const LunoAppShell());
    expect(find.byType(LunoLoadingArtwork), findsOneWidget);
    expect(find.byType(BattleWelcomeScreen), findsNothing);
    await showLiveOnboarding(tester);
    expect(find.byKey(const ValueKey('tutorial-onboarding')), findsOneWidget);
    expect(find.byType(BattlePracticeCampaign), findsOneWidget);
    expect(find.byType(BattleWelcomeScreen), findsOneWidget);
    expect(find.byType(TutorialScreen), findsNothing);
    expect(find.text('ATLA'), findsNothing);
    await advanceLiveWelcome(tester);
    expect(find.byType(BattleV1Screen), findsOneWidget);
    expect(find.byType(UsernameSetupScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    final pawn = find.byKey(const ValueKey('square-8'));
    expect(pawn.hitTestable(), findsOneWidget);
    await journeyTap(tester, pawn);
    final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
    expect(board.selected, 8);
    expect(board.targets, containsAll([16, 24]));
    expect(board.view.rules.terminal, isNull);
    final coach = tester.widget<BattlePracticeCoach>(
      find.byType(BattlePracticeCoach),
    );
    expect(coach.progress.guidedMatch, isTrue);
    expect(coach.progress.canFinish(board.view), isFalse);
    expect(find.byKey(const ValueKey('practice-next')), findsNothing);
    expect(GameStore.instance.hasCompletedTutorial, isFalse);
    expect(GameStore.instance.firstSessionMatchCompleted, isFalse);
  }

  Future<void> terminalFlow(WidgetTester tester) async {
    prepare(tester);
    final store = GameStore.instance;
    final initialPlayer = store.data.toJson();
    final initialRank = (store.rankTrophies, store.rankArenaIdx);
    await tester.pumpWidget(const LunoAppShell());
    await completeLiveOnboarding(tester);
    expect(store.hasCompletedTutorial, isTrue);
    expect(store.firstSessionMatchCompleted, isTrue);
    expect(store.firstSessionMatchesStarted, 1);
    expect(store.needsFirstSessionMatch, isFalse);
    expect(store.tutorialStep, 0);
    expect(store.practiceStage, isNull);
    expect(store.data.toJson(), initialPlayer);
    expect((store.rankTrophies, store.rankArenaIdx), initialRank);
    expect(find.byType(BattleV1Screen), findsNothing);
    expect(find.byType(UsernameSetupScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.enterText(find.byType(TextField), 'YeniOyuncu');
    await journeyTap(tester, find.text('ÇEVRİMDIŞI DEVAM ET'));
    expect(store.hasChosenUsername, isTrue);
    expect(store.data.username, 'yenioyuncu');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BattleV1Screen), findsNothing);
    await journeyTap(tester, find.byKey(const ValueKey('home-primary-battle')));
    expect(find.byType(PlayModeScreen), findsOneWidget);
    expect(find.byType(BattleV1Screen), findsNothing);
    expect(store.firstSessionMatchesStarted, 1);
  }

  Future<void> resumeFlow(WidgetTester tester) async {
    prepare(tester);
    final store = GameStore.instance;
    await tester.pumpWidget(const LunoAppShell());
    await showLiveOnboarding(tester);
    await journeyTap(tester, find.byKey(const ValueKey('welcome-next')));
    expect(store.welcomeStep, 1);
    await journeyFlush(tester, store);
    final restored = GameStore.createForTesting();
    addTearDown(restored.dispose);
    await journeyAwait(tester, restored.load);
    expect(restored.welcomeStep, 1);
    expect(restored.hasCompletedTutorial, isFalse);
    expect(restored.firstSessionMatchCompleted, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await journeyPump(tester);
    await tester.pumpWidget(const LunoAppShell());
    await showLiveOnboarding(tester);
    expect(find.byKey(const ValueKey('welcome-title-1')), findsOneWidget);
    await advanceLiveWelcome(tester);
    expect(store.welcomeStep, 3);
    expect(store.hasCompletedTutorial, isFalse);
    expect(store.firstSessionMatchCompleted, isFalse);
    expect(find.byType(UsernameSetupScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  }

  Future<void> optionalGuide(WidgetTester tester) async {
    prepare(tester);
    tester.view.physicalSize = const Size(320, 568);
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
        home: const TutorialScreen(),
      ),
    );
    VoidCallback? oldTap;
    for (var index = 0; index < 9; index++) {
      expect(find.text('REHBER  ${index + 1}/10'), findsOneWidget);
      await completeLesson(tester, index);
      final button = find.byWidgetPredicate(
        (w) => w is LunoButton && w.label == 'DEVAM ET',
      );
      expect(button.hitTestable(), findsOneWidget);
      oldTap = tester.widget<LunoButton>(button).onPressed!;
      await tester.tap(button);
      oldTap();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('REHBER  10/10'), findsOneWidget);
    expect(GameStore.instance.hasCompletedTutorial, isFalse);
    expect(GameStore.instance.firstSessionMatchCompleted, isFalse);
    final previous = find.text('ÖNCEKİ');
    expect(previous.hitTestable(), findsOneWidget);
    await tester.tap(previous);
    await tester.pump();
    expect(find.text('REHBER  9/10'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    oldTap!();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'fresh, terminal, resumed and optional journeys keep one singleton widget zone',
    (tester) async {
      final store = GameStore.instance;
      // The singleton retains preference futures. Keep these scenarios in one
      // FakeAsync zone and isolate their real account owners instead of resetting it.
      final scenarios = [freshFlow, terminalFlow, resumeFlow, optionalGuide];
      for (var index = 0; index < scenarios.length; index++) {
        await journeyAwait(
          tester,
          () => store.bindAccount('tutorial-flow-$index'),
        );
        await scenarios[index](tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await journeyFlush(tester, store);
      }
    },
  );
}
