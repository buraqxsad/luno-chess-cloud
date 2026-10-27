import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'helpers/v222_card_scenarios.dart';

const expected = {
  CardId.radar: [
    'Rakip bir kartını sorguladı. Sonuç yalnızca ona gösterilir.',
    'The opponent checked one of your cards. Only they see the result.',
  ],
  CardId.prophecy: [
    'Rakip kendi destesindeki sırayı seçiyor. Kartları sana gizli.',
    'The opponent is ordering their own deck. Those cards stay hidden from you.',
  ],
  CardId.fateExchange: [
    'Rakip bir kart feda etti; kendi destesinden bir kart seçiyor. Seçimi sana gizli.',
    'The opponent sacrificed a card and is choosing one from their own deck. Their choice stays hidden from you.',
  ],
};

void main() {
  for (final language in ['tr', 'en']) {
    for (final card in expected.keys) {
      testWidgets('$language/${card.wire}: notice identifies private owner', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var state = cardScenario(card, PieceColor.black);
        Widget notice(AuthoritativeBattleState data) => MaterialApp(
          locale: Locale(language),
          supportedLocales: LunoLocalizations.supportedLocales,
          localizationsDelegates: const [
            LunoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: BattleCastNotice(
                  view: data.view(PieceColor.white),
                  child: const Text('Idle'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(notice(state));
        final action = BattleRulesCore.legalActions(
          state.view(PieceColor.black),
        ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
        state = DeckManager.apply(state, action);
        await tester.pumpWidget(notice(state));
        await tester.pump(const Duration(milliseconds: 420));
        expect(
          find.text(expected[card]![language == 'en' ? 1 : 0]),
          findsOneWidget,
        );
        expect(state.view(PieceColor.white).knowledge.pendingCards, isEmpty);
        if (card != CardId.radar) {
          final resolve =
              BattleRulesCore.legalActions(
                state.view(PieceColor.black),
              ).whereType<ResolveAction>().first;
          state = DeckManager.apply(state, resolve);
          await tester.pumpWidget(notice(state));
          await tester.pump();
          expect(
            find.text(expected[card]![language == 'en' ? 1 : 0]),
            findsNothing,
          );
          expect(
            find.text(
              language == 'en'
                  ? 'The opponent\'s private card choice is complete. Their choice stays hidden from you.'
                  : 'Rakibin özel kart seçimi tamamlandı. Seçim sana gizli.',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
