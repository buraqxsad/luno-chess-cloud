import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/action_guide.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, boundaryKey;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture;
import 'rc_screen_capture_test.dart' show capture;
import 'v227_coach_guidance_test.dart' show coach;
import 'v227_onboarding_lesson_contract_test.dart' show waitForOwnTurn;

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = false
      ..onboardingBattleStage = 0
      ..practiceStage = null;
  });

  for (final language in ['tr', 'en']) {
    final en = language == 'en';
    testWidgets('blocked opening piece gives actionable guidance $language', (
      tester,
    ) async {
      final progress = BattlePracticeProgress(0, onboarding: true);
      final view = DeckManager.newBattle(
        white: progress.deck,
      ).view(PieceColor.white);
      expect(
        BattleRulesCore.legalActions(
          view,
        ).whereType<ChessMoveAction>().any((a) => a.uci.startsWith('c1')),
        isFalse,
      );
      final bubble = await coach(
        tester,
        language,
        progress,
        view,
        selectedPiece: 2,
      );
      expect(bubble.text, contains(en ? 'no legal move' : 'yasal hamlesi yok'));
      expect(bubble.text, contains(en ? 'another piece' : 'Başka taş'));
      expect(
        bubble.text,
        isNot(contains(en ? 'lit squares' : 'Işıklı kareler')),
      );
    });

    testWidgets('missing lesson card does not blame mana $language', (
      tester,
    ) async {
      final progress = BattlePracticeProgress(0, onboarding: true);
      final view = battleFixture(hand: [CardId.radar]).view(PieceColor.white);
      final bubble = await coach(tester, language, progress, view);
      expect(
        bubble.text,
        contains(en ? 'not in your hand yet' : 'henüz elinde değil'),
      );
      expect(
        bubble.text,
        isNot(contains(en ? 'saving mana' : 'mana biriktir')),
      );
      expect(
        bubble.text,
        isNot(contains(en ? 'save a little more' : 'biraz daha biriktirelim')),
      );
    });

    testWidgets(
      'exhausted lesson deck offers recovery, not a promised draw $language',
      (tester) async {
        final progress = BattlePracticeProgress(0, onboarding: true);
        final base = battleFixture(hand: [CardId.radar]);
        final draft = RuleDraft(base.rules)..deckCounts[PieceColor.white] = 0;
        final view = AuthoritativeBattleState(
          draft.freeze(),
          base.hidden,
        ).view(PieceColor.white);
        final bubble = await coach(tester, language, progress, view);
        expect(
          bubble.text,
          contains(en ? 'Restart practice' : 'yeniden başlat'),
        );
        expect(
          bubble.text,
          isNot(contains(en ? 'refill your hand' : 'elin yenilenir')),
        );
      },
    );

    testWidgets(
      'normal battle explains a blocked piece without sending an action $language',
      (tester) async {
        final sent = <String>[];
        await renderBattle(
          tester,
          language: language,
          state: battleFixture(firstTurn: true),
          requestOverride: (path, body) async {
            sent.add(path);
            throw StateError('Selection must not send an action');
          },
        );
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(2);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BattleActionGuide>(find.byType(BattleActionGuide))
              .instruction,
          contains(en ? 'no legal move' : 'yasal hamlesi yok'),
        );
        expect(sent, isEmpty);
        noOverflow(tester);
        await closeCapture(tester);
      },
    );

    testWidgets(
      'blocked lesson card with enough mana explains unavailability $language',
      (tester) async {
        final progress = BattlePracticeProgress(1, onboarding: true);
        final base = battleFixture(hand: [CardId.freeze]);
        final draft = RuleDraft(base.rules)
          ..modifiers.add(
            const PendingModifier(
              id: 'v229-block',
              type: ModifierType.cardBlock,
              owner: PieceColor.black,
              responseSide: PieceColor.white,
              targetCard: CardId.freeze,
              ownTurn: 2,
            ),
          );
        final view = AuthoritativeBattleState(
          draft.freeze(),
          base.hidden,
        ).view(PieceColor.white);
        expect(view.rules.mana[view.viewer], greaterThanOrEqualTo(4));
        expect(
          BattleRulesCore.legalActions(view).whereType<PlayCardAction>(),
          isEmpty,
        );
        for (final selected in [null, CardId.freeze]) {
          final bubble = await coach(
            tester,
            language,
            progress,
            view,
            selected: selected,
          );
          expect(
            bubble.text,
            contains(en ? 'cannot be played right now' : 'şu anda oynanamıyor'),
          );
          expect(
            bubble.text,
            isNot(contains(en ? 'saving mana' : 'mana biriktir')),
          );
          expect(
            bubble.text,
            isNot(
              contains(en ? 'save a little more' : 'biraz daha biriktirelim'),
            ),
          );
        }
      },
    );

    testWidgets(
      'guided goals show live completion, free play has no card goals $language',
      (tester) async {
        final progress = BattlePracticeProgress(0, onboarding: true);
        final view = battleFixture(
          hand: [CardId.shelter],
        ).view(PieceColor.white);
        await coach(tester, language, progress, view);
        expect(find.byKey(const ValueKey('practice-goals')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('practice-goal-play')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('practice-goal-discard')),
          findsOneWidget,
        );
        expect(find.text(en ? '0/4 moves' : '0/4 hamle'), findsOneWidget);
        progress
          ..cast = true
          ..discarded = true
          ..moves = 2;
        await coach(tester, language, progress, view);
        final goals = find.byKey(const ValueKey('practice-goals'));
        expect(
          find.descendant(of: goals, matching: find.byIcon(Icons.check_circle)),
          findsNWidgets(2),
        );
        expect(find.text(en ? '2/4 moves' : '2/4 hamle'), findsOneWidget);
        final free = BattlePracticeProgress(2, onboarding: true)..moves = 1;
        await coach(tester, language, free, view);
        expect(find.byKey(const ValueKey('practice-goal-play')), findsNothing);
        expect(
          find.byKey(const ValueKey('practice-goal-discard')),
          findsNothing,
        );
        expect(find.text(en ? '1/4 moves' : '1/4 hamle'), findsOneWidget);
        noOverflow(tester);
      },
    );

    testWidgets(
      'live practice explains blocked bishop and accepts a free opening $language',
      (tester) async {
        await tester.pumpWidget(
          shell(
            const BattleV1Screen(practiceStage: 0, practiceOnboarding: true),
            language: language,
            reduced: true,
          ),
        );
        await warm(tester);
        final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        board.onTap(2);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TutorialCoach>(find.byType(TutorialCoach)).text,
          contains(en ? 'no legal move' : 'yasal hamlesi yok'),
        );
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
          0,
        );
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(12);
        await tester.pumpAndSettle();
        tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(28);
        await tester.pumpAndSettle();
        await waitForOwnTurn(tester);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
          greaterThanOrEqualTo(2),
        );
        expect(find.text(en ? '1/4 moves' : '1/4 hamle'), findsOneWidget);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(360, 640), 1.6),
      (const Size(844, 390), 1.0),
    ]) {
      testWidgets(
        'opening goals and hand remain reachable $language $size $scale',
        (tester) async {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              const BattleV1Screen(practiceStage: 0, practiceOnboarding: true),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          await warm(tester);
          noOverflow(tester);
          final goals = find.byKey(const ValueKey('practice-goals'));
          await tester.ensureVisible(goals);
          await tester.pumpAndSettle();
          expect(goals.hitTestable(), findsOneWidget);
          for (final card in [CardId.shelter, CardId.radar, CardId.prophecy]) {
            final tile = find.byKey(ValueKey('hand-${card.wire}'));
            await tester.ensureVisible(tile);
            await tester.pumpAndSettle();
            expect(tile.hitTestable(), findsOneWidget);
          }
          noOverflow(tester);
          await capture(
            tester,
            'opening-$language-${size.width.toInt()}-${size.height.toInt()}-$scale',
            repaintKey: boundaryKey,
            outputDirectory: 'qa/v229/screens',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
