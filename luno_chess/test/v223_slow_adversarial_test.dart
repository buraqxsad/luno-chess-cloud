import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_slow_cases.dart';

Widget _app(Widget child, {String language = 'en'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

Widget _notice(PlayerView view) => BattleCastNotice(
  key: const ValueKey('slow-audit-notice'),
  view: view,
  child: const Text('current turn guide'),
);

Future<void> _touch(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('V223 Slow independent adversarial authority', () {
    for (final audit in slowAuditCases) {
      test(audit.name, () {
        audit.run(
          (condition, reason) => expect(condition, isTrue, reason: reason),
        );
      });
    }
  });

  for (final caster in PieceColor.values) {
    test(
      'Slow ${caster.name}: response-loss retry cannot double-consume or strand intent',
      () async {
        var state = slowReady(
          caster.isWhite
              ? '4k3/8/8/8/3r4/8/8/K7 w - - 0 10'
              : '4k3/8/8/8/3R4/8/8/K7 b - - 0 10',
          black: const [CardId.slow, CardId.mine, CardId.radar],
        );
        var version = 0, attempts = 0;
        final bodies = <Map<String, dynamic>>[];
        final persisted = <String?>[];
        final uid = caster.isWhite ? 'self' : 'other';
        final controller = BattleV1Controller(
          uid: uid,
          matchId: v1MatchId,
          initialResponse: v1Response(state: state, side: caster, uid: uid),
          persistPending: (value) async => persisted.add(value),
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            bodies.add(Map.of(body));
            attempts++;
            if (attempts == 1) {
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              version++;
              throw StateError('simulated-response-lost-after-commit');
            }
            // Server receipt replay returns its accepted snapshot, never reapplies.
            return v1Response(
              state: state,
              side: caster,
              uid: uid,
              version: version,
            );
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            PlayCardAction(CardId.slow, target: slowSquare('d4')),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.snapshot!.stateVersion, 0);
        await controller.retryPending();
        expect(attempts, 2);
        expect(bodies[0]['actionId'], bodies[1]['actionId']);
        expect(bodies[0]['expectedStateVersion'], 0);
        expect(bodies[1]['expectedStateVersion'], 0);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(controller.snapshot!.stateVersion, 1);
        expect(state.rules.mana[caster], 4);
        expect(
          state.rules.used[caster]!.where((card) => card == CardId.slow),
          hasLength(1),
        );
        expect(state.rules.pieceEffects, hasLength(1));
        expect(persisted.whereType<String>(), hasLength(1));
        expect(persisted.last, isNull);
      },
    );

    test(
      'Slow ${caster.name}: stale rejection clears intent and reconnect restores progress',
      () async {
        var state = slowReady(
          caster.isWhite
              ? '4k3/8/8/8/3r4/8/8/K7 w - - 0 10'
              : '4k3/8/8/8/3R4/8/8/K7 b - - 0 10',
          black: const [CardId.slow, CardId.mine, CardId.radar],
        );
        var version = 0, stale = true, accepted = 0;
        final uid = caster.isWhite ? 'self' : 'other';
        final controller = BattleV1Controller(
          uid: uid,
          matchId: v1MatchId,
          initialResponse: v1Response(state: state, side: caster, uid: uid),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              if (stale) {
                stale = false;
                state = DeckManager.apply(state, const PassAction());
                version++;
                throw const BattleV1Rejection('STALE_STATE');
              }
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              accepted++;
              version++;
            }
            return v1Response(
              state: state,
              side: caster,
              uid: uid,
              version: version,
            );
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            PlayCardAction(CardId.slow, target: slowSquare('d4')),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isA<BattleV1Rejection>());
        expect(state.rules.used[caster], isEmpty);
        expect(state.rules.mana[caster], 6);
        await controller.reconnect();
        expect(controller.error, isNull);
        expect(controller.view!.rules.phase, BattlePhase.chess);
        final move = ChessMoveAction(caster.isWhite ? 'a1b1' : 'e8f8');
        expect(
          controller.legalActions.map((action) => action.key),
          contains(move.key),
        );
        expect(await controller.submit(move), isTrue);
        expect(accepted, 1);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(state.rules.pieceEffects, isEmpty);
      },
    );

    for (final language in ['en', 'tr']) {
      testWidgets(
        'Slow ${caster.name}/$language: actual screen rejects retarget and casts once',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var state = slowReady(
            caster.isWhite
                ? '4k3/ppnbrq2/8/8/8/8/PPNBRQ2/4K3 w - - 0 10'
                : '4k3/ppnbrq2/8/8/8/8/PPNBRQ2/4K3 b - - 0 10',
            black: const [CardId.slow, CardId.mine, CardId.radar],
          );
          final rank = caster.isWhite ? '7' : '2';
          final target = slowSquare('d$rank');
          final protected = slowSquare('e$rank');
          state = slowEdit(
            state,
            (draft) => draft.pieceEffects.add(
              ActivePieceEffect(
                id: 'protected-rook',
                type: PieceEffectType.shelter,
                owner: caster.opposite,
                pieceId: draft.pieceIds[protected]!,
                responseSide: caster,
                duration: EffectDuration.card,
              ),
            ),
          );
          var version = 0;
          final sent = <BattleAction>[];
          final uid = caster.isWhite ? 'self' : 'other';
          Map<String, dynamic> response() {
            final result = v1Response(
              state: state,
              side: caster,
              uid: uid,
              version: version,
            );
            ((result['view'] as Map)['public'] as Map)['clock']['activeSide'] =
                sideWire(state.rules.board.turn);
            return result;
          }

          final controller = BattleV1Controller(
            uid: uid,
            matchId: v1MatchId,
            initialResponse: response(),
            persistPending: (_) async {},
            request: (path, body) async {
              if (path == '/submitBattleV1Action') {
                final action = BattleAction.fromJson(body['intent'] as Map);
                sent.add(action);
                state = DeckManager.apply(state, action);
                version++;
              }
              return response();
            },
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _app(
              BattleV1Screen(controllerOverride: controller),
              language: language,
            ),
          );
          await tester.pumpAndSettle();
          await _touch(tester, 'hand-slow');
          await _touch(tester, 'square-$target');
          expect(find.byKey(ValueKey('card-preview-$target')), findsOneWidget);
          await _touch(tester, 'square-$protected');
          expect(find.byKey(ValueKey('card-preview-$target')), findsNothing);
          expect(
            tester
                .widget<BattleCommand>(find.byKey(const ValueKey('play-card')))
                .onPressed,
            isNull,
          );
          expect(
            sent,
            isEmpty,
            reason: 'Protected retarget cannot cast a stale bishop target.',
          );
          await _touch(tester, 'square-$target');
          await _touch(tester, 'play-card');
          expect(sent.map((action) => action.key), ['play:slow:$target:']);
          expect(state.rules.mana[caster], 4);
          expect(state.rules.pieceEffects.single.type, PieceEffectType.slow);
          expect(
            state.rules.pieceEffects.single.pieceId,
            state.rules.pieceIds[target],
          );
          await _touch(
            tester,
            'square-${slowSquare(caster.isWhite ? 'e1' : 'e8')}',
          );
          await _touch(
            tester,
            'square-${slowSquare(caster.isWhite ? 'd1' : 'd8')}',
          );
          expect(sent.whereType<ChessMoveAction>(), hasLength(1));
          expect(state.rules.board.turn, caster.opposite);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    test(
      'Slow ${caster.name}: exact accepted frame retains original target',
      () {
        final pair = slowPairedCasts(caster);
        final tracker = BattlePresentationTracker();
        final states = [
          pair.before,
          pair.cast,
          pair.moved,
          pair.response,
          pair.after,
        ];
        for (var version = 0; version < states.length; version++) {
          tracker.observe(states[version].view(caster), version);
        }
        expect(tracker.frames, hasLength(4));
        final castFrame = tracker.frames.first;
        expect(acceptedBattleCasts(castFrame.before, castFrame.after), [
          (card: CardId.slow, side: caster),
        ]);
        expect(
          BattleSpellCue.fromViews(
            CardId.slow,
            caster,
            castFrame.before,
            castFrame.after,
          ).squares,
          [slowSquare('d4')],
        );
        expect(tracker.frames.last.after.rules.pieceEffects, isEmpty);
        expect(
          BattleSpellCue.fromViews(
            CardId.purify,
            caster.opposite,
            tracker.frames[2].before,
            tracker.frames[2].after,
          ).squares,
          [slowSquare('d4')],
        );
      },
    );

    testWidgets('Slow ${caster.name}: earlier cast cannot be labelled latest', (
      tester,
    ) async {
      final pair = slowPairedCasts(caster);
      await tester.pumpWidget(_app(_notice(pair.before.view(caster))));
      await tester.pumpWidget(_app(_notice(pair.after.view(caster))));
      await tester.pump(const Duration(milliseconds: 450));
      // Two real casts occurred. The last one was responder Purify, not the
      // last element of a white-then-black used-card set traversal.
      expect(find.byKey(const ValueKey('cast-notice-slow')), findsNothing);
      // A version gap may instead establish a neutral baseline. There is no
      // requirement to infer a cast order absent accepted event metadata.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Slow ${caster.name}: consumed debuff is not described as active', (
      tester,
    ) async {
      final reply = slowResponseReady(caster);
      final defender = caster.opposite;
      final cast = slowReady(
        caster.isWhite
            ? '4k3/8/8/8/3r4/8/8/K7 w - - 0 10'
            : '4k3/8/8/8/3R4/8/8/K7 b - - 0 10',
        white:
            caster.isWhite
                ? const [CardId.slow, CardId.mine, CardId.radar]
                : const [CardId.prophecy, CardId.fateExchange, CardId.fog],
        black:
            caster.isWhite
                ? const [CardId.prophecy, CardId.fateExchange, CardId.fog]
                : const [CardId.slow, CardId.mine, CardId.radar],
      );
      final accepted = DeckManager.apply(
        cast,
        PlayCardAction(CardId.slow, target: slowSquare('d4')),
      );
      await tester.pumpWidget(_app(_notice(cast.view(caster))));
      await tester.pumpWidget(_app(_notice(accepted.view(caster))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(
          "The target is limited to 2 squares on its owner's next chess move.",
        ),
        findsOneWidget,
      );
      final expired = slowMove(
        DeckManager.apply(reply, const PassAction()),
        defender.isWhite ? 'a1b1' : 'e8f8',
      );
      expect(expired.rules.pieceEffects, isEmpty);
      await tester.pumpWidget(_app(_notice(expired.view(caster))));
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        find.text(
          "The target is limited to 2 squares on its owner's next chess move.",
        ),
        findsNothing,
        reason:
            'A completed response move cannot leave future-tense active Slow copy.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('Slow: a skipped network version is a new presentation baseline', () {
    final states = slowBatchedProjection();
    final tracker =
        BattlePresentationTracker()
          ..observe(states.before.view(PieceColor.black), 10)
          ..observe(states.expired.view(PieceColor.black), 14);
    expect(
      tracker.frames,
      isEmpty,
      reason: 'The old cast target cannot be recovered from an expired effect.',
    );
    expect(
      BattleSpellCue.fromViews(
        CardId.slow,
        PieceColor.white,
        states.before.view(PieceColor.black),
        states.expired.view(PieceColor.black),
      ).squares,
      isEmpty,
    );
  });

  testWidgets(
    'Slow: initial, duplicate and synchronization baseline never replay',
    (tester) async {
      final states = slowBatchedProjection();
      final after = states.cast.view(PieceColor.white);
      Widget baseline(int epoch) => BattleCastNotice(
        key: const ValueKey('slow-audit-notice'),
        view: after,
        synchronizationEpoch: epoch,
        child: const Text('baseline'),
      );
      await tester.pumpWidget(_app(baseline(0)));
      await tester.pumpWidget(_app(baseline(0)));
      expect(find.byKey(const ValueKey('cast-notice-slow')), findsNothing);
      await tester.pumpWidget(_app(baseline(1)));
      expect(find.byKey(const ValueKey('cast-notice-slow')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
