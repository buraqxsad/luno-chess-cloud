import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/engine/piece.dart';
import 'fixtures.dart';
import 'interaction_test.dart' show Harness, mount, tap, cleanup;

void main() {
  testWidgets(
    'Prophecy resolves only an allowed private order and survives refresh',
    (tester) async {
      final h = Harness(hand: [CardId.prophecy, CardId.shelter, CardId.mine]);
      h.state = DeckManager.apply(
        h.state,
        const PlayCardAction(CardId.prophecy),
      );
      h.controller.snapshot = null;
      await h.controller.reconnect();
      await mount(tester, h);
      await tap(tester, 'open-private');
      expect(find.byType(PrivateChoiceSheet), findsOneWidget);
      expect(
        find.text(
          'Destenin üstünü inceliyorsun. Sırayı belirle; bu işlem eline kart çekmez.',
        ),
        findsOneWidget,
      );
      await h.controller.reconnect();
      await tester.pumpAndSettle();
      final known = h.controller.view!.knowledge.pendingCards;
      for (final card in known) {
        expect(find.byKey(ValueKey('private-${card.wire}')), findsOneWidget);
      }
      await tap(tester, 'confirm-private');
      expect(h.sent.single, isA<ResolveAction>());
      expect(h.controller.view!.rules.phase, BattlePhase.chess);
      await cleanup(tester);
    },
  );
  testWidgets('Fate requires a selected take card before confirmation', (
    tester,
  ) async {
    final h = Harness(hand: [CardId.fateExchange, CardId.shelter, CardId.mine]);
    h.state = DeckManager.apply(
      h.state,
      const PlayCardAction(CardId.fateExchange, sacrifice: CardId.shelter),
    );
    h.controller.snapshot = null;
    await h.controller.reconnect();
    await mount(tester, h);
    await tap(tester, 'open-private');
    await tap(tester, 'confirm-private');
    expect(h.sent, isEmpty);
    final chosen = h.controller.view!.knowledge.pendingCards.first;
    await tap(tester, 'private-${chosen.wire}');
    await tap(tester, 'confirm-private');
    expect((h.sent.single as ResolveAction).selected, chosen);
    expect(h.controller.view!.ownHand, contains(chosen));
    await cleanup(tester);
  });
  testWidgets('private reveal has no opponent projection entry point', (
    tester,
  ) async {
    final state = DeckManager.apply(
      battleFixture(hand: [CardId.prophecy, CardId.shelter, CardId.mine]),
      const PlayCardAction(CardId.prophecy),
    );
    final enemy = state.view(PieceColor.black);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateChoiceSheet(view: enemy, actions: const []),
        ),
      ),
    );
    expect(find.text('Kehanet'), findsNothing);
    expect(find.byKey(const ValueKey('confirm-private')), findsNothing);
  });
  testWidgets('exact Break Seal choice removes only the chosen enemy effect', (
    tester,
  ) async {
    final h = Harness(hand: [CardId.breakSeal, CardId.shelter, CardId.mine]);
    final d = RuleDraft(h.state.rules)
      ..boardEffects.addAll([
        BoardEffectInstance(
          id: 'e1',
          type: BoardEffectType.mine,
          owner: PieceColor.black,
          squares: [28],
          responseSide: PieceColor.white,
          duration: EffectDuration.persistent,
        ),
        BoardEffectInstance(
          id: 'e2',
          type: BoardEffectType.lockedSquare,
          owner: PieceColor.black,
          squares: [28],
          responseSide: PieceColor.white,
          duration: EffectDuration.move,
        ),
        BoardEffectInstance(
          id: 'e3',
          type: BoardEffectType.fog,
          owner: PieceColor.white,
          squares: boardZone(28),
          responseSide: PieceColor.black,
          duration: EffectDuration.card,
        ),
      ]);
    h.state = AuthoritativeBattleState(d.freeze(), h.state.hidden);
    h.controller.snapshot = null;
    await h.controller.reconnect();
    await mount(tester, h);
    await tap(tester, 'hand-break_seal');
    await tap(tester, 'square-28');
    expect(find.byKey(const ValueKey('play:break_seal:e1:')), findsOneWidget);
    expect(find.byKey(const ValueKey('play:break_seal:e2:')), findsOneWidget);
    expect(find.byKey(const ValueKey('play:break_seal:e3:')), findsNothing);
    await tap(tester, 'play:break_seal:e2:');
    expect(h.sent, isEmpty);
    await tap(tester, 'play-card');
    expect(h.sent.single.key, 'play:break_seal:e2:');
    expect(
      h.state.rules.boardEffects.map((e) => e.id),
      containsAll(['e1', 'e3']),
    );
    expect(h.state.rules.boardEffects.map((e) => e.id), isNot(contains('e2')));
    await cleanup(tester);
  });
  for (final type in BoardEffectType.values) {
    testWidgets(
      '${type == BoardEffectType.mine ? 'own' : 'public'} $type remains '
      'visible under pieces in both orientations',
      (tester) async {
        final base = battleFixture();
        for (final side in PieceColor.values) {
          final owner = type == BoardEffectType.mine ? side : PieceColor.black;
          final d = RuleDraft(base.rules)
            ..boardEffects.add(
              BoardEffectInstance(
                id: 'e1',
                type: type,
                owner: owner,
                squares:
                    type == BoardEffectType.fog ||
                            type == BoardEffectType.boardSeal
                        ? boardZone(12)
                        : [12],
                responseSide: owner.opposite,
                duration:
                    type == BoardEffectType.mine
                        ? EffectDuration.persistent
                        : EffectDuration.move,
              ),
            );
          final v = PlayerView(
            d.freeze(),
            side,
            base.hidden.hands[side]!,
            base.hidden.knowledge[side]!,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox.square(
                  dimension: 320,
                  child: BattleBoard(view: v, onTap: (_) {}),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('effect-e1-12')), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('own and enemy Mines remain public in both board orientations', (
    tester,
  ) async {
    final base = battleFixture();
    for (final side in PieceColor.values) {
      final d = RuleDraft(base.rules)
        ..boardEffects.addAll([
          BoardEffectInstance(
            id: 'own-mine',
            type: BoardEffectType.mine,
            owner: side,
            squares: [12],
            responseSide: side.opposite,
            duration: EffectDuration.persistent,
          ),
          BoardEffectInstance(
            id: 'enemy-mine',
            type: BoardEffectType.mine,
            owner: side.opposite,
            squares: [20],
            responseSide: side,
            duration: EffectDuration.persistent,
          ),
        ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 320,
              child: BattleBoard(
                view: PlayerView(
                  d.freeze(),
                  side,
                  base.hidden.hands[side]!,
                  base.hidden.knowledge[side]!,
                ),
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('effect-own-mine-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('effect-enemy-mine-20')), findsOneWidget);
      final semantics = tester.widgetList<Semantics>(find.ancestor(
        of: find.byKey(const ValueKey('square-20')),
        matching: find.byType(Semantics),
      ));
      expect(semantics.any((s) => s.properties.label?.contains('Mayın') == true), isTrue);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('overlap keeps every effect and vow independently addressable', (
    tester,
  ) async {
    final base = battleFixture(), d = RuleDraft(base.rules);
    for (final type in BoardEffectType.values) {
      d.boardEffects.add(
        BoardEffectInstance(
          id: type.name,
          type: type,
          owner:
              type == BoardEffectType.mine
                  ? PieceColor.white
                  : PieceColor.black,
          squares:
              type == BoardEffectType.fog || type == BoardEffectType.boardSeal
                  ? boardZone(12)
                  : [12],
          responseSide:
              type == BoardEffectType.mine
                  ? PieceColor.black
                  : PieceColor.white,
          duration:
              type == BoardEffectType.mine
                  ? EffectDuration.persistent
                  : EffectDuration.move,
        ),
      );
    }
    d.vows.add(
      const VowState(
        id: 'watch',
        type: VowType.watch,
        owner: PieceColor.black,
        pieceId: null,
        square: 12,
        remainingMoves: 1,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 320,
            child: BattleBoard(
              view: PlayerView(
                d.freeze(),
                PieceColor.white,
                base.hidden.hands[PieceColor.white]!,
                PlayerKnowledgeState(),
              ),
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final type in BoardEffectType.values) {
      expect(find.byKey(ValueKey('effect-${type.name}-12')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('vow-watch')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'terminal disables every card and square and dismisses private choice',
    (tester) async {
      final h = Harness(hand: [CardId.prophecy, CardId.shelter, CardId.mine]);
      h.state = DeckManager.apply(
        h.state,
        const PlayCardAction(CardId.prophecy),
      );
      h.controller.snapshot = null;
      await h.controller.reconnect();
      await mount(tester, h);
      await tap(tester, 'open-private');
      expect(find.byType(PrivateChoiceSheet), findsOneWidget);
      expect(h.sent, isEmpty);
      final d =
          RuleDraft(h.state.rules)
            ..phase = BattlePhase.terminal
            ..terminal = const TerminalState(
              'timeout',
              winner: PieceColor.black,
            );
      h.state = AuthoritativeBattleState(d.freeze(), h.state.hidden);
      h.version++;
      await h.controller.reconnect();
      await tester.pumpAndSettle();
      expect(find.byType(PrivateChoiceSheet), findsNothing);
      expect(find.byType(BattleBoard), findsNothing);
      expect(find.byType(BattleCardTile), findsNothing);
      for (final key in [
        'open-private',
        'confirm-private',
        'play-card',
        'discard-card',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      expect(find.text('Yenilgi'), findsOneWidget);

      expect(find.byKey(const ValueKey('result-review-board')), findsOneWidget);
      final reviewTitle = find.text('Tahtayı incele');
      await tester.ensureVisible(reviewTitle);
      await tester.tap(reviewTitle);
      await tester.pumpAndSettle();
      final board = find.byType(BattleBoard);
      expect(board, findsOneWidget);
      expect(tester.widget<BattleBoard>(board).enabled, false);
      final squares = tester.widgetList<InkWell>(
        find.descendant(of: board, matching: find.byType(InkWell)),
      );
      expect(squares, hasLength(64));
      expect(squares.every((square) => square.onTap == null), isTrue);
      final terminalState = h.state.toJson();
      await tap(tester, 'square-12');
      await tap(tester, 'square-28');
      expect(h.sent, isEmpty);
      expect(h.state.toJson(), terminalState);
      expect(find.byType(PrivateChoiceSheet), findsNothing);
      expect(find.byType(BattleCardTile), findsNothing);
      await tester.ensureVisible(reviewTitle);
      await tester.tap(reviewTitle);
      await tester.pumpAndSettle();
      expect(find.byType(BattleBoard), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );
}
