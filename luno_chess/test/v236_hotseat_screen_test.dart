import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/draw_motion.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

const _curtain = ValueKey('hotseat-curtain');
const _ack = ValueKey('hotseat-ready');

BattleV1LocalSession _session(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(BattleV1Screen));
  return state.localSession as BattleV1LocalSession;
}

Future<void> _touch(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectConcealed(WidgetTester tester) {
  expect(find.byKey(_curtain), findsOneWidget);
  expect(find.byType(BattleHand, skipOffstage: false), findsNothing);
  expect(find.byType(BattleCardTile, skipOffstage: false), findsNothing);
  expect(find.byType(BattleBoard, skipOffstage: false), findsNothing);
  expect(find.byType(BattleCastStage, skipOffstage: false), findsNothing);
  expect(find.byType(BattleOpponentDraw, skipOffstage: false), findsNothing);
  expect(find.byType(PrivateKnowledgeSheet, skipOffstage: false), findsNothing);
  expect(find.byType(PrivateChoiceSheet, skipOffstage: false), findsNothing);
  expect(find.byType(OpponentArsenalSheet, skipOffstage: false), findsNothing);
  expect(find.byType(CardDetailSheet, skipOffstage: false), findsNothing);
  final l = LunoLocalizations.of(tester.element(find.byKey(_curtain)));
  for (final copy in [
    BattleCopy.hand,
    BattleCopy.deck,
    BattleCopy.arsenal,
    BattleCopy.privateChoice,
    BattleCopy.privateKnowledge,
    BattleCopy.upcoming,
  ]) {
    final label = RegExp.escape(l.battle(copy));
    expect(
      find.bySemanticsLabel(RegExp(r'(^|[\s,.:])' + label + r'($|[\s,.:])')),
      findsNothing,
      reason: 'Private $copy labels must not survive before acknowledgement.',
    );
  }
  expect(find.bySemanticsLabel(RegExp('My deck|Destem')), findsNothing);
  for (final card in CardId.values) {
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(l.battleCardName(card)))),
      findsNothing,
      reason: '${card.wire} must not survive in the semantics tree.',
    );
  }
}

