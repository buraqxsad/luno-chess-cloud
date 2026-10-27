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
  final control = find.byKey(ValueKey(key));
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  expect(
    control.hitTestable(),
    findsOneWidget,
    reason: '$key must be a real visible control',
  );
  await tester.tap(control);
  await tester.pumpAndSettle();
}

int square(String uci, int offset) =>
    uci.codeUnitAt(offset) - 97 + (uci.codeUnitAt(offset + 1) - 49) * 8;

void main() {
  for (final language in ['tr', 'en']) {
    for (final card in CardId.values) {
      for (final discard in [false, true]) {
        testWidgets(
          '${card.wire}/black/$language: ${discard ? 'discard' : 'cast'} through actual battle controls preserves chess flow',
          (tester) async {
            tester.view.physicalSize =
                language == 'tr' ? const Size(320, 568) : const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            const side = PieceColor.black;
            var state = cardScenario(card, side);
            var version = 0;
            final sent = <BattleAction>[];
            final expected = BattleRulesCore.legalActions(state.view(side))
                .whereType<PlayCardAction>()
                .firstWhere((action) => action.card == card);
            final controller = BattleV1Controller(
              uid: 'other',
              matchId: v1MatchId,
              initialResponse: v1Response(
                state: state,
                side: side,
                version: version,
              ),
              persistPending: (_) async {},
              request: (path, body) async {
                if (path == '/submitBattleV1Action') {
                  final action = BattleAction.fromJson(body['intent'] as Map);
                  sent.add(action);
                  state = DeckManager.apply(state, action);
                  version++;
                }
                return v1Response(state: state, side: side, version: version);
              },
            );
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                supportedLocales: LunoLocalizations.supportedLocales,
                localizationsDelegates: const [
                  LunoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          language == 'tr' ? 1.5 : 1,
                        ),
                      ),
                      child: child!,
                    ),
                home: BattleV1Screen(controllerOverride: controller),
              ),
            );
            await tester.pumpAndSettle();
            await touch(tester, 'hand-${card.wire}');
            if (discard) {
              final close = find.byTooltip(
                language == 'tr' ? 'Kapat' : 'Close',
              );
              if (close.evaluate().isNotEmpty) {
                await tester.tap(close);
                await tester.pumpAndSettle();
              }
              await touch(tester, 'discard-card');
              expect(sent.map((action) => action.key), [
                'discard:${card.wire}',
              ]);
              expect(state.rules.mana[side], 6);
            } else {
              if (expected.target is int) {
                await touch(tester, 'square-${expected.target}');
                if (movementCards.contains(card)) {
                  final move =
                      BattleRulesCore.specialMoves(
                        state.rules,
                        card,
                        expected.target as int,
                        side,
                      ).first;
                  await touch(tester, 'square-${move.to}');
                }
              } else if (cardDefinitions[card]!.target ==
                  CardTargetType.opponentCard) {
                await touch(tester, 'arsenal-${expected.target}');
              } else if (expected.sacrifice != null) {
                await touch(tester, expected.key);
              } else if (expected.target is String) {
                await touch(
                  tester,
                  'square-${card == CardId.purify ? 54 : 35}',
                );
              }
              expect(
                sent,
                isEmpty,
                reason: 'Selecting does not silently submit a card.',
              );
              await touch(tester, 'play-card');
              expect(
                sent.whereType<PlayCardAction>().map((action) => action.key),
                [expected.key],
              );
              expect(state.rules.used[side], [card]);
              if (state.rules.pending != null) {
                final instruction =
                    card == CardId.fateExchange
                        ? language == 'tr'
                            ? 'Destenden 1 kart seç'
                            : 'Take 1 card from your deck'
                        : language == 'tr'
                        ? 'Destendeki kartların sırasını seç'
                        : 'Choose and confirm your upcoming card order';
                expect(find.textContaining(instruction), findsWidgets);
                await touch(tester, 'open-private');
                if (card == CardId.fateExchange) {
                  await touch(
                    tester,
                    'private-${state.hidden.knowledge[side]!.pendingCards.first.wire}',
                  );
                }
                await touch(tester, 'confirm-private');
                expect(sent.whereType<ResolveAction>(), hasLength(1));
              }
            }
            if (discard || !movementCards.contains(card)) {
              expect(state.rules.phase, BattlePhase.chess);
              final move = BattleRulesCore.legalActions(state.view(side))
                  .whereType<ChessMoveAction>()
                  .firstWhere((action) => action.uci.length == 4);
              await touch(tester, 'square-${square(move.uci, 0)}');
              await touch(tester, 'square-${square(move.uci, 2)}');
            }
            expect(sent.whereType<ChessMoveAction>(), hasLength(1));
            expect(state.rules.board.turn, PieceColor.white);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
      }
    }
  }
}
