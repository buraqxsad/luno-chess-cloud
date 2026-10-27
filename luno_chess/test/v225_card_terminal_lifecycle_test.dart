import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

List<CardId> _deck(CardId card) =>
    [
      card,
      ...starterDeck.where((candidate) => candidate != card),
    ].take(10).toList();

int _seedWithBlackCard(CardId card) {
  for (var seed = 0; seed < 1000; seed++) {
    final deck = [...starterDeck]..shuffle(Random(seed));
    if (deck.take(3).contains(card)) return seed;
  }
  throw StateError('No opening deck found for ${card.wire}');
}

Future<BattleV1LocalSession> _readyToCast(
  CardId card, {
  required int Function() clockNow,
}) async {
  final setup = switch (card) {
    CardId.purify => CardId.chain,
    CardId.breakSeal => CardId.lockedSquare,
    _ => null,
  };
  final session = BattleV1LocalSession(
    hotseat: true,
    minutes: 1,
    practiceDeck: _deck(card),
    random: Random(setup == null ? 225 : _seedWithBlackCard(setup)),
    clockNow: clockNow,
  );
  addTearDown(session.dispose);
  for (final uci in [
    'b2b3',
    'b7b6',
    'g1f3',
    'g8f6',
    'e2e4',
    'e7e5',
    'f1c4',
    'f8c5',
  ]) {
    if (session.view.rules.phase == BattlePhase.card) {
      final setupAction =
          session.view.viewer == PieceColor.black &&
                  session.view.rules.ownTurns[PieceColor.black] == 2 &&
                  setup != null
              ? session.legalActions.whereType<PlayCardAction>().firstWhere(
                (action) => action.card == setup,
              )
              : const PassAction();
      expect(await session.submit(setupAction), isTrue);
    }
    expect(await session.submit(ChessMoveAction(uci)), isTrue);
    if (session.view.viewer == PieceColor.white &&
        session.legalActions.whereType<PlayCardAction>().any(
          (action) => action.card == card,
        )) {
      return session;
    }
  }
  fail('The actual opening did not make ${card.wire} available');
}

Future<BattleV1LocalSession> _thirdTurn(
  CardId card, {
  bool practice = true,
  int Function()? clockNow,
}) async {
  final session = BattleV1LocalSession(
    hotseat: true,
    practice: practice,
    minutes: 1,
    practiceDeck: _deck(card),
    random: Random(225),
    clockNow: clockNow,
  );
  addTearDown(session.dispose);
  for (final uci in ['b2b3', 'e7e5', 'g1f3', 'b7b6']) {
    if (session.view.rules.phase == BattlePhase.card) {
      expect(await session.submit(const PassAction()), isTrue);
    }
    expect(await session.submit(ChessMoveAction(uci)), isTrue);
  }
  expect(session.view.viewer, PieceColor.white);
  expect(session.view.rules.ownTurns[PieceColor.white], 3);
  expect(session.view.rules.phase, BattlePhase.card);
  return session;
}

