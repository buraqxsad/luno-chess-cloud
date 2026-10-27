import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_shelter_cases.dart';

Widget _app(Widget child, {bool reduced = false, String language = 'en'}) =>
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
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
      home: Scaffold(body: child),
    );

Widget _board(
  PlayerView view, {
  bool reduced = false,
  List<BattleAcceptedFrame>? frames,
  int epoch = 0,
}) => _app(
  Center(
    child: SizedBox.square(
      dimension: 320,
      child: BattleBoard(
        view: view,
        acceptedFrames: frames,
        enabled: false,
        synchronizationEpoch: epoch,
        onTap: (_) {},
      ),
    ),
  ),
  reduced: reduced,
);

Finder _aura(String id) => find.byKey(ValueKey('piece-effect-$id'));
Finder _moving(String id) => find.byKey(ValueKey('moving-piece-$id'));

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final audit in shelterAuditCases()) {
    test('SHELTER ${audit.name}', audit.run);
  }

  for (final side in PieceColor.values) {
    int q(String value) => shelterSquare(value, side);
    String move(String value) => shelterMove(value, side);
    final original = shelterScenario(side: side);
    final cast = DeckManager.apply(
      original,
      PlayCardAction(CardId.shelter, target: q('d2')),
    );
    final moved = DeckManager.apply(cast, ChessMoveAction(move('d2d6')));
    final expired = DeckManager.apply(moved, const PassAction());
    final id = original.rules.pieceIds[q('d2')]!;
    final effectId = shelterEffects(cast).single.id;

    for (final viewer in PieceColor.values) {
      test('SHELTER ${side.name}/${viewer.name} public cast cue is exact', () {
        final before = original.view(viewer), after = cast.view(viewer);
        final cues = acceptedBattleCasts(before, after);
        expect(cues, [(card: CardId.shelter, side: side)]);
        expect(
          BattleSpellCue.fromViews(CardId.shelter, side, before, after).squares,
          [q('d2')],
        );
        expect(acceptedBattleCasts(after, moved.view(viewer)), isEmpty);
        expect(
          acceptedBattleCasts(moved.view(viewer), expired.view(viewer)),
          isEmpty,
        );
        expect(acceptedBattleCasts(after, after), isEmpty);
      });

      testWidgets(
        'SHELTER ${side.name}/${viewer.name} aura moves and expires',
        (tester) async {
          await tester.pumpWidget(_board(original.view(viewer)));
          await tester.pumpAndSettle();
          expect(_aura(effectId), findsNothing);
          await tester.pumpWidget(_board(cast.view(viewer)));
          await tester.pumpAndSettle();
          expect(_aura(effectId), findsOneWidget);
          final source = tester.getCenter(
            find.byKey(ValueKey('square-${q('d2')}')),
          );
          expect(
            (tester.getCenter(_aura(effectId)) - source).distance,
            lessThan(1),
          );
          await tester.pumpWidget(_board(moved.view(viewer)));
          await tester.pumpAndSettle();
          final destination = tester.getCenter(
            find.byKey(ValueKey('square-${q('d6')}')),
          );
          expect(
            (tester.getCenter(_aura(effectId)) - destination).distance,
            lessThan(1),
          );
          await tester.pumpWidget(_board(expired.view(viewer)));
          await tester.pumpAndSettle();
          expect(_aura(effectId), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );

      // Diagnostic reproducer for the source-observed travelling-aura suspicion.
      // The expected center follows identity, not a prescribed widget hierarchy.
      testWidgets(
        'SH-UI-01 ${side.name}/${viewer.name} shield travels with mover',
        (tester) async {
          await tester.pumpWidget(_board(cast.view(viewer)));
          await tester.pumpAndSettle();
          await tester.pumpWidget(_board(moved.view(viewer)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(_moving(id), findsOneWidget);
          expect(_aura(effectId), findsOneWidget);
          final movingCenter = tester.getCenter(_moving(id));
          final shieldCenter = tester.getCenter(_aura(effectId));
          final cell =
              tester.getSize(find.byKey(ValueKey('square-${q('d6')}'))).width;
          expect(
            (shieldCenter - movingCenter).distance,
            lessThan(cell / 4),
            reason:
                'Protection is identity-bound; its aura must not jump '
                'several cells ahead while the protected piece is travelling.',
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        'SHELTER ${side.name}/${viewer.name} reduced motion stays exact',
        (tester) async {
          await tester.pumpWidget(_board(cast.view(viewer), reduced: true));
          await tester.pump();
          await tester.pumpWidget(_board(moved.view(viewer), reduced: true));
          await tester.pump();
          expect(_moving(id), findsNothing);
          expect(_aura(effectId), findsOneWidget);
          expect(
            (tester.getCenter(_aura(effectId)) -
                    tester.getCenter(find.byKey(ValueKey('square-${q('d6')}'))))
                .distance,
            lessThan(1),
          );
          expect(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is BattleSpellPainter,
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('SHELTER ${side.name} accepted frames preserve original target', (
      tester,
    ) async {
      final tracker =
          BattlePresentationTracker()..observe(original.view(side), 10);
      await tester.pumpWidget(
        _board(original.view(side), frames: tracker.frames),
      );
      await tester.pumpAndSettle();
      tracker.observe(cast.view(side), 11);
      tracker.observe(moved.view(side), 12);
      tracker.observe(expired.view(side), 13);
      final castFrame = tracker.frames.first;
      final originalCue = BattleSpellCue.fromViews(
        CardId.shelter,
        side,
        castFrame.before,
        castFrame.after,
      );
      final frameBeforeFollow = jsonEncode(castFrame.after.toJson());
      expect(castFrame.after.rules.pieceIds[q('d2')], id);
      expect(castFrame.after.rules.pieceIds[q('d6')], isNull);
      expect(originalCue.squares, [
        q('d2'),
      ], reason: 'Accepted history records the original cast square.');
      expect(originalCue.boundPieceIds, [id]);
      final followedCue = originalCue.following(expired.rules);
      expect(followedCue.squares, [
        q('d6'),
      ], reason: 'Playback locates that identity in the current projection.');
      expect(originalCue.squares, [
        q('d2'),
      ], reason: 'Following must not mutate the accepted cast cue.');
      expect(
        jsonEncode(castFrame.after.toJson()),
        frameBeforeFollow,
        reason: 'Following must not rewrite the retained accepted frame.',
      );
      await tester.pumpWidget(
        _board(expired.view(side), frames: tracker.frames),
      );
      await tester.pump();
      final paintings =
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<BattleSpellPainter>()
              .where((p) => p.cue.card == CardId.shelter)
              .toList();
      expect(paintings, hasLength(1));
      expect(paintings.single.cue.boundPieceIds, [id]);
      expect(
        paintings.single.cue.squares,
        [q('d6')],
        reason:
            'The retained cast supplies identity, which follows the current piece.',
      );
      await tester.pump(battleEffectDuration(CardId.shelter));
      await tester.pump();
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<BattleSpellPainter>()
            .where((p) => p.cue.card == CardId.shelter),
        isEmpty,
      );
      await tester.pumpWidget(
        _board(expired.view(side), frames: tracker.frames, epoch: 1),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BattleSpellPainter,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SHELTER ${side.name} simultaneous freeze aura is retained', (
      tester,
    ) async {
      final state = shelterEdit(
        cast,
        (d) => d.pieceEffects.add(
          shelterDebuff(
            d,
            side,
            q('d2'),
            PieceEffectType.freeze,
            id: 'old-freeze',
          ),
        ),
      );
      await tester.pumpWidget(_board(state.view(side), reduced: true));
      await tester.pumpAndSettle();
      expect(_aura(effectId), findsOneWidget);
      expect(_aura('old-freeze'), findsOneWidget);
      expect(tester.widget<BattleArt>(_aura(effectId)).name, 'board-shelter');
      expect(
        tester.widget<BattleArt>(_aura('old-freeze')).name,
        'board-freeze',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final pending in [CardId.prophecy, CardId.fateExchange]) {
      testWidgets(
        'SHELTER ${side.name} survives ${pending.wire} private chooser',
        (tester) async {
          final start = shelterCastAndMove(
            shelterScenario(side: side, enemyHand: [pending, CardId.radar]),
            side,
          );
          final entered = DeckManager.apply(
            start,
            PlayCardAction(
              pending,
              sacrifice: pending == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          final choices =
              BattleRulesCore.legalActions(
                entered.view(side.opposite),
              ).whereType<ResolveAction>().toList();
          await tester.pumpWidget(
            _app(
              Column(
                children: [
                  SizedBox.square(
                    dimension: 160,
                    child: BattleBoard(
                      view: entered.view(side),
                      enabled: false,
                      onTap: (_) {},
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: PrivateChoiceSheet(
                        view: entered.view(side.opposite),
                        actions: choices,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(_aura(shelterEffects(entered).single.id), findsOneWidget);
          expect(entered.view(side).knowledge.pendingCards, isEmpty);
          await tester.pumpWidget(
            _board(
              DeckManager.apply(entered, choices.last).view(side),
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(_aura(shelterEffects(entered).single.id), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'SHELTER ${side.name} screen retarget, invalid feedback and expiry',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var state = shelterScenario(side: side), version = 60;
        final sent = <BattleAction>[];
        final controller = BattleV1Controller(
          uid: side.isWhite ? 'self' : 'other',
          matchId: v1MatchId,
          initialResponse: v1Response(
            state: state,
            version: version,
            side: side,
          ),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              final action = BattleAction.fromJson(body['intent'] as Map);
              sent.add(action);
              state = DeckManager.apply(state, action);
              version++;
            }
            return v1Response(state: state, version: version, side: side);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller)),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'hand-shelter');
        await _tap(tester, 'square-${q('d2')}');
        expect(find.byKey(ValueKey('card-preview-${q('d2')}')), findsOneWidget);
        await _tap(tester, 'square-${q('c2')}');
        expect(find.byKey(ValueKey('card-preview-${q('d2')}')), findsNothing);
        expect(find.byKey(ValueKey('card-preview-${q('c2')}')), findsOneWidget);
        await _tap(tester, 'square-${q('a1')}');
        expect(find.textContaining('That target is not valid'), findsOneWidget);
        expect(find.byKey(ValueKey('card-preview-${q('c2')}')), findsNothing);
        expect(sent, isEmpty);
        await _tap(tester, 'square-${q('d2')}');
        await _tap(tester, 'play-card');
        expect(sent.whereType<PlayCardAction>().single.target, q('d2'));
        final activeId = shelterEffects(state).single.id;
        expect(_aura(activeId), findsOneWidget);
        await _tap(tester, 'square-${q('d2')}');
        await _tap(tester, 'square-${q('d6')}');
        expect(sent.whereType<ChessMoveAction>().single.uci, move('d2d6'));
        expect(_aura(activeId), findsOneWidget);
        expect(state.rules.pieceIds[q('d6')], id);
        state = DeckManager.apply(state, const PassAction());
        version++;
        await controller.reconnect(synchronization: false);
        await tester.pumpAndSettle();
        expect(_aura(activeId), findsNothing);
        expect(state.view(side).knowledge.pendingCards, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    test(
      'SHELTER ${side.name} online projection retains public identity only',
      () {
        final response = v1Response(state: cast, version: 21, side: side);
        final parsed = BattleV1Snapshot.fromResponse(
          response,
          side.isWhite ? 'self' : 'other',
        );
        expect(
          parsed.player.rules.pieceEffects.single.toJson(),
          shelterEffects(cast).single.toJson(),
        );
        expect(parsed.player.ownHand, cast.hidden.hands[side]);
        expect(
          parsed.player.knowledge.toJson(),
          cast.hidden.knowledge[side]!.toJson(),
        );
        expect(parsed.player.toJson().keys.toSet(), {
          'rules',
          'viewer',
          'ownHand',
          'knowledge',
        });
        final public = (response['view'] as Map)['public'] as Map;
        final rules = jsonDecode(public['rulesJson'] as String) as Map;
        expect(rules.containsKey('hidden'), isFalse);
        expect(rules.containsKey('hands'), isFalse);
        expect(rules.containsKey('decks'), isFalse);
      },
    );

    test(
      'SH-UI-02 ${side.name} captured shield identity cannot transfer cue',
      () {
        final start = shelterScenario(
          side: side,
          fen: '3r3k/8/8/8/8/8/3R4/K7 w - - 0 12',
        );
        final victim = start.rules.pieceIds[q('d2')]!;
        final shielded = DeckManager.apply(
          start,
          PlayCardAction(CardId.shelter, target: q('d2')),
        );
        var next = DeckManager.apply(shielded, ChessMoveAction(move('a1b1')));
        next = DeckManager.apply(next, const PassAction());
        next = DeckManager.apply(next, ChessMoveAction(move('d8d2')));
        expect(next.rules.pieceIds.contains(victim), isFalse);
        expect(next.rules.board.pieceAt(q('d2'))!.color, side.opposite);
        final cue = BattleSpellCue.fromViews(
          CardId.shelter,
          side,
          start.view(side),
          shielded.view(side),
        );
        expect(cue.boundPieceIds, [victim]);
        final followed = cue.following(next.rules);
        expect(
          followed.squares.every(
            (square) => next.rules.pieceIds[square] == victim,
          ),
          isTrue,
          reason:
              'The accepted shield cue cannot attach to a replacement '
              'enemy piece after its protected identity has been captured.',
        );
      },
    );

    testWidgets(
      'SH-UI-02 ${side.name} batched capture does not shield enemy capturer',
      (tester) async {
        final start = shelterScenario(
          side: side,
          fen: '3r3k/8/8/8/8/8/3R4/K7 w - - 0 12',
        );
        final victim = start.rules.pieceIds[q('d2')]!;
        final tracker =
            BattlePresentationTracker()..observe(start.view(side), 30);
        await tester.pumpWidget(
          _board(start.view(side), frames: tracker.frames),
        );
        await tester.pumpAndSettle();
        var next = DeckManager.apply(
          start,
          PlayCardAction(CardId.shelter, target: q('d2')),
        );
        tracker.observe(next.view(side), 31);
        next = DeckManager.apply(next, ChessMoveAction(move('a1b1')));
        tracker.observe(next.view(side), 32);
        next = DeckManager.apply(next, const PassAction());
        tracker.observe(next.view(side), 33);
        next = DeckManager.apply(next, ChessMoveAction(move('d8d2')));
        tracker.observe(next.view(side), 34);
        await tester.pumpWidget(
          _board(next.view(side), frames: tracker.frames),
        );
        await tester.pump();
        final shields = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<BattleSpellPainter>()
            .where((p) => p.cue.card == CardId.shelter);
        expect(
          shields.every(
            (p) => p.cue.squares.every(
              (square) => next.rules.pieceIds[square] == victim,
            ),
          ),
          isTrue,
          reason:
              'Retained accepted history must not visually protect the capturer.',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    test(
      'SHELTER ${side.name} lost accepted response retries one effect',
      () async {
        var state = shelterScenario(side: side), version = 90;
        var serverApplications = 0, submissions = 0;
        String? acceptedId;
        String? persisted;
        final controller = BattleV1Controller(
          uid: side.isWhite ? 'self' : 'other',
          matchId: v1MatchId,
          initialResponse: v1Response(
            state: state,
            version: version,
            side: side,
          ),
          persistPending: (value) async => persisted = value,
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              submissions++;
              if (acceptedId == null) {
                acceptedId = body['actionId'] as String;
                state = DeckManager.apply(
                  state,
                  BattleAction.fromJson(body['intent'] as Map),
                );
                serverApplications++;
                version++;
                throw StateError('simulated-lost-accepted-response');
              }
              expect(
                body['actionId'],
                acceptedId,
                reason: 'Retry must preserve the accepted idempotency key.',
              );
            }
            return v1Response(state: state, version: version, side: side);
          },
        );
        addTearDown(controller.dispose);
        final action = PlayCardAction(CardId.shelter, target: q('d2'));
        expect(await controller.submit(action), isFalse);
        expect(controller.hasPendingIntent, isTrue);
        expect(persisted, isNotNull);
        expect(
          controller.view!.rules.pieceEffects,
          isEmpty,
          reason:
              'Unacknowledged private transport state is not a fake accepted Shield.',
        );
        expect(shelterEffects(state), hasLength(1));
        await controller.retryPending();
        expect(serverApplications, 1);
        expect(submissions, 2);
        expect(controller.hasPendingIntent, isFalse);
        expect(persisted, isNull);
        expect(controller.error, isNull);
        expect(
          controller.view!.rules.pieceEffects.single.toJson(),
          shelterEffects(state).single.toJson(),
        );
        expect(controller.view!.rules.mana[side], 4);
        expect(controller.view!.rules.used[side], [CardId.shelter]);
        expect(state.hidden.hands[side], [CardId.purify]);
        expect(controller.view!.rules.effectSequence, 101);
        final after = jsonEncode(controller.view!.toJson());
        await controller.retryPending();
        expect(serverApplications, 1);
        expect(submissions, 2);
        expect(jsonEncode(controller.view!.toJson()), after);
      },
    );

    for (final pending in [CardId.prophecy, CardId.fateExchange]) {
      testWidgets(
        'SHELTER ${side.name} cancel ${pending.wire} sheet does not expire',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final responseSide = side.opposite;
          var state = shelterCastAndMove(
            shelterScenario(side: side, enemyHand: [pending, CardId.radar]),
            side,
          );
          state = DeckManager.apply(
            state,
            PlayCardAction(
              pending,
              sacrifice: pending == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          final shieldId = shelterEffects(state).single.id;
          final pendingBefore = jsonEncode(state.toJson());
          var version = 100;
          final sent = <BattleAction>[];
          final controller = BattleV1Controller(
            uid: responseSide.isWhite ? 'self' : 'other',
            matchId: v1MatchId,
            initialResponse: v1Response(
              state: state,
              version: version,
              side: responseSide,
            ),
            persistPending: (_) async {},
            request: (path, body) async {
              if (path == '/submitBattleV1Action') {
                final action = BattleAction.fromJson(body['intent'] as Map);
                sent.add(action);
                state = DeckManager.apply(state, action);
                version++;
              }
              return v1Response(
                state: state,
                version: version,
                side: responseSide,
              );
            },
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _app(BattleV1Screen(controllerOverride: controller)),
          );
          await tester.pumpAndSettle();
          expect(_aura(shieldId), findsOneWidget);
          await _tap(tester, 'open-private');
          expect(find.byType(PrivateChoiceSheet), findsOneWidget);
          Navigator.of(tester.element(find.byType(PrivateChoiceSheet))).pop();
          await tester.pumpAndSettle();
          expect(find.byType(PrivateChoiceSheet), findsNothing);
          expect(sent, isEmpty);
          expect(
            jsonEncode(state.toJson()),
            pendingBefore,
            reason:
                'Closing presentation is not completing a private rules choice.',
          );
          expect(_aura(shieldId), findsOneWidget);
          await _tap(tester, 'open-private');
          if (pending == CardId.fateExchange) {
            final selected =
                state.hidden.knowledge[responseSide]!.pendingCards.last;
            await _tap(tester, 'private-${selected.wire}');
          }
          await _tap(tester, 'confirm-private');
          expect(sent.whereType<ResolveAction>(), hasLength(1));
          expect(_aura(shieldId), findsNothing);
          expect(state.rules.phase, BattlePhase.chess);
          expect(state.view(side).knowledge.pendingCards, isEmpty);
          expect(state.view(side).knowledge.knownUpcomingCards, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  test('SHELTER full copy distinguishes direct protection from immunity', () {
    for (final language in ['tr', 'en']) {
      final copy = LunoLocalizations(
        Locale(language),
      ).battleCardExplanation(CardId.shelter);
      expect(copy.selection, isNotEmpty);
      expect(copy.effect, contains(language == 'tr' ? 'doğrudan' : 'directly'));
      expect(
        copy.duration,
        contains(language == 'tr' ? 'kart aşaması' : 'card phase'),
      );
      expect(copy.caution, contains(language == 'tr' ? 'Mayın' : 'Mine'));
      expect(copy.caution, contains(language == 'tr' ? 'önceden' : 'existing'));
    }
  });
}
