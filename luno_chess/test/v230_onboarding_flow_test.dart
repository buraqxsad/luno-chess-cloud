import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, warm, noOverflow;
import 'battle_ui/fixtures.dart';
import 'v227_coach_guidance_test.dart' show coach;

void main() {
  setupPracticeTestAssets();

  test('welcome advances once per confirmed step and persists', () async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.load();
    expect(store.welcomeStep, 0);
    final revision = store.accountBindingRevision;
    final first = store.advanceWelcomeStep(0, revision);
    final duplicate = store.advanceWelcomeStep(0, revision);
    expect(await first, true);
    expect(await duplicate, false);
    expect(store.welcomeStep, 1);
    final restored = GameStore.createForTesting();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.welcomeStep, 1);
    expect(restored.hasCompletedTutorial, false);
    expect(restored.onboardingBattleStage, 0);
    for (var step = 1; step < GameStore.welcomeStepCount; step++) {
      expect(await restored.advanceWelcomeStep(step, revision), true);
    }
    expect(await restored.advanceWelcomeStep(3, revision), false);
    expect(restored.hasCompletedTutorial, false);
  });

  test(
    'welcome state is isolated across account changes and erasure',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.bindAccount('welcome-a');
      final owner = store.accountBindingRevision;
      await store.advanceWelcomeStep(0, owner);
      await store.bindAccount('welcome-b');
      expect(store.welcomeStep, 0);
      expect(await store.advanceWelcomeStep(0, owner), false);
      await store.bindAccount('welcome-a');
      expect(store.welcomeStep, 1);
      await store.eraseLocalAccount('welcome-a');
      expect(store.welcomeStep, 0);
    },
  );

  for (final stage in [1, 2]) {
    test(
      'existing stage $stage learners are not sent back to greeting',
      () async {
        SharedPreferences.setMockInitialValues({
          'luno_player_v1': jsonEncode({
            ...PlayerData.initial().toJson(),
            'tutorialCompleted': false,
            'onboardingBattleStage': stage,
          }),
        });
        final store = GameStore.createForTesting();
        addTearDown(store.dispose);
        await store.load();
        expect(store.welcomeStep, GameStore.welcomeStepCount);
        expect(store.onboardingBattleStage, stage);
        expect(store.hasCompletedTutorial, false);
      },
    );
  }

  for (final raw in [null, '3', true, -10, 100]) {
    test('welcome parser safely normalizes $raw', () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'welcomeStep': raw,
        }),
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.welcomeStep, raw == 100 ? 3 : 0);
      expect(store.loaded, true);
    });
  }

  for (final legacy in [
    {'tutorialStep': 4},
    {'introductionSchema': 1, 'introductionStep': 3},
    {'firstSessionMatchesStarted': 1},
  ]) {
    test('legacy partial learner avoids repeated welcome $legacy', () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          ...legacy,
        }),
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.welcomeStep, GameStore.welcomeStepCount);
      expect(store.hasCompletedTutorial, false);
    });
  }

  testWidgets('one campaign changes from greeting to actual Baby Luno board', (
    tester,
  ) async {
    final store = GameStore.instance;
    await store.load();
    store
      ..hasCompletedTutorial = false
      ..welcomeStep = 0
      ..onboardingBattleStage = 0;
    await tester.pumpWidget(
      shell(const BattlePracticeCampaign(onboarding: true), reduced: true),
    );
    await warm(tester);
    expect(find.byType(BattleWelcomeScreen), findsOneWidget);
    expect(find.byType(BattleV1Screen), findsNothing);
    final owner = store.accountBindingRevision;
    for (var step = 0; step < GameStore.welcomeStepCount; step++) {
      await store.advanceWelcomeStep(step, owner);
      await tester.pump();
    }
    await warm(tester);
    expect(find.byType(BattleWelcomeScreen), findsNothing);
    final battle = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
    expect(battle.practiceStage, 0);
    expect(battle.practiceOnboarding, true);
    expect(battle.guidedFirstMatch, true);
    expect(BattlePracticeProgress(0, onboarding: true).level, aiLevels.first);
    expect(store.hasCompletedTutorial, false);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'guided match never gates legal cards, and four moves do not finish it',
    () {
      final progress = BattlePracticeProgress(
        0,
        onboarding: true,
        guidedMatch: true,
      );
      final view = battleFixture(
        hand: [CardId.shelter, CardId.radar],
      ).view(PieceColor.white);
      final legal = BattleRulesCore.legalActions(view);
      expect(progress.lessonActions(view, legal), same(legal));
      progress
        ..moves = 4
        ..cast = true
        ..discarded = true;
      expect(progress.complete, false);
      expect(progress.stopsPlay, false);
      expect(progress.canFinish(view), false);
      final ended =
          RuleDraft(view.rules)
            ..phase = BattlePhase.terminal
            ..terminal = const TerminalState(
              'resign',
              winner: PieceColor.black,
            );
      expect(
        progress.canFinish(
          PlayerView(ended.freeze(), view.viewer, view.ownHand, view.knowledge),
        ),
        true,
      );
    },
  );

  test(
    'guided completion replaces extra forced first match without a reward',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      final owner = store.accountBindingRevision;
      await store.completeGuidedOnboarding(owner);
      expect(store.hasCompletedTutorial, false);
      for (var step = 0; step < GameStore.welcomeStepCount; step++) {
        await store.advanceWelcomeStep(step, owner);
      }
      final before = store.data.toJson();
      await store.completeGuidedOnboarding(owner);
      await store.completeGuidedOnboarding(owner);
      expect(store.hasCompletedTutorial, true);
      expect(store.needsFirstSessionMatch, false);
      expect(store.firstSessionMatchesStarted, 1);
      expect(store.hasChosenUsername, false);
      expect(store.data.toJson(), before);
      await store.flush();
      final restored = GameStore.createForTesting();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.hasCompletedTutorial, true);
      expect(restored.needsFirstSessionMatch, false);
    },
  );

  for (final card in [CardId.shelter, CardId.freeze]) {
    test('${card.wire} suggestions are legal, optional and public-only', () {
      final view = battleFixture(hand: [card]).view(PieceColor.white);
      final actions = BattleRulesCore.legalActions(view);
      final target = battlePracticeCardTarget(view, card, actions);
      expect(target, isNotNull);
      expect(
        actions.whereType<PlayCardAction>().any(
          (a) => a.card == card && a.target == target,
        ),
        true,
      );
      final selection = BattleInteraction()..select(card, actions);
      expect(battlePracticeBoardSquare(view, selection, actions), target);
      expect(selection.play, isNull);
      expect(
        actions.whereType<PlayCardAction>().where(
          (a) => a.card == card && a.target != target,
        ),
        isNotEmpty,
      );
      final draft = RuleDraft(view.rules)..mana[view.viewer] = 0;
      final poor = PlayerView(
        draft.freeze(),
        view.viewer,
        view.ownHand,
        view.knowledge,
      );
      expect(
        battlePracticeCardTarget(
          poor,
          card,
          BattleRulesCore.legalActions(poor),
        ),
        isNull,
      );
    });

    for (final language in ['tr', 'en']) {
      testWidgets(
        '${card.wire} explanation refers to live target and result $language',
        (tester) async {
          final progress = BattlePracticeProgress(
            card == CardId.shelter ? 0 : 1,
            onboarding: true,
          );
          var state = battleFixture(hand: [card]);
          final view = state.view(PieceColor.white);
          final actions = BattleRulesCore.legalActions(view);
          final suggested = battlePracticeCardTarget(view, card, actions)!;
          final text = await coach(
            tester,
            language,
            progress,
            view,
            selected: card,
          );
          expect(
            text.text,
            contains(language == 'en' ? 'For example' : 'Örneğin'),
          );
          final action = actions.whereType<PlayCardAction>().firstWhere(
            (a) => a.card == card && a.target == suggested,
          );
          state = DeckManager.apply(state, action);
          progress.accepted(action, view, state.view(PieceColor.white));
          final after = await coach(
            tester,
            language,
            progress,
            state.view(PieceColor.white),
          );
          expect(
            after.text,
            contains(language == 'en' ? 'effect on' : 'etkisini'),
          );
          expect(
            after.text,
            contains(language == 'en' ? 'your move' : 'Hamle hakkın'),
          );
        },
      );
    }
  }

  for (final card in movementCards) {
    for (final language in ['tr', 'en']) {
      testWidgets(
        '${card.wire} coaching respects the actual bound chess move $language',
        (tester) async {
          final piece = switch (card) {
            CardId.rookBend => 'R',
            CardId.angryN => 'N',
            CardId.shadowPass => 'B',
            _ => 'P',
          };
          final base = battleFixture(hand: [card]);
          final draft = RuleDraft(base.rules)
            ..board = Board.fromFen(
              card == CardId.shadowPass
                  ? '4k3/8/8/4P3/3B4/8/8/4K3 w - - 0 1'
                  : '4k3/8/8/8/3${piece}4/8/8/4K3 w - - 0 1',
            );
          draft.pieceIds = List.generate(
            64,
            (i) => draft.board.pieceAt(i) == null ? null : 'q$i',
          );
          var state = AuthoritativeBattleState(draft.freeze(), base.hidden);
          final before = state.view(PieceColor.white);
          final play = BattleRulesCore.legalActions(
            before,
          ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
          state = DeckManager.apply(state, play);
          expect(state.rules.special, isNotNull);
          final progress = BattlePracticeProgress(
            0,
            onboarding: true,
            guidedMatch: true,
          );
          progress.accepted(play, before, state.view(PieceColor.white));
          final bubble = await coach(
            tester,
            language,
            progress,
            state.view(PieceColor.white),
          );
          expect(
            bubble.text,
            contains(language == 'en' ? 'marked piece on' : 'işaretli taşla'),
          );
          expect(
            bubble.text,
            isNot(contains(language == 'en' ? 'your choice' : 'sana kalmış')),
          );
        },
      );
    }
  }
}