Future<void> _expectClosedWithoutRefund(
  BattleV1LocalSession session, {
  void Function()? finish,
  String reason = 'resign',
}) async {
  final before = session.view;
  final beforeJson = jsonEncode(before.toJson());
  final oldAction = session.legalActions.first;
  final version = session.version;
  var notifications = 0;
  session.addListener(() => notifications++);

  (finish ?? session.resign)();

  final after = session.view;
  expect(session.terminal?.reason, reason);
  expect(session.terminal?.winner, before.viewer.opposite);
  expect(after.rules.phase, BattlePhase.terminal);
  expect(after.rules.terminal?.toJson(), session.terminal?.toJson());
  expect(after.rules.pending, isNull);
  expect(after.rules.special, isNull);
  expect(after.knowledge.pendingCards, isEmpty);
  expect(BattleRulesCore.legalActions(after), isEmpty);
  final json = jsonDecode(jsonEncode(after.toJson())) as Map;
  final reloaded = PlayerView(
    RuleState.fromJson(json['rules'] as Map),
    parseSide(json['viewer'] as String),
    parseCards(json['ownHand']),
    PlayerKnowledgeState.fromJson(json['knowledge'] as Map),
  );
  expect(BattleRulesCore.legalActions(reloaded), isEmpty);
  expect(session.legalActions, isEmpty);
  expect(session.version, version + 1);
  expect(notifications, 1);
  expect(jsonEncode(before.toJson()), beforeJson);

  final expectedRules =
      before.rules.toJson()
        ..['phase'] = BattlePhase.terminal.name
        ..['terminal'] = after.rules.terminal?.toJson()
        ..['pending'] = null
        ..['special'] = null;
  expect(after.rules.toJson(), expectedRules);
  expect(after.ownHand, before.ownHand);
  expect(
    after.knowledge.knownUpcomingCards,
    before.knowledge.knownUpcomingCards,
  );
  expect(
    after.knowledge.radarObservations.map(
      (observation) => observation.toJson(),
    ),
    before.knowledge.radarObservations.map(
      (observation) => observation.toJson(),
    ),
  );

  final endedJson = jsonEncode(after.toJson());
  expect(await session.submit(oldAction), isFalse);
  session.resign();
  session.checkTimeout();
  session.observe(true);
  expect(jsonEncode(session.view.toJson()), endedJson);
  expect(session.version, version + 1);
  expect(notifications, 1);
}

