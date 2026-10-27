import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/draw_flow.dart';
import 'package:luno_chess/battle_ui/draw_motion.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'battle_ui/fixtures.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_ui/visual_test.dart' show renderBattle;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, warm, noOverflow;
import 'helpers/battle_v1_response.dart';

PlayerView project(
  AuthoritativeBattleState s, {
  PieceColor side = PieceColor.white,
}) =>
    PlayerView(s.rules, side, s.hidden.hands[side]!, s.hidden.knowledge[side]!);
AuthoritativeBattleState moved(AuthoritativeBattleState s) {
  if (s.rules.phase == BattlePhase.card) {
    s = DeckManager.apply(s, const PassAction());
  }
  final move =
      BattleRulesCore.legalActions(
        project(s),
      ).whereType<ChessMoveAction>().first;
  return DeckManager.apply(s, move);
}

void main() {
  setupPracticeTestAssets();
  test('initial three-card hand is baseline, not normal draw', () {
    final s = battleFixture(firstTurn: true), tracker = BattleDrawTracker();
    tracker.observe(project(s), 0);
    expect(s.hidden.hands[PieceColor.white], hasLength(3));
    expect(tracker.notice, isNull);
  });
  test('own draw proves deck, hand, draw count and chess ply deltas', () {
    final before = battleFixture(firstTurn: true),
        after = moved(before),
        tracker = BattleDrawTracker();
    tracker.observe(project(before), 0);
    tracker.observe(project(after), 1);
    expect(tracker.notice!.ownCard, after.hidden.hands[PieceColor.white]!.last);
    expect(tracker.notice!.kind, BattleArrivalKind.draw);
    expect(after.rules.deckCounts[PieceColor.white], 6);
    expect(after.rules.handCounts[PieceColor.white], 4);
  });
  test('same-version rebuild and duplicate retry retain one notice token', () {
    final before = battleFixture(firstTurn: true),
        after = moved(before),
        tracker = BattleDrawTracker();
    tracker.observe(project(before), 0);
    tracker.observe(project(after), 1);
    final event = tracker.notice;
    for (var i = 0; i < 20; i++) {
      tracker.observe(project(after), 1);
      expect(tracker.notice, same(event));
    }
  });
  for (final version in [1, 4, -1]) {
    test(
      'synchronization/stale projection replacement never replays draw $version',
      () {
        final before = battleFixture(firstTurn: true),
            after = moved(before),
            tracker = BattleDrawTracker();
        tracker.observe(project(before), 0);
        tracker.observe(project(after), version, epoch: 1);
        expect(tracker.notice, isNull);
      },
    );
  }
  test('missed multi-version history is rendered without replay', () {
    final before = battleFixture(firstTurn: true),
        tracker = BattleDrawTracker();
    tracker.observe(project(before), 0);
    tracker.observe(project(moved(before)), 3);
    expect(tracker.notice, isNull);
  });
  test('opponent draw contains no card identity', () {
    final before = battleFixture(firstTurn: true),
        after = moved(before),
        tracker = BattleDrawTracker();
    tracker.observe(project(before, side: PieceColor.black), 0);
    tracker.observe(project(after, side: PieceColor.black), 1);
    expect(tracker.notice!.opponent, true);
    expect(tracker.notice!.ownCard, isNull);
    expect(after.rules.arsenals[PieceColor.white], hasLength(10));
  });
  test('hand insertion alone and unchanged deck are not normal draw', () {
    final before = battleFixture(firstTurn: true),
        tracker = BattleDrawTracker();
    final draft = RuleDraft(before.rules);
    draft.ply++;
    final fake = PlayerView(draft.freeze(), PieceColor.white, [
      ...project(before).ownHand,
      CardId.radar,
    ], project(before).knowledge);
    tracker.observe(project(before), 0);
    tracker.observe(fake, 1);
    expect(tracker.notice, isNull);
  });
  for (final card in [CardId.prophecy, CardId.fateExchange]) {
    test('private ${card.wire} resolution has distinct semantics', () {
      var state = battleFixture(hand: [card, CardId.shelter, CardId.chain]);
      final play = BattleRulesCore.legalActions(
        project(state),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
      state = DeckManager.apply(state, play);
      final before = project(state), tracker = BattleDrawTracker();
      final action =
          BattleRulesCore.legalActions(before).whereType<ResolveAction>().first;
      state = DeckManager.apply(state, action);
      tracker.observe(before, 10);
      tracker.observe(project(state), 11);
      if (card == CardId.prophecy) {
        expect(tracker.notice, isNull);
      } else {
        expect(tracker.notice!.kind, BattleArrivalKind.exchange);
        expect(tracker.notice!.ownCard, action.selected);
      }
    });
  }
  test(
    'controller differentiates foreground polling and reconnect baseline',
    () async {
      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(),
        persistPending: (_) async {},
        request: (_, _) async => v1Response(),
      );
      await c.reconnect(synchronization: false);
      expect(c.synchronizationEpoch, 0);
      await c.reconnect();
      expect(c.synchronizationEpoch, 1);
      c.dispose();
    },
  );
  testWidgets('initial mount with deck source never shows From deck badge', (
    tester,
  ) async {
    final source = GlobalKey();
    await tester.pumpWidget(
      shell(
        Scaffold(
          body: Column(
            children: [
              SizedBox(key: source, width: 40, height: 50),
              SizedBox(
                width: 90,
                height: 150,
                child: BattleCardArrival(
                  card: CardId.radar,
                  source: source,
                  child: const ColoredBox(color: Colors.cyan),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final cancellation in ['background', 'reduced-motion', 'synchronized']) {
    testWidgets('opponent draw cancels without replay: $cancellation', (
      tester,
    ) async {
      final source = GlobalKey(), target = GlobalKey();
      Widget stage(int? trigger, {bool reduced = false}) => shell(
        Scaffold(
          body: BattleOpponentDraw(
            trigger: trigger,
            source: source,
            target: target,
            child: Column(
              children: [
                SizedBox(key: source, width: 40, height: 50),
                const SizedBox(height: 200),
                SizedBox(key: target, width: 60, height: 40),
              ],
            ),
          ),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(stage(null));
      await tester.pumpWidget(stage(1));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('opponent-closed-draw')),
        findsOneWidget,
      );
      if (cancellation == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpWidget(stage(2));
        await tester.pump();
        expect(find.byType(BattleClosedCard), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(stage(2));
      } else if (cancellation == 'reduced-motion') {
        await tester.pumpWidget(stage(1, reduced: true));
        await tester.pumpWidget(stage(1));
      } else {
        await tester.pumpWidget(stage(null));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(BattleClosedCard), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final card in [CardId.prophecy, CardId.fateExchange]) {
    testWidgets(
      'production private ${card.wire} flow is not a normal closed draw',
      (tester) async {
        final h = Harness(hand: [card, CardId.shelter, CardId.chain]);
        addTearDown(h.controller.dispose);
        await tester.pumpWidget(shell(battleScreenForAudit(h), language: 'en'));
        await warm(tester);
        final play = h.controller.legalActions
            .whereType<PlayCardAction>()
            .firstWhere((a) => a.card == card);
        await h.controller.submit(play);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('open-private')));
        await tester.tap(find.byKey(const ValueKey('open-private')));
        await tester.pumpAndSettle();
        final selected = h.controller.view!.knowledge.pendingCards.first;
        if (card == CardId.fateExchange) {
          await tester.tap(find.byKey(ValueKey('private-${selected.wire}')));
          await tester.pump();
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('confirm-private')),
        );
        await tester.tap(find.byKey(const ValueKey('confirm-private')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('From deck'), findsNothing);
        expect(find.byType(BattleClosedCard), findsNothing);
        if (card == CardId.fateExchange) {
          expect(find.text('Selected card'), findsOneWidget);
          final arrival = tester.widget<BattleCardArrival>(
            find.byWidgetPredicate(
              (w) => w is BattleCardArrival && w.card == selected,
            ),
          );
          expect(arrival.exchange, true);
          expect(arrival.absoluteOrigin, isNotNull);
        }
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('normal draw completes within 700ms and never remount-replays', (
    tester,
  ) async {
    final h = Harness(firstTurn: true);
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(shell(battleScreenForAudit(h), reduced: false));
    await warm(tester);
    final move = h.controller.legalActions.whereType<ChessMoveAction>().first;
    await h.controller.submit(move);
    await tester.pump();
    await tester.pump();
    final card = h.controller.view!.ownHand.last;
    expect(find.byKey(ValueKey('draw-source-${card.wire}')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(ValueKey('draw-source-${card.wire}')), findsNothing);
    await h.controller.reconnect();
    await tester.pump();
    expect(find.byKey(ValueKey('draw-source-${card.wire}')), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });
  for (final lang in ['tr', 'en']) {
    testWidgets(
      'public arsenal terminology and separate opponent counts $lang',
      (tester) async {
        await renderBattle(tester, language: lang);
        expect(find.text(lang == 'tr' ? 'Deste 7' : 'Deck 7'), findsWidgets);
        expect(find.text(lang == 'tr' ? 'El 3' : 'Hand 3'), findsOneWidget);
        expect(
          find.textContaining(
            lang == 'tr' ? 'Rakibin Destesi' : "Opponent's Deck",
          ),
          findsNothing,
        );
        expect(
          tester
              .widget<BattleDeckAccess>(
                find.byKey(const ValueKey('open-arsenal')),
              )
              .cardCount,
          10,
        );
        expect(find.byType(BattleClosedCard), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

// Reuse the actual production screen, not a presentation-only imitation.
Widget battleScreenForAudit(Harness h) => BattleV1Screen(
  controllerOverride: h.controller,
  clockOverride: (_) => 300000,
);
