import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'helpers/v222_card_scenarios.dart';
import 'helpers/v223_slow_cases.dart';

Widget app(Widget child, String language) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('tr'), Locale('en')],
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  for (final side in PieceColor.values) {
    for (final language in ['tr', 'en']) {
      testWidgets(
        '${side.name}/$language: exact frames announce latest cast, never side order',
        (tester) async {
          final pair = slowPairedCasts(side);
          final tracker =
              BattlePresentationTracker()..observe(pair.before.view(side), 0);
          Widget notice(AuthoritativeBattleState state) => app(
            BattleCastNotice(
              view: state.view(side),
              acceptedFrames: tracker.frames,
              child: const Text('next-action'),
            ),
            language,
          );
          await tester.pumpWidget(notice(pair.before));
          final states = [pair.cast, pair.moved, pair.response, pair.after];
          for (var i = 0; i < states.length; i++) {
            tracker.observe(states[i].view(side), i + 1);
          }
          await tester.pumpWidget(notice(pair.after));
          await tester.pump(const Duration(milliseconds: 450));
          expect(
            find.byKey(const ValueKey('cast-notice-purify')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('cast-notice-slow')), findsNothing);
          expect(find.textContaining('1 mana'), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 2200));
          await tester.pumpWidget(notice(pair.after));
          await tester.pump(const Duration(milliseconds: 1500));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('cast-notice-purify')),
            findsNothing,
            reason: 'A duplicate projection cannot restart a notice timer.',
          );
          expect(find.text('next-action'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '${side.name}/$language: a version gap clears stale card notice',
        (tester) async {
          final pair = slowPairedCasts(side);
          final tracker =
              BattlePresentationTracker()..observe(pair.before.view(side), 0);
          Widget notice(AuthoritativeBattleState state) => app(
            BattleCastNotice(
              view: state.view(side),
              acceptedFrames: tracker.frames,
              child: const Text('synchronized-action'),
            ),
            language,
          );
          await tester.pumpWidget(notice(pair.before));
          tracker.observe(pair.cast.view(side), 1);
          await tester.pumpWidget(notice(pair.cast));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('cast-notice-slow')),
            findsOneWidget,
          );
          tracker.observe(pair.after.view(side), 8);
          await tester.pumpWidget(notice(pair.after));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('cast-notice-slow')), findsNothing);
          expect(
            find.byKey(const ValueKey('cast-notice-purify')),
            findsNothing,
          );
          expect(find.text('synchronized-action'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '${side.name}/$language: completed movement is historical, not a new move instruction',
        (tester) async {
          final initial = cardScenario(CardId.pawnDeviation, side);
          final play = BattleRulesCore.legalActions(initial.view(side))
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == CardId.pawnDeviation);
          final cast = DeckManager.apply(initial, play);
          final after = DeckManager.apply(
            cast,
            BattleRulesCore.legalActions(
              cast.view(side),
            ).whereType<ChessMoveAction>().first,
          );
          final tracker =
              BattlePresentationTracker()..observe(initial.view(side), 0);
          Widget notice(AuthoritativeBattleState state) => app(
            BattleCastNotice(
              view: state.view(side),
              acceptedFrames: tracker.frames,
              child: const Text('next-action'),
            ),
            language,
          );
          await tester.pumpWidget(notice(initial));
          tracker.observe(cast.view(side), 1);
          tracker.observe(after.view(side), 2);
          await tester.pumpWidget(notice(after));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('cast-notice-pawn_deviation')),
            findsOneWidget,
          );
          expect(
            find.text(
              language == 'tr'
                  ? 'Kartın özel taş hamlesi tamamlandı.'
                  : "The card's special chess move is complete.",
            ),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '${side.name}/$language: opponent discard never claims your hand freed a slot',
        (tester) async {
          final initial = cardScenario(CardId.radar, side.opposite);
          final after = DeckManager.apply(
            initial,
            const DiscardAction(CardId.radar),
          );
          Widget notice(AuthoritativeBattleState state) => app(
            BattleCastNotice(
              view: state.view(side),
              child: const Text('next-action'),
            ),
            language,
          );
          await tester.pumpWidget(notice(initial));
          await tester.pumpWidget(notice(after));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.text(
              language == 'tr'
                  ? 'Rakibin elinde bir kartlık yer açıldı.'
                  : "One slot in the opponent's hand was freed.",
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              language == 'tr'
                  ? 'Elinde bir kartlık yer açıldı.'
                  : 'One hand slot was freed.',
            ),
            findsNothing,
          );
          expect(initial.hidden.hands[side], after.hidden.hands[side]);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