void main() {
  for (final card in [CardId.prophecy, CardId.fateExchange]) {
    test(
      'resign cancels ${card.wire} private resolution without refund',
      () async {
        final session = await _thirdTurn(card);
        final action = session.legalActions
            .whereType<PlayCardAction>()
            .firstWhere((action) => action.card == card);
        expect(await session.submit(action), isTrue);
        expect(session.view.rules.phase, BattlePhase.pending);
        expect(session.view.knowledge.pendingCards, isNotEmpty);
        await _expectClosedWithoutRefund(session);
      },
    );
  }

  for (final card in movementCards) {
    test('resign revokes ${card.wire} bound movement without refund', () async {
      final session = await _thirdTurn(card);
      final action = session.legalActions
          .whereType<PlayCardAction>()
          .firstWhere((action) => action.card == card);
      expect(await session.submit(action), isTrue);
      expect(session.view.rules.phase, BattlePhase.chess);
      expect(session.view.rules.special?.card, card);
      await _expectClosedWithoutRefund(session);
    });
  }

  test('resign in a card window also closes the public rule state', () async {
    final session = await _thirdTurn(CardId.radar);
    await _expectClosedWithoutRefund(session);
  });

  for (final card in [CardId.prophecy, CardId.fateExchange, ...movementCards]) {
    test('timeout cancels ${card.wire} before its remaining action', () async {
      var now = 0;
      final session = await _thirdTurn(
        card,
        practice: false,
        clockNow: () => now,
      );
      final action = session.legalActions
          .whereType<PlayCardAction>()
          .firstWhere((action) => action.card == card);
      expect(await session.submit(action), isTrue);
      now += session.remaining(PieceColor.white);
      await _expectClosedWithoutRefund(
        session,
        finish: session.checkTimeout,
        reason: 'timeout',
      );
      expect(session.remaining(PieceColor.white), 0);
      final blackRemaining = session.remaining(PieceColor.black);
      now += 600000;
      expect(session.remaining(PieceColor.black), blackRemaining);
    });
  }

  test(
    'expiration rejects a delayed private resolution without drawing',
    () async {
      var now = 0;
      final session = await _thirdTurn(
        CardId.fateExchange,
        practice: false,
        clockNow: () => now,
      );
      final cast = session.legalActions.whereType<PlayCardAction>().firstWhere(
        (action) => action.card == CardId.fateExchange,
      );
      expect(await session.submit(cast), isTrue);
      final resolve = session.legalActions.whereType<ResolveAction>().first;
      final hand = session.view.ownHand;
      final mana = session.view.rules.mana;
      final counts = session.view.rules.drawCounts;
      final ply = session.view.rules.ply;
      now += session.remaining(PieceColor.white);

      expect(await session.submit(resolve), isFalse);
      expect(session.terminal?.reason, 'timeout');
      expect(session.view.rules.phase, BattlePhase.terminal);
      expect(session.view.ownHand, hand);
      expect(session.view.rules.mana, mana);
      expect(session.view.rules.drawCounts, counts);
      expect(session.view.rules.ply, ply);
      expect(session.view.rules.pending, isNull);
      expect(session.view.knowledge.pendingCards, isEmpty);
    },
  );

  test(
    'practice does not time out while a private card choice is open',
    () async {
      var now = 0;
      final session = await _thirdTurn(CardId.prophecy, clockNow: () => now);
      expect(
        await session.submit(const PlayCardAction(CardId.prophecy)),
        isTrue,
      );
      final before = jsonEncode(session.view.toJson());
      final version = session.version;
      now = 600000;
      session.checkTimeout();
      expect(session.terminal, isNull);
      expect(session.version, version);
      expect(jsonEncode(session.view.toJson()), before);
      expect(
        await session.submit(
          session.legalActions.whereType<ResolveAction>().first,
        ),
        isTrue,
      );
      expect(session.view.rules.phase, BattlePhase.chess);
    },
  );

  test('expired enemy turn wins over a late local resignation', () async {
    var now = 0;
    final session = BattleV1LocalSession(
      minutes: 1,
      clockNow: () => now,
      random: Random(225),
    );
    addTearDown(session.dispose);
    expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
    session.observe(false);
    expect(session.view.rules.board.turn, PieceColor.black);
    now += session.remaining(PieceColor.black);
    session.resign();
    expect(session.terminal?.reason, 'timeout');
    expect(session.terminal?.winner, PieceColor.white);
    expect(session.view.rules.phase, BattlePhase.terminal);
    final version = session.version;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(session.view.rules.board.turn, PieceColor.black);
    expect(session.version, version);
    expect(session.busy, isFalse);
  });

  test('observing a finished AI turn cannot restart its card worker', () async {
    var now = 0;
    final session = BattleV1LocalSession(
      minutes: 1,
      clockNow: () => now,
      random: Random(225),
    );
    addTearDown(session.dispose);
    expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
    session.observe(false);
    now += session.remaining(PieceColor.black);
    session.checkTimeout();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(session.busy, isFalse);
    var notifications = 0;
    session.addListener(() => notifications++);
    final before = jsonEncode(session.view.toJson());
    final version = session.version;
    session.observe(true);
    expect(notifications, 0);
    expect(session.busy, isFalse);
    expect(jsonEncode(session.view.toJson()), before);
    expect(session.version, version);
  });

  for (final card in CardId.values) {
    for (final timeout in [false, true]) {
      test(
        '${card.wire}: actual cast then ${timeout ? 'timeout' : 'resign'} keeps its ledger',
        () async {
          var now = 0;
          final session = await _readyToCast(card, clockNow: () => now);
          final cast = session.legalActions
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          final oldMana = session.view.rules.mana[PieceColor.white]!;
          final cost = BattleRulesCore.effectiveCost(
            session.view.rules,
            PieceColor.white,
            card,
          );
          expect(await session.submit(cast), isTrue);
          expect(session.view.rules.used[PieceColor.white], contains(card));
          expect(session.view.ownHand, isNot(contains(card)));
          expect(session.view.rules.mana[PieceColor.white], oldMana - cost);
          if (timeout) now += session.remaining(PieceColor.white);
          await _expectClosedWithoutRefund(
            session,
            finish: timeout ? session.checkTimeout : session.resign,
            reason: timeout ? 'timeout' : 'resign',
          );
        },
      );
    }
  }

  for (final card in [
    CardId.prophecy,
    CardId.pawnDeviation,
    CardId.pawnAdvance,
  ]) {
    for (final timeout in [false, true]) {
      test(
        'black ${card.wire}: termination closes the same card transaction timeout=$timeout',
        () async {
          var now = 0;
          final session = BattleV1LocalSession(
            hotseat: true,
            minutes: 1,
            practiceDeck: _deck(CardId.radar),
            random: Random(_seedWithBlackCard(card)),
            clockNow: () => now,
          );
          addTearDown(session.dispose);
          for (final uci in ['b2b3', 'b7b6', 'g1f3', 'g8f6', 'e2e4']) {
            if (session.view.rules.phase == BattlePhase.card) {
              expect(await session.submit(const PassAction()), isTrue);
            }
            expect(await session.submit(ChessMoveAction(uci)), isTrue);
          }
          expect(session.view.viewer, PieceColor.black);
          final cast = session.legalActions
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          expect(await session.submit(cast), isTrue);
          if (timeout) now += session.remaining(PieceColor.black);
          await _expectClosedWithoutRefund(
            session,
            finish: timeout ? session.checkTimeout : session.resign,
            reason: timeout ? 'timeout' : 'resign',
          );
        },
      );
    }
  }

  for (final openFate in [false, true]) {
    for (final timeout in [false, true]) {
      test(
        'termination preserves prior Radar and resolved Prophecy knowledge: fate=$openFate timeout=$timeout',
        () async {
          var now = 0;
          final session = BattleV1LocalSession(
            hotseat: true,
            minutes: 1,
            practiceDeck:
                [
                  CardId.radar,
                  CardId.prophecy,
                  CardId.fateExchange,
                  ...starterDeck.where(
                    (card) => card != CardId.radar && card != CardId.prophecy,
                  ),
                ].take(10).toList(),
            random: Random(225),
            clockNow: () => now,
          );
          addTearDown(session.dispose);
          expect(await session.submit(const ChessMoveAction('b2b3')), isTrue);
          expect(await session.submit(const ChessMoveAction('b7b6')), isTrue);
          final radar = session.legalActions
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == CardId.radar);
          expect(await session.submit(radar), isTrue);
          expect(await session.submit(const ChessMoveAction('g1f3')), isTrue);
          expect(await session.submit(const PassAction()), isTrue);
          expect(await session.submit(const ChessMoveAction('g8f6')), isTrue);
          expect(
            await session.submit(const PlayCardAction(CardId.prophecy)),
            isTrue,
          );
          expect(
            await session.submit(
              ResolveAction(
                session.view.knowledge.pendingCards.reversed.toList(),
              ),
            ),
            isTrue,
          );
          if (openFate) {
            expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
            expect(await session.submit(const PassAction()), isTrue);
            expect(await session.submit(const ChessMoveAction('e7e5')), isTrue);
            expect(await session.submit(const PassAction()), isTrue);
            expect(await session.submit(const ChessMoveAction('f1c4')), isTrue);
            expect(await session.submit(const PassAction()), isTrue);
            expect(await session.submit(const ChessMoveAction('f8c5')), isTrue);
            final fate = session.legalActions
                .whereType<PlayCardAction>()
                .firstWhere((action) => action.card == CardId.fateExchange);
            expect(await session.submit(fate), isTrue);
            expect(session.view.knowledge.pendingCards, hasLength(3));
          }
          expect(session.view.knowledge.radarObservations, hasLength(1));
          expect(session.view.knowledge.knownUpcomingCards, isNotEmpty);
          if (timeout) now += session.remaining(PieceColor.white);
          await _expectClosedWithoutRefund(
            session,
            finish: timeout ? session.checkTimeout : session.resign,
            reason: timeout ? 'timeout' : 'resign',
          );
        },
      );
    }
  }
}
