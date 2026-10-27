import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, boundaryKey;
import 'battle_ui/fixtures.dart';
import 'rc_screen_capture_test.dart' show capture;
import 'v227_onboarding_lesson_contract_test.dart' show waitForOwnTurn;

void main() {
  setupPracticeTestAssets();

  test(
    'implicit card passing does not replace the explicit button exercise',
    () {
      final before = battleFixture().view(PieceColor.white);
      final transition = BattleRulesCore.transition(before, const PassAction());
      final after = PlayerView(
        transition.rules,
        before.viewer,
        before.ownHand,
        before.knowledge,
      );
      final implicit = BattlePracticeProgress(
        0,
        onboarding: true,
        guidedMatch: true,
      );
      implicit.accepted(
        const PassAction(),
        before,
        after,
        explicitCardPass: false,
      );
      expect(implicit.passed, false);
      final explicit = BattlePracticeProgress(
        0,
        onboarding: true,
        guidedMatch: true,
      );
      explicit.accepted(const PassAction(), before, after);
      expect(explicit.passed, true);
      explicit.accepted(const PassAction(), before, after);
      expect(explicit.checkpoint.toJson()['passed'], true);
    },
  );

  test('actual legal play teaches each basic without requiring a win', () {
    final progress = BattlePracticeProgress(
      0,
      onboarding: true,
      guidedMatch: true,
    );
    var state = DeckManager.newBattle(white: progress.deck);
    for (var step = 0; step < 100 && !progress.complete; step++) {
      expect(state.rules.terminal, isNull);
      final side = state.rules.board.turn;
      final view = state.view(side);
      final legal = BattleRulesCore.legalActions(view);
      BattleAction action;
      if (view.rules.phase == BattlePhase.card) {
        if (side == PieceColor.white && !progress.cast) {
          action =
              legal
                  .whereType<PlayCardAction>()
                  .where((a) => a.card == CardId.shelter && a.target is int)
                  .firstOrNull ??
              const PassAction();
        } else if (side == PieceColor.white && !progress.discarded) {
          action = legal.whereType<DiscardAction>().first;
        } else {
          action = const PassAction();
        }
      } else {
        action = legal.whereType<ChessMoveAction>().first;
      }
      final before = state.view(PieceColor.white);
      state = DeckManager.apply(state, action);
      progress.accepted(action, before, state.view(PieceColor.white));
    }
    expect(progress.moves, 4);
    expect(progress.cast && progress.discarded && progress.passed, true);
    expect(progress.complete, true);
    expect(state.rules.terminal, isNull);
    expect(progress.canFinish(state.view(PieceColor.white)), true);
  });

  test('checkpoints normalize malformed data and never regress', () {
    expect(
      BattleLearningCheckpoint.fromJson({'schema': 2, 'moves': 4}).moves,
      0,
    );
    expect(
      BattleLearningCheckpoint.fromJson({'schema': 1, 'moves': -3}).moves,
      0,
    );
    expect(
      BattleLearningCheckpoint.fromJson({'schema': 1, 'moves': 99}).moves,
      4,
    );
    final merged = const BattleLearningCheckpoint(
      moves: 2,
      cast: true,
    ).merge(const BattleLearningCheckpoint(moves: 1, discarded: true));
    expect(merged.moves, 2);
    expect(merged.cast && merged.discarded, true);
    expect(merged.merge(const BattleLearningCheckpoint(moves: 99)).moves, 4);
  });

  test(
    'saved skills resume per account, stale writes and skips are ignored',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.bindAccount('learning-a');
      final owner = store.accountBindingRevision;
      final before = store.data.toJson();
      await store.saveGuidedLearning(
        const BattleLearningCheckpoint(moves: 2, cast: true),
        owner,
      );
      await store.saveGuidedLearning(
        const BattleLearningCheckpoint(moves: 1),
        owner,
      );
      expect(store.guidedLearning.moves, 2);
      expect(store.data.toJson(), before);
      await store.flush();
      final restored = GameStore.createForTesting();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.guidedLearning.moves, 2);
      expect(restored.guidedLearning.cast, true);
      await store.bindAccount('learning-b');
      await store.saveGuidedLearning(
        const BattleLearningCheckpoint(moves: 4),
        owner,
      );
      await store.skipGuidedOnboarding(owner);
      expect(store.guidedLearning.moves, 0);
      expect(store.hasCompletedTutorial, false);
      await store.bindAccount('learning-a');
      expect(store.guidedLearning.moves, 2);
      await store.eraseLocalAccount('learning-a');
      expect(store.guidedLearning.moves, 0);
    },
  );

  test(
    'skip is local, idempotent and does not create a career reward',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      final before = store.data.toJson();
      await store.skipGuidedOnboarding(store.accountBindingRevision);
      await store.skipGuidedOnboarding(store.accountBindingRevision);
      expect(store.hasCompletedTutorial, true);
      expect(store.hasChosenUsername, false);
      expect(store.data.toJson(), before);
    },
  );

  testWidgets('partial saved skills resume on a fresh playable board', (
    tester,
  ) async {
    final saved = GameStore.createForTesting();
    addTearDown(saved.dispose);
    await saved.load();
    for (var step = 0; step < GameStore.welcomeStepCount; step++) {
      await saved.advanceWelcomeStep(step, saved.accountBindingRevision);
    }
    await saved.saveGuidedLearning(
      const BattleLearningCheckpoint(moves: 2, cast: true, passed: true),
      saved.accountBindingRevision,
    );
    await saved.flush();
    final restored = GameStore.createForTesting();
    addTearDown(restored.dispose);
    await restored.load();
    final before = restored.data.toJson();
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial();
    await tester.pumpWidget(
      shell(BattlePracticeCampaign(onboarding: true, storeOverride: restored)),
    );
    await warm(tester);
    final coach = tester.widget<BattlePracticeCoach>(
      find.byType(BattlePracticeCoach),
    );
    expect(coach.progress.moves, 2);
    expect(coach.progress.cast && coach.progress.passed, true);
    expect(coach.progress.discarded, false);
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
      0,
    );
    for (var turn = 0; turn < 2; turn++) {
      await waitForOwnTurn(tester);
      var board = tester.widget<BattleBoard>(find.byType(BattleBoard));
      if (board.view.rules.phase == BattlePhase.card) {
        final card = find.byKey(ValueKey('hand-${CardId.shelter.wire}'));
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('discard-card')));
        await tester.pumpAndSettle();
      }
      board = tester.widget<BattleBoard>(find.byType(BattleBoard));
      final move =
          BattleRulesCore.legalActions(
            board.view,
          ).whereType<ChessMoveAction>().first;
      int square(int start) =>
          move.uci.codeUnitAt(start) -
          97 +
          (int.parse(move.uci[start + 1]) - 1) * 8;
      await tester.tap(find.byKey(ValueKey('square-${square(0)}')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('square-${square(2)}')));
      await tester.pumpAndSettle();
    }
    expect(restored.guidedLearning.moves, 4);
    expect(restored.guidedLearning.discarded, true);
    await tester.tap(find.byKey(const ValueKey('practice-next')));
    await tester.pumpAndSettle();
    expect(restored.hasCompletedTutorial, true);
    expect(restored.data.toJson(), before);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'guided replay starts clean and closes without changing account progress',
    (tester) async {
      final store = GameStore.instance;
      store
        ..loaded = true
        ..data = PlayerData.initial()
        ..hasCompletedTutorial = true
        ..guidedLearning = const BattleLearningCheckpoint(
          moves: 4,
          cast: true,
          discarded: true,
          passed: true,
        )
        ..practiceStage = 2;
      final before = store.data.toJson();
      final checkpoint = store.guidedLearning.toJson();
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => const BattlePracticeCampaign(
                                  guidedReplay: true,
                                ),
                          ),
                        ),
                    child: const Text('Replay'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Replay'));
      await tester.pumpAndSettle();
      await warm(tester);
      final battle = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
      expect(battle.practiceCheckpoint, isNull);
      expect(battle.onPracticeProgress, isNull);
      expect(battle.onPracticeSkip, isNull);
      expect(
        tester
            .widget<BattlePracticeCoach>(find.byType(BattlePracticeCoach))
            .progress
            .moves,
        0,
      );
      await battle.onPracticeComplete!();
      await tester.pumpAndSettle();
      expect(find.byType(BattleV1Screen), findsNothing);
      expect(store.guidedLearning.toJson(), checkpoint);
      expect(store.hasCompletedTutorial, true);
      expect(store.practiceStage, 2);
      expect(store.data.toJson(), before);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final language in ['tr', 'en']) {
    testWidgets('welcome skip requires confirmation $language', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await tester.pumpWidget(
        shell(BattleWelcomeScreen(playerStore: store), language: language),
      );
      await warm(tester);
      await capture(
        tester,
        'welcome-$language',
        repaintKey: boundaryKey,
        outputDirectory: 'qa/v235-v226/screens',
      );
      await tester.tap(find.byKey(const ValueKey('welcome-skip')));
      await tester.pumpAndSettle();
      expect(store.hasCompletedTutorial, false);
      await tester.tap(
        find.text(language == 'en' ? 'Keep learning' : 'Öğrenmeye devam'),
      );
      await tester.pumpAndSettle();
      expect(store.hasCompletedTutorial, false);
      await tester.tap(find.byKey(const ValueKey('welcome-skip')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(language == 'en' ? 'Skip for now' : 'Şimdilik geç'),
      );
      await tester.pumpAndSettle();
      expect(store.hasCompletedTutorial, true);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    });

    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(390, 844), 1.8),
      (const Size(768, 1024), 1.0),
    ]) {
      testWidgets(
        'resumed basics completion is reachable $language $size $scale',
        (tester) async {
          GameStore.instance
            ..loaded = true
            ..data = PlayerData.initial();
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var completed = 0;
          await tester.pumpWidget(
            shell(
              BattleV1Screen(
                practiceStage: 0,
                practiceOnboarding: true,
                guidedFirstMatch: true,
                practiceCheckpoint: const BattleLearningCheckpoint(
                  moves: 4,
                  cast: true,
                  discarded: true,
                  passed: true,
                ),
                onPracticeComplete: () async {
                  completed++;
                },
              ),
              language: language,
              scale: scale,
            ),
          );
          await warm(tester);
          noOverflow(tester);
          final next = find.byKey(const ValueKey('practice-next'));
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          expect(next.hitTestable(), findsOneWidget);
          await capture(
            tester,
            'basics-complete-$language-${size.width.toInt()}-$scale',
            repaintKey: boundaryKey,
            outputDirectory: 'qa/v235-v226/screens',
          );
          if (scale > 1) {
            await tester.drag(
              find.byKey(const ValueKey('lesson-speech-scroll')),
              const Offset(0, -700),
            );
            await tester.pumpAndSettle();
            await capture(
              tester,
              'basics-speech-scrolled-$language',
              repaintKey: boundaryKey,
              outputDirectory: 'qa/v235-v226/screens',
            );
            expect(next.hitTestable(), findsOneWidget);
          }
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(completed, 1);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'actual touch lesson completes without finishing Baby Luno match $language',
      (tester) async {
        GameStore.instance
          ..loaded = true
          ..data = PlayerData.initial();
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var completed = 0;
        BattleLearningCheckpoint saved = const BattleLearningCheckpoint();
        await tester.pumpWidget(
          shell(
            BattleV1Screen(
              practiceStage: 0,
              practiceOnboarding: true,
              guidedFirstMatch: true,
              onPracticeProgress: (value) async {
                saved = value;
              },
              onPracticeComplete: () async {
                completed++;
              },
            ),
            language: language,
          ),
        );
        await warm(tester);
        for (var turn = 0; turn < 4; turn++) {
          await waitForOwnTurn(tester);
          expect(
            find.byType(OpponentArsenalSheet),
            findsNothing,
            reason: 'before turn $turn',
          );
          var board = tester.widget<BattleBoard>(find.byType(BattleBoard));
          if (board.view.rules.phase == BattlePhase.card) {
            if (!saved.cast) {
              final shelter = find.byKey(
                ValueKey('hand-${CardId.shelter.wire}'),
              );
              await tester.ensureVisible(shelter);
              await tester.pumpAndSettle();
              await tester.tap(shelter);
              await tester.pumpAndSettle();
              expect(
                find.byType(OpponentArsenalSheet),
                findsNothing,
                reason: 'after shelter selection',
              );
              board = tester.widget<BattleBoard>(find.byType(BattleBoard));
              expect(board.targets, isNotEmpty);
              await tester.tap(
                find.byKey(ValueKey('square-${board.targets.first}')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('play-card')));
            } else if (!saved.discarded) {
              final hand = tester.widget<BattleHand>(find.byType(BattleHand));
              final discardCard = hand.view.ownHand.firstWhere(
                (card) =>
                    cardDefinitions[card]!.target !=
                        CardTargetType.opponentCard &&
                    cardDefinitions[card]!.target != CardTargetType.sacrifice,
              );
              final tile = find.byKey(ValueKey('hand-${discardCard.wire}'));
              await tester.ensureVisible(tile);
              await tester.pumpAndSettle();
              await tester.tap(tile);
              await tester.pumpAndSettle();
              expect(
                find.byType(OpponentArsenalSheet),
                findsNothing,
                reason: 'after discard selection',
              );
              await capture(
                tester,
                'discard-before-$language',
                repaintKey: boundaryKey,
                outputDirectory: 'qa/v235-v226/screens',
              );
              expect(
                tester
                    .widget<TextButton>(
                      find.byKey(const ValueKey('discard-card')),
                    )
                    .onPressed,
                isNotNull,
              );
              await tester.tap(find.byKey(const ValueKey('discard-card')));
            } else {
              await tester.tap(find.byKey(const ValueKey('pass-card')));
            }
            await tester.pumpAndSettle();
          }
          board = tester.widget<BattleBoard>(find.byType(BattleBoard));
          expect(board.view.rules.phase, BattlePhase.chess);
          final move =
              BattleRulesCore.legalActions(
                board.view,
              ).whereType<ChessMoveAction>().first;
          int square(int start) =>
              move.uci.codeUnitAt(start) -
              97 +
              (int.parse(move.uci[start + 1]) - 1) * 8;
          await tester.tap(find.byKey(ValueKey('square-${square(0)}')));
          await tester.pump();
          await tester.tap(find.byKey(ValueKey('square-${square(2)}')));
          await tester.pumpAndSettle();
          expect(
            find.byType(OpponentArsenalSheet),
            findsNothing,
            reason: 'after move $turn',
          );
        }
        expect(saved.moves, 4);
        expect(saved.cast && saved.discarded && saved.passed, true);
        expect(
          tester
              .widget<BattleBoard>(find.byType(BattleBoard))
              .view
              .rules
              .terminal,
          isNull,
        );
        final next = find.byKey(const ValueKey('practice-next'));
        await tester.ensureVisible(next);
        await capture(
          tester,
          'touch-basics-$language',
          repaintKey: boundaryKey,
          outputDirectory: 'qa/v235-v226/screens',
        );
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(completed, 1);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }

  test('completed basic exercises can finish before checkmate or victory', () {
    final before = battleFixture().view(PieceColor.white);
    final transition = BattleRulesCore.transition(before, const PassAction());
    final after = PlayerView(
      transition.rules,
      before.viewer,
      before.ownHand,
      before.knowledge,
    );
    final progress =
        BattlePracticeProgress(0, onboarding: true, guidedMatch: true)
          ..moves = 4
          ..cast = true
          ..discarded = true;
    progress.accepted(const PassAction(), before, after);
    expect(after.rules.terminal, isNull);
    expect(progress.complete, isTrue);
    expect(progress.canFinish(after), isTrue);
  });

  test(
    'selected chess piece coaching points at one of its legal destinations',
    () {
      final cardView = battleFixture().view(PieceColor.white);
      final transition = BattleRulesCore.transition(
        cardView,
        const PassAction(),
      );
      final view = PlayerView(
        transition.rules,
        cardView.viewer,
        cardView.ownHand,
        cardView.knowledge,
      );
      final legal = BattleRulesCore.legalActions(view);
      final selection = BattleInteraction()..piece = Square.of(4, 1);
      final suggested = battlePracticeBoardSquare(view, selection, legal);
      final destinations = legal
          .whereType<ChessMoveAction>()
          .where((action) => action.uci.startsWith('e2'))
          .map(
            (action) => Square.of(
              action.uci.codeUnitAt(2) - 97,
              int.parse(action.uci[3]) - 1,
            ),
          );
      expect(destinations, isNotEmpty);
      expect(destinations, contains(suggested));
      expect(suggested, isNot(selection.piece));
    },
  );
}
