import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

class _BoundaryClock {
  int now = 0;
  List<int> _samples = const [];
  int _next = 0;

  int read() {
    if (_next < _samples.length) now = _samples[_next++];
    return now;
  }

  void arm(BattleV1LocalSession session, {bool expireAtCommit = true}) {
    final left = session.remaining(session.view.rules.board.turn);
    expect(left, greaterThan(0));
    final deadline = now + left;
    _samples = [deadline - 1, expireAtCommit ? deadline : deadline - 1];
    _next = 0;
  }
}

List<CardId> _deck(CardId first) =>
    [first, ...starterDeck.where((card) => card != first)].take(10).toList();

BattleV1LocalSession _session(
  _BoundaryClock clock, {
  bool practice = false,
  CardId first = CardId.radar,
}) {
  final session = BattleV1LocalSession(
    hotseat: true,
    practice: practice,
    minutes: 1,
    practiceDeck: _deck(first),
    random: Random(235),
    clockNow: clock.read,
  );
  addTearDown(session.dispose);
  return session;
}

Future<void> _moves(BattleV1LocalSession session, List<String> moves) async {
  for (final uci in moves) {
    if (session.view.rules.phase == BattlePhase.card) {
      expect(await session.submit(const PassAction()), isTrue);
    }
    expect(await session.submit(ChessMoveAction(uci)), isTrue);
  }
}

Map<String, Object?> _ledger(PlayerView view) {
  final rules =
      Map<String, Object?>.from(view.rules.toJson())
        ..remove('phase')
        ..remove('terminal')
        ..remove('pending')
        ..remove('special');
  final knowledge = Map<String, Object?>.from(view.knowledge.toJson())
    ..remove('pendingCards');
  return {
    'rules': rules,
    'viewer': view.viewer,
    'hand': view.ownHand,
    'knowledge': knowledge,
  };
}

Future<void> _expectRejectedAtCommit(
  BattleV1LocalSession session,
  _BoundaryClock clock,
  BattleAction action,
) async {
  final before = _ledger(session.view);
  final loser = session.view.rules.board.turn;
  final version = session.version;
  final frames = <PlayerView>[];
  session.addListener(() => frames.add(session.view));
  clock.arm(session);

  expect(await session.submit(action), isFalse);
  expect(session.terminal?.reason, 'timeout');
  expect(session.terminal?.winner, loser.opposite);
  expect(session.version, version + 1);
  expect(frames, hasLength(1));
  expect(frames.single.rules.phase, BattlePhase.terminal);
  expect(_ledger(session.view), before);
  expect(_ledger(frames.single), before);
  expect(session.view.rules.pending, isNull);
  expect(session.view.rules.special, isNull);
  expect(session.view.knowledge.pendingCards, isEmpty);
  expect(session.remaining(loser), 0);
  expect(session.legalActions, isEmpty);

  final frozenVersion = session.version;
  clock.now += 600000;
  session.checkTimeout();
  expect(await session.submit(action), isFalse);
  expect(session.version, frozenVersion);
  expect(frames, hasLength(1));
}

