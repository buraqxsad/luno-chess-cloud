import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/draw_motion.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/fixtures.dart';

const _pose = ValueKey('hand-card-pose');
const _arrival = ValueKey('hand-arrival-position');
const _closedDraw = ValueKey('opponent-closed-draw');
const _discard = ValueKey('hand-discard-departure');

Widget _host(Widget child, {bool reduced = false, bool ticking = true}) =>
    shell(
      Scaffold(body: TickerMode(enabled: ticking, child: child)),
      reduced: reduced,
      language: 'en',
    );

Transform _cardPose(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(_pose).first);

Future<void> _expectMotionIdle(WidgetTester tester) async {
  const expectedTickers = {
    '_BattleCardMotionState': 2,
    '_BattleHandDiscardState': 1,
    '_BattleCardArrivalState': 1,
    '_BattleCardSelectionFlashState': 1,
    '_BattleOpponentDrawState': 1,
  };
  var checked = 0;
  void checkOwnedTickers() {
    for (final state in tester.allStates) {
      final name = state.runtimeType.toString();
      final expected = expectedTickers[name];
      if (expected == null) continue;
      final tickers = <Ticker>[];
      for (final property in state.toDiagnosticsNode().getProperties()) {
        final value = property.value;
        if (value is Ticker) tickers.add(value);
        if (value is Set<Ticker>) tickers.addAll(value);
      }
      expect(tickers, hasLength(expected), reason: '$name ticker coverage');
      for (final ticker in tickers) {
        expect(ticker.isActive, isFalse, reason: '$name has an active ticker');
        expect(ticker.isTicking, isFalse, reason: '$name is still ticking');
      }
      checked++;
    }
  }

  // Check the original deadline first, including active-but-muted tickers.
  checkOwnedTickers();
  expect(checked, greaterThan(0));
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
  });
  // The owned animations must already be idle above. Material's separate ink
  // fade can start at this completion frame; require it to settle, bounded.
  await tester.pumpAndSettle(
    const Duration(milliseconds: 16),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 1),
  );
  checkOwnedTickers();
  expect(tester.binding.hasScheduledFrame, isFalse);
}

