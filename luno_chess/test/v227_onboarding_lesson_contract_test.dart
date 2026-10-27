import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_introduction_screen.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, boundaryKey;
import 'rc_screen_capture_test.dart' show capture;

AuthoritativeBattleState cardTurn(List<CardId> first) {
  final deck =
      [
        ...first,
        ...CardId.values.where((card) => !first.contains(card)),
      ].take(10).toList();
  final state = DeckManager.newBattle(white: deck);
  final rules =
      RuleDraft(state.rules)
        ..phase = BattlePhase.card
        ..ownTurns = {PieceColor.white: 2, PieceColor.black: 1}
        ..mana = {PieceColor.white: 6, PieceColor.black: 6};
  return AuthoritativeBattleState(rules.freeze(), state.hidden);
}

Future<void> waitForOwnTurn(WidgetTester tester) async {
  for (var i = 0; i < 18; i++) {
    final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
    if (board.enabled && board.view.rules.board.turn == PieceColor.white) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 950));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  fail('The practice AI did not hand the turn back to the learner.');
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = false
      ..welcomeStep = 0
      ..onboardingBattleStage = 0
      ..practiceStage = null;
  });

  for (final stage in [0, 1]) {
    test('guided stage $stage gates cards, never invents card illegality', () {
      final progress = BattlePracticeProgress(stage, onboarding: true);
      final state = cardTurn([progress.card, CardId.radar, CardId.prophecy]);
      final view = state.view(PieceColor.white);
      final legal = BattleRulesCore.legalActions(view);
      expect(
        legal.whereType<PlayCardAction>().any((a) => a.card == CardId.radar),
        true,
      );
      final lesson = progress.lessonActions(view, legal);
      expect(lesson, isNotEmpty);
      expect(
        lesson.every((a) => a is PlayCardAction && a.card == progress.card),
        true,
      );
      expect(lesson.every((a) => BattleRulesCore.isLegalAction(view, a)), true);
      expect(progress.complete, false);
      progress.accepted(const PassAction(), view, view);
      expect(progress.cast, false);
      expect(progress.moves, 0);
    });

    test(
      'guided stage $stage keeps every legal chess choice after play and discard',
      () {
        final progress = BattlePracticeProgress(stage, onboarding: true);
        var state = cardTurn([progress.card, CardId.radar, CardId.prophecy]);
        var before = state.view(PieceColor.white);
        final play =
            progress
                .lessonActions(before, BattleRulesCore.legalActions(before))
                .first;
        state = DeckManager.apply(state, play);
        progress.accepted(play, before, state.view(PieceColor.white));
        expect(progress.cast, true);
        final after = state.view(PieceColor.white);
        final chess = BattleRulesCore.legalActions(after);
        expect(
          progress.lessonActions(after, chess).map((a) => a.key),
          chess.map((a) => a.key),
        );
        expect(chess.whereType<ChessMoveAction>().length, greaterThan(1));

        final nextRules = RuleDraft(state.rules)..phase = BattlePhase.card;
        state = AuthoritativeBattleState(nextRules.freeze(), state.hidden);
        before = state.view(PieceColor.white);
        final discard = progress.lessonActions(
          before,
          BattleRulesCore.legalActions(before),
        );
        expect(discard, isNotEmpty);
        expect(discard.every((a) => a is DiscardAction), true);
        final mana = before.rules.mana[PieceColor.white];
        state = DeckManager.apply(state, discard.first);
        progress.accepted(discard.first, before, state.view(PieceColor.white));
        expect(progress.discarded, true);
        expect(state.rules.phase, BattlePhase.chess);
        expect(state.rules.mana[PieceColor.white], mana);
        expect(
          BattleRulesCore.legalActions(
            state.view(PieceColor.white),
          ).whereType<ChessMoveAction>(),
          isNotEmpty,
        );
      },
    );

    for (final opening in ['a2a4', 'b1c3', 'e2e4', 'g1f3']) {
      test(
        'guided $stage accepts free opening $opening and needs actual lesson actions',
        () {
          final progress = BattlePracticeProgress(stage, onboarding: true);
          var state = DeckManager.newBattle(white: progress.deck);
          for (var i = 0; i < 100 && !progress.complete; i++) {
            final side = state.rules.board.turn;
            final before = state.view(side);
            final legal = BattleRulesCore.legalActions(before);
            final lesson =
                side == PieceColor.white
                    ? progress.lessonActions(before, legal)
                    : legal;
            final action =
                side == PieceColor.white && progress.moves == 0
                    ? lesson.whereType<ChessMoveAction>().firstWhere(
                      (a) => a.uci == opening,
                    )
                    : lesson.whereType<PlayCardAction>().firstOrNull ??
                        lesson.whereType<DiscardAction>().firstOrNull ??
                        lesson.whereType<ResolveAction>().firstOrNull ??
                        lesson.whereType<PassAction>().firstOrNull ??
                        lesson.whereType<ChessMoveAction>().firstOrNull;
            expect(action, isNotNull);
            state = DeckManager.apply(state, action!);
            progress.accepted(action, before, state.view(side));
          }
          expect(progress.complete, true);
          expect(progress.stopsPlay, true);
          expect(progress.cast && progress.discarded, true);
          expect(progress.moves, greaterThanOrEqualTo(4));
        },
      );
    }
  }

  for (final card in CardId.values) {
    test('discard-only ${card.wire} selection has no play choices', () {
      final selection = BattleInteraction();
      final actions = [DiscardAction(card)];
      selection.select(card, actions);
      expect(selection.card, card);
      expect(selection.options(actions), isEmpty);
    });
    test('third practice has no lesson gate for ${card.wire}', () {
      final progress = BattlePracticeProgress(2, onboarding: true);
      final state = cardTurn([card]);
      final view = state.view(PieceColor.white);
      final legal = BattleRulesCore.legalActions(view);
      expect(progress.freePlay, true);
      expect(
        progress.lessonActions(view, legal).map((a) => a.key),
        legal.map((a) => a.key),
      );
      expect(practiceFocus(progress, view, card, false), BattleCoachFocus.none);
    });
  }

  test(
    'third practice completes with chess only, no forced cast or discard',
    () {
      final progress = BattlePracticeProgress(2, onboarding: true);
      var state = DeckManager.newBattle(white: progress.deck);
      for (var i = 0; i < 30 && !progress.complete; i++) {
        final side = state.rules.board.turn;
        final before = state.view(side);
        final legal = progress.lessonActions(
          before,
          BattleRulesCore.legalActions(before),
        );
        final action =
            legal.whereType<PassAction>().firstOrNull ??
            legal.whereType<ChessMoveAction>().first;
        state = DeckManager.apply(state, action);
        progress.accepted(action, before, state.view(side));
      }
      expect(progress.complete, true);
      expect(progress.stopsPlay, false);
      expect(progress.cast || progress.discarded, false);
    },
  );

  test(
    'three stages persist, reject duplicates and do not reset returning players',
    () async {
      final store = GameStore.createForTesting();
      await store.load();
      for (var stage = 0; stage < 3; stage++) {
        await store.completeOnboardingBattle(
          stage + 1,
          store.accountBindingRevision,
        );
        expect(store.onboardingBattleStage, stage);
        await store.completeOnboardingBattle(
          stage,
          store.accountBindingRevision,
        );
        await store.completeOnboardingBattle(
          stage,
          store.accountBindingRevision,
        );
        final restored = GameStore.createForTesting();
        await restored.load();
        expect(restored.onboardingBattleStage, (stage + 1).clamp(0, 2));
        expect(restored.hasCompletedTutorial, stage == 2);
      }
      expect(store.hasChosenUsername, false);
      expect(store.practiceStage, isNull);
    },
  );

  test(
    'stage progress belongs to its account, stale completion cannot cross owners',
    () async {
      final store = GameStore.createForTesting();
      await store.load();
      await store.bindAccount('learner-a');
      final revision = store.accountBindingRevision;
      await store.completeOnboardingBattle(0, revision);
      await store.bindAccount('learner-b');
      await store.completeOnboardingBattle(1, revision);
      expect(store.onboardingBattleStage, 0);
      await store.bindAccount('learner-a');
      expect(store.onboardingBattleStage, 1);
    },
  );

  test(
    'legacy completed tutorial remains completed without enrolling again',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'tutorialCompleted': true,
          'usernameChosen': true,
        }),
      });
      final store = GameStore.createForTesting();
      await store.load();
      expect(store.hasCompletedTutorial, true);
    },
  );

  testWidgets(
    'startup opens the unified welcome, not the detached introduction',
    (tester) async {
      await tester.pumpWidget(const LunoAppShell());
      tester
          .widget<LunoLoadingArtwork>(find.byType(LunoLoadingArtwork))
          .onShown!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BattlePracticeCampaign), findsOneWidget);
      expect(find.byType(BattleIntroductionScreen), findsNothing);
      expect(find.byType(BattleBoard), findsNothing);
      expect(find.byType(BattleWelcomeScreen), findsOneWidget);
      expect(find.byType(TutorialCoach), findsOneWidget);
      expect(find.byKey(const ValueKey('practice-next')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  for (final (from, to) in [(8, 24), (1, 18)]) {
    testWidgets('actual practice accepts unscripted chess taps $from-$to', (
      tester,
    ) async {
      await tester.pumpWidget(
        shell(
          const BattleV1Screen(practiceStage: 0, practiceOnboarding: true),
          reduced: true,
        ),
      );
      await warm(tester);
      tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(from);
      await tester.pump();
      expect(
        tester.widget<TutorialCoach>(find.byType(TutorialCoach)).text,
        contains('Işıklı kareler'),
      );
      tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(to);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
      expect(board.view.rules.ply, 1);
      expect(board.view.rules.board.squares[from], isNull);
      expect(board.view.rules.board.squares[to], isNotNull);
      expect(
        tester
            .widget<BattlePracticeCoach>(find.byType(BattlePracticeCoach))
            .progress
            .moves,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      // The already-started bot delay is guarded by the disposed session.
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final language in ['tr', 'en']) {
    testWidgets(
      'real card lesson and discard retain the chess move $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            const BattleV1Screen(practiceStage: 0, practiceOnboarding: true),
            language: language,
            reduced: true,
          ),
        );
        await warm(tester);
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(12);
        await tester.pump();
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(28);
        await tester.pump();
        await waitForOwnTurn(tester);
        final wrongCard = find.byKey(const ValueKey('hand-radar'));
        expect(wrongCard.hitTestable(), findsOneWidget);
        final beforeDetail =
            tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules;
        await tester.tap(wrongCard);
        await tester.pumpAndSettle();
        expect(find.byType(CardDetailSheet), findsOneWidget);
        expect(
          tester.widget<CardDetailSheet>(find.byType(CardDetailSheet)).card,
          CardId.radar,
        );
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is BattleIconControl && widget.icon == Icons.close,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CardDetailSheet), findsNothing);
        expect(
          identical(
            tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules,
            beforeDetail,
          ),
          true,
        );
        expect(find.byType(BattleHand), findsOneWidget);
        expect(
          tester.widget<TutorialCoach>(find.byType(TutorialCoach)).text,
          contains(
            language == 'tr'
                ? 'Bu eğitim adımında Siper'
                : 'For this lesson, we are trying Shelter',
          ),
        );
        final hand = find.byKey(const ValueKey('hand-shelter'));
        expect(hand.hitTestable(), findsOneWidget);
        noOverflow(tester);
        await capture(
          tester,
          'wrong-card-$language-320',
          repaintKey: boundaryKey,
          outputDirectory: 'qa/v227/screens',
        );
        await tester.tap(hand);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('practice-selected-card')),
          findsOneWidget,
        );
        expect(find.byType(BattleHand), findsNothing);
        var board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        expect(board.targets, isNotEmpty);
        expect(
          tester.getRect(find.byType(BattleBoard)).height,
          greaterThanOrEqualTo(200),
        );
        board.onTap(board.targets.first);
        await tester.pump();
        final play = find.byKey(const ValueKey('play-card'));
        expect(play.hitTestable(), findsOneWidget);
        await capture(
          tester,
          'target-ready-$language-320',
          repaintKey: boundaryKey,
          outputDirectory: 'qa/v227/screens',
        );
        await tester.tap(play);
        await tester.pumpAndSettle();
        board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        expect(board.view.rules.phase, BattlePhase.chess);
        expect(
          board.view.rules.used[PieceColor.white],
          contains(CardId.shelter),
        );
        var chess =
            BattleRulesCore.legalActions(
              board.view,
            ).whereType<ChessMoveAction>().first;
        int square(String uci, int start) =>
            uci.codeUnitAt(start) - 97 + (int.parse(uci[start + 1]) - 1) * 8;
        board.onTap(square(chess.uci, 0));
        await tester.pump();
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .onTap(square(chess.uci, 2));
        await tester.pump();
        await waitForOwnTurn(tester);
        final ownHand = tester.widget<BattleHand>(find.byType(BattleHand));
        ownHand.onSelect(ownHand.view.ownHand.first);
        await tester.pumpAndSettle();
        final mana =
            tester
                .widget<BattleBoard>(find.byType(BattleBoard))
                .view
                .rules
                .mana[PieceColor.white];
        final discard = find.byKey(const ValueKey('discard-card'));
        await capture(
          tester,
          'before-discard-$language-320',
          repaintKey: boundaryKey,
          outputDirectory: 'qa/v227/screens',
        );
        expect(discard, findsOneWidget);
        expect(discard.hitTestable(), findsOneWidget);
        await tester.tap(discard);
        await tester.pumpAndSettle();
        board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        expect(board.view.rules.phase, BattlePhase.chess);
        expect(board.view.rules.mana[PieceColor.white], mana);
        expect(
          tester
              .widget<BattlePracticeCoach>(find.byType(BattlePracticeCoach))
              .progress
              .discarded,
          true,
        );
        expect(
          BattleRulesCore.legalActions(board.view).whereType<ChessMoveAction>(),
          isNotEmpty,
        );
        noOverflow(tester);
        await capture(
          tester,
          'after-discard-$language-320',
          repaintKey: boundaryKey,
          outputDirectory: 'qa/v227/screens',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
      },
    );

    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 568), 1.0),
      (const Size(360, 640), 1.6),
      (const Size(768, 1024), 1.0),
      (const Size(844, 390), 1.0),
    ]) {
      for (var stage = 0; stage < 3; stage++) {
        testWidgets(
          'live lesson $stage $language ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              shell(
                BattleV1Screen(practiceStage: stage, practiceOnboarding: true),
                language: language,
                scale: scale,
                reduced: true,
              ),
            );
            await warm(tester);
            expect(find.byType(TutorialCoach), findsOneWidget);
            expect(find.byType(BattleBoard), findsOneWidget);
            noOverflow(tester);
            if (size.height > size.width) {
              for (final tile in find.byType(BattleCardTile).evaluate()) {
                final rect = tester.getRect(find.byWidget(tile.widget));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(
                  rect.bottom,
                  lessThanOrEqualTo(size.height),
                  reason:
                      'The hand must stay on screen, not below the scroll viewport.',
                );
              }
            }
            if (size.width == 390 ||
                (size.width == 320 && stage == 0) ||
                (scale > 1 && stage == 0)) {
              await capture(
                tester,
                'lesson-$stage-$language-${size.width.toInt()}-${size.height.toInt()}',
                repaintKey: boundaryKey,
                outputDirectory: 'qa/v227/screens',
              );
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
      }
    }
  }

  testWidgets(
    'third practice keeps playing after goals, with an explicit exit CTA',
    (tester) async {
      var completed = 0;
      VoidCallback? staleContinue;
      await tester.pumpWidget(
        shell(
          BattleV1Screen(
            practiceStage: 2,
            practiceOnboarding: true,
            onPracticeComplete: () async {
              completed++;
            },
          ),
          reduced: true,
        ),
      );
      await warm(tester);
      const preferred = ['e2e4', 'g1f3', 'f1c4', 'b1c3', 'd2d3'];
      for (var move = 0; move < 5; move++) {
        await waitForOwnTurn(tester);
        var board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        final progress =
            tester
                .widget<BattlePracticeCoach>(find.byType(BattlePracticeCoach))
                .progress;
        if (move == 4) {
          expect(progress.complete, true);
          expect(progress.stopsPlay, false);
          expect(board.enabled, true);
          expect(find.byKey(const ValueKey('practice-next')), findsOneWidget);
          staleContinue =
              tester
                  .widget<BattleCommand>(
                    find.byKey(const ValueKey('practice-next')),
                  )
                  .onPressed;
          expect(staleContinue, isNotNull);
        }
        final legal = progress.lessonActions(
          board.view,
          BattleRulesCore.legalActions(board.view),
        );
        final moves = BattleInteraction().moves(board.view, legal);
        final action =
            moves.where((a) => a.uci == preferred[move]).firstOrNull ??
            moves.first;
        final from =
            action.uci.codeUnitAt(0) - 97 + (int.parse(action.uci[1]) - 1) * 8;
        final to =
            action.uci.codeUnitAt(2) - 97 + (int.parse(action.uci[3]) - 1) * 8;
        board.onTap(from);
        await tester.pump();
        board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        board.onTap(to);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(progress.moves, move + 1);
      }
      await waitForOwnTurn(tester);
      final prophecy = find.byKey(const ValueKey('hand-prophecy'));
      expect(prophecy.hitTestable(), findsOneWidget);
      await tester.tap(prophecy);
      await tester.pumpAndSettle();
      staleContinue!();
      await tester.pump();
      expect(
        completed,
        0,
        reason: 'A selected card must be resolved or closed.',
      );
      await tester.tap(find.byKey(const ValueKey('play-card')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.phase,
        BattlePhase.pending,
      );
      expect(find.byKey(const ValueKey('practice-next')), findsNothing);
      staleContinue();
      await tester.pump();
      expect(
        completed,
        0,
        reason: 'A pending card decision must not be skipped.',
      );
      final private = find.byKey(const ValueKey('open-private'));
      expect(private.hitTestable(), findsOneWidget);
      await tester.tap(private);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-private')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.phase,
        BattlePhase.chess,
      );
      expect(find.byKey(const ValueKey('practice-next')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      staleContinue();
      await tester.pump();
      expect(
        completed,
        0,
        reason: 'Background callbacks cannot finish training.',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('practice-next')));
      await tester.pump();
      expect(completed, 1);
      await tester.pumpWidget(const SizedBox());
      staleContinue();
      await tester.pump();
      expect(completed, 1, reason: 'A disposed lesson cannot finish again.');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  for (var stage = 0; stage < 3; stage++) {
    testWidgets('terminal practice $stage has a safe continuation or retry', (
      tester,
    ) async {
      var completed = 0;
      await tester.pumpWidget(
        shell(
          BattleV1Screen(
            practiceStage: stage,
            practiceOnboarding: true,
            onPracticeComplete: () async {
              completed++;
            },
          ),
          reduced: true,
        ),
      );
      await warm(tester);
      final dynamic screenState = tester.state(find.byType(BattleV1Screen));
      screenState.localSession.resign();
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('practice-next'));
      if (stage == 2) {
        expect(next, findsOneWidget);
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(completed, 1);
      } else {
        expect(next, findsNothing);
        expect(find.byKey(const ValueKey('local-rematch')), findsOneWidget);
        expect(completed, 0);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