void _prepare(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 4));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setupPracticeTestAssets();

  testWidgets(
    'initial hand and both turn directions require explicit handover',
    (tester) async {
      _prepare(tester);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          shell(
            const BattleV1Screen(local: true),
            language: 'en',
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        _expectConcealed(tester);
        expect(_session(tester).view.viewer, PieceColor.white);
        await _touch(tester, 'hotseat-ready');
        expect(find.byType(BattleHand), findsOneWidget);
        final oldTap =
            tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap;
        final oldDeck =
            tester
                .widget<IconButton>(find.byKey(const ValueKey('open-own-deck')))
                .onPressed!;
        await _touch(tester, 'square-12');
        await _touch(tester, 'square-28');
        expect(_session(tester).view.viewer, PieceColor.black);
        _expectConcealed(tester);
        final version = _session(tester).version;
        oldTap(52);
        oldTap(36);
        oldDeck();
        await tester.pump();
        expect(_session(tester).version, version);
        expect(find.byType(OpponentArsenalSheet), findsNothing);
        _expectConcealed(tester);
        await _touch(tester, 'hotseat-ready');
        expect(find.byType(BattleHand), findsOneWidget);
        oldTap(52);
        oldTap(36);
        oldDeck();
        await tester.pump();
        expect(_session(tester).version, version);
        expect(find.byType(OpponentArsenalSheet), findsNothing);
        await _touch(tester, 'square-52');
        await _touch(tester, 'square-36');
        expect(_session(tester).view.viewer, PieceColor.white);
        _expectConcealed(tester);
        await _touch(tester, 'hotseat-ready');
        final dynamic state = tester.state(find.byType(BattleV1Screen));
        final selection = state.selection as BattleInteraction;
        expect(selection.card, isNull);
        expect(selection.piece, isNull);
        expect(selection.play, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final surface in ['selection', 'deck', 'detail', 'tooltip']) {
    testWidgets(
      '$surface is removed on background and not restored on resume',
      (tester) async {
        _prepare(tester);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            shell(
              const BattleV1Screen(local: true),
              language: 'en',
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          await _touch(tester, 'hotseat-ready');
          final session = _session(tester);
          if (surface == 'selection') {
            tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(12);
          } else if (surface == 'deck') {
            await _touch(tester, 'open-own-deck');
            expect(find.byType(OpponentArsenalSheet), findsOneWidget);
          } else if (surface == 'detail') {
            await tester.longPress(
              find.byKey(ValueKey('hand-${session.view.ownHand.first.wire}')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(CardDetailSheet), findsOneWidget);
          } else {
            final tooltip = tester.state<TooltipState>(
              find.descendant(
                of: find.byKey(const ValueKey('open-own-deck')),
                matching: find.byType(Tooltip),
              ),
            );
            tooltip.ensureTooltipVisible();
            await tester.pump(const Duration(milliseconds: 200));
          }
          final version = session.version;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          _expectConcealed(tester);
          expect(
            find.byType(OpponentArsenalSheet, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.byType(CardDetailSheet, skipOffstage: false),
            findsNothing,
          );
          expect(find.textContaining('My deck'), findsNothing);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          _expectConcealed(tester);
          expect(session.version, version);
          await _touch(tester, 'hotseat-ready');
          final dynamic state = tester.state(find.byType(BattleV1Screen));
          expect((state.selection as BattleInteraction).piece, isNull);
          expect(find.byType(OpponentArsenalSheet), findsNothing);
          expect(find.byType(CardDetailSheet), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final card in [CardId.prophecy, CardId.fateExchange]) {
    testWidgets(
      'pending ${card.wire} stays private without resolving on resume',
      (tester) async {
        _prepare(tester);
        final semantics = tester.ensureSemantics();
        BattleV1LocalSession? ownedSession;
        void disposeSession() {
          final session = ownedSession;
          ownedSession = null;
          session?.dispose();
        }

        addTearDown(disposeSession);
        try {
          final session = BattleV1LocalSession(
            hotseat: true,
            practiceDeck:
                [
                  card,
                  ...starterDeck.where((item) => item != card),
                ].take(10).toList(),
            random: Random(236),
          );
          ownedSession = session;
          await tester.pumpWidget(
            shell(
              BattleV1Screen(local: true, localSessionOverride: session),
              language: 'en',
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          for (final uci in ['b2b3', 'e7e5', 'g1f3', 'b7b6']) {
            if (session.view.rules.phase == BattlePhase.card) {
              expect(await session.submit(const PassAction()), isTrue);
            }
            expect(await session.submit(ChessMoveAction(uci)), isTrue);
          }
          await tester.pumpAndSettle();
          await _touch(tester, 'hotseat-ready');
          final cast = session.legalActions
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          expect(await session.submit(cast), isTrue);
          await tester.pumpAndSettle();
          expect(session.view.rules.phase, BattlePhase.pending);
          final pendingCards = [...session.view.knowledge.pendingCards];
          expect(pendingCards, isNotEmpty);
          await _touch(tester, 'open-private');
          expect(find.byType(PrivateChoiceSheet), findsOneWidget);
          final version = session.version;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          _expectConcealed(tester);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          _expectConcealed(tester);
          expect(session.version, version);
          expect(session.view.rules.phase, BattlePhase.pending);
          expect(session.view.knowledge.pendingCards, pendingCards);
          await _touch(tester, 'hotseat-ready');
          expect(find.byType(PrivateChoiceSheet), findsNothing);
          await _touch(tester, 'open-private');
          if (card == CardId.fateExchange) {
            await _touch(tester, 'private-${pendingCards.first.wire}');
          }
          await _touch(tester, 'confirm-private');
          expect(session.view.rules.phase, BattlePhase.chess);
          expect(session.version, version + 1);
          final oldKnowledge =
              tester
                  .widget<BattleKnowledgePreview>(
                    find.byType(BattleKnowledgePreview),
                  )
                  .onOpen!;
          expect(
            await session.submit(
              session.legalActions.whereType<ChessMoveAction>().first,
            ),
            isTrue,
          );
          await tester.pumpAndSettle();
          _expectConcealed(tester);
          await _touch(tester, 'hotseat-ready');
          oldKnowledge();
          await tester.pumpAndSettle();
          expect(find.byType(PrivateKnowledgeSheet), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          try {
            disposeSession();
          } finally {
            semantics.dispose();
          }
        }
      },
    );
  }

  testWidgets(
    'background before private sheet first build cannot leave a stale route',
    (tester) async {
      _prepare(tester);
      await tester.pumpWidget(
        shell(const BattleV1Screen(local: true), language: 'en', reduced: true),
      );
      await tester.pumpAndSettle();
      await _touch(tester, 'hotseat-ready');
      await tester.tap(find.byKey(const ValueKey('open-own-deck')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(_curtain), findsOneWidget);
      expect(
        find.byType(OpponentArsenalSheet, skipOffstage: false),
        findsNothing,
      );
      expect(find.byKey(_ack).hitTestable(), findsOneWidget);
      await _touch(tester, 'hotseat-ready');
      expect(find.byType(BattleHand), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale ready callback is rejected and rematch begins concealed', (
    tester,
  ) async {
    _prepare(tester);
    await tester.pumpWidget(
      shell(const BattleV1Screen(local: true), language: 'en', reduced: true),
    );
    await tester.pumpAndSettle();
    final staleReady = tester.widget<FilledButton>(find.byKey(_ack)).onPressed!;
    await _touch(tester, 'hotseat-ready');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    staleReady();
    await tester.pumpAndSettle();
    expect(find.byKey(_curtain), findsOneWidget);
    await _touch(tester, 'hotseat-ready');
    _session(tester).resign();
    await tester.pumpAndSettle();
    await _touch(tester, 'local-rematch');
    expect(_session(tester).view.viewer, PieceColor.white);
    expect(_session(tester).version, 0);
    expect(find.byKey(_curtain), findsOneWidget);
    staleReady();
    await tester.pump();
    expect(find.byKey(_curtain), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'handover does not pause the authoritative local clock or timeout',
    () async {
      var now = 0;
      final session = BattleV1LocalSession(
        hotseat: true,
        minutes: 1,
        clockNow: () => now,
        random: Random(236),
      );
      addTearDown(session.dispose);
      expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
      now = 17000;
      expect(session.remaining(PieceColor.black), 43000);
      session.observe(false);
      now = 61000;
      session.observe(true);
      expect(session.terminal?.reason, 'timeout');
      expect(session.terminal?.winner, PieceColor.white);
      expect(await session.submit(const ChessMoveAction('e7e5')), isFalse);
    },
  );

  testWidgets('curtain clock repaints while acknowledgement is withheld', (
    tester,
  ) async {
    _prepare(tester);
    var remaining = 60000;
    await tester.pumpWidget(
      shell(
        BattleV1Screen(local: true, clockOverride: (_) => remaining),
        language: 'en',
        reduced: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_curtain), findsOneWidget);
    expect(tester.widget<BattleClock>(find.byType(BattleClock)).active, isTrue);
    expect(find.text('1:00'), findsOneWidget);
    remaining = 43000;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0:43'), findsOneWidget);
    expect(find.byKey(_curtain), findsOneWidget);
    expect(_session(tester).version, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('withheld acknowledgement cannot prevent an incoming timeout', (
    tester,
  ) async {
    _prepare(tester);
    var now = 0;
    final session = BattleV1LocalSession(
      hotseat: true,
      minutes: 1,
      clockNow: () => now,
      random: Random(236),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      shell(
        BattleV1Screen(local: true, localSessionOverride: session),
        language: 'en',
        reduced: true,
      ),
    );
    await tester.pumpAndSettle();
    await _touch(tester, 'hotseat-ready');
    await _touch(tester, 'square-12');
    await _touch(tester, 'square-28');
    expect(find.byKey(_curtain), findsOneWidget);
    expect(session.view.viewer, PieceColor.black);
    now = 61000;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(session.terminal?.reason, 'timeout');
    expect(session.terminal?.winner, PieceColor.white);
    expect(find.byKey(_ack), findsNothing);
    expect(find.byType(BattleHand, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('local-rematch')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['tr', 'en']) {
    for (final size in [const Size(320, 568), const Size(430, 932)]) {
      testWidgets('curtain fits $language ${size.width} at 2x text', (
        tester,
      ) async {
        _prepare(tester);
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          shell(
            const BattleV1Screen(local: true),
            language: language,
            scale: 2,
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_curtain), findsOneWidget);
        await tester.ensureVisible(find.byKey(_ack));
        expect(find.byKey(_ack).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
