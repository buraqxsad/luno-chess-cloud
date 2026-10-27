import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_introduction_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_deck_account_test.dart' show response;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'online_request_session_test.dart' show TestAuth;
import 'v214_active_deck_test.dart' show reply;
import 'v217_player_journey_support.dart' show journeyAwait;

Future<void> tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = true
      ..hasChosenUsername = false
      ..firstSessionMatchesStarted = 0;
  });
  for (final language in ['tr', 'en']) {
    testWidgets('V216 every intro board fits 320px text150 $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final stage in IntroductionStage.values) {
        final store = GameStore.createForTesting();
        await tester.runAsync(store.load);
        store.introductionStep = stage.index;
        await tester.pumpWidget(
          shell(
            BattleIntroductionScreen(playerStore: store),
            language: language,
            scale: 1.5,
            reduced: true,
          ),
        );
        await tick(tester);
        final coach = tester.widget<TutorialCoach>(find.byType(TutorialCoach));
        final board = tester.getRect(find.byType(BattleBoard));
        final body = tester.getRect(
          find.byKey(const ValueKey('introduction-body')),
        );
        debugPrint(
          '${stage.name}: coach=${tester.getSize(find.byType(TutorialCoach)).height}, predicted=${TutorialCoach.heightFor(tester.element(find.byType(TutorialCoach)), coach.text, 296)}, board=$board, body=$body',
        );
        expect(
          board.bottom,
          lessThanOrEqualTo(body.bottom + 1),
          reason: stage.name,
        );
        expect(board.width, greaterThanOrEqualTo(220), reason: stage.name);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.save);
        store.dispose();
      }
    });
    testWidgets(
      'V216 wrong tap is visible, non-mutating and clears on correct action $language',
      (tester) async {
        final store = GameStore.createForTesting();
        await tester.runAsync(store.load);
        addTearDown(store.dispose);
        await tester.pumpWidget(
          shell(
            BattleIntroductionScreen(playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        await tick(tester);
        final initial =
            tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(63);
        await tick(tester);
        expect(
          tester.widget<TutorialCoach>(find.byType(TutorialCoach)).feedback,
          isTrue,
        );
        expect(store.introductionStep, 0);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
          same(initial.rules),
        );
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(8);
        await tick(tester);
        expect(store.introductionStep, 1);
        expect(
          tester.widget<TutorialCoach>(find.byType(TutorialCoach)).feedback,
          isFalse,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(store.introductionStep, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.save);
      },
    );

    testWidgets(
      'V216 Mine cost/result and 320px board stay visible $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = GameStore.createForTesting();
        await tester.runAsync(store.load);
        addTearDown(store.dispose);
        store.introductionStep = IntroductionStage.mana.index;
        await tester.pumpWidget(
          shell(
            BattleIntroductionScreen(playerStore: store),
            language: language,
            scale: 1.5,
            reduced: true,
          ),
        );
        await tick(tester);
        expect(
          tester.getSize(find.byType(BattleBoard)).width,
          greaterThanOrEqualTo(220),
        );
        expect(
          tester.getRect(find.byType(BattleBoard)).bottom,
          lessThanOrEqualTo(
            tester
                    .getRect(find.byKey(const ValueKey('introduction-body')))
                    .bottom +
                1,
          ),
        );
        tester
            .widget<BattleCardTile>(find.byKey(const ValueKey('hand-mine')))
            .onSelect!();
        await tick(tester);
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(26);
        await tick(tester);
        tester
            .widget<LunoButton>(
              find.byKey(const ValueKey('introduction-command-mineConfirm')),
            )
            .onPressed!();
        await tick(tester);
        expect(store.introductionStep, IntroductionStage.secondPiece.index);
        final view = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
        expect(view.rules.mana[PieceColor.white], 0);
        expect(
          find.byKey(const ValueKey('introduction-mana-result')),
          findsOneWidget,
        );
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.save);
      },
    );

    testWidgets(
      'V216 Skip cancels automatic lesson and never chooses username $language',
      (tester) async {
        final store = GameStore.createForTesting();
        await tester.runAsync(store.load);
        addTearDown(store.dispose);
        store.introductionStep = IntroductionStage.draw.index;
        final before = jsonEncode(store.data.toJson());
        await tester.pumpWidget(
          shell(
            BattleIntroductionScreen(playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        await tick(tester);
        final skip =
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('introduction-skip')),
                )
                .onPressed!;
        skip();
        skip();
        await tick(tester);
        final completedView =
            tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tick(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tick(tester);
        await tester.pump(const Duration(seconds: 3));
        expect(store.hasCompletedTutorial, isTrue);
        expect(store.hasChosenUsername, isFalse);
        expect(store.needsFirstSessionMatch, isTrue);
        expect(jsonEncode(store.data.toJson()), before);
        expect(store.introductionStep, 0);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
          same(completedView.rules),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.save);
      },
    );

    testWidgets(
      'V216 bottom Battle starts actual first AI exactly once $language',
      (tester) async {
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: TestAuth(),
          playerStore: GameStore.instance,
          client: MockClient((_) async => reply(response())),
          appCheck: () async => 'check',
        );
        addTearDown(online.dispose);
        await journeyAwait(tester, online.start);
        await journeyAwait(tester, online.getBattleV1Deck);
        GameStore.instance
          ..hasCompletedTutorial = true
          ..hasChosenUsername = false
          ..firstSessionMatchesStarted = 0;
        await tester.pumpWidget(
          shell(HomeScreen(online: online), language: language, reduced: true),
        );
        await tick(tester);
        final art = find.byWidgetPredicate(
          (w) => w is LunoArt && w.path == LunoAssets.navBattle,
        );
        final action =
            tester
                .widget<InkWell>(
                  find.ancestor(of: art, matching: find.byType(InkWell)).first,
                )
                .onTap!;
        action();
        action();
        await tick(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(BattleV1Screen), findsOneWidget);
        expect(find.byType(PlayModeScreen), findsNothing);
        expect(GameStore.instance.hasChosenUsername, isFalse);
        expect(GameStore.instance.firstSessionMatchCompleted, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'V216 Academy action and mana are above board; invalidated target cannot silently cast',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 3)),
          ),
          language: 'en',
          reduced: true,
        ),
      );
      await tick(tester);
      expect(
        tester.getRect(find.byType(TutorialCoach)).top,
        lessThan(tester.getRect(find.byType(BattleBoard)).top),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('lesson-mana'))).top,
        lessThan(tester.getRect(find.byType(BattleBoard)).top),
      );
      final target = find.byKey(const ValueKey('lesson-opponent-chain'));
      tester.widget<OutlinedButton>(target).onPressed!();
      await tick(tester);
      expect(
        tester
            .widget<BattleCommand>(
              find.byKey(const ValueKey('lesson-play-card')),
            )
            .onPressed,
        isNotNull,
      );
      tester
          .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
          .onChanged!(1);
      await tick(tester);
      expect(
        tester
            .widget<BattleCommand>(
              find.byKey(const ValueKey('lesson-play-card')),
            )
            .onPressed,
        isNull,
      );
      tester
          .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
          .onChanged!(3);
      await tick(tester);
      expect(
        tester
            .widget<BattleCommand>(
              find.byKey(const ValueKey('lesson-play-card')),
            )
            .onPressed,
        isNull,
      );
      tester.widget<OutlinedButton>(target).onPressed!();
      await tick(tester);
      tester
          .widget<BattleCommand>(find.byKey(const ValueKey('lesson-play-card')))
          .onPressed!();
      await tick(tester);
      expect(
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .rules
            .mana[PieceColor.white],
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'V216 Academy rejects stale, covered, paused and disposed callbacks',
    (tester) async {
      Widget lesson(int step) => shell(
        Scaffold(
          body: SingleChildScrollView(child: BattleLessonStage(step: step)),
        ),
        language: 'en',
        reduced: true,
      );
      await tester.pumpWidget(lesson(3));
      await tick(tester);
      final target =
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('lesson-opponent-chain')),
              )
              .onPressed!;
      target();
      await tick(tester);
      final cast =
          tester
              .widget<BattleCommand>(
                find.byKey(const ValueKey('lesson-play-card')),
              )
              .onPressed!;
      final initial =
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tick(tester);
      cast();
      target();
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
        same(initial),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tick(tester);
      final navigator = Navigator.of(
        tester.element(find.byType(BattleLessonStage)),
      );
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      cast();
      target();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
        same(initial),
      );
      await tester.pumpWidget(lesson(5));
      await tick(tester);
      final next =
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
      cast();
      target();
      await tick(tester);
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
        same(next),
      );
      await tester.pumpWidget(const SizedBox());
      expect(cast, returnsNormally);
      expect(target, returnsNormally);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('V216 Academy repeated cast is one canonical mana spend', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: SingleChildScrollView(child: BattleLessonStage(step: 3)),
        ),
        reduced: true,
      ),
    );
    await tick(tester);
    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('lesson-opponent-chain')),
        )
        .onPressed!();
    await tick(tester);
    final cast =
        tester
            .widget<BattleCommand>(
              find.byKey(const ValueKey('lesson-play-card')),
            )
            .onPressed!;
    cast();
    cast();
    await tick(tester);
    expect(
      tester
          .widget<BattleBoard>(find.byType(BattleBoard))
          .view
          .rules
          .mana[PieceColor.white],
      1,
    );
    expect(find.byKey(const ValueKey('lesson-play-card')), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'V216 Academy wrong target gives one-action feedback without mutating rules',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 5)),
          ),
          language: 'en',
          reduced: true,
        ),
      );
      await tick(tester);
      final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
      board.onTap(63);
      await tick(tester);
      expect(
        tester.widget<TutorialCoach>(find.byType(TutorialCoach)).feedback,
        isTrue,
      );
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
        same(board.view.rules),
      );
      tester
          .widget<BattleBoard>(find.byType(BattleBoard))
          .onTap(board.targets.first);
      await tick(tester);
      expect(
        tester.widget<TutorialCoach>(find.byType(TutorialCoach)).feedback,
        isFalse,
      );
      expect(
        tester
            .widget<BattleCommand>(
              find.byKey(const ValueKey('lesson-play-card')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'V216 Academy previous target confirmation cannot cast a newly selected target',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 3)),
          ),
          reduced: true,
        ),
      );
      await tick(tester);
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-opponent-chain')),
          )
          .onPressed!();
      await tick(tester);
      final oldCast =
          tester
              .widget<BattleCommand>(
                find.byKey(const ValueKey('lesson-play-card')),
              )
              .onPressed!;
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-opponent-freeze')),
          )
          .onPressed!();
      await tick(tester);
      final rules =
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
      oldCast();
      await tick(tester);
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
        same(rules),
      );
      tester
          .widget<BattleCommand>(find.byKey(const ValueKey('lesson-play-card')))
          .onPressed!();
      await tick(tester);
      expect(
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .rules
            .mana[PieceColor.white],
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'V216 Home paused action and entrance settle without starting first match',
    (tester) async {
      await tester.pumpWidget(shell(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      final action =
          tester
              .widget<InkWell>(
                find.byKey(const ValueKey('home-primary-battle')),
              )
              .onTap!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tick(tester);
      action();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(BattleV1Screen), findsNothing);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('home-cta-arrival')))
            .transform
            .storage[13],
        0,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tick(tester);
      expect(GameStore.instance.hasChosenUsername, isFalse);
      expect(GameStore.instance.firstSessionMatchCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('V216 Home background clears all held press feedback', (
    tester,
  ) async {
    await tester.pumpWidget(shell(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 800));
    final highlights =
        tester
            .widgetList<InkWell>(find.byType(InkWell))
            .map((widget) => widget.onHighlightChanged)
            .whereType<ValueChanged<bool>>()
            .toList();
    expect(highlights, hasLength(7));
    for (final highlight in highlights) {
      highlight(true);
    }
    await tick(tester);
    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .where((scale) => scale.scale < 1)
          .length,
      7,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tick(tester);
    for (final highlight in highlights) {
      highlight(true);
    }
    await tick(tester);
    expect(tester.binding.framesEnabled, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tick(tester);
    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .every((scale) => scale.scale == 1),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('V216 Academy old account cannot submit a prepared card', (
    tester,
  ) async {
    await tester.runAsync(
      () => GameStore.instance.bindAccount('v216-lesson-owner'),
    );
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: SingleChildScrollView(child: BattleLessonStage(step: 3)),
        ),
        reduced: true,
      ),
    );
    await tick(tester);
    final target =
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('lesson-opponent-chain')),
            )
            .onPressed!;
    target();
    await tick(tester);
    final cast =
        tester
            .widget<BattleCommand>(
              find.byKey(const ValueKey('lesson-play-card')),
            )
            .onPressed!;
    final rules =
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
    await tester.runAsync(
      () => GameStore.instance.bindAccount('v216-lesson-next'),
    );
    cast();
    target();
    await tick(tester);
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
      same(rules),
    );
    expect(GameStore.instance.hasChosenUsername, isFalse);
    expect(GameStore.instance.hasCompletedTutorial, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(cast, returnsNormally);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'V216 Home entrance is bounded and reduced-motion safe $reduced',
      (tester) async {
        await tester.pumpWidget(shell(const HomeScreen(), reduced: reduced));
        await tester.pump(const Duration(milliseconds: 100));
        final transform =
            tester
                .widget<Transform>(
                  find.byKey(const ValueKey('home-cta-arrival')),
                )
                .transform;
        expect(transform.storage[13], reduced ? 0 : greaterThan(0));
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          tester
              .widget<Transform>(find.byKey(const ValueKey('home-cta-arrival')))
              .transform
              .storage[13],
          0,
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'V216 Introduction rejects a replacement store with the same epoch',
    (tester) async {
      final first = GameStore.createForTesting()..loaded = true;
      final next = GameStore.createForTesting()..loaded = true;
      addTearDown(first.dispose);
      addTearDown(next.dispose);
      expect(first.accountBindingRevision, next.accountBindingRevision);
      await tester.pumpWidget(
        shell(BattleIntroductionScreen(playerStore: first), reduced: true),
      );
      await tick(tester);
      final oldTap = tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap;
      await tester.pumpWidget(
        shell(BattleIntroductionScreen(playerStore: next), reduced: true),
      );
      await tick(tester);
      oldTap(8);
      tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(8);
      await tick(tester);
      expect(first.introductionStep, 0);
      expect(next.introductionStep, 0);
      expect(next.hasCompletedTutorial, isFalse);
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).enabled,
        isFalse,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'V216 Academy pre-background confirmation cannot cast after resume',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 3)),
          ),
          reduced: true,
        ),
      );
      await tick(tester);
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-opponent-chain')),
          )
          .onPressed!();
      await tick(tester);
      final stale =
          tester
              .widget<BattleCommand>(
                find.byKey(const ValueKey('lesson-play-card')),
              )
              .onPressed!;
      final rules =
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tick(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tick(tester);
      stale();
      await tick(tester);
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
        same(rules),
      );
      tester
          .widget<BattleCommand>(find.byKey(const ValueKey('lesson-play-card')))
          .onPressed!();
      await tick(tester);
      expect(
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .rules
            .mana[PieceColor.white],
        1,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('V216 Academy malformed input preserves prepared action', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: SingleChildScrollView(child: BattleLessonStage(step: 3)),
        ),
        reduced: true,
      ),
    );
    await tick(tester);
    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('lesson-opponent-chain')),
        )
        .onPressed!();
    await tick(tester);
    final rules =
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
    final mana =
        tester
            .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
            .onChanged!;
    for (final value in [double.nan, double.infinity, -1.0, 0.0, 7.0]) {
      expect(() => mana(value), returnsNormally);
    }
    final tap = tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap;
    for (final square in [-1, 64, 1000000]) {
      expect(() => tap(square), returnsNormally);
    }
    await tick(tester);
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
      same(rules),
    );
    tester
        .widget<BattleCommand>(find.byKey(const ValueKey('lesson-play-card')))
        .onPressed!();
    await tick(tester);
    expect(
      tester
          .widget<BattleBoard>(find.byType(BattleBoard))
          .view
          .rules
          .mana[PieceColor.white],
      1,
    );
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'V216 Academy changed order rejects stale and duplicate confirmation',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 7)),
          ),
          reduced: true,
        ),
      );
      await tick(tester);
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-card-prophecy')),
          )
          .onPressed!();
      await tick(tester);
      tester
          .widget<BattleCommand>(find.byKey(const ValueKey('lesson-play-card')))
          .onPressed!();
      await tick(tester);
      final before =
          tester
              .widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
              .view;
      final oldConfirm =
          tester
              .widget<BattleCommand>(
                find.byKey(const ValueKey('lesson-resolve')),
              )
              .onPressed!;
      final swap =
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('lesson-swap-order')),
              )
              .onPressed!;
      swap();
      swap();
      await tick(tester);
      oldConfirm();
      await tick(tester);
      expect(
        tester
            .widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
            .view
            .rules,
        same(before.rules),
      );
      final confirm =
          tester
              .widget<BattleCommand>(
                find.byKey(const ValueKey('lesson-resolve')),
              )
              .onPressed!;
      confirm();
      confirm();
      await tick(tester);
      final after =
          tester
              .widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
              .view;
      expect(after.knowledge.pendingCards, isEmpty);
      expect(
        after.knowledge.knownUpcomingCards,
        before.knowledge.pendingCards.reversed.toList(),
      );
      expect(
        after.rules.mana[PieceColor.white],
        before.rules.mana[PieceColor.white],
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'V216 Home covered held presses clear and reject stale feedback',
    (tester) async {
      await tester.pumpWidget(shell(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 800));
      final highlights =
          tester
              .widgetList<InkWell>(find.byType(InkWell))
              .map((widget) => widget.onHighlightChanged)
              .whereType<ValueChanged<bool>>()
              .toList();
      expect(highlights, hasLength(7));
      for (final highlight in highlights) {
        highlight(true);
      }
      await tick(tester);
      expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .where((scale) => scale.scale < 1),
        hasLength(7),
      );
      final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      for (final highlight in highlights) {
        highlight(true);
      }
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .every((scale) => scale.scale == 1),
        isTrue,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('V216 Home departed account rejects feedback before next frame', (
    tester,
  ) async {
    await tester.runAsync(
      () => GameStore.instance.bindAccount('v216-press-owner'),
    );
    GameStore.instance.hasCompletedTutorial = true;
    await tester.pumpWidget(shell(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 800));
    final highlights =
        tester
            .widgetList<InkWell>(find.byType(InkWell))
            .map((widget) => widget.onHighlightChanged)
            .whereType<ValueChanged<bool>>()
            .toList();
    expect(highlights, hasLength(7));
    await tester.runAsync(
      () => GameStore.instance.bindAccount('v216-press-next'),
    );
    for (final highlight in highlights) {
      highlight(true);
    }
    await tick(tester);
    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .every((scale) => scale.scale == 1),
      isTrue,
    );
    expect(GameStore.instance.hasCompletedTutorial, isFalse);
    expect(GameStore.instance.hasChosenUsername, isFalse);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