void main() {
  setupPracticeTestAssets();

  test(
    'opponent draw arc has exact, clamped endpoints and bounded samples',
    () {
      for (final ends in [
        (const Offset(300, 80), const Offset(40, 300)),
        (const Offset(40, 300), const Offset(300, 80)),
        (const Offset(20, 30), const Offset(20, 30)),
        (const Offset(10, 80), const Offset(310, 80)),
      ]) {
        final (from, to) = ends;
        expect(battleOpponentDrawPoint(from, to, 0), from);
        expect(battleOpponentDrawPoint(from, to, 1), to);
        expect(battleOpponentDrawPoint(from, to, -1), from);
        expect(battleOpponentDrawPoint(from, to, 2), to);
        final bounds = Rect.fromPoints(from, to).inflate(56);
        Offset? previous;
        for (var i = 0; i <= 100; i++) {
          final point = battleOpponentDrawPoint(from, to, i / 100);
          expect(point.dx.isFinite && point.dy.isFinite, isTrue);
          expect(bounds.contains(point), isTrue);
          if (previous != null) {
            expect((point - previous).distance, lessThan(25));
          }
          previous = point;
        }
      }
      const from = Offset(10, 80), to = Offset(310, 80);
      expect(battleOpponentDrawPoint(from, to, .06).dx, lessThan(from.dx));
      expect(battleOpponentDrawPoint(from, to, .47).dy, lessThan(50));
      expect(battleOpponentDrawPoint(from, to, .91).dx, to.dx);
      expect(battleOpponentDrawPoint(from, to, .91).dy, closeTo(77, .001));
    },
  );

  testWidgets('press and selection keep the slot and detail hit area stable', (
    tester,
  ) async {
    var selections = 0, details = 0;
    Widget card(bool selected) => _host(
      Center(
        child: SizedBox(
          width: 100,
          height: 184,
          child: BattleCardTile(
            card: CardId.freeze,
            cost: 3,
            selected: selected,
            onSelect: () => selections++,
            onDetail: () => details++,
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(false));
    final tile = find.byType(BattleCardTile);
    final size = tester.getSize(tile);
    final detail = find.byKey(const ValueKey('detail-freeze'));
    final detailPoint = tester.getCenter(detail);
    final pressPoint = tester.getRect(tile).bottomLeft + const Offset(25, -25);
    final gesture = await tester.startGesture(pressPoint);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(_cardPose(tester).transform.storage[0], lessThan(.97));
    expect(_cardPose(tester).transformHitTests, isFalse);
    expect(tester.getSize(tile), size);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(selections, 1);
    expect(_cardPose(tester).transform.storage[0], closeTo(1, .001));

    await tester.pumpWidget(card(true));
    await tester.pump(const Duration(milliseconds: 220));
    expect(_cardPose(tester).transform.storage[13], lessThan(-6));
    expect(_cardPose(tester).transform.storage[13], greaterThan(-7));
    expect(tester.getSize(tile), size);
    expect(tester.getSize(detail), const Size(44, 44));
    await tester.tapAt(detailPoint);
    await tester.pump(const Duration(milliseconds: 700));
    expect(details, 1);
    expect(selections, 1);
    expect(_cardPose(tester).transform.storage[13], closeTo(-6, .001));
    await _expectMotionIdle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drag and cancel release press without invoking selection', (
    tester,
  ) async {
    var selections = 0;
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 100,
            height: 184,
            child: BattleCardTile(
              card: CardId.freeze,
              cost: 3,
              onSelect: () => selections++,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BattleCardTile)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.moveBy(const Offset(60, 0));
    await gesture.cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(_cardPose(tester).transform.storage[0], closeTo(1, .001));
    expect(selections, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final cancellation in ['reduced', 'ticker', 'background']) {
    testWidgets('press and selection finish without replay: $cancellation', (
      tester,
    ) async {
      Widget card(bool selected, {bool reduced = false, bool ticking = true}) =>
          _host(
            Center(
              child: SizedBox(
                width: 100,
                height: 184,
                child: BattleCardTile(
                  card: CardId.freeze,
                  cost: 3,
                  selected: selected,
                  onSelect: () {},
                ),
              ),
            ),
            reduced: reduced,
            ticking: ticking,
          );
      await tester.pumpWidget(card(false));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BattleCardTile)),
      );
      await tester.pumpWidget(card(true));
      await tester.pump(const Duration(milliseconds: 80));
      if (cancellation == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        await tester.pumpWidget(
          card(
            true,
            reduced: cancellation == 'reduced',
            ticking: cancellation != 'ticker',
          ),
        );
      }
      await gesture.cancel();
      await tester.pumpWidget(card(true));
      expect(find.byType(BattleCardSelectionFlash), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(_cardPose(tester).transform.storage[0], closeTo(1.012, .001));
      expect(_cardPose(tester).transform.storage[13], closeTo(-6, .001));
      await _expectMotionIdle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final cancellation in ['reduced', 'ticker', 'background', 'trigger']) {
    testWidgets('own arrival cancels pending motion: $cancellation', (
      tester,
    ) async {
      final source = GlobalKey();
      var taps = 0;
      Widget stage(int? trigger, {bool reduced = false, bool ticking = true}) =>
          _host(
            Column(
              children: [
                SizedBox(key: source, width: 40, height: 50),
                const SizedBox(height: 100),
                SizedBox(
                  width: 100,
                  height: 184,
                  child: BattleCardArrival(
                    card: CardId.freeze,
                    source: source,
                    trigger: trigger,
                    child: GestureDetector(
                      key: const ValueKey('arrival-hit'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                      child: const ColoredBox(color: Colors.cyan),
                    ),
                  ),
                ),
              ],
            ),
            reduced: reduced,
            ticking: ticking,
          );
      await tester.pumpWidget(stage(null));
      final hit = tester.getCenter(find.byKey(const ValueKey('arrival-hit')));
      await tester.pumpWidget(stage(1));
      await tester.pump();
      expect(find.byType(BattleClosedCard), findsOneWidget);
      expect(
        tester.widget<Transform>(find.byKey(_arrival)).transformHitTests,
        isFalse,
      );
      await tester.tapAt(hit);
      expect(taps, 1);
      if (cancellation == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        await tester.pumpWidget(
          stage(
            cancellation == 'trigger' ? null : 1,
            reduced: cancellation == 'reduced',
            ticking: cancellation != 'ticker',
          ),
        );
      }
      await tester.pumpWidget(stage(cancellation == 'trigger' ? null : 1));
      expect(find.byType(BattleClosedCard), findsNothing);
      await tester.pump(const Duration(milliseconds: 750));
      final transform = tester.widget<Transform>(find.byKey(_arrival));
      expect(transform.transform.storage[12], closeTo(0, .001));
      expect(transform.transform.storage[13], closeTo(0, .001));
      expect(find.byType(BattleClosedCard), findsNothing);
      await _expectMotionIdle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('arrival endpoints settle and duplicate tokens do not restart', (
    tester,
  ) async {
    final source = GlobalKey();
    Widget stage(int? trigger) => _host(
      Column(
        children: [
          SizedBox(key: source, width: 40, height: 50),
          const SizedBox(height: 100),
          SizedBox(
            width: 100,
            height: 184,
            child: BattleCardArrival(
              card: CardId.freeze,
              source: source,
              trigger: trigger,
              child: const ColoredBox(color: Colors.cyan),
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(stage(null));
    final destination = tester.getCenter(find.byKey(_arrival));
    final from = tester.getCenter(find.byKey(source));
    await tester.pumpWidget(stage(1));
    await tester.pump();
    final start = tester.widget<Transform>(find.byKey(_arrival)).transform;
    expect(start.storage[12], closeTo(from.dx - destination.dx, .001));
    expect(start.storage[13], closeTo(from.dy - destination.dy, .001));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpWidget(stage(1));
    expect(find.byType(BattleClosedCard), findsNothing);
    final end = tester.widget<Transform>(find.byKey(_arrival)).transform;
    expect(end.storage[12], closeTo(0, .001));
    expect(end.storage[13], closeTo(0, .001));
    await _expectMotionIdle(tester);
    await tester.pumpWidget(stage(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 750));
    expect(tester.takeException(), isNull);
  });

  for (final cancellation in ['reduced', 'ticker', 'background', 'trigger']) {
    testWidgets(
      'opponent closed draw is private and cancellable: $cancellation',
      (tester) async {
        final source = GlobalKey(), target = GlobalKey();
        var taps = 0;
        Widget stage(
          int? trigger, {
          bool reduced = false,
          bool ticking = true,
        }) => _host(
          BattleOpponentDraw(
            trigger: trigger,
            source: source,
            target: target,
            child: Column(
              children: [
                SizedBox(key: source, width: 40, height: 50),
                const SizedBox(height: 160),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: SizedBox(key: target, width: 60, height: 40),
                ),
              ],
            ),
          ),
          reduced: reduced,
          ticking: ticking,
        );
        await tester.pumpWidget(stage(null));
        await tester.pumpWidget(stage(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 570));
        expect(find.byKey(_closedDraw), findsOneWidget);
        expect(find.byType(BattleCardArt), findsNothing);
        expect(find.byType(BattleCardTile), findsNothing);
        await tester.tapAt(tester.getCenter(find.byKey(target)));
        expect(taps, 1);
        if (cancellation == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          await tester.pumpWidget(
            stage(
              cancellation == 'trigger' ? null : 1,
              reduced: cancellation == 'reduced',
              ticking: cancellation != 'ticker',
            ),
          );
        }
        await tester.pumpWidget(stage(cancellation == 'trigger' ? null : 1));
        expect(find.byKey(_closedDraw), findsNothing);
        await tester.pump(const Duration(milliseconds: 750));
        expect(find.byKey(_closedDraw), findsNothing);
        await _expectMotionIdle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'only an accepted own discard gets a departure: reduced=$reduced',
      (tester) async {
        final before = battleFixture();
        final after = DeckManager.apply(
          before,
          const DiscardAction(CardId.chain),
        );
        var selections = 0;
        Widget stage(AuthoritativeBattleState state) => _host(
          Center(
            child: SizedBox(
              width: 390,
              child: BattleHand(
                view: state.view(PieceColor.white),
                enabled: true,
                cost: (_) => 2,
                selectable: (_) => true,
                onSelect: (_) => selections++,
                onDetail: (_) {},
              ),
            ),
          ),
          reduced: reduced,
        );
        await tester.pumpWidget(stage(before));
        final handSize = tester.getSize(find.byType(BattleHand));
        await tester.tap(find.byKey(const ValueKey('hand-chain')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(_discard), findsNothing);
        await tester.pumpWidget(stage(after));
        expect(find.byKey(_discard), reduced ? findsNothing : findsOneWidget);
        expect(
          after.rules.mana[PieceColor.white],
          before.rules.mana[PieceColor.white],
        );
        expect(tester.getSize(find.byType(BattleHand)), handSize);
        if (!reduced) {
          final overlay = tester.widget<IgnorePointer>(find.byKey(_discard));
          expect(overlay.ignoring, isTrue);
        }
        final previousSelections = selections;
        await tester.tap(find.byKey(const ValueKey('hand-shelter')));
        expect(selections, previousSelections + 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpWidget(stage(after));
        expect(find.byKey(_discard), findsNothing);
        await _expectMotionIdle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('discard cancels on background and stays consumed on resume', (
    tester,
  ) async {
    final before = battleFixture();
    final after = DeckManager.apply(before, const DiscardAction(CardId.chain));
    Widget stage(AuthoritativeBattleState state) => _host(
      SizedBox(
        width: 390,
        child: BattleHand(
          view: state.view(PieceColor.white),
          enabled: true,
          cost: (_) => 2,
          selectable: (_) => true,
          onSelect: (_) {},
          onDetail: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(stage(before));
    await tester.pumpWidget(stage(after));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(_discard), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byKey(_discard), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(stage(after));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(_discard), findsNothing);
    await _expectMotionIdle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
