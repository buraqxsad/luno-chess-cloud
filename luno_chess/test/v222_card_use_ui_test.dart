import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'helpers/battle_v1_response.dart';
import 'helpers/v222_card_scenarios.dart';

Future<void> touch(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(
    finder,
    findsOneWidget,
    reason: 'Real visible control $key must exist.',
  );
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final card in CardId.values) {
    testWidgets(
      '${card.wire}: actual hand, target and confirmation controls submit once',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var state = cardScenario(card, PieceColor.white);
        var version = 0;
        final sent = <BattleAction>[];
        final expected = BattleRulesCore.legalActions(
          state.view(PieceColor.white),
        ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: v1Response(state: state, version: version),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              final action = BattleAction.fromJson(body['intent'] as Map);
              sent.add(action);
              state = DeckManager.apply(state, action);
              version++;
            }
            return v1Response(state: state, version: version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('tr'),
            supportedLocales: LunoLocalizations.supportedLocales,
            localizationsDelegates: const [
              LunoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: BattleV1Screen(controllerOverride: controller),
          ),
        );
        await tester.pumpAndSettle();
        await touch(tester, 'hand-${card.wire}');
        if (expected.target is int) {
          await touch(tester, 'square-${expected.target}');
          if (movementCards.contains(card)) {
            final special =
                BattleRulesCore.specialMoves(
                  state.rules,
                  card,
                  expected.target as int,
                  PieceColor.white,
                ).first;
            await touch(tester, 'square-${special.to}');
          }
        } else if (cardDefinitions[card]!.target ==
            CardTargetType.opponentCard) {
          await touch(tester, 'arsenal-${expected.target}');
        } else if (expected.sacrifice != null) {
          await touch(tester, expected.key);
        } else if (expected.target is String) {
          final square = card == CardId.purify ? 9 : 28;
          await touch(tester, 'square-$square');
        }
        expect(
          sent,
          isEmpty,
          reason: 'Selecting a card/target must not silently cast.',
        );
        await touch(tester, 'play-card');
        expect(sent.whereType<PlayCardAction>().map((a) => a.key), [
          expected.key,
        ]);
        expect(state.rules.used[PieceColor.white], [card]);
        if (card == CardId.prophecy || card == CardId.fateExchange) {
          await touch(tester, 'open-private');
          if (card == CardId.fateExchange) {
            await touch(
              tester,
              'private-${state.hidden.knowledge[PieceColor.white]!.pendingCards.first.wire}',
            );
          }
          await touch(tester, 'confirm-private');
          expect(sent.whereType<ResolveAction>(), hasLength(1));
          expect(state.rules.phase, BattlePhase.chess);
        }
        if (card == CardId.radar) {
          expect(
            find.byKey(const ValueKey('battle-radar-result')),
            findsOneWidget,
          );
        }
        if (!movementCards.contains(card)) {
          expect(state.rules.phase, BattlePhase.chess);
          final move = BattleRulesCore.legalActions(
            state.view(PieceColor.white),
          ).whereType<ChessMoveAction>().firstWhere((a) => a.uci.length == 4);
          await touch(tester, 'square-${squareOf(move.uci, 0)}');
          await touch(tester, 'square-${squareOf(move.uci, 2)}');
        }
        expect(sent.whereType<ChessMoveAction>(), hasLength(1));
        expect(state.rules.board.turn, PieceColor.black);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
    testWidgets('${card.wire}: discarding preserves the chess move', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = cardScenario(card, PieceColor.white, mana: 3);
      var version = 0;
      final sent = <BattleAction>[];
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(state: state, version: version),
        persistPending: (_) async {},
        request: (path, body) async {
          if (path == '/submitBattleV1Action') {
            final action = BattleAction.fromJson(body['intent'] as Map);
            sent.add(action);
            state = DeckManager.apply(state, action);
            version++;
          }
          return v1Response(state: state, version: version);
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: LunoLocalizations.supportedLocales,
          localizationsDelegates: const [
            LunoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: BattleV1Screen(controllerOverride: controller),
        ),
      );
      await tester.pumpAndSettle();
      await touch(tester, 'hand-${card.wire}');
      expect(sent, isEmpty);
      final close = find.byTooltip('Kapat');
      if (close.evaluate().isNotEmpty) {
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
      }
      await touch(tester, 'discard-card');
      expect(sent.map((a) => a.key), ['discard:${card.wire}']);
      expect(state.rules.phase, BattlePhase.chess);
      expect(state.rules.board.turn, PieceColor.white);
      expect(state.rules.mana[PieceColor.white], 3);
      final move = BattleRulesCore.legalActions(
        state.view(PieceColor.white),
      ).whereType<ChessMoveAction>().firstWhere((a) => a.uci.length == 4);
      await touch(tester, 'square-${squareOf(move.uci, 0)}');
      await touch(tester, 'square-${squareOf(move.uci, 2)}');
      expect(sent.whereType<ChessMoveAction>(), hasLength(1));
      expect(state.rules.board.turn, PieceColor.black);
      expect(state.rules.used[PieceColor.white], isEmpty);
      expect(state.rules.discarded[PieceColor.white], [card]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

int squareOf(String uci, int offset) =>
    uci.codeUnitAt(offset) - 97 + (uci.codeUnitAt(offset + 1) - 49) * 8;
