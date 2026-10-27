import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import '../qa/v223/prophecy/independent_checks.dart';
import 'helpers/battle_v1_response.dart';
import 'helpers/v223_prophecy_cases.dart';

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor side,
  int version,
) {
  final response = v1Response(state: state, side: side, version: version);
  final public = response['view']['public'] as Map;
  final players = public['players'] as Map;
  (players['w'] as Map)['uid'] = side.isWhite ? 'self' : 'other';
  (players['b'] as Map)['uid'] = side.isWhite ? 'other' : 'self';
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  return response;
}

Widget _app(Widget child, String language, {double scale = 1}) => MaterialApp(
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
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
  home: child,
);

Future<void> _tap(WidgetTester tester, Finder control) async {
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(ValueKey(key)));

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final scenario in prophecyIndependentCases()) {
    test('V223 Prophecy ${scenario.name}', scenario.run);
  }
  for (final side in PieceColor.values) {
    test(
      '${side.name}: lost cast response retries the same intent exactly once',
      () async {
        var server = prophecyCase(side: side, position: 'v223-queen-pin');
        var version = 0, casts = 0, resolves = 0;
        final stored = <String?>[];
        String? firstId;
        var loseReply = true;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(server, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              final action = BattleAction.fromJson(body['intent'] as Map);
              if (action is PlayCardAction) {
                if (firstId == null) {
                  firstId = body['actionId'] as String;
                  server = DeckManager.apply(server, action);
                  version++;
                  casts++;
                } else {
                  expect(body['actionId'], firstId);
                }
                if (loseReply) {
                  loseReply = false;
                  throw StateError('lost-reply');
                }
              } else {
                server = DeckManager.apply(server, action);
                version++;
                if (action is ResolveAction) resolves++;
              }
            }
            return _response(server, side, version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(const PlayCardAction(CardId.prophecy)),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(casts, 1);
        await controller.reconnect();
        expect(controller.view!.knowledge.pendingCards, [
          CardId.chain,
          CardId.slow,
        ]);
        await controller.retryPending();
        expect(controller.hasPendingIntent, isFalse);
        expect(casts, 1);
        expect(server.rules.mana[side], 5);
        expect(stored.last, isNull);
        expect(
          await controller.submit(ResolveAction([CardId.slow, CardId.chain])),
          isTrue,
        );
        expect(resolves, 1);
        expect(server.rules.mana[side], 5);
        expect(server.rules.drawCounts[side], 3);
      },
    );
    test(
      '${side.name}: lost resolution reply retries without a second resolution',
      () async {
        var server = prophecyCast(
          prophecyCase(side: side, position: 'v223-pinned-ep'),
        );
        var version = 1, resolves = 0;
        String? firstId;
        var loseReply = true;
        final stored = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(server, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              final action = BattleAction.fromJson(body['intent'] as Map);
              expect(action, isA<ResolveAction>());
              if (firstId == null) {
                firstId = body['actionId'] as String;
                server = DeckManager.apply(server, action);
                resolves++;
                version++;
              } else {
                expect(body['actionId'], firstId);
              }
              if (loseReply) {
                loseReply = false;
                throw StateError('lost-resolution-reply');
              }
            }
            return _response(server, side, version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(ResolveAction([CardId.slow, CardId.chain])),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.busy, isFalse);
        await controller.reconnect();
        expect(controller.view!.rules.phase, BattlePhase.chess);
        await controller.retryPending();
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.busy, isFalse);
        expect(resolves, 1);
        expect(server.rules.mana[side], 5);
        expect(server.rules.drawCounts[side], 3);
        expect(server.rules.used[side], [CardId.prophecy]);
        expect(controller.view!.knowledge.pendingCards, isEmpty);
        expect(controller.view!.knowledge.knownUpcomingCards, [
          CardId.slow,
          CardId.chain,
        ]);
        expect(stored.last, isNull);
      },
    );
    for (final reason in ['timeout', 'resign']) {
      test(
        '${side.name}: $reason result guards an abandoned pending server projection',
        () async {
          final pending = prophecyCast(prophecyCase(side: side));
          final draft =
              RuleDraft(pending.rules)
                ..phase = BattlePhase.terminal
                ..pending = null;
          // Preserve the confirmed server defect to bound its current client impact.
          final terminal = AuthoritativeBattleState(
            draft.freeze(),
            pending.hidden,
          );
          final response = _response(terminal, side, 2);
          response['status'] = 'finished';
          final public = response['view']['public'] as Map;
          public['result'] = {
            'reason': reason,
            'winner': sideWire(side.opposite),
            'finishedAt': 1000,
          };
          public['settlementStatus'] = 'pending';
          var sent = 0;
          final controller = BattleV1Controller(
            uid: 'self',
            matchId: v1MatchId,
            initialResponse: response,
            persistPending: (_) async {},
            request: (_, _) async {
              sent++;
              return response;
            },
          );
          addTearDown(controller.dispose);
          expect(controller.legalActions, isEmpty);
          expect(
            await controller.submit(ResolveAction([CardId.slow, CardId.chain])),
            isFalse,
          );
          expect(sent, 0);
          expect(controller.busy, isFalse);
        },
      );
    }
    for (final language in ['en', 'tr']) {
      for (final count in [1, 2]) {
        testWidgets(
          '${side.name} $language deck=$count: visible private choice confirms an independently chosen order',
          (tester) async {
            _viewport(tester, const Size(390, 844));
            var state = prophecyCase(
              side: side,
              deckCount: count,
              position: 'v223-promotion-escape',
            );
            var version = 0;
            final sent = <BattleAction>[];
            final controller = BattleV1Controller(
              uid: 'self',
              matchId: v1MatchId,
              initialResponse: _response(state, side, version),
              persistPending: (_) async {},
              request: (path, body) async {
                if (path == '/submitBattleV1Action') {
                  final action = BattleAction.fromJson(body['intent'] as Map);
                  sent.add(action);
                  state = DeckManager.apply(state, action);
                  version++;
                }
                return _response(state, side, version);
              },
            );
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              _app(BattleV1Screen(controllerOverride: controller), language),
            );
            await tester.pumpAndSettle();
            await _key(tester, 'hand-prophecy');
            await _key(tester, 'square-${side.isWhite ? 4 : 60}');
            expect(
              sent,
              isEmpty,
              reason: 'Board interaction must not cast or target Prophecy.',
            );
            await _key(tester, 'play-card');
            expect(sent.single, isA<PlayCardAction>());
            expect(state.rules.phase, BattlePhase.pending);
            await _key(tester, 'open-private');
            expect(find.byType(PrivateChoiceSheet), findsOneWidget);
            if (count == 2) {
              final second = find.byKey(const ValueKey('private-slow'));
              await _tap(
                tester,
                find.descendant(
                  of: second,
                  matching: find.byTooltip(
                    language == 'en' ? 'Earlier' : 'Öne al',
                  ),
                ),
              );
            }
            await _key(tester, 'confirm-private');
            final resolution = sent.whereType<ResolveAction>().single;
            expect(resolution.selected, isNull);
            expect(
              resolution.order,
              count == 1 ? [CardId.chain] : [CardId.slow, CardId.chain],
            );
            expect(state.rules.phase, BattlePhase.chess);
            expect(state.rules.mana[side], 5);
            expect(state.rules.drawCounts[side], 3);
            expect(find.byType(PrivateChoiceSheet), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
      }
    }
    testWidgets(
      '${side.name}: pending choice survives dismissal and polling; newer state prevents stale resolution',
      (tester) async {
        _viewport(tester, const Size(390, 844));
        var state = prophecyCast(
          prophecyCase(side: side, position: 'v223-castle-transit'),
        );
        var version = 1;
        final sent = <BattleAction>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              sent.add(BattleAction.fromJson(body['intent'] as Map));
            }
            return _response(state, side, version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller), 'en'),
        );
        await tester.pumpAndSettle();
        await _key(tester, 'open-private');
        await controller.reconnect(synchronization: false);
        await tester.pumpAndSettle();
        expect(find.byType(PrivateChoiceSheet), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PrivateChoiceSheet), findsNothing);
        expect(controller.view!.rules.phase, BattlePhase.pending);
        expect(controller.view!.rules.mana[side], 5);
        expect(controller.view!.rules.used[side], [CardId.prophecy]);
        expect(controller.view!.rules.drawCounts[side], 3);
        expect(sent, isEmpty);
        await _key(tester, 'open-private');
        expect(find.byType(PrivateChoiceSheet), findsOneWidget);
        state = prophecyResolve(state);
        version++;
        await controller.reconnect(synchronization: false);
        await tester.pumpAndSettle();
        expect(find.byType(PrivateChoiceSheet), findsNothing);
        expect(sent, isEmpty);
        expect(controller.view!.rules.phase, BattlePhase.chess);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
