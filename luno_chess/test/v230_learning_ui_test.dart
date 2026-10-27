import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, boundaryKey;
import 'rc_screen_capture_test.dart' show capture;
import 'v227_coach_guidance_test.dart' show coach;
import 'v227_onboarding_lesson_contract_test.dart' show waitForOwnTurn;
import 'battle_ui/fixtures.dart';

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = false
      ..welcomeStep = 0
      ..onboardingBattleStage = 0;
  });

  for (final language in ['tr', 'en']) {
    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(360, 640), 1.6),
      (const Size(844, 390), 1.0),
      (const Size(768, 1024), 1.0),
    ]) {
      testWidgets(
        'welcome all steps are readable and actionable $language $size $scale',
        (tester) async {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.instance;
          await tester.pumpWidget(
            shell(
              const BattleWelcomeScreen(),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          await warm(tester);
          for (var step = 0; step < 3; step++) {
            expect(store.welcomeStep, step);
            expect(find.byKey(ValueKey('welcome-title-$step')), findsOneWidget);
            expect(find.byType(TutorialCoach), findsOneWidget);
            noOverflow(tester);
            if (size.width == 320 && language == 'tr') {
              await capture(
                tester,
                'welcome-$step-$language-top',
                repaintKey: boundaryKey,
                outputDirectory: 'qa/v230/screens',
              );
            }
            final content = find.byKey(ValueKey('welcome-content-$step'));
            await tester.drag(content, const Offset(0, -850));
            await tester.pumpAndSettle();
            noOverflow(tester);
            final next = find.byKey(const ValueKey('welcome-next'));
            expect(next.hitTestable(), findsOneWidget);
            if (size.width == 320 && language == 'tr') {
              await capture(
                tester,
                'welcome-$step-$language',
                repaintKey: boundaryKey,
                outputDirectory: 'qa/v230/screens',
              );
            }
            await tester.tap(next);
            await tester.pumpAndSettle();
          }
          expect(store.welcomeStep, 3);
          expect(store.hasCompletedTutorial, false);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'guided selection keeps actual card guidance and all choices $language',
      (tester) async {
        final p = BattlePracticeProgress(
          0,
          onboarding: true,
          guidedMatch: true,
        );
        final view = battleFixture(
          hand: [CardId.freeze, CardId.shelter],
        ).view(PieceColor.white);
        final text = await coach(
          tester,
          language,
          p,
          view,
          selected: CardId.freeze,
        );
        expect(text.text, contains(language == 'en' ? 'Freeze' : 'Dondurma'));
        expect(
          text.text,
          isNot(
            contains(
              language == 'en' ? 'For this lesson' : 'Bu eğitim adımında',
            ),
          ),
        );
        final ready = await coach(
          tester,
          language,
          p,
          view,
          selected: CardId.freeze,
          targetReady: true,
        );
        expect(
          ready.text,
          contains(
            '${BattleRulesCore.effectiveCost(view.rules, view.viewer, CardId.freeze)} mana',
          ),
        );
        expect(
          ready.text,
          contains(language == 'en' ? 'chess move' : 'taş hamleni'),
        );
      },
    );

    testWidgets('guided board and every hand card stay reachable $language', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        shell(
          const BattleV1Screen(
            practiceStage: 0,
            practiceOnboarding: true,
            guidedFirstMatch: true,
          ),
          language: language,
          reduced: true,
        ),
      );
      await warm(tester);
      expect(find.byType(BattleBoard), findsOneWidget);
      expect(find.byKey(const ValueKey('practice-next')), findsNothing);
      for (final card in [CardId.shelter, CardId.radar, CardId.prophecy]) {
        final tile = find.byKey(ValueKey('hand-${card.wire}'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        expect(tile.hitTestable(), findsOneWidget);
      }
      noOverflow(tester);
      await capture(
        tester,
        'guided-opening-$language',
        repaintKey: boundaryKey,
        outputDirectory: 'qa/v230/screens',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in ['tr', 'en']) {
    testWidgets('live card target teaching stays readable $language', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        shell(
          const BattleV1Screen(
            practiceStage: 0,
            practiceOnboarding: true,
            guidedFirstMatch: true,
          ),
          language: language,
          reduced: true,
        ),
      );
      await warm(tester);
      tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(12);
      await tester.pump();
      tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(28);
      await tester.pumpAndSettle();
      await waitForOwnTurn(tester);
      final card = find.byKey(const ValueKey('hand-shelter'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TutorialCoach>(find.byType(TutorialCoach)).text,
        contains(language == 'en' ? 'For example' : 'Örneğin'),
      );
      expect(find.byKey(const ValueKey('hand-radar')), findsOneWidget);
      expect(find.byKey(const ValueKey('hand-prophecy')), findsOneWidget);
      noOverflow(tester);
      final bubble = tester.getRect(find.byType(TutorialCoach));
      final speechViewport = tester.getRect(
        find.byKey(const ValueKey('lesson-speech-scroll')),
      );
      expect(bubble.top, greaterThanOrEqualTo(speechViewport.top - .5));
      expect(
        bubble.bottom,
        lessThanOrEqualTo(speechViewport.bottom + .5),
        reason:
            'The complete current instruction must be visible without scrolling its bubble.',
      );
      await capture(
        tester,
        'guided-target-$language',
        repaintKey: boundaryKey,
        outputDirectory: 'qa/v230/screens',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('covered and background welcome callbacks cannot advance', (
    tester,
  ) async {
    final store = GameStore.instance;
    await tester.pumpWidget(shell(const BattleWelcomeScreen(), reduced: true));
    await warm(tester);
    final button = tester.widget<BattleCommand>(
      find.byKey(const ValueKey('welcome-next')),
    );
    final VoidCallback callback = button.onPressed!;
    final context = tester.element(find.byType(BattleWelcomeScreen));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    callback();
    await tester.pump();
    expect(store.welcomeStep, 0);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    callback();
    await tester.pump();
    expect(store.welcomeStep, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    callback();
    await tester.pumpAndSettle();
    expect(store.welcomeStep, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background time cannot consume the visible loading interval', (
    tester,
  ) async {
    await tester.pumpWidget(const LunoAppShell());
    tester
        .widget<LunoLoadingArtwork>(find.byType(LunoLoadingArtwork))
        .onShown!();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(BattleWelcomeScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BattleWelcomeScreen), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BattleWelcomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
