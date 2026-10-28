import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/battle_learning_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/guide_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:luno_chess/widgets/living_guide.dart';
import 'package:luno_chess/widgets/luno_arcane_halo.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey, noOverflow;
import 'rc_screen_capture_test.dart' show capture, visualOnline;

const _captures = String.fromEnvironment('LUNO_GUIDE_CAPTURE_DIRECTORY');

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captures.isEmpty) return;
  await capture(
    tester,
    name,
    repaintKey: boundaryKey,
    outputDirectory: _captures,
  );
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setupPracticeTestAssets();
  late GameStore store;
  setUp(() {
    store = GameStore.createForTesting();
    store.loaded = true;
    store.hasCompletedTutorial = true;
    store.hasChosenUsername = true;
    store.practiceStage = 2;
    LunoSettings.instance.language = LunoSettings.languageTurkish;
    addTearDown(store.dispose);
  });

  testWidgets(
    'actual Home guide shortcut opens learning hub and returns home',
    (tester) async {
      final online = await visualOnline();
      addTearDown(online.dispose);
      final singleton = GameStore.instance;
      singleton.loaded = true;
      singleton.hasCompletedTutorial = true;
      singleton.hasChosenUsername = true;
      singleton.firstSessionMatchesStarted = 2;
      await tester.pumpWidget(shell(HomeScreen(online: online), reduced: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('REHBER'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.byType(GuideTurnDemo), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guide-practise-basics')),
        findsOneWidget,
      );
      final back =
          MaterialLocalizations.of(
            tester.element(find.byType(GuideScreen)),
          ).backButtonTooltip;
      await tester.tap(find.byTooltip(back));
      await tester.pumpAndSettle();
      expect(find.byType(GuideScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in ['tr', 'en']) {
    testWidgets(
      'turn demo teaches cast move and draw without account changes $language',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final before = jsonEncode(store.data.toJson());
        await tester.pumpWidget(
          shell(
            TutorialScreen(playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        await _capture(tester, 'guide-hub-$language');
        final button = find.byKey(const ValueKey('guide-demo-next'));
        await _reveal(tester, find.byType(GuideTurnDemo));
        expect(find.text('2 / 6 mana'), findsOneWidget);
        expect(
          find.text(language == 'tr' ? 'El 3 / 4' : 'Hand 3 / 4'),
          findsOneWidget,
        );
        final pawn = find.byKey(const ValueKey('guide-demo-pawn'));
        final start = tester.getCenter(pawn);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('0 / 6 mana'), findsOneWidget);
        expect(
          find.text(language == 'tr' ? 'El 2 / 4' : 'Hand 2 / 4'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('guide-demo-status-1')),
          findsOneWidget,
        );
        await _capture(tester, 'guide-shelter-$language');
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.getCenter(pawn).dy, lessThan(start.dy - 10));
        expect(find.text('0 / 6 mana'), findsOneWidget);
        expect(
          find.text(language == 'tr' ? 'El 3 / 4' : 'Hand 3 / 4'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('guide-demo-status-2')),
          findsOneWidget,
        );
        await _capture(tester, 'guide-move-and-draw-$language');
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('2 / 6 mana'), findsOneWidget);
        expect(jsonEncode(store.data.toJson()), before);
        expect(store.practiceStage, 2);
        expect(store.hasCompletedTutorial, isTrue);
        expect(tester.hasRunningAnimations, isFalse);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(320, 568), 2.0),
      (const Size(768, 1024), 1.3),
    ]) {
      testWidgets(
        'all guide lessons remain reachable $language $size x$scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              GuideScreen(playerStore: store),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          noOverflow(tester);
          if (size.width == 320 && scale == 2) {
            await _capture(tester, 'guide-large-text-$language');
          }
          final context = tester.element(find.byType(GuideScreen));
          final lessons = LunoLocalizations.of(context).battleLessons;
          for (var index = 0; index < lessons.length; index++) {
            final header = find.byKey(ValueKey('guide-lesson-$index'));
            await _reveal(tester, header);
            if (find
                .byKey(ValueKey('guide-lesson-copy-$index'))
                .evaluate()
                .isEmpty) {
              await tester.tap(header);
              await tester.pumpAndSettle();
            }
            expect(find.text(lessons[index].body), findsOneWidget);
            expect(find.text(lessons[index].hint), findsOneWidget);
            noOverflow(tester);
          }
          await _reveal(
            tester,
            find.byKey(const ValueKey('guide-card-catalog')),
          );
          expect(
            find.byKey(const ValueKey('guide-card-catalog')).hitTestable(),
            findsOneWidget,
          );
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'mentor and Blender halo animate once and settle when backgrounded',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell(GuideScreen(playerStore: store)));
      await tester.pumpAndSettle();
      await _reveal(tester, find.byType(GuideTurnDemo));
      await tester.tap(find.byKey(const ValueKey('guide-demo-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      final halo = tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo));
      expect(halo.progress, greaterThan(0));
      expect(halo.progress, lessThan(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(
        tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo)).progress,
        1,
      );
      expect(tester.hasRunningAnimations, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Pause while the separate implicit pawn animation is still in flight.
      // No capture helper (and its extra time) runs before these assertions.
      final button = find.byKey(const ValueKey('guide-demo-next'));
      final pawn = find.byKey(const ValueKey('guide-demo-pawn'));
      final start = tester.getCenter(pawn).dy;
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.widget(pawn), isA<AnimatedPositioned>());
      final moving = tester.getCenter(pawn).dy;
      expect(moving, lessThan(start));
      expect(
        tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo)).progress,
        inExclusiveRange(0, 1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(tester.widget(pawn), isA<Positioned>());
      final settled = tester.getCenter(pawn).dy;
      expect(settled, lessThan(moving));
      expect(
        tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo)).progress,
        1,
      );
      expect(tester.hasRunningAnimations, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.getCenter(pawn).dy, settled);
      expect(tester.hasRunningAnimations, isFalse);

      // Capture an independent replay after lifecycle checks have completed.
      if (_captures.isNotEmpty) {
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        await _capture(tester, 'guide-live-shelter');
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final stop in ['reduced motion', 'disabled TickerMode']) {
    testWidgets('in-flight guide pawn settles with $stop', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Rebuilding this fixture changes only the motion setting. Recreating
      // ThemeData would introduce an unrelated 200ms MaterialApp theme tween.
      final stableTheme = LunoTheme.dark;
      Widget page({bool reduced = false, bool tickerEnabled = true}) => shell(
        TickerMode(
          enabled: tickerEnabled,
          child: GuideScreen(playerStore: store),
        ),
        reduced: reduced,
        theme: stableTheme,
      );

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await _reveal(tester, find.byType(GuideTurnDemo));
      final button = find.byKey(const ValueKey('guide-demo-next'));
      final pawn = find.byKey(const ValueKey('guide-demo-pawn'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      final start = tester.getCenter(pawn).dy;
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.widget(pawn), isA<AnimatedPositioned>());
      final moving = tester.getCenter(pawn).dy;
      expect(moving, lessThan(start));
      expect(
        tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo)).progress,
        inExclusiveRange(0, 1),
      );

      await tester.pumpWidget(
        page(
          reduced: stop == 'reduced motion',
          tickerEnabled: stop != 'disabled TickerMode',
        ),
      );
      expect(tester.widget(pawn), isA<Positioned>());
      final settled = tester.getCenter(pawn).dy;
      expect(settled, lessThan(moving));
      expect(
        tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo)).progress,
        1,
      );
      expect(tester.hasRunningAnimations, isFalse);
      noOverflow(tester);

      await tester.pumpWidget(page());
      expect(tester.getCenter(pawn).dy, settled);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'guide navigation rejects repeated pushes and preserves saved Academy',
    (tester) async {
      await tester.pumpWidget(
        shell(TutorialScreen(playerStore: store), reduced: true),
      );
      await tester.pumpAndSettle();
      final action =
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('guide-academy-shortcut')),
              )
              .onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.byType(BattlePracticeCampaign), findsOneWidget);
      final campaign = tester.widget<BattlePracticeCampaign>(
        find.byType(BattlePracticeCampaign),
      );
      expect(campaign.replay, isTrue);
      expect(identical(campaign.storeOverride, store), isTrue);
      expect(store.practiceStage, 2);
      Navigator.of(tester.element(find.byType(BattlePracticeCampaign))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GuideScreen), findsOneWidget);
      expect(store.practiceStage, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'onboarding and explicit interactive lessons keep original exercise flow',
    (tester) async {
      for (final onboarding in [true, false]) {
        await tester.pumpWidget(
          shell(
            TutorialScreen(
              key: ValueKey(onboarding),
              playerStore: store,
              onboarding: onboarding,
              lessonMode: !onboarding,
            ),
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GuideScreen), findsNothing);
        expect(find.byType(BattleLessonStage), findsOneWidget);
        expect(find.text('REHBER  1/10'), findsOneWidget);
        expect(find.text('DEVAM ET'), findsOneWidget);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
