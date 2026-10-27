import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_mine_cases.dart';

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor viewer,
  int version,
) {
  final response = v1Response(state: state, side: viewer, version: version);
  final public = response['view']['public'] as Map;
  public['players'] = {
    sideWire(viewer): {'uid': 'self', 'name': 'Self', 'bot': false},
    sideWire(viewer.opposite): {'uid': 'other', 'name': 'Other', 'bot': false},
  };
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  return response;
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  if (settle) await tester.pumpAndSettle();
}

void main() {
  final oracles =
      jsonDecode(File('qa/v223/mine/oracles.json').readAsStringSync()) as List;
  for (final auditCase in [
    ...mineOracleCases(oracles),
    ...mineCoreCases(),
    ...mineBoundaryCases(),
  ]) {
    test('MINE core: ${auditCase.name}', auditCase.run);
  }

  for (final reflect in [false, true]) {
    final side = reflect ? mineBlack : mineWhite;
    final prefix = sideWire(side);
    int sq(String value) => mineSquare(value) ^ (reflect ? 56 : 0);
    String uci(String value) => reflect ? mineReflectMove(value) : value;

    test(
      '$prefix Mine delayed acceptance blocks an overlapping chess submission',
      () async {
        final initial = minePosition(
          mineCaptureFen,
          reflect: reflect,
          phase: BattlePhase.card,
        );
        final play = PlayCardAction(CardId.mine, target: sq('e4'));
        final accepted = DeckManager.apply(initial, play);
        final gate = Completer<Map<String, dynamic>>();
        final sent = <Map<String, dynamic>>[];
        final persisted = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(initial, side, 0),
          persistPending: (value) async => persisted.add(value),
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            sent.add(Map<String, dynamic>.from(body));
            return gate.future;
          },
        );
        addTearDown(controller.dispose);
        final pending = controller.submit(play);
        await Future<void>.delayed(Duration.zero);
        expect(controller.busy, isTrue);
        expect(
          controller.view!.rules.boardEffects,
          isEmpty,
          reason: 'no optimistic trap before authority acceptance',
        );
        expect(await controller.submit(ChessMoveAction(uci('e2e4'))), isFalse);
        expect(await controller.submit(play), isFalse);
        expect(sent, hasLength(1));
        gate.complete(_response(accepted, side, 1));
        expect(await pending, isTrue);
        expect(controller.view!.rules.boardEffects, hasLength(1));
        expect(controller.view!.rules.pieceEffects, isEmpty);
        expect(controller.view!.rules.mana[side], 4);
        expect(controller.view!.rules.ply, 0);
        expect(controller.view!.rules.phase, BattlePhase.chess);
        expect(controller.hasPendingIntent, isFalse);
        expect(persisted.whereType<String>(), hasLength(1));
      },
    );

    test(
      '$prefix Mine lost response retries identical intent without a second trap/debit',
      () async {
        var state = minePosition(
          mineCaptureFen,
          reflect: reflect,
          phase: BattlePhase.card,
        );
        final bodies = <String>[];
        var serverCommits = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, 0),
          persistPending: (_) async {},
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            bodies.add(jsonEncode(body));
            if (serverCommits == 0) {
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              serverCommits++;
              throw StateError('simulated-response-loss-after-commit');
            }
            expect(
              bodies.last,
              bodies.first,
              reason: 'same anchored action ID and intent',
            );
            return _response(state, side, 1);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            PlayCardAction(CardId.mine, target: sq('e4')),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.error, isNotNull);
        expect(controller.view!.rules.boardEffects, isEmpty);
        await controller.retryPending();
        expect(bodies, hasLength(2));
        expect(serverCommits, 1);
        expect(controller.error, isNull);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.view!.rules.boardEffects, hasLength(1));
        expect(controller.view!.rules.effectSequence, 1);
        expect(controller.view!.rules.mana[side], 4);
        expect(controller.view!.rules.used[side], [CardId.mine]);
        expect(controller.view!.ownHand, hasLength(2));
      },
    );

    test(
      '$prefix Mine stale-state rejection is atomic and remains retryable after refresh',
      () async {
        final initial = minePosition(
          mineCaptureFen,
          reflect: reflect,
          phase: BattlePhase.card,
        );
        var fail = true, version = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(initial, side, 0),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/getBattleV1') {
              return _response(initial, side, version);
            }
            if (fail) throw const BattleV1Rejection('STALE_STATE');
            final next = DeckManager.apply(
              initial,
              BattleAction.fromJson(body['intent'] as Map),
            );
            return _response(next, side, ++version);
          },
        );
        addTearDown(controller.dispose);
        final play = PlayCardAction(CardId.mine, target: sq('e4'));
        expect(await controller.submit(play), isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.view!.rules.toJson(), initial.rules.toJson());
        fail = false;
        await controller.reconnect();
        expect(await controller.submit(play), isTrue);
        expect(controller.view!.rules.boardEffects, hasLength(1));
        expect(controller.view!.rules.mana[side], 4);
      },
    );

    testWidgets(
      '$prefix Mine card and board taps in one UI frame cannot skip or double a move',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var state = minePosition(
          mineCaptureFen,
          reflect: reflect,
          phase: BattlePhase.card,
        );
        var version = 0;
        final sent = <BattleAction>[];
        final gate = Completer<Map<String, dynamic>>();
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path != '/submitBattleV1Action') {
              return _response(state, side, version);
            }
            final action = BattleAction.fromJson(body['intent'] as Map);
            sent.add(action);
            state = DeckManager.apply(state, action);
            version++;
            if (action is PlayCardAction) return gate.future;
            return _response(state, side, version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller)),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'hand-mine');
        await _tap(tester, 'square-${sq('e4')}');
        expect(sent, isEmpty, reason: 'selection is not a cast');
        await _tap(tester, 'play-card', settle: false);
        // No pump between confirmation and these board taps: one rendered frame.
        await _tap(tester, 'square-${sq('e2')}', settle: false);
        await _tap(tester, 'square-${sq('e4')}', settle: false);
        await tester.pump();
        expect(sent.map((action) => action.key), ['play:mine:${sq('e4')}:']);
        expect(state.rules.ply, 0);
        gate.complete(_response(state, side, version));
        await tester.pumpAndSettle();
        expect(state.rules.phase, BattlePhase.chess);
        await _tap(tester, 'square-${sq('e2')}');
        await _tap(tester, 'square-${sq('e4')}');
        expect(sent.map((action) => action.key), [
          'play:mine:${sq('e4')}:',
          'move:${uci('e2e4')}',
        ]);
        expect(state.rules.ply, 1);
        expect(state.rules.board.turn, side.opposite);
        expect(
          state.rules.boardEffects,
          hasLength(1),
          reason: 'friendly arrival does not trigger',
        );
        expect(state.rules.pieceEffects, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
