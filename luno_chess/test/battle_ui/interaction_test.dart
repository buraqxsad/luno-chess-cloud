import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import '../helpers/battle_v1_response.dart';
import 'fixtures.dart';

class Harness {
  AuthoritativeBattleState state;
  int version = 0;
  bool mismatch = false;
  Completer<void>? hold;
  final sent = <BattleAction>[];
  late final BattleV1Controller controller;
  Harness({
    List<CardId> hand = const [
      CardId.shelter,
      CardId.chain,
      CardId.lockedSquare,
    ],
    bool firstTurn = false,
  }) : state = battleFixture(hand: hand, firstTurn: firstTurn) {
    controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: response(),
      persistPending: (_) async {},
      request: (path, body) async {
        if (path == '/submitBattleV1Action') {
          final action = BattleAction.fromJson(body['intent'] as Map);
          sent.add(action);
          if (hold != null) await hold!.future;
          state = DeckManager.apply(state, action);
          version++;
        }
        final next = response();
        if (mismatch) {
          ((next['view'] as Map)['private'] as Map)['stateVersion'] =
              version + 1;
        }
        return next;
      },
    );
  }
  Map<String, dynamic> response() => v1Response(state: state, version: version);
}

Future<void> mount(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(h.controller.dispose);
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
      home: BattleV1Screen(controllerOverride: h.controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('first turn locks cards without hiding their details', (
    tester,
  ) async {
    final h = Harness(firstTurn: true);
    await mount(tester, h);
    expect(
      tester
          .widget<BattleCardTile>(find.byKey(const ValueKey('hand-shelter')))
          .enabled,
      false,
    );
    await tap(tester, 'hand-shelter');
    expect(h.sent, isEmpty);
    expect(find.text('İlk tur: yalnızca satranç hamlesi'), findsOneWidget);
    await cleanup(tester);
  });
  testWidgets('select and cancel do not submit', (tester) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'hand-shelter');
    expect(
      tester
          .widget<BattleCardTile>(find.byKey(const ValueKey('hand-shelter')))
          .selected,
      true,
    );
    await tap(tester, 'cancel-card');
    expect(h.sent, isEmpty);
    expect(
      tester
          .widget<BattleCardTile>(find.byKey(const ValueKey('hand-shelter')))
          .selected,
      false,
    );
    await cleanup(tester);
  });
  testWidgets('illegal card target never submits or silently passes', (
    tester,
  ) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'hand-shelter');
    await tap(tester, 'square-60');
    await tap(tester, 'play-card');
    expect(h.sent, isEmpty);
    expect(find.byKey(const ValueKey('cancel-card')), findsOneWidget);
    await cleanup(tester);
  });
  testWidgets('PLAY requires a legal target and submits exactly once', (
    tester,
  ) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'hand-shelter');
    await tap(tester, 'square-12');
    await tap(tester, 'play-card');
    expect(h.sent.map((a) => a.key), ['play:shelter:12:']);
    await cleanup(tester);
  });
  testWidgets('DISCARD is explicit and submits exactly once', (tester) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'hand-chain');
    expect(h.sent, isEmpty);
    await tap(tester, 'discard-card');
    expect(h.sent.map((a) => a.key), ['discard:chain']);
    await cleanup(tester);
  });
  testWidgets('unselected legal move safely commits PASS then the move', (
    tester,
  ) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'square-12');
    await tap(tester, 'square-28');
    expect(h.sent.map((a) => a.key), ['pass', 'move:e2e4']);
    await cleanup(tester);
  });
  testWidgets('selected card prevents implicit PASS', (tester) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'hand-chain');
    await tap(tester, 'square-12');
    await tap(tester, 'square-28');
    expect(h.sent, isEmpty);
    await cleanup(tester);
  });
  testWidgets(
    'pending duplicate taps produce one intent and no optimistic board change',
    (tester) async {
      final h = Harness()..hold = Completer<void>();
      await mount(tester, h);
      await tap(tester, 'hand-shelter');
      await tap(tester, 'square-12');
      await tap(tester, 'play-card');
      await tester.tap(find.byKey(const ValueKey('play-card')));
      await tester.pump();
      expect(h.sent, hasLength(1));
      expect(h.controller.view!.rules.phase, BattlePhase.card);
      h.hold!.complete();
      await tester.pumpAndSettle();
      await cleanup(tester);
    },
  );
  testWidgets('paired projection mismatch blocks every battle action', (
    tester,
  ) async {
    final h = Harness();
    await mount(tester, h);
    h.mismatch = true;
    await h.controller.reconnect();
    await tester.pumpAndSettle();
    await tap(tester, 'square-12');
    await tap(tester, 'square-28');
    expect(h.sent, isEmpty);
    expect(find.text('Maç verisi şu anda doğrulanamıyor'), findsOneWidget);
    await cleanup(tester);
  });
  testWidgets('same-version poll preserves card selection', (tester) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'hand-shelter');
    await h.controller.reconnect();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BattleCardTile>(find.byKey(const ValueKey('hand-shelter')))
          .selected,
      true,
    );
    await cleanup(tester);
  });
  testWidgets('arsenal gives public usage but no hand membership', (
    tester,
  ) async {
    final h = Harness();
    await mount(tester, h);
    await tap(tester, 'open-arsenal');
    expect(find.text('Kullanılmadı'), findsNWidgets(10));
    expect(find.text('Elde'), findsNothing);
    expect(find.byKey(const ValueKey('arsenal-radar')), findsOneWidget);
    await cleanup(tester);
  });
  test('movement selection cannot move a different piece after binding', () {
    final state = battleFixture(
      hand: [CardId.pawnDeviation, CardId.shelter, CardId.mine],
    );
    final view = state.view(PieceColor.white), ui = BattleInteraction();
    ui.select(CardId.pawnDeviation, const [
      PlayCardAction(CardId.pawnDeviation, target: 12),
    ]);
    ui.tap(12, view, const [PlayCardAction(CardId.pawnDeviation, target: 12)]);
    ui.tap(21, view, const [PlayCardAction(CardId.pawnDeviation, target: 12)]);
    expect(ui.specialDestination?.uci, 'e2f3');
    final next = DeckManager.apply(
      state,
      const PlayCardAction(CardId.pawnDeviation, target: 12),
    ).view(PieceColor.white);
    ui.synchronize(next, 1);
    ui.tap(11, next, const [ChessMoveAction('e2f3')]);
    expect(ui.piece, 12);
  });
}
