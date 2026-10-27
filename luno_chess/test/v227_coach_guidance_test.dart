import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, warm;
import 'battle_ui/fixtures.dart' show battleFixture;

Future<TutorialCoach> coach(
  WidgetTester tester,
  String language,
  BattlePracticeProgress progress,
  PlayerView view, {
  CardId? selected,
  bool targetReady = false,
  int? selectedPiece,
  bool invalidTarget = false,
  String? freeInstruction,
}) async {
  await tester.pumpWidget(
    shell(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: BattlePracticeCoach(
              progress: progress,
              view: view,
              selected: selected,
              targetReady: targetReady,
              selectedPiece: selectedPiece,
              invalidTarget: invalidTarget,
              freeInstruction: freeInstruction,
            ),
          ),
        ),
      ),
      language: language,
      reduced: true,
    ),
  );
  await warm(tester);
  return tester.widget<TutorialCoach>(find.byType(TutorialCoach));
}

void expectFreeChess(BattlePracticeProgress progress, PlayerView view) {
  final legal = BattleRulesCore.legalActions(view);
  final moves = legal.whereType<ChessMoveAction>().toList();
  expect(moves.length, greaterThan(1));
  expect(
    progress
        .lessonActions(view, legal)
        .whereType<ChessMoveAction>()
        .map((action) => action.key),
    moves.map((action) => action.key),
    reason: 'A coach suggestion must not force a particular chess move.',
  );
}

