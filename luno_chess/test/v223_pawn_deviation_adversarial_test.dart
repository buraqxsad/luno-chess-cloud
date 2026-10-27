import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_pawn_deviation_cases.dart';

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

class _PawnAuthorityHarness {
  AuthoritativeBattleState state;
  final PieceColor side;
  final requested = <Map<String, dynamic>>[];
  final accepted = <BattleAction>[];
  final persisted = <String?>[];
  final _receipts = <String, String>{};
  int version = 0;
  bool loseCastResponse = false, loseMoveResponse = false;
  Completer<void>? holdCast;
  late final BattleV1Controller controller;

  _PawnAuthorityHarness(this.side, {AuthoritativeBattleState? initial})
    : state = initial ?? pawnFixture(side: side) {
    controller = BattleV1Controller(
      uid: side.isWhite ? 'self' : 'other',
      matchId: v1MatchId,
      initialResponse: response(),
      persistPending: (json) async {
        persisted.add(json);
      },
      request: (path, body) async {
        if (path == '/submitBattleV1Action') {
          requested.add(Map<String, dynamic>.from(body));
          final intent = jsonEncode(body['intent']);
          final id = body['actionId'] as String;
          final prior = _receipts[id];
          if (prior == null) {
            if (body['expectedStateVersion'] != version) {
              throw const BattleV1Rejection('STALE_STATE');
            }
            final action = BattleAction.fromJson(body['intent'] as Map);
            if (action is PlayCardAction && holdCast != null) {
              await holdCast!.future;
            }
            state = DeckManager.apply(state, action);
            accepted.add(action);
            version++;
            _receipts[id] = intent;
            if (action is PlayCardAction && loseCastResponse) {
              loseCastResponse = false;
              throw StateError('simulated-lost-cast-response');
            }
            if (action is ChessMoveAction && loseMoveResponse) {
              loseMoveResponse = false;
              throw StateError('simulated-lost-move-response');
            }
          } else if (prior != intent) {
            throw const BattleV1Rejection('ACTION_ID_CONFLICT');
          }
        }
        return response();
      },
    );
  }

