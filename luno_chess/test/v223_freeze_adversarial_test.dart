import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_freeze_cases.dart';

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor viewer,
  int version,
) {
  final result = v1Response(state: state, side: viewer, version: version);
  final public = result['view']['public'] as Map;
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  final terminal = state.rules.terminal;
  if (terminal != null) {
    result['status'] = 'finished';
    public['settlementStatus'] = 'pending';
    public['result'] = {
      'reason': terminal.reason,
      'winner': terminal.winner == null ? null : sideWire(terminal.winner!),
      'finishedAt': 1000,
    };
  }
  return result;
}

String _uid(PieceColor side) => side.isWhite ? 'self' : 'other';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _touch(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget, reason: 'Required mechanic control $key');
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final auditCase in freezeCoreCases()) {
    test('FREEZE core: ${auditCase.name}', auditCase.run);
  }

  for (final reflected in [false, true]) {
    final side = reflected ? PieceColor.black : PieceColor.white;
    final enemy = side.opposite;
    final label = side.name;
    int square(String text) => freezeSquare(text) ^ (reflected ? 56 : 0);
    String move(String text) => reflected ? freezeReflectMove(text) : text;
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.card,
      List<CardId> hand = const [CardId.freeze, CardId.purify, CardId.prophecy],
    }) =>
        freezePosition(fen, reflect: reflected, phase: phase, actorHand: hand);

    test(
      '$label Freeze selection never gives movement to a frozen own piece',
      () {
        final state = freezeOn(
          position('8/7k/8/8/3R4/8/8/K7 w - - 0 83'),
          square('d4'),
        );
        final view = state.view(side);
        final actions = BattleRulesCore.legalActions(view);
        final before = freezeEncoded(state.toJson());
        final selection = BattleInteraction();
        expect(selection.tap(square('d4'), view, actions), isEmpty);
        expect(selection.piece, square('d4'));
        expect(selection.targets(view, actions), isEmpty);
        expect(selection.tap(square('d5'), view, actions), isEmpty);
        expect(selection.invalidTarget, isTrue);
        expect(selection.targets(view, actions), isEmpty);
        selection.tap(square('a1'), view, actions);
        expect(
          selection.targets(view, actions),
          {'b1', 'a2', 'b2'}.map(square).toSet(),
        );
        expect(
          selection
              .tap(square('b1'), view, actions)
              .map((action) => action.key),
          ['move:${move('a1b1')}'],
        );
        expect(
          freezeEncoded(state.toJson()),
          before,
          reason: 'Card-phase move preview cannot thaw the real state',
        );
      },
    );

    test(
      '$label delayed Freeze ACK blocks a second cast and chess submission',
      () async {
        var state = position('6k1/8/8/8/2r1n3/8/8/5K2 w - - 0 85');
        final original = state;
        var version = 10;
        final started = Completer<void>();
        final reply = Completer<Map<String, dynamic>>();
        final sent = <Map<String, dynamic>>[];
        final stored = <String?>[];
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) {
            expect(path, '/submitBattleV1Action');
            sent.add(Map<String, dynamic>.from(body));
            started.complete();
            return reply.future;
          },
        );
        addTearDown(controller.dispose);
        final first = controller.submit(
          PlayCardAction(CardId.freeze, target: square('c4')),
        );
        await started.future;
        expect(controller.busy, isTrue);
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.view!.rules.toJson(), original.rules.toJson());
        expect(
          await controller.submit(
            PlayCardAction(CardId.freeze, target: square('e4')),
          ),
          isFalse,
        );
        expect(await controller.submit(ChessMoveAction(move('f1e1'))), isFalse);
        expect(sent, hasLength(1));
        state = DeckManager.apply(
          state,
          BattleAction.fromJson(sent.single['intent'] as Map),
        );
        reply.complete(_response(state, side, ++version));
        expect(await first, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.view!.rules.mana[side], 2);
        expect(controller.view!.rules.pieceEffects, hasLength(1));
        expect(
          controller.view!.rules.pieceEffects.single.pieceId,
          original.rules.pieceIds[square('c4')],
        );
        expect(stored.whereType<String>(), hasLength(1));
        expect(stored.last, isNull);
        freezeInventory(state);
      },
    );

    test(
      '$label lost Freeze ACK retries the same identity without double cost',
      () async {
        var state = position('6k1/8/8/8/2r1n3/8/8/5K2 w - - 0 87');
        final original = state;
        var version = 20;
        final sent = <Map<String, dynamic>>[];
        final stored = <String?>[];
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (value) async {
            stored.add(value);
          },
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            sent.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
            if (sent.length == 1) {
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              version++;
              throw StateError('Freeze ACK lost after server commit');
            }
            if (sent.length == 2) {
              expect(
                body,
                sent.first,
                reason: 'Retry must reuse ID, version and target',
              );
            } else {
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              version++;
            }
            return _response(state, side, version);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            PlayCardAction(CardId.freeze, target: square('c4')),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.error, isA<StateError>());
        expect(state.rules.mana[side], 2, reason: 'Mock server accepted once');
        expect(
          controller.snapshot!.stateVersion,
          20,
          reason: 'No speculative local acceptance',
        );
        expect(await controller.submit(ChessMoveAction(move('f1e1'))), isFalse);
        await controller.retryPending();
        expect(controller.error, isNull);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.snapshot!.stateVersion, 21);
        expect(state.rules.mana[side], 2);
        expect(state.rules.effectSequence, original.rules.effectSequence + 1);
        expect(state.rules.used[side], [CardId.freeze]);
        expect(stored.whereType<String>(), hasLength(1));
        expect(await controller.submit(ChessMoveAction(move('f1e1'))), isTrue);
        expect(sent, hasLength(3));
        expect(state.rules.board.turn, enemy);
        expect(
          state.rules.pieceEffects,
          hasLength(1),
          reason: 'Caster move after ACK retry does not thaw enemy rook',
        );
        freezeInventory(state);
      },
    );

    test(
      '$label stale Freeze request clears rejection without modifying newer effect',
      () async {
        final original = position('6k1/8/8/8/2r1n3/8/8/5K2 w - - 0 89');
        final newer = DeckManager.apply(
          original,
          PlayCardAction(CardId.freeze, target: square('e4')),
        );
        final before = freezeEncoded(newer.toJson());
        final paths = <String>[];
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(original, side, 30),
          persistPending: (_) async {},
          request: (path, body) async {
            paths.add(path);
            if (path == '/submitBattleV1Action') {
              throw const BattleV1Rejection('STALE_STATE');
            }
            return _response(newer, side, 31);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            PlayCardAction(CardId.freeze, target: square('c4')),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isA<BattleV1Rejection>());
        await controller.reconnect();
        expect(controller.error, isNull);
        expect(controller.snapshot!.stateVersion, 31);
        expect(
          controller.view!.rules.pieceEffects.single.pieceId,
          newer.rules.pieceIds[square('e4')],
        );
        expect(controller.view!.rules.mana[side], 2);
        expect(paths, ['/submitBattleV1Action', '/getBattleV1']);
        expect(freezeEncoded(newer.toJson()), before);
      },
    );

    test(
      '$label Freeze restriction terminal snapshot admits no retry/new action',
      () async {
        final root = position('1k6/pppr4/8/8/8/8/6K1/4R3 w - - 0 91');
        final cast = DeckManager.apply(
          root,
          PlayCardAction(CardId.freeze, target: square('d7')),
        );
        final terminal = DeckManager.apply(cast, ChessMoveAction(move('e1e8')));
        var requests = 0;
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(terminal, side, 42),
          persistPending: (_) async {},
          request: (_, _) async {
            requests++;
            return _response(terminal, side, 42);
          },
        );
        addTearDown(controller.dispose);
        expect(controller.legalActions, isEmpty);
        expect(await controller.submit(const PassAction()), isFalse);
        expect(
          await controller.submit(
            PlayCardAction(CardId.freeze, target: square('d7')),
          ),
          isFalse,
        );
        expect(await controller.submit(ChessMoveAction(move('e8d8'))), isFalse);
        expect(
          requests,
          0,
          reason: 'Terminal must not create futile network work',
        );
        expect(controller.hasPendingIntent, isFalse);
      },
    );

    testWidgets(
      '$label frozen piece is inspectable; another real board move continues',
      (tester) async {
        _phone(tester);
        var state = freezeOn(
          position('8/7k/8/8/3R4/8/8/K7 w - - 0 93'),
          square('d4'),
        );
        var version = 50;
        final sent = <BattleAction>[];
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (_) async {},
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            final action = BattleAction.fromJson(body['intent'] as Map);
            sent.add(action);
            state = DeckManager.apply(state, action);
            return _response(state, side, ++version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller)),
        );
        await tester.pumpAndSettle();
        await _touch(tester, 'square-${square('d4')}');
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).selected,
          square('d4'),
        );
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).targets,
          isEmpty,
        );
        await _touch(tester, 'square-${square('d5')}');
        expect(
          sent,
          isEmpty,
          reason: 'Restricted tap cannot silently pass/cast/move',
        );
        expect(state.rules.pieceEffects, hasLength(1));
        await _touch(tester, 'square-${square('a1')}');
        await _touch(tester, 'square-${square('b1')}');
        expect(sent.map((action) => action.key), [
          'pass',
          'move:${move('a1b1')}',
        ]);
        expect(state.rules.pieceEffects, isEmpty);
        expect(state.rules.board.turn, enemy);
        expect(state.rules.ply, 1);
        freezeInventory(state);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      '$label real Purify instance choice preserves Mine capture restriction',
      (tester) async {
        _phone(tester);
        var state = freezeOn(
          position(
            '7k/8/8/8/3R1p2/8/8/K7 w - - 0 95',
            hand: [CardId.purify, CardId.freeze, CardId.prophecy],
          ),
          square('d4'),
        );
        state = freezeOn(
          state,
          square('d4'),
          type: PieceEffectType.mineDebuff,
          id: 'v223-old-mine',
        );
        var version = 60;
        final sent = <BattleAction>[];
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (_) async {},
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            final action = BattleAction.fromJson(body['intent'] as Map);
            sent.add(action);
            state = DeckManager.apply(state, action);
            return _response(state, side, ++version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller)),
        );
        await tester.pumpAndSettle();
        await _touch(tester, 'hand-purify');
        await _touch(tester, 'square-${square('d4')}');
        await _touch(tester, 'play:purify:v223-freeze:');
        expect(sent, isEmpty, reason: 'Instance choice is not a cast');
        await _touch(tester, 'play-card');
        expect(sent.map((action) => action.key), ['play:purify:v223-freeze:']);
        expect(state.rules.pieceEffects.single.id, 'v223-old-mine');
        await _touch(tester, 'square-${square('d4')}');
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).targets,
          isNot(contains(square('f4'))),
        );
        await _touch(tester, 'square-${square('f4')}');
        expect(sent, hasLength(1), reason: 'Mine capture remains unavailable');
        await _touch(tester, 'square-${square('e4')}');
        expect(sent.map((action) => action.key), [
          'play:purify:v223-freeze:',
          'move:${move('d4e4')}',
        ]);
        expect(
          state.rules.pieceEffects,
          isEmpty,
          reason: 'Moving target consumes old Mine after Freeze was purified',
        );
        freezeInventory(state);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      '$label Freeze plus chess in one UI frame keeps mechanical response',
      (tester) async {
        _phone(tester);
        var state = position('6k1/8/8/8/2r1n3/8/8/5K2 w - - 0 97');
        final initial = state;
        var version = 70;
        final sent = <BattleAction>[];
        final controller = BattleV1Controller(
          uid: _uid(side),
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (_) async {},
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            final action = BattleAction.fromJson(body['intent'] as Map);
            sent.add(action);
            state = DeckManager.apply(state, action);
            return _response(state, side, ++version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller)),
        );
        await tester.pumpAndSettle();
        // No pump between the two accepted actions: this is mechanics, not VFX QA.
        expect(
          await controller.submit(
            PlayCardAction(CardId.freeze, target: square('c4')),
          ),
          isTrue,
        );
        expect(await controller.submit(ChessMoveAction(move('f1e1'))), isTrue);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.fen,
          initial.rules.fen,
          reason: 'No intervening screen build',
        );
        await tester.pump();
        final rendered =
            tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
        expect(rendered.rules.toJson(), state.rules.toJson());
        expect(rendered.rules.mana[side], 2);
        expect(rendered.rules.used[side], [CardId.freeze]);
        expect(rendered.rules.pieceEffects, hasLength(1));
        expect(rendered.rules.pieceEffects.single.responseSide, enemy);
        expect(
          freezeMoves(
            state,
            enemy,
          ).any((uci) => uci.startsWith(move('c4c4').substring(0, 2))),
          isFalse,
        );
        expect(sent.map((action) => action.key), [
          'play:freeze:${square('c4')}:',
          'move:${move('f1e1')}',
        ]);
        expect(state.rules.ply, 1);
        freezeInventory(state);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