void main() {
  setupPracticeTestAssets();

  for (final language in ['tr', 'en']) {
    final en = language == 'en';
    for (final stage in [0, 1]) {
      testWidgets('guided $stage opening is a free chess choice $language', (
        tester,
      ) async {
        final progress = BattlePracticeProgress(stage, onboarding: true);
        final view = DeckManager.newBattle(
          white: progress.deck,
        ).view(PieceColor.white);
        expectFreeChess(progress, view);
        final opening = await coach(tester, language, progress, view);
        expect(
          opening.text,
          contains(
            en
                ? (stage == 0 ? 'any white piece' : 'Choose your opening')
                : (stage == 0 ? '\u0130stedi\u011fin' : 'sen se\u00e7'),
          ),
        );
        expect(opening.heading, contains(en ? 'PRACTICE' : 'ANTRENMAN'));
        expect(opening.text, isNot(contains('e2')));
        expect(opening.text, isNot(contains('e4')));
        if (stage == 0) {
          final selected = await coach(
            tester,
            language,
            progress,
            view,
            selectedPiece: 1,
          );
          expect(
            selected.text,
            contains(en ? 'lit squares' : 'I\u015f\u0131kl\u0131 kareler'),
          );
        }
      });

      testWidgets(
        'guided $stage selection, cast and discard agree with rules $language',
        (tester) async {
          final progress = BattlePracticeProgress(stage, onboarding: true);
          var state = battleFixture(hand: [progress.card, CardId.radar]);
          var view = state.view(PieceColor.white);
          var actions = progress.lessonActions(
            view,
            BattleRulesCore.legalActions(view),
          );
          expect(actions, isNotEmpty);
          expect(
            actions.every(
              (a) => a is PlayCardAction && a.card == progress.card,
            ),
            true,
          );
          final prompt = await coach(
            tester,
            language,
            progress,
            view,
            selected: CardId.radar,
          );
          expect(
            prompt.text,
            contains(
              en ? 'For this lesson' : 'Bu e\u011fitim ad\u0131m\u0131nda',
            ),
          );
          expect(
            practiceFocus(progress, view, CardId.radar, false),
            BattleCoachFocus.hand,
          );

          final target = await coach(
            tester,
            language,
            progress,
            view,
            selected: progress.card,
          );
          expect(target.text, contains(en ? 'marked' : 'i\u015faretli'));
          if (stage == 0) {
            expect(
              target.text,
              contains(
                en
                    ? 'not chess captures'
                    : 'ta\u015f al\u0131nmas\u0131n\u0131 engellemez',
              ),
            );
          }
          expect(
            practiceFocus(progress, view, progress.card, false),
            BattleCoachFocus.board,
          );
          final ready = await coach(
            tester,
            language,
            progress,
            view,
            selected: progress.card,
            targetReady: true,
          );
          expect(
            ready.text,
            contains(
              en ? 'Confirm with Play Card' : 'Kart\u0131 Oyna ile onayla',
            ),
          );
          expect(
            practiceFocus(progress, view, progress.card, true),
            BattleCoachFocus.controls,
          );

          final play = actions.first;
          state = DeckManager.apply(state, play);
          progress.accepted(play, view, state.view(PieceColor.white));
          view = state.view(PieceColor.white);
          expect(progress.cast, true);
          expectFreeChess(progress, view);
          final afterCast = await coach(tester, language, progress, view);
          expect(
            afterCast.text,
            contains(en ? 'your choice' : 'sana kalm\u0131\u015f'),
          );

          // Advance only the phase, as in the existing v227 lesson contract fixture.
          state = AuthoritativeBattleState(
            (RuleDraft(state.rules)..phase = BattlePhase.card).freeze(),
            state.hidden,
          );
          view = state.view(PieceColor.white);
          actions = progress.lessonActions(
            view,
            BattleRulesCore.legalActions(view),
          );
          expect(actions, isNotEmpty);
          expect(actions.every((a) => a is DiscardAction), true);
          final discard = await coach(
            tester,
            language,
            progress,
            view,
            selected: CardId.radar,
          );
          expect(discard.text, contains(en ? 'Discard' : 'Feda Et'));
          expect(
            discard.text,
            contains(en ? 'no mana' : 'Mana kazanmazs\u0131n'),
          );
          expect(
            practiceFocus(progress, view, CardId.radar, false),
            BattleCoachFocus.controls,
          );
          final mana = view.rules.mana[PieceColor.white];
          state = DeckManager.apply(state, actions.first);
          progress.accepted(actions.first, view, state.view(PieceColor.white));
          view = state.view(PieceColor.white);
          expect(progress.discarded, true);
          expect(view.rules.mana[PieceColor.white], mana);
          expectFreeChess(progress, view);
          final afterDiscard = await coach(tester, language, progress, view);
          expect(
            afterDiscard.text,
            contains(en ? 'your choice' : 'sana kalm\u0131\u015f'),
          );
        },
      );
    }

    testWidgets('third stage is free, not a pawn-advance lesson $language', (
      tester,
    ) async {
      final progress = BattlePracticeProgress(2, onboarding: true);
      final first = DeckManager.newBattle(
        white: progress.deck,
      ).view(PieceColor.white);
      expectFreeChess(progress, first);
      final opening = await coach(tester, language, progress, first);
      expect(opening.heading, contains(en ? 'FREE PLAY' : 'SERBEST'));
      expect(
        opening.text,
        contains(
          en
              ? 'Turn one is chess only'
              : '\u0130lk tur sadece ta\u015f hamlesi',
        ),
      );
      final view = battleFixture(
        hand: [CardId.shelter, CardId.radar],
      ).view(PieceColor.white);
      final legal = BattleRulesCore.legalActions(view);
      expect(
        progress.lessonActions(view, legal).map((a) => a.key),
        legal.map((a) => a.key),
      );
      final free = await coach(tester, language, progress, view);
      expect(
        free.text,
        contains(
          en ? 'any legal card' : '\u0130stedi\u011fin yasal kart\u0131',
        ),
      );
      expect(
        free.text,
        contains(en ? 'without using a card' : 'kart kullanmadan'),
      );
      expect(
        free.text,
        isNot(
          contains(
            en ? 'For this lesson' : 'Bu e\u011fitim ad\u0131m\u0131nda',
          ),
        ),
      );
      expect(practiceFocus(progress, view, null, false), BattleCoachFocus.none);
    });

    for (final completed in [false, true]) {
      testWidgets(
        'free selected-card feedback survives completion=$completed $language',
        (tester) async {
          final progress = BattlePracticeProgress(2, onboarding: true)
            ..moves = completed ? 4 : 0;
          final view = battleFixture(
            hand: [CardId.shelter],
          ).view(PieceColor.white);
          final instruction =
              en
                  ? 'Shelter is ready. Confirm the selected target.'
                  : 'Siper haz\u0131r. Se\u00e7ilen hedefi onayla.';
          final selected = await coach(
            tester,
            language,
            progress,
            view,
            selected: CardId.shelter,
            targetReady: true,
            freeInstruction: instruction,
          );
          expect(selected.text, instruction);
          final invalid = await coach(
            tester,
            language,
            progress,
            view,
            selected: CardId.shelter,
            invalidTarget: true,
            freeInstruction: instruction,
          );
          expect(invalid.feedback, true);
          expect(invalid.text, contains(en ? 'not valid' : 'uygun de\u011fil'));
          expect(invalid.text, contains(en ? 'legal target' : 'yasal hedef'));
          expect(invalid.text, isNot(instruction));
          if (completed) {
            final idle = await coach(tester, language, progress, view);
            expect(
              idle.text,
              contains(en ? 'Keep practising' : 'denemeye devam et'),
            );
            expect(
              idle.text,
              isNot(
                contains(
                  en ? 'You played a card' : 'Kart\u0131 kulland\u0131n',
                ),
              ),
            );
            expect(
              progress.cast || progress.discarded || progress.stopsPlay,
              false,
            );
          }
        },
      );

      for (final card in [CardId.prophecy, CardId.fateExchange]) {
        testWidgets(
          'pending ${card.wire} outranks free feedback, completed=$completed $language',
          (tester) async {
            final progress = BattlePracticeProgress(2, onboarding: true)
              ..moves = completed ? 4 : 0;
            var state = battleFixture(hand: [card, CardId.shelter]);
            var view = state.view(PieceColor.white);
            final play = BattleRulesCore.legalActions(
              view,
            ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
            state = DeckManager.apply(state, play);
            view = state.view(PieceColor.white);
            expect(view.rules.pending?.card, card);
            final legal = BattleRulesCore.legalActions(view);
            expect(legal.whereType<ResolveAction>(), isNotEmpty);
            expect(legal.whereType<ChessMoveAction>(), isEmpty);
            expect(
              progress.lessonActions(view, legal).map((a) => a.key),
              legal.map((a) => a.key),
            );
            final pending = await coach(
              tester,
              language,
              progress,
              view,
              selected: card,
              invalidTarget: true,
              freeInstruction:
                  en
                      ? 'Move a piece now.'
                      : '\u015eimdi ta\u015f\u0131n\u0131 oynat.',
            );
            expect(pending.text, contains(en ? 'confirm' : 'onayla'));
            expect(
              pending.text,
              contains(en ? 'Then move' : 'Sonra ta\u015f\u0131n\u0131'),
            );
            if (card == CardId.fateExchange) {
              expect(
                pending.text,
                contains(en ? 'Take 1 card' : '1 kart se\u00e7'),
              );
            } else {
              expect(
                pending.text,
                contains(
                  en
                      ? 'upcoming card order'
                      : 'kartlar\u0131n s\u0131ras\u0131n\u0131',
                ),
              );
            }
            expect(
              pending.text,
              isNot(contains(en ? 'Keep practising' : 'denemeye devam et')),
            );
          },
        );
      }
    }
  }

  test(
    'completed free practice still focuses controls for a pending decision',
    () {
      final progress = BattlePracticeProgress(2, onboarding: true)..moves = 4;
      var state = battleFixture(hand: [CardId.prophecy]);
      final play = BattleRulesCore.legalActions(state.view(PieceColor.white))
          .whereType<PlayCardAction>()
          .firstWhere((a) => a.card == CardId.prophecy);
      state = DeckManager.apply(state, play);
      final view = state.view(PieceColor.white);
      expect(progress.complete, true);
      expect(progress.stopsPlay, false);
      expect(view.rules.pending, isNotNull);
      expect(
        practiceFocus(progress, view, null, false),
        BattleCoachFocus.controls,
        reason:
            'Free-play completion must not hide an unresolved card decision.',
      );
    },
  );
}
