import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 950));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> showLiveOnboarding(WidgetTester tester) async {
  final loading = find.byType(LunoLoadingArtwork);
  if (loading.evaluate().isNotEmpty) {
    // Signal artwork rendering, never the startup gate or player completion.
    final artwork = tester.widget<LunoLoadingArtwork>(loading);
    expect(artwork.onShown, isNotNull);
    artwork.onShown!();
    await tester.pump(const Duration(milliseconds: 1500));
  }
  await _settle(tester);
  expect(loading, findsNothing);
  expect(find.byType(UsernameSetupScreen), findsNothing);
  expect(find.byType(HomeScreen), findsNothing);
}

Future<void> advanceLiveWelcome(WidgetTester tester) async {
  final store = GameStore.instance;
  expect(GameStore.welcomeStepCount, 3);
  for (var step = store.welcomeStep; step < 3; step++) {
    expect(find.byType(BattleWelcomeScreen), findsOneWidget);
    expect(find.byKey(ValueKey('welcome-title-$step')), findsOneWidget);
    expect(find.byType(BattleV1Screen), findsNothing);
    expect(store.hasCompletedTutorial, isFalse);
    expect(store.firstSessionMatchCompleted, isFalse);
    await _tap(tester, find.byKey(const ValueKey('welcome-next')));
    expect(store.welcomeStep, step + 1);
  }
  expect(find.byType(BattleWelcomeScreen), findsNothing);
  final match = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
  expect(match.practiceStage, 0);
  expect(match.practiceOnboarding, isTrue);
  expect(match.guidedFirstMatch, isTrue);
  expect(match.practiceCanExit, isFalse);
}

Future<void> completeLiveOnboarding(WidgetTester tester) async {
  final store = GameStore.instance;
  await showLiveOnboarding(tester);
  await advanceLiveWelcome(tester);

  for (var attempt = 0; attempt < 60; attempt++) {
    final coach = tester.widget<BattlePracticeCoach>(
      find.byType(BattlePracticeCoach),
    );
    final progress = coach.progress;
    var board = tester.widget<BattleBoard>(find.byType(BattleBoard));
    expect(progress.guidedMatch, isTrue);
    expect(progress.stage, 0);
    expect(progress.level.id, 'bebek');
    expect(board.view.rules.terminal, isNull);
    expect(progress.canFinish(board.view), isFalse);
    expect(find.byKey(const ValueKey('practice-next')), findsNothing);
    expect(store.hasCompletedTutorial, isFalse);
    expect(store.firstSessionMatchCompleted, isFalse);
    if (!board.enabled || board.view.rules.board.turn != PieceColor.white) {
      await _settle(tester);
      continue;
    }
    if (progress.moves >= 4 && progress.cast && progress.discarded) break;

    final legal = BattleRulesCore.legalActions(board.view);
    final actions = progress.lessonActions(board.view, legal);
    expect(
      actions.map((action) => action.key),
      unorderedEquals(legal.map((action) => action.key)),
      reason: 'Guidance must not filter legal play.',
    );
    final card =
        actions
            .whereType<PlayCardAction>()
            .where((action) => action.card == progress.card)
            .firstOrNull;
    final discard = actions.whereType<DiscardAction>().firstOrNull;
    if (!progress.cast && card != null) {
      await _tap(tester, find.byKey(ValueKey('hand-${card.card.wire}')));
      board = tester.widget<BattleBoard>(find.byType(BattleBoard));
      expect(board.targets, isNotEmpty);
      await _tap(tester, find.byKey(ValueKey('square-${board.targets.first}')));
      await _tap(tester, find.byKey(const ValueKey('play-card')));
      expect(progress.cast, isTrue);
    } else if (progress.cast && !progress.discarded && discard != null) {
      await _tap(tester, find.byKey(ValueKey('hand-${discard.card.wire}')));
      await _tap(tester, find.byKey(const ValueKey('discard-card')));
      expect(progress.discarded, isTrue);
    } else {
      final moves = BattleInteraction().moves(board.view, actions);
      expect(moves, isNotEmpty);
      const openings = ['e2e4', 'g1f3', 'f1c4', 'b1c3'];
      final wanted = openings[progress.moves.clamp(0, 3)];
      final move =
          moves.where((action) => action.uci == wanted).firstOrNull ??
          moves.first;
      int square(int offset) =>
          move.uci.codeUnitAt(offset) -
          97 +
          (int.parse(move.uci[offset + 1]) - 1) * 8;
      final before = progress.moves;
      await _tap(tester, find.byKey(ValueKey('square-${square(0)}')));
      await _tap(tester, find.byKey(ValueKey('square-${square(2)}')));
      expect(progress.moves, before + 1);
    }
  }

  final coach = tester.widget<BattlePracticeCoach>(
    find.byType(BattlePracticeCoach),
  );
  final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
  expect(coach.progress.moves, greaterThanOrEqualTo(4));
  expect(coach.progress.cast && coach.progress.discarded, isTrue);
  expect(board.enabled, isTrue, reason: 'Wait for the real Baby Luno reply.');
  expect(board.view.rules.board.turn, PieceColor.white);
  expect(coach.progress.complete, isFalse);
  expect(coach.progress.canFinish(board.view), isFalse);
  expect(find.byKey(const ValueKey('practice-next')), findsNothing);

  // A real resignation bounds the E2E without manufacturing a game result.
  await _tap(
    tester,
    find.byTooltip('Match menu').evaluate().isNotEmpty
        ? find.byTooltip('Match menu')
        : find.byTooltip('Maç menüsü'),
  );
  await _tap(tester, find.byKey(const ValueKey('resign-menu')));
  expect(
    tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.terminal,
    isNull,
    reason: 'Opening the resignation confirmation must not finish the match.',
  );
  expect(store.hasCompletedTutorial, isFalse);
  await _tap(
    tester,
    find.text('Resign').evaluate().isNotEmpty
        ? find.text('Resign')
        : find.text('Teslim ol'),
  );
  expect(find.byType(BattleBoard), findsNothing);
  final finished =
      tester.widget<BattlePracticeCoach>(find.byType(BattlePracticeCoach)).view;
  final terminal = finished.rules.terminal;
  expect(terminal?.reason, 'resign');
  expect(terminal?.winner, PieceColor.black);
  expect(coach.progress.canFinish(finished), isTrue);
  expect(store.hasCompletedTutorial, isFalse);
  expect(store.firstSessionMatchCompleted, isFalse);
  await _tap(tester, find.byKey(const ValueKey('practice-next')));
  expect(store.hasCompletedTutorial, isTrue);
  expect(store.firstSessionMatchCompleted, isTrue);
  expect(store.needsFirstSessionMatch, isFalse);
}