  Map<String, dynamic> response() {
    final result = v1Response(state: state, side: side, version: version);
    final public = (result['view'] as Map)['public'] as Map;
    (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
    if (state.rules.terminal case final terminal?) {
      result['status'] = 'finished';
      public['result'] = {
        'reason': terminal.reason,
        'winner': terminal.winner == null ? null : sideWire(terminal.winner!),
      };
    }
    return result;
  }
}

Future<void> _mount(WidgetTester tester, _PawnAuthorityHarness harness) async {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(harness.controller.dispose);
  await tester.pumpWidget(
    _app(
      BattleV1Screen(
        controllerOverride: harness.controller,
        clockOverride: (_) => 300000,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Widget _feedback(
  PlayerView view,
  List<BattleAcceptedFrame> frames, {
  int epoch = 0,
  bool reduced = false,
}) => _app(
  Scaffold(
    body: Center(
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: SizedBox.square(
          dimension: 320,
          child: BattleAcceptedFeedback(
            view: view,
            acceptedFrames: frames,
            synchronizationEpoch: epoch,
            showAnnouncements: false,
          ),
        ),
      ),
    ),
  ),
);

BattleSpellPainter _pawnPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('spell-pawn_deviation-0')),
            )
            .painter!
        as BattleSpellPainter;

void main() {
  for (final entry in pawnDeviationCases()) {
    test('pawn_deviation authority ${entry.name}', entry.run);
  }

  for (final side in PieceColor.values) {
    group('pawn_deviation ${side.name} interaction and projection', () {
      test('selection needs both source pawn and independent destination', () {
        final view = pawnFixture(side: side).view(side);
        final actions = BattleRulesCore.legalActions(view);
        final ui = BattleInteraction()..synchronize(view, 0);
        ui.select(CardId.pawnDeviation, actions);
        expect(ui.targets(view, actions), {
          pawnSquare(side, 27),
          pawnSquare(side, 28),
        });
        ui.tap(pawnSquare(side, 27), view, actions);
        expect(ui.play?.target, pawnSquare(side, 27));
        expect(ui.specialDestination, isNull);
        expect(ui.targets(view, actions), {
          pawnSquare(side, 34),
          pawnSquare(side, 36),
        });
        ui.tap(pawnSquare(side, 34), view, actions);
        expect(ui.specialDestination?.uci, pawnUci(side, 'd4c5'));
        expect(ui.preview(), {pawnSquare(side, 27), pawnSquare(side, 34)});
      });

      test(
        'invalid destination clears only old destination; reselection clears it too',
        () {
          final view = pawnFixture(side: side).view(side);
          final actions = BattleRulesCore.legalActions(view);
          final ui = BattleInteraction()..select(CardId.pawnDeviation, actions);
          ui.tap(pawnSquare(side, 27), view, actions);
          ui.tap(pawnSquare(side, 34), view, actions);
          ui.tap(pawnSquare(side, 4), view, actions);
          expect(ui.specialDestination, isNull);
          expect(ui.play?.target, pawnSquare(side, 27));
          expect(ui.piece, pawnSquare(side, 27));
          expect(ui.invalidTarget, true);
          expect(ui.preview(), {pawnSquare(side, 27)});
          ui.tap(pawnSquare(side, 36), view, actions);
          expect(ui.specialDestination?.uci, pawnUci(side, 'd4e5'));
          ui.tap(pawnSquare(side, 28), view, actions);
          expect(ui.specialDestination, isNull);
          expect(ui.play?.target, pawnSquare(side, 28));
          ui.tap(pawnSquare(side, 35), view, actions);
          expect(ui.specialDestination?.uci, pawnUci(side, 'e4d5'));
        },
      );

      test(
        'same version retains selection; accepted cast binds and clears preview',
        () {
          final state = pawnFixture(side: side), view = state.view(side);
          final actions = BattleRulesCore.legalActions(view);
          final ui = BattleInteraction()..synchronize(view, 10);
          ui.select(CardId.pawnDeviation, actions);
          ui.tap(pawnSquare(side, 27), view, actions);
          ui.tap(pawnSquare(side, 34), view, actions);
          ui.synchronize(state.view(side), 10);
          expect(ui.specialDestination?.uci, pawnUci(side, 'd4c5'));
          final cast = pawnCast(state).view(side);
          ui.synchronize(cast, 11);
          expect(ui.card, isNull);
          expect(ui.play, isNull);
          expect(ui.specialDestination, isNull);
          expect(ui.piece, pawnSquare(side, 27));
          final boundActions = BattleRulesCore.legalActions(cast);
          ui.tap(pawnSquare(side, 4), cast, boundActions);
          expect(ui.piece, pawnSquare(side, 27));
          expect(
            ui.tap(pawnSquare(side, 34), cast, boundActions).single.key,
            'move:${pawnUci(side, 'd4c5')}',
          );
        },
      );

      test(
        'unaffordable card remains discardable but has no legal target preview',
        () {
          final view = pawnFixture(side: side, mana: 1).view(side);
          final actions = BattleRulesCore.legalActions(view);
          final ui = BattleInteraction()..select(CardId.pawnDeviation, actions);
          expect(ui.card, CardId.pawnDeviation);
          expect(ui.targets(view, actions), isEmpty);
          ui.tap(pawnSquare(side, 27), view, actions);
          expect(ui.play, isNull);
          expect(ui.specialDestination, isNull);
          expect(ui.moves(view, actions), isEmpty);
        },
      );

      test('pending private resolution cannot produce movement taps', () {
        final state = DeckManager.apply(
          pawnFixture(side: side),
          const PlayCardAction(CardId.prophecy),
        );
        final view = state.view(side), ui = BattleInteraction();
        ui.synchronize(view, 1);
        expect(
          ui.tap(
            pawnSquare(side, 27),
            view,
            BattleRulesCore.legalActions(view),
          ),
          isEmpty,
        );
        expect(ui.piece, isNull);
        expect(ui.targets(view, BattleRulesCore.legalActions(view)), isEmpty);
      });

      test(
        'accepted frame cue follows pawn identity across combined builds',
        () {
          final state = pawnFixture(side: side);
          final cast = pawnCast(state), moved = pawnMove(cast, 'd4c5');
          final tracker =
              BattlePresentationTracker()
                ..observe(state.view(side), 0)
                ..observe(cast.view(side), 1)
                ..observe(moved.view(side), 2);
          expect(tracker.frames, hasLength(2));
          final frame = tracker.frames.first;
          final cue = BattleSpellCue.fromViews(
            CardId.pawnDeviation,
            side,
            frame.before,
            frame.after,
          );
          expect(cue.squares, [pawnSquare(side, 27)]);
          expect(cue.boundPieceIds, [
            state.rules.pieceIds[pawnSquare(side, 27)],
          ]);
          expect(cue.following(moved.rules).squares, [pawnSquare(side, 34)]);
          expect(
            acceptedBattleCasts(
              state.view(side.opposite),
              cast.view(side.opposite),
            ).map((c) => '${c.card.wire}:${c.side.name}'),
            ['pawn_deviation:${side.name}'],
          );
          expect(
            acceptedBattleCards(cast.view(side), moved.view(side)),
            isEmpty,
          );
          expect(
            frame.after.rules.pieceIds[pawnSquare(side, 27)],
            state.rules.pieceIds[pawnSquare(side, 27)],
          );
        },
      );

      test(
        'tracker does not replay initial cast, jump, epoch change or viewer handoff',
        () {
          final state = pawnFixture(side: side), cast = pawnCast(state);
          final tracker =
              BattlePresentationTracker()..observe(cast.view(side), 1);
          expect(tracker.frames, isEmpty);
          tracker.observe(cast.view(side), 1);
          expect(tracker.frames, isEmpty);
          tracker.reset();
          tracker.observe(state.view(side), 0);
          tracker.observe(cast.view(side), 1);
          expect(tracker.frames, hasLength(1));
          tracker.observe(cast.view(side), 4);
          expect(tracker.frames, isEmpty);
          tracker.observe(cast.view(side), 5, epoch: 1);
          expect(tracker.frames, isEmpty);
          tracker.observe(cast.view(side.opposite), 6, epoch: 1);
          expect(tracker.frames, isEmpty);
        },
      );

      test(
        'lost cast response retries the same intent without consuming twice',
        () async {
          final h = _PawnAuthorityHarness(side)..loseCastResponse = true;
          addTearDown(h.controller.dispose);
          final action = PlayCardAction(
            CardId.pawnDeviation,
            target: pawnSquare(side, 27),
          );
          expect(await h.controller.submit(action), false);
          expect(h.controller.hasPendingIntent, true);
          expect(
            h.controller.view!.rules.special,
            isNull,
            reason: 'No optimistic authorization before receipt.',
          );
          expect(h.state.rules.special, isNotNull);
          expect(h.state.rules.mana[side], 4);
          await h.controller.retryPending();
          expect(h.requested, hasLength(2));
          expect(h.requested[0]['actionId'], h.requested[1]['actionId']);
          expect(h.requested[0]['intent'], h.requested[1]['intent']);
          expect(h.accepted, hasLength(1));
          expect(h.controller.hasPendingIntent, false);
          expect(h.controller.view!.rules.special?.from, pawnSquare(side, 27));
          expect(h.controller.view!.rules.handCounts[side], 2);
          expect(h.controller.view!.rules.ply, 0);
          expect(h.persisted.whereType<String>(), hasLength(1));
          expect(h.persisted.last, isNull);
        },
      );

      test('lost bound-move response cannot advance or draw twice', () async {
        final h = _PawnAuthorityHarness(side);
        addTearDown(h.controller.dispose);
        expect(
          await h.controller.submit(
            PlayCardAction(CardId.pawnDeviation, target: pawnSquare(side, 27)),
          ),
          true,
        );
        h.loseMoveResponse = true;
        expect(
          await h.controller.submit(ChessMoveAction(pawnUci(side, 'd4c5'))),
          false,
        );
        expect(h.controller.view!.rules.special, isNotNull);
        expect(h.state.rules.special, isNull);
        await h.controller.retryPending();
        expect(h.requested[1]['actionId'], h.requested[2]['actionId']);
        expect(h.accepted, hasLength(2));
        expect(h.controller.view!.rules.ply, 1);
        expect(h.controller.view!.rules.drawCounts[side], 4);
        expect(h.controller.view!.rules.handCounts[side], 3);
        expect(h.controller.view!.rules.special, isNull);
      });

      test(
        'reconnect after timeout closes bound move instead of hanging retry',
        () async {
          final h = _PawnAuthorityHarness(side);
          addTearDown(h.controller.dispose);
          expect(
            await h.controller.submit(
              PlayCardAction(
                CardId.pawnDeviation,
                target: pawnSquare(side, 27),
              ),
            ),
            true,
          );
          h.state = pawnEdit(h.state, (d) {
            d.phase = BattlePhase.terminal;
            d.terminal = TerminalState('timeout', winner: side.opposite);
          });
          h.version++;
          await h.controller.reconnect();
          expect(h.controller.view!.rules.phase, BattlePhase.terminal);
          expect(h.controller.legalActions, isEmpty);
          expect(
            await h.controller.submit(ChessMoveAction(pawnUci(side, 'd4c5'))),
            false,
          );
          expect(h.controller.hasPendingIntent, false);
          expect(h.controller.busy, false);
          expect(h.accepted, hasLength(1));
          expect(h.state.rules.ply, 0);
        },
      );
    });

    testWidgets(
      '${side.name} screen Play requires destination and submits cast then one move',
      (tester) async {
        final h = _PawnAuthorityHarness(side);
        await _mount(tester, h);
        await _tap(tester, 'hand-pawn_deviation');
        await _tap(tester, 'square-${pawnSquare(side, 27)}');
        expect(
          tester
              .widget<BattleCommand>(find.byKey(const ValueKey('play-card')))
              .onPressed,
          isNull,
        );
        await _tap(tester, 'square-${pawnSquare(side, 34)}');
        await _tap(tester, 'play-card');
        expect(h.accepted.map((a) => a.key), [
          'play:pawn_deviation:${pawnSquare(side, 27)}:',
          'move:${pawnUci(side, 'd4c5')}',
        ]);
        expect(h.state.rules.ply, 1);
        expect(h.state.rules.board.turn, side.opposite);
        expect(h.state.rules.special, isNull);
        expect(
          find.byKey(const ValueKey('cast-notice-pawn_deviation')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('confirm-private')), findsNothing);
        expect(find.byKey(const ValueKey('battle-radar-result')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      '${side.name} accepted retry recovers bound pawn without replaying card',
      (tester) async {
        final h = _PawnAuthorityHarness(side)..loseCastResponse = true;
        await _mount(tester, h);
        await _tap(tester, 'hand-pawn_deviation');
        await _tap(tester, 'square-${pawnSquare(side, 27)}');
        await _tap(tester, 'square-${pawnSquare(side, 34)}');
        await _tap(tester, 'play-card');
        expect(h.accepted, hasLength(1));
        expect(h.controller.hasPendingIntent, true);
        await h.controller.retryPending();
        await tester.pumpAndSettle();
        expect(h.controller.view!.rules.special?.from, pawnSquare(side, 27));
        await _tap(tester, 'square-${pawnSquare(side, 34)}');
        expect(h.accepted.map((a) => a.key), [
          'play:pawn_deviation:${pawnSquare(side, 27)}:',
          'move:${pawnUci(side, 'd4c5')}',
        ]);
        expect(h.state.rules.mana[side], 4);
        expect(h.state.rules.drawCounts[side], 4);
        expect(h.requested, hasLength(3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      '${side.name} combined cast/move paints at accepted destination once',
      (tester) async {
        final state = pawnFixture(side: side),
            cast = pawnCast(pawnFixture(side: side));
        final moved = pawnMove(cast, 'd4c5');
        final tracker =
            BattlePresentationTracker()..observe(state.view(side), 0);
        await tester.pumpWidget(_feedback(state.view(side), tracker.frames));
        tracker.observe(cast.view(side), 1);
        tracker.observe(moved.view(side), 2);
        await tester.pumpWidget(_feedback(moved.view(side), tracker.frames));
        await tester.pump(const Duration(milliseconds: 500));
        expect(_pawnPainter(tester).cue.squares, [pawnSquare(side, 34)]);
        expect(_pawnPainter(tester).cue.side, side);
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.byKey(const ValueKey('spell-pawn_deviation-0')),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('spell-pawn_deviation-0')),
          findsNothing,
        );
        await tester.pumpWidget(_feedback(moved.view(side), tracker.frames));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(const ValueKey('spell-pawn_deviation-0')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      '${side.name} reduced motion and sync epoch cannot replay pawn cast',
      (tester) async {
        final state = pawnFixture(side: side),
            cast = pawnCast(pawnFixture(side: side));
        final tracker =
            BattlePresentationTracker()..observe(state.view(side), 0);
        await tester.pumpWidget(
          _feedback(state.view(side), tracker.frames, reduced: true),
        );
        tracker.observe(cast.view(side), 1);
        await tester.pumpWidget(
          _feedback(cast.view(side), tracker.frames, reduced: true),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(const ValueKey('spell-pawn_deviation-0')),
          findsNothing,
        );
        tracker.observe(cast.view(side), 1, epoch: 1);
        await tester.pumpWidget(
          _feedback(cast.view(side), tracker.frames, epoch: 1),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(const ValueKey('spell-pawn_deviation-0')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  test('Pawn Deviation retains V222 timing and finite board orientation', () {
    expect(battleEffectDuration(CardId.pawnDeviation).inMilliseconds, 1500);
    expect(battleEffectTiming(CardId.pawnDeviation).travel.inMilliseconds, 450);
    expect(battleSpellEnvelope(.5), 1);
    expect(battleSpellEnvelope(1), 0);
    expect(battleSpellEnvelope(double.nan), 0);
    expect(
      battleSquareCenter(27, PieceColor.white, 40),
      const Offset(140, 180),
    );
    expect(
      battleSquareCenter(36, PieceColor.black, 40),
      const Offset(140, 180),
    );
  });
}