void main() {
  for (final kind in ['move', 'pass', 'discard', 'play', 'resolve']) {
    test('$kind crossing flag fall at commit publishes timeout only', () async {
      final clock = _BoundaryClock();
      final session = _session(
        clock,
        first: kind == 'resolve' ? CardId.fateExchange : CardId.radar,
      );
      late BattleAction action;
      if (kind == 'move') {
        action = const ChessMoveAction('e2e4');
      } else if (kind == 'resolve') {
        await _moves(session, ['b2b3', 'e7e5', 'g1f3', 'b7b6']);
        final cast = session.legalActions
            .whereType<PlayCardAction>()
            .firstWhere((candidate) => candidate.card == CardId.fateExchange);
        expect(await session.submit(cast), isTrue);
        expect(session.view.rules.phase, BattlePhase.pending);
        expect(session.view.knowledge.pendingCards, isNotEmpty);
        action = session.legalActions.whereType<ResolveAction>().first;
      } else {
        await _moves(session, ['e2e4', 'e7e5']);
        expect(session.view.rules.phase, BattlePhase.card);
        action = switch (kind) {
          'pass' => const PassAction(),
          'discard' => session.legalActions.whereType<DiscardAction>().first,
          'play' => session.legalActions.whereType<PlayCardAction>().firstWhere(
            (candidate) => candidate.card == CardId.shelter,
          ),
          _ => throw StateError('Unexpected action kind'),
        };
      }

      await _expectRejectedAtCommit(session, clock, action);
    });
  }

  test('mating move cannot replace flag fall with a checkmate win', () async {
    final clock = _BoundaryClock();
    final session = _session(clock);
    await _moves(session, ['f2f3', 'e7e5', 'g2g4']);
    if (session.view.rules.phase == BattlePhase.card) {
      expect(await session.submit(const PassAction()), isTrue);
    }
    expect(session.view.rules.board.turn, PieceColor.black);

    await _expectRejectedAtCommit(
      session,
      clock,
      const ChessMoveAction('d8h4'),
    );
    expect(session.terminal?.winner, PieceColor.white);
  });

  test(
    'move committed with one millisecond left retains its increment',
    () async {
      final clock = _BoundaryClock();
      final session = _session(clock);
      final frames = <PlayerView>[];
      session.addListener(() => frames.add(session.view));
      clock.arm(session, expireAtCommit: false);

      expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
      expect(session.terminal, isNull);
      expect(session.version, 1);
      expect(session.view.rules.ply, 1);
      expect(session.view.rules.board.turn, PieceColor.black);
      expect(session.remaining(PieceColor.white), 2001);
      expect(session.remaining(PieceColor.black), 60000);
      expect(frames, hasLength(1));
    },
  );

  test('on-time terminal move still publishes checkmate once', () async {
    final clock = _BoundaryClock();
    final session = _session(clock);
    await _moves(session, ['f2f3', 'e7e5', 'g2g4']);
    if (session.view.rules.phase == BattlePhase.card) {
      expect(await session.submit(const PassAction()), isTrue);
    }
    final version = session.version;
    var notifications = 0;
    session.addListener(() => notifications++);
    clock.arm(session, expireAtCommit: false);

    expect(await session.submit(const ChessMoveAction('d8h4')), isTrue);
    expect(session.terminal?.reason, 'checkmate');
    expect(session.terminal?.winner, PieceColor.black);
    expect(session.version, version + 1);
    expect(notifications, 1);
    expect(session.remaining(PieceColor.black), 2001);
    final terminalVersion = session.version;
    clock.now += 600000;
    session.checkTimeout();
    expect(session.version, terminalVersion);
    expect(session.terminal?.reason, 'checkmate');
  });

  test(
    'untimed practice still accepts actions after the timed deadline',
    () async {
      final clock = _BoundaryClock();
      final session = _session(clock, practice: true);
      clock.now = 600000;

      expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
      expect(session.terminal, isNull);
      expect(session.version, 1);
      expect(session.view.rules.ply, 1);
      expect(session.remaining(PieceColor.white), 60000);
    },
  );

  testWidgets('flag fall during resignation beats the pending AI turn', (
    tester,
  ) async {
    final clock = _BoundaryClock();
    final session = BattleV1LocalSession(
      minutes: 1,
      random: Random(235),
      clockNow: clock.read,
    );
    addTearDown(session.dispose);
    expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
    expect(session.busy, isTrue);
    expect(session.view.viewer, PieceColor.white);
    expect(session.view.rules.board.turn, PieceColor.black);
    session.observe(false);
    final before = _ledger(session.view);
    final version = session.version;
    clock.arm(session);

    session.resign();
    expect(session.terminal?.reason, 'timeout');
    expect(session.terminal?.winner, PieceColor.white);
    expect(session.remaining(PieceColor.black), 0);
    expect(session.version, version + 1);
    expect(_ledger(session.view), before);

    await tester.pump(const Duration(milliseconds: 500));
    expect(session.busy, isFalse);
    expect(session.version, version + 1);
    expect(_ledger(session.view), before);
    expect(session.terminal?.reason, 'timeout');
    expect(session.terminal?.winner, PieceColor.white);
  });

  testWidgets('practice suspension needs no terminal result to stop the bot', (
    tester,
  ) async {
    final clock = _BoundaryClock();
    final session = BattleV1LocalSession(
      practice: true,
      random: Random(235),
      clockNow: clock.read,
    );
    addTearDown(session.dispose);
    expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
    expect(session.busy, isTrue);
    final accepted = _ledger(session.view);
    final version = session.version;

    session.observe(false);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(session.busy, isFalse);
    expect(session.terminal, isNull);
    expect(session.version, version);
    expect(_ledger(session.view), accepted);

    session.observe(false);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(session.busy, isFalse);
    expect(session.terminal, isNull);
    expect(session.version, version);
    expect(_ledger(session.view), accepted);
    expect(tester.takeException(), isNull);
  });
}
